"""Shared bounded subprocess streaming and termination primitives."""
from __future__ import annotations

import math
import queue
import subprocess
import threading
import time
from collections.abc import Callable, Sequence
from typing import Any


class ProcessCancelledError(RuntimeError):
    """Raised when a running child process is cancelled by its caller."""


def _validate_non_negative_finite(value: float, name: str) -> None:
    """Reject invalid timeout values before they reach process-control code."""
    if not math.isfinite(value) or value < 0:
        raise ValueError(f"{name} must be a finite, non-negative number.")


def terminate_process(proc: subprocess.Popen[str], grace_seconds: float = 1.0) -> None:
    """Terminate a child with bounded waits; never wait indefinitely."""
    _validate_non_negative_finite(grace_seconds, "grace_seconds")
    if proc.poll() is not None:
        return
    try:
        proc.terminate()
    except OSError:
        # The process may have exited between poll() and terminate().
        pass
    try:
        proc.wait(timeout=grace_seconds)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        proc.kill()
    except OSError:
        # The process may have exited between wait() and kill().
        pass
    try:
        proc.wait(timeout=grace_seconds)
    except subprocess.TimeoutExpired:
        # Keep termination bounded even if the OS has not reaped the process yet.
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
    """Run a child while bounding runtime, queued output, and retained diagnostics.

    Output lines can be dropped when the bounded reader queue is full. The returned
    output includes a count of omitted lines so callers do not mistake it for a
    complete transcript. Exceptions raised by the callback cancel the child and
    propagate to the caller.
    """
    if not command:
        raise ValueError("command must contain an executable.")
    if any(not isinstance(argument, str) for argument in command):
        raise TypeError("command arguments must all be strings.")
    if timeout is not None:
        _validate_non_negative_finite(timeout, "timeout")
    if max_output_chars < 0:
        raise ValueError("max_output_chars must be non-negative.")
    if max_queue_lines < 1:
        raise ValueError("max_queue_lines must be at least 1.")
    if cancel_event is not None and cancel_event.is_set():
        raise ProcessCancelledError("Process cancelled before launch.")

    proc = subprocess.Popen(
        list(command),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        stdin=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
        **(popen_kwargs or {}),
    )
    assert proc.stdout is not None
    lines: queue.Queue[str | None] = queue.Queue(maxsize=max_queue_lines)
    drops = {"count": 0}
    drops_lock = threading.Lock()

    def reader() -> None:
        try:
            for line in proc.stdout:
                try:
                    lines.put_nowait(line)
                except queue.Full:
                    with drops_lock:
                        drops["count"] += 1
        finally:
            # Ensure the consumer can observe EOF even if the queue is saturated.
            while True:
                try:
                    lines.put_nowait(None)
                    break
                except queue.Full:
                    try:
                        lines.get_nowait()
                        with drops_lock:
                            drops["count"] += 1
                    except queue.Empty:
                        continue

    thread = threading.Thread(target=reader, name="DroidLab-ProcessReader", daemon=True)
    thread.start()
    deadline = None if timeout is None else time.monotonic() + timeout
    retained: list[str] = []
    retained_chars = 0
    omitted = 0
    stream_closed = False
    try:
        while not stream_closed:
            if cancel_event is not None and cancel_event.is_set():
                raise ProcessCancelledError("Process cancelled by user.")
            if deadline is not None and time.monotonic() >= deadline:
                raise subprocess.TimeoutExpired(list(command), timeout)
            wait = 0.1
            if deadline is not None:
                wait = min(wait, max(0.01, deadline - time.monotonic()))
            try:
                line = lines.get(timeout=wait)
            except queue.Empty:
                continue
            if line is None:
                stream_closed = True
                continue
            if on_line is not None:
                on_line(line)
            if retained_chars + len(line) <= max_output_chars:
                retained.append(line)
                retained_chars += len(line)
            else:
                omitted += 1
        code = proc.wait(timeout=2)
        with drops_lock:
            omitted += drops["count"]
        output = "".join(retained)
        if omitted:
            output += f"\n[DroidLab: {omitted} additional output line(s) omitted]\n"
        return subprocess.CompletedProcess(list(command), code, output, "")
    except BaseException:
        terminate_process(proc)
        raise
    finally:
        try:
            proc.stdout.close()
        except (OSError, ValueError):
            pass
        # A descendant can retain the pipe after the direct child exits. Never wait
        # indefinitely for the daemon reader in that case.
        if thread.is_alive():
            thread.join(timeout=0.25)
