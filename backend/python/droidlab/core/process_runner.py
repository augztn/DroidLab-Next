"""Bounded subprocess streaming and process-tree termination primitives."""
from __future__ import annotations

import math
import os
import queue
import signal
import subprocess
import threading
import time
from collections.abc import Callable, Sequence
from typing import Any


class ProcessCancelledError(RuntimeError):
    """Raised when a running child process is cancelled by its caller."""


def _validate_non_negative_finite(value: float, name: str) -> None:
    if not math.isfinite(value) or value < 0:
        raise ValueError(f"{name} must be a finite, non-negative number.")


def terminate_process(
    proc: subprocess.Popen[str],
    grace_seconds: float = 1.0,
) -> None:
    """Terminate a child and its owned process group with bounded waits."""
    _validate_non_negative_finite(grace_seconds, "grace_seconds")
    if os.name == "nt":
        try:
            subprocess.run(
                ["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=max(1.0, grace_seconds + 1.0),
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            pass
        if proc.poll() is None:
            try:
                proc.terminate()
            except OSError:
                pass
            try:
                proc.wait(timeout=grace_seconds)
            except subprocess.TimeoutExpired:
                try:
                    proc.kill()
                except OSError:
                    pass
                try:
                    proc.wait(timeout=grace_seconds)
                except subprocess.TimeoutExpired:
                    pass
        return

    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError, OSError):
        if proc.poll() is None:
            try:
                proc.terminate()
            except OSError:
                pass
    try:
        proc.wait(timeout=grace_seconds)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError, OSError):
        if proc.poll() is None:
            try:
                proc.kill()
            except OSError:
                pass
    try:
        proc.wait(timeout=grace_seconds)
    except subprocess.TimeoutExpired:
        pass


def run_streaming(
    command: Sequence[str],
    *,
    timeout: float | None = None,
    cancel_event: threading.Event | None = None,
    on_line: Callable[[str], None] | None = None,
    max_output_chars: int = 2 * 1024 * 1024,
    max_queue_lines: int = 1000,
    popen_kwargs: dict[str, Any] | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run a child with bounded reads, queue, retained output and runtime."""
    if not command:
        raise ValueError("command must contain an executable.")
    if any(not isinstance(argument, str) or "\x00" in argument for argument in command):
        raise ValueError("command arguments must be strings without NUL bytes.")
    if timeout is not None:
        _validate_non_negative_finite(timeout, "timeout")
    if max_output_chars < 0:
        raise ValueError("max_output_chars must be non-negative.")
    if max_queue_lines < 1:
        raise ValueError("max_queue_lines must be at least 1.")
    if cancel_event is not None and cancel_event.is_set():
        raise ProcessCancelledError("Process cancelled before launch.")

    launch_options = dict(popen_kwargs or {})
    if os.name == "posix":
        launch_options["start_new_session"] = True
    proc = subprocess.Popen(
        list(command),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        stdin=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
        **launch_options,
    )
    stdout = proc.stdout
    assert stdout is not None

    chunks: queue.Queue[str | None] = queue.Queue(maxsize=max_queue_lines)
    dropped = 0
    dropped_lock = threading.Lock()

    def record_drop() -> None:
        nonlocal dropped
        with dropped_lock:
            dropped += 1

    def reader() -> None:
        try:
            while True:
                chunk = stdout.readline(16 * 1024)
                if not chunk:
                    break
                try:
                    chunks.put_nowait(chunk)
                except queue.Full:
                    record_drop()
        finally:
            while True:
                try:
                    chunks.put_nowait(None)
                    break
                except queue.Full:
                    try:
                        chunks.get_nowait()
                        record_drop()
                    except queue.Empty:
                        continue

    reader_thread = threading.Thread(
        target=reader,
        name="DroidLab-ProcessReader",
        daemon=True,
    )
    reader_thread.start()
    deadline = None if timeout is None else time.monotonic() + timeout
    retained: list[str] = []
    retained_chars = 0
    omitted = 0

    try:
        while True:
            if cancel_event is not None and cancel_event.is_set():
                raise ProcessCancelledError("Process cancelled by user.")
            if deadline is not None and time.monotonic() >= deadline:
                raise subprocess.TimeoutExpired(list(command), timeout)
            wait_seconds = 0.1
            if deadline is not None:
                wait_seconds = min(wait_seconds, max(0.01, deadline - time.monotonic()))
            try:
                chunk = chunks.get(timeout=wait_seconds)
            except queue.Empty:
                continue
            if chunk is None:
                break
            if on_line is not None:
                on_line(chunk.rstrip("\r\n"))
            if retained_chars + len(chunk) <= max_output_chars:
                retained.append(chunk)
                retained_chars += len(chunk)
            else:
                omitted += 1

        code = proc.wait(timeout=2)
        with dropped_lock:
            omitted += dropped
        output = "".join(retained)
        if omitted:
            output += f"\n[DroidLab: {omitted} additional output chunk(s) omitted]\n"
        return subprocess.CompletedProcess(list(command), code, output, "")
    except BaseException:
        terminate_process(proc)
        raise
    finally:
        try:
            stdout.close()
        except (OSError, ValueError):
            pass
        if reader_thread.is_alive():
            reader_thread.join(timeout=0.25)
