"""Shared bounded subprocess streaming and termination primitives."""

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
    """Reject invalid timeout values before they reach process-control code."""
    if not math.isfinite(value) or value < 0:
        raise ValueError(f"{name} must be a finite, non-negative number.")


def terminate_process(proc: subprocess.Popen[str], grace_seconds: float = 1.0) -> None:
    """Terminate a child and its subprocess tree with bounded waits.

    POSIX children are launched in a new session, allowing their process group to
    be signalled even if the direct child has already exited but a descendant still
    holds the output pipe open. Windows uses taskkill's tree option where available.
    """
    _validate_non_negative_finite(grace_seconds, "grace_seconds")

    if os.name == "nt":
        # taskkill can still find descendants after the direct process has exited.
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

    # run_streaming starts a new session, so this group belongs to this operation.
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        if proc.poll() is None:
            try:
                proc.terminate()
            except OSError:
                pass
    except OSError:
        if proc.poll() is None:
            try:
                proc.terminate()
            except OSError:
                pass

    try:
        proc.wait(timeout=grace_seconds)
    except subprocess.TimeoutExpired:
        pass

    # Kill remaining group members too; the group may outlive its leader and keep
    # stdout open. The direct child is reaped below whenever the OS permits it.
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        if proc.poll() is None:
            try:
                proc.kill()
            except OSError:
                pass
    except OSError:
        if proc.poll() is None:
            try:
                proc.kill()
            except OSError:
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

    launch_options = dict(popen_kwargs or {})
    if os.name == "posix":
        # Process-tree termination relies on this operation owning its process group.
        # Do not let caller-supplied Popen options silently disable that guarantee.
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
    lines: queue.Queue[str | None] = queue.Queue(maxsize=max_queue_lines)
    drops = {"count": 0}
    drops_lock = threading.Lock()

    def reader() -> None:
        try:
            for line in stdout:
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
                raise subprocess.TimeoutExpired(
                    list(command), timeout if timeout is not None else 0.0
                )
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
            stdout.close()
        except (OSError, ValueError):
            pass
        # Descendants are terminated on exceptional paths; never wait indefinitely
        # for the daemon reader if a platform pipe implementation remains blocked.
        if thread.is_alive():
            thread.join(timeout=0.25)
