"""Adapter for the documented payload-dumper-go command-line backend."""
from __future__ import annotations

import hashlib
import logging
import math
import os
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Callable
from pathlib import Path

if __package__:
    from .command_guards import is_valid_partition_name
    from .process_runner import ProcessCancelledError, run_streaming, terminate_process
else:
    from command_guards import is_valid_partition_name
    from process_runner import ProcessCancelledError, run_streaming, terminate_process

Progress = Callable[[str], None]


def _configured_timeout(name: str, default: float) -> float:
    """Read a finite positive timeout override, falling back safely on bad input."""
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        value = float(raw)
    except ValueError:
        logging.warning("Ignoring invalid %s value %r; using %s seconds", name, raw, default)
        return default
    if not math.isfinite(value) or value <= 0:
        logging.warning("Ignoring invalid %s value %r; using %s seconds", name, raw, default)
        return default
    if value > 86400:
        logging.warning("Capping %s at 86400 seconds", name)
        return 86400
    return value


INSPECTION_TIMEOUT_SECONDS = _configured_timeout("DROIDLAB_PAYLOAD_INSPECTION_TIMEOUT", 120)
EXTRACTION_TIMEOUT_SECONDS = _configured_timeout("DROIDLAB_PAYLOAD_EXTRACTION_TIMEOUT", 3600)


class BackendError(RuntimeError):
    """Raised when the extraction backend cannot complete an operation."""


def _bundle_root() -> Path:
    """Resolve the bundle root for development, PyInstaller, and AppImage runs."""
    if getattr(sys, "frozen", False):
        executable = Path(sys.executable).resolve()
        # AppImage: AppDir/usr/bin/droidlab-gui-bin; backend is under AppDir/opt.
        if executable.parent.name == "bin" and executable.parent.parent.name == "usr":
            return executable.parent.parent.parent
        return executable.parent
    # core/payload_dumper.py -> droidlab/core -> droidlab -> src -> project root
    return Path(__file__).resolve().parents[3]


def _find_cli() -> list[str] | None:
    root = _bundle_root()
    candidates = [
        root / "opt" / "payload-dumper" / "bin" / "payload-dumper-go",
        root / "opt" / "payload-dumper" / "bin" / "payload-dumper-go.exe",
        root / "bin" / "payload-dumper-go",
        root / "bin" / "payload-dumper-go.exe",
        root / "payload-dumper-go",
        root / "payload-dumper-go.exe",
    ]
    for item in candidates:
        if item.is_file() and (os.name == "nt" or os.access(item, os.X_OK)):
            return [str(item)]
    for name in ("payload-dumper-go", "payload-dumper-go.exe"):
        found = shutil.which(name)
        if found:
            return [found]
    return None



def _terminate_process(proc: subprocess.Popen, grace_seconds: float = 5.0) -> None:
    """Compatibility wrapper around the shared bounded termination helper."""
    terminate_process(proc, grace_seconds)


def _run_process(
    cli: list[str],
    args: list[str],
    progress: Progress | None = None,
    cancel_event=None,
    operation: str = "Payload operation",
    timeout: float = 3600,
) -> subprocess.CompletedProcess[str]:
    """Run the backend with a bounded lifetime and shared streaming controls."""
    command = cli + args
    try:
        return run_streaming(
            command,
            timeout=timeout,
            cancel_event=cancel_event,
            on_line=(lambda line: progress(line.rstrip())) if progress else None,
            popen_kwargs={},
        )
    except ProcessCancelledError as exc:
        raise BackendError(f"{operation} cancelled by user.") from exc
    except subprocess.TimeoutExpired as exc:
        limit = timeout if exc.timeout is None else exc.timeout
        raise BackendError(f"{operation} timed out after {limit:g} seconds.") from exc
    except OSError as exc:
        raise BackendError(f"Could not start payload-dumper-go: {exc}") from exc


def _run(
    args: list[str],
    progress: Progress | None = None,
    cancel_event=None,
) -> subprocess.CompletedProcess[str]:
    cli = _find_cli()
    if not cli:
        raise BackendError("payload-dumper-go was not found. Install it or use the bundled AppImage.")
    return _run_process(
        cli, args, progress, cancel_event, "Inspection", timeout=INSPECTION_TIMEOUT_SECONDS
    )


def inspect_source(
    source: str,
    output_dir: str = "",
    progress: Progress | None = None,
    cancel_event=None,
) -> list[dict]:
    path = Path(source).expanduser().resolve()
    if not path.is_file():
        raise BackendError(f"Input file does not exist: {path}")
    result = _run(["-l", "-m", str(path)], progress=progress, cancel_event=cancel_event)
    if result.returncode:
        raise BackendError(result.stdout.strip() or "Could not inspect the OTA payload.")
    parts = []
    for line in result.stdout.splitlines():
        name, sep, size = line.partition(":")
        if not sep or not name.strip():
            continue
        try:
            size_bytes = int(size.strip()) * 1024
        except ValueError:
            continue
        partition_name = name.strip()
        if not is_valid_partition_name(partition_name):
            continue
        parts.append({"name": partition_name, "size_bytes": size_bytes, "hash": ""})
    return parts


