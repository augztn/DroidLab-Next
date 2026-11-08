"""Path validation for dedicated ADB host/device file transfers."""
from __future__ import annotations

import errno
import os
import shutil
import json
import re
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


def validate_apk_source(value: object) -> Path:
    """Validate a local APK before passing it to the ADB package installer."""
    source = validate_push_source(value)
    if source.suffix.lower() != ".apk":
        raise ValueError("Choose an Android application package with the .apk extension.")
    if source.stat().st_size <= 0:
        raise ValueError("The APK file is empty.")
    return source


def validate_apk_sources(value: object) -> list[Path]:
    if not isinstance(value, list) or not value or len(value) > 100:
        raise ValueError("apk_paths must contain between 1 and 100 APK files.")
    sources = [validate_apk_source(item) for item in value]
    if len({str(item) for item in sources}) != len(sources):
        raise ValueError("Select each APK file only once.")
    return sources


def validate_package_name(value: object) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+", value):
        raise ValueError("Invalid Android package name.")
    return value


def validate_app_backup(value: object) -> tuple[Path, list[Path]]:
    if not isinstance(value, str) or not value.strip():
        raise ValueError("backup_path must be a backup folder.")
    root = Path(value).expanduser()
    if root.is_symlink() or not root.is_dir():
        raise ValueError("Backup path must be an existing directory, not a symbolic link.")
    root = root.resolve(strict=True)
    manifest_path = root / "manifest.json"
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise ValueError("Backup manifest is missing or unsafe.")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError("Backup manifest is invalid.") from error
    if not isinstance(manifest, dict) or manifest.get("schema_version") != 1:
        raise ValueError("Unsupported app backup format.")
    validate_package_name(manifest.get("package"))
    entries = manifest.get("files")
    if not isinstance(entries, list) or not entries or len(entries) > 64:
        raise ValueError("Backup contains no valid APK set.")
    apks = []
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError("Backup manifest contains an invalid entry.")
        name = entry.get("file")
        if not isinstance(name, str) or Path(name).name != name or not name.endswith(".apk"):
            raise ValueError("Backup manifest contains an unsafe APK filename.")
        apk = root / name
        if apk.is_symlink() or not apk.is_file() or apk.stat().st_size <= 0:
            raise ValueError(f"Backup APK is missing or invalid: {name}")
        apks.append(apk.resolve(strict=True))
    return root, apks
