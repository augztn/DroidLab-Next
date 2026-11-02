"""Path validation for dedicated ADB host/device file transfers."""
from __future__ import annotations

import errno
import os
import shutil
from pathlib import Path, PurePosixPath


def validate_android_path(value: object, field_name: str) -> str:
    if not isinstance(value, str) or not value.strip() or "\x00" in value:
        raise ValueError(f"{field_name} must be a non-empty Android path.")
    path = PurePosixPath(value.strip())
    if not path.is_absolute() or path == PurePosixPath("/") or ".." in path.parts:
        raise ValueError(f"{field_name} must be an absolute non-root path without '..' segments.")
    if value.strip().startswith("-"):
        raise ValueError(f"{field_name} must not be an ADB option.")
    return str(path)


def validate_push_source(value: object) -> Path:
    if not isinstance(value, str) or not value.strip():
        raise ValueError("source_path must be a local file path.")
    source = Path(value).expanduser()
    if source.is_symlink() or not source.is_file():
        raise ValueError("ADB push source must be an existing regular file, not a symlink or directory.")
    return source.resolve(strict=True)


def validate_pull_directory(value: object) -> Path:
    if not isinstance(value, str) or not value.strip():
        raise ValueError("destination_path must be a local directory.")
    destination = Path(value).expanduser()
    if destination.is_symlink():
        raise ValueError("ADB pull destination must not be a symbolic link.")
    destination.mkdir(parents=True, exist_ok=True)
    if not destination.is_dir():
        raise ValueError("ADB pull destination must be a directory.")
    return destination.resolve(strict=True)


def ensure_pull_target_is_new(remote_path: str, destination: Path) -> None:
    filename = PurePosixPath(remote_path).name
    target = destination / filename
    if target.exists() or target.is_symlink():
        raise FileExistsError(f"Refusing to overwrite existing pull destination: {target}")


def publish_file_no_replace(source: Path, destination: Path) -> None:
    """Publish a staged file without replacing an existing path.

    Hard links provide an atomic publish on filesystems that support them.
    FAT/exFAT and some network filesystems do not support hard links, so fall
    back to an exclusive create followed by a bounded streaming copy.
    """
    try:
        os.link(source, destination)
        return
    except FileExistsError:
        raise
    except OSError as error:
        unsupported = {
            errno.EPERM,
            errno.EACCES,
            errno.EXDEV,
            getattr(errno, "EOPNOTSUPP", errno.EPERM),
            getattr(errno, "ENOTSUP", errno.EPERM),
        }
        if error.errno not in unsupported:
            raise

    flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_BINARY", 0)
    descriptor = os.open(destination, flags, 0o600)
    try:
        with os.fdopen(descriptor, "wb") as output, source.open("rb") as input_stream:
            shutil.copyfileobj(input_stream, output, length=1024 * 1024)
            output.flush()
            os.fsync(output.fileno())
    except Exception:
        try:
            destination.unlink()
        except OSError:
            pass
        raise