def extract(
    source: str,
    output_dir: str,
    selected: list[str] | None = None,
    progress: Progress | None = None,
    cancel_event=None,
) -> list[Path]:
    src = Path(source).expanduser().resolve()
    if not output_dir or not output_dir.strip():
        raise BackendError("Choose an output directory.")
    out = Path(output_dir).expanduser().resolve()
    if not src.is_file():
        raise BackendError(f"Input file does not exist: {src}")
    if src.suffix.lower() not in {".bin", ".zip"}:
        raise BackendError("Choose a payload .bin file or OTA .zip file.")
    cli = _find_cli()
    if not cli:
        raise BackendError("payload-dumper-go was not found. Install it or use the bundled AppImage.")
    if selected:
        invalid = [
            name for name in selected
            if not isinstance(name, str) or not is_valid_partition_name(name)
        ]
        if invalid:
            raise BackendError("Invalid partition selection; refresh the partition list and try again.")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)
    # A unique sibling staging directory keeps backend output isolated while
    # remaining on the same filesystem as the destination for atomic linking.
    stage = Path(tempfile.mkdtemp(prefix=".droidlab-extract-", dir=str(out.parent)))
    published: list[Path] = []
    try:
        args = ["-o", str(stage)]
        if selected:
            args.extend(["-p", ",".join(selected)])
        args.append(str(src))
        if progress:
            progress("Starting payload-dumper-go in an isolated staging directory.")
        # OTA extraction can legitimately take a long time on slow storage, but
        # a stuck backend must not keep the worker alive indefinitely.
        result = _run_process(
            cli, args, progress, cancel_event, "Extraction", timeout=EXTRACTION_TIMEOUT_SECONDS
        )
        if result.returncode:
            raise BackendError(
                f"payload-dumper-go exited with status {result.returncode}. "
                "Check the log; some delta OTA operation types are unsupported."
            )
        if cancel_event is not None and cancel_event.is_set():
            raise BackendError("Extraction cancelled by user.")

        artifacts = sorted(
            path for path in stage.rglob("*.img")
            if path.is_file() and not path.is_symlink() and path.stat().st_size > 0
        )
        if not artifacts:
            raise BackendError("Extraction completed without producing any non-empty .img artifacts.")

        if selected:
            actual = {path.stem.casefold() for path in artifacts}
            missing = sorted({name.casefold() for name in selected} - actual)
            if missing:
                raise BackendError(
                    "Extraction did not produce the requested partition image(s): "
                    + ", ".join(missing)
                )

        output_root = out.resolve()
        for artifact in artifacts:
            relative = artifact.relative_to(stage)
            destination = out / relative
            # Do not allow a backend-created symlink or path resolution to publish
            # outside the chosen output root.
            destination_parent = destination.parent.resolve()
            try:
                destination_parent.relative_to(output_root)
            except ValueError as exc:
                raise BackendError("An extracted artifact resolves outside the output directory.") from exc
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination_parent = destination.parent.resolve()
            try:
                destination_parent.relative_to(output_root)
            except ValueError as exc:
                raise BackendError("An output path resolves outside the output directory.") from exc
            if destination.exists() or destination.is_symlink():
                raise BackendError(
                    f"Output already exists and will not be overwritten: {destination}"
                )
            try:
                # Hard-link publication is atomic and fails if a destination
                # appeared concurrently; stage is created on the same filesystem.
                os.link(artifact, destination)
            except FileExistsError as exc:
                raise BackendError(
                    f"Output already exists and will not be overwritten: {destination}"
                ) from exc
            except OSError as exc:
                raise BackendError(f"Could not publish extracted artifact {destination}: {exc}") from exc
            published.append(destination)
            artifact.unlink()

        if cancel_event is not None and cancel_event.is_set():
            raise BackendError("Extraction cancelled before publication completed.")
        if progress:
            progress(f"Published {len(published)} verified non-empty image artifact(s).")
        return published
    except Exception:
        # Publication is a multi-file operation, not a filesystem-wide atomic
        # transaction. Roll back files created by this operation on failure.
        for destination in reversed(published):
            try:
                destination.unlink(missing_ok=True)
            except OSError:
                pass
        raise
    finally:
        try:
            shutil.rmtree(stage)
        except FileNotFoundError:
            pass
        except OSError as exc:
            # Cleanup failure must not mask the original extraction/cancellation
            # exception, or turn a successful publication into a false failure.
            logging.warning("Could not remove payload staging directory %s: %s", stage, exc)
            if progress:
                try:
                    progress(f"Warning: could not remove temporary staging directory {stage}: {exc}")
                except Exception:
                    logging.debug("Could not report staging cleanup warning", exc_info=True)


def sha256_file(path: str, chunk_size: int = 1024 * 1024) -> str:
    """Compute a SHA-256 fingerprint; this alone is not OTA integrity verification."""
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        while chunk := stream.read(chunk_size):
            digest.update(chunk)
    return digest.hexdigest()
