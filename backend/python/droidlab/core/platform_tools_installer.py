"""User-initiated Android Platform-Tools installer.

Google's SDK license does not grant general redistribution rights for the SDK
package. DroidLab therefore never ships or mirrors these binaries: the user
explicitly accepts Google's SDK terms and downloads the official archive
directly to their own per-user application-data directory.
"""
from __future__ import annotations

import hashlib
import os
import platform
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath
from typing import Callable
from urllib.parse import urlparse

PLATFORM_TOOLS_VERSION = "37.0.1"
PLATFORM_TOOLS_PAGE = "https://developer.android.com/tools/releases/platform-tools"
DOWNLOAD_URLS = {
    "win32": "https://dl.google.com/android/repository/platform-tools_r37.0.1-win.zip",
    "darwin": "https://dl.google.com/android/repository/platform-tools_r37.0.1-darwin.zip",
}
# Pinned checksums: Microsoft winget manifest (Windows) and Homebrew Cask
# manifest (macOS), both pointing to Google's versioned HTTPS archives.
PLATFORM_TOOLS_SHA256 = {
    "win32": "45f4d63113e895ebde0c90f194099a4676b6ac653bd28d54314a9e022bbc1a99",
    "darwin": "ee39ad5967e95c2a07f04dbcbde96b1a0c916ba376096db5d2f498b7727a5d1d",
}
MAX_ARCHIVE_BYTES = 64 * 1024 * 1024
MAX_UNCOMPRESSED_BYTES = 256 * 1024 * 1024
MAX_ARCHIVE_ENTRIES = 2048
_DOWNLOAD_LOCK = threading.Lock()


def managed_platform_tools_dir(
    *,
    platform_name: str | None = None,
    home: Path | None = None,
    environment: dict[str, str] | None = None,
) -> Path:
    """Return the per-user versioned install location for this OS."""
    platform_name = platform_name or sys.platform
    environment = os.environ if environment is None else environment
    home = Path.home() if home is None else Path(home)

    if platform_name == "win32":
        base = environment.get("LOCALAPPDATA") or str(home / "AppData" / "Local")
    elif platform_name == "darwin":
        base = str(home / "Library" / "Application Support")
    else:
        base = environment.get("XDG_DATA_HOME") or str(home / ".local" / "share")
    return Path(base).expanduser() / "DroidLab" / "platform-tools" / PLATFORM_TOOLS_VERSION


def _tool_names(platform_name: str) -> tuple[str, str]:
    suffix = ".exe" if platform_name == "win32" else ""
    return "adb" + suffix, "fastboot" + suffix


def platform_tools_status(
    *,
    platform_name: str | None = None,
    install_dir: Path | None = None,
) -> dict[str, object]:
    platform_name = platform_name or sys.platform
    directory = install_dir or managed_platform_tools_dir(platform_name=platform_name)
    adb_name, fastboot_name = _tool_names(platform_name)
    adb = directory / adb_name
    fastboot = directory / fastboot_name
    return {
        "supported": platform_name in DOWNLOAD_URLS,
        "version": PLATFORM_TOOLS_VERSION,
        "installed": adb.is_file() and fastboot.is_file(),
        "directory": str(directory),
        "adb_path": str(adb) if adb.is_file() else None,
        "fastboot_path": str(fastboot) if fastboot.is_file() else None,
        "license_url": PLATFORM_TOOLS_PAGE,
    }


def _assert_supported_architecture(platform_name: str) -> None:
    machine = platform.machine().lower()
    if platform_name == "win32" and machine not in {"amd64", "x86_64"}:
        raise RuntimeError(
            f"Google Platform-Tools Windows package is not configured for {machine or 'unknown'}."
        )
    if platform_name == "darwin" and machine not in {"arm64", "aarch64", "x86_64"}:
        raise RuntimeError(
            f"Google Platform-Tools macOS package is not configured for {machine or 'unknown'}."
        )


def _download_archive(url: str, destination: Path, *, expected_sha256: str, opener: Callable = urllib.request.urlopen) -> int:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "DroidLab-PlatformTools-Installer/1.0"},
    )
    total = 0
    digest = hashlib.sha256()
    with opener(request, timeout=45) as response, destination.open("wb") as output:
        final_url = response.geturl()
        parsed = urlparse(final_url)
        host = (parsed.hostname or "").lower()
        if parsed.scheme != "https" or not (
            host == "dl.google.com"
            or host.endswith(".google.com")
            or host.endswith(".googleusercontent.com")
            or host.endswith(".gvt1.com")
        ):
            raise RuntimeError("Platform-Tools download did not remain on an approved Google HTTPS host.")
        content_length = response.headers.get("Content-Length")
        if content_length and int(content_length) > MAX_ARCHIVE_BYTES:
            raise RuntimeError("Platform-Tools archive exceeds the configured download size limit.")
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_ARCHIVE_BYTES:
                raise RuntimeError("Platform-Tools archive exceeds the configured download size limit.")
            output.write(chunk)
            digest.update(chunk)
        output.flush()
        os.fsync(output.fileno())
    if total == 0:
        raise RuntimeError("Google returned an empty Platform-Tools archive.")
    actual_sha256 = digest.hexdigest()
    if actual_sha256 != expected_sha256.lower():
        raise RuntimeError(
            f"Platform-Tools SHA-256 mismatch: expected {expected_sha256}, received {actual_sha256}."
        )
    return total


def _safe_extract(archive: Path, destination: Path) -> Path:
    destination.mkdir(parents=True, exist_ok=True)
    total_size = 0
    seen: set[str] = set()
    with zipfile.ZipFile(archive) as bundle:
        infos = bundle.infolist()
        if not infos or len(infos) > MAX_ARCHIVE_ENTRIES:
            raise RuntimeError("Platform-Tools archive has an unexpected number of entries.")
        corrupt = bundle.testzip()
        if corrupt is not None:
            raise RuntimeError(f"Platform-Tools archive failed CRC validation: {corrupt}")
        for info in infos:
            raw_name = info.filename
            if "\\" in raw_name or "\x00" in raw_name:
                raise RuntimeError("Platform-Tools archive contains an unsafe path.")
            relative = PurePosixPath(raw_name)
            if relative.is_absolute() or not relative.parts or relative.parts[0] != "platform-tools":
                raise RuntimeError("Platform-Tools archive contains an unexpected top-level path.")
            if any(part in {"", ".", ".."} for part in relative.parts):
                raise RuntimeError("Platform-Tools archive contains a path traversal entry.")
            if any(":" in part for part in relative.parts):
                raise RuntimeError("Platform-Tools archive contains a drive-qualified path.")
            normalized = relative.as_posix().rstrip("/")
            if normalized in seen:
                raise RuntimeError("Platform-Tools archive contains duplicate paths.")
            seen.add(normalized)

            mode = (info.external_attr >> 16) & 0xFFFF
            if stat.S_ISLNK(mode):
                raise RuntimeError("Platform-Tools archive contains a symbolic link.")
            is_directory = info.is_dir()
            if not is_directory:
                total_size += info.file_size
                if total_size > MAX_UNCOMPRESSED_BYTES:
                    raise RuntimeError("Platform-Tools archive exceeds the extraction size limit.")

            target = destination.joinpath(*relative.parts)
            if is_directory:
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with bundle.open(info, "r") as source, target.open("xb") as output:
                shutil.copyfileobj(source, output, length=1024 * 1024)
            permissions = stat.S_IMODE(mode)
            if permissions:
                target.chmod(permissions)
            elif target.name in {"adb", "fastboot"}:
                target.chmod(0o755)

    root = destination / "platform-tools"
    if not root.is_dir():
        raise RuntimeError("Google Platform-Tools archive is missing its platform-tools directory.")
    return root


def _probe_tool(path: Path, args: list[str]) -> str:
    result = subprocess.run(
        [str(path), *args],
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
        creationflags=(getattr(subprocess, "CREATE_NO_WINDOW", 0) if os.name == "nt" else 0),
    )
    output = (result.stdout or "") + "\n" + (result.stderr or "")
    if result.returncode != 0 or PLATFORM_TOOLS_VERSION not in output:
        raise RuntimeError(
            f"Downloaded {path.name} did not report the expected Platform-Tools version "
            f"{PLATFORM_TOOLS_VERSION} (exit {result.returncode})."
        )
    return output.strip()


def _verified_probe(
    probe: Callable[[Path, list[str]], str],
    path: Path,
    args: list[str],
) -> str:
    output = probe(path, args)
    if not isinstance(output, str) or PLATFORM_TOOLS_VERSION not in output:
        raise RuntimeError(
            f"{path.name} did not report the expected Platform-Tools version {PLATFORM_TOOLS_VERSION}."
        )
    return output


def install_platform_tools(
    *,
    license_accepted: bool,
    platform_name: str | None = None,
    install_dir: Path | None = None,
    opener: Callable = urllib.request.urlopen,
    version_probe: Callable[[Path, list[str]], str] | None = None,
) -> dict[str, object]:
    """Download, validate and atomically install the official Google tools."""
    if license_accepted is not True:
        raise PermissionError("You must accept Google's Android SDK license before downloading Platform-Tools.")
    platform_name = platform_name or sys.platform
    if platform_name not in DOWNLOAD_URLS:
        raise RuntimeError("Automatic Platform-Tools installation is currently supported on Windows and macOS.")
    _assert_supported_architecture(platform_name)

    destination = install_dir or managed_platform_tools_dir(platform_name=platform_name)
    adb_name, fastboot_name = _tool_names(platform_name)
    probe = version_probe or _probe_tool

    with _DOWNLOAD_LOCK:
        current = platform_tools_status(platform_name=platform_name, install_dir=destination)
        if current["installed"]:
            try:
                _verified_probe(probe, Path(str(current["adb_path"])), ["version"])
                _verified_probe(probe, Path(str(current["fastboot_path"])), ["--version"])
                return {**current, "already_installed": True, "download_bytes": 0}
            except (OSError, RuntimeError, subprocess.SubprocessError):
                pass

        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(
            prefix=f".platform-tools-{PLATFORM_TOOLS_VERSION}-",
            dir=destination.parent,
        ) as temporary:
            temporary_root = Path(temporary)
            archive = temporary_root / "platform-tools.zip"
            extraction = temporary_root / "extract"
            download_bytes = _download_archive(
                DOWNLOAD_URLS[platform_name],
                archive,
                expected_sha256=PLATFORM_TOOLS_SHA256[platform_name],
                opener=opener,
            )
            extracted_root = _safe_extract(archive, extraction)
            adb = extracted_root / adb_name
            fastboot = extracted_root / fastboot_name
            if not adb.is_file() or not fastboot.is_file():
                raise RuntimeError("Google archive is missing adb or fastboot for this platform.")
            if platform_name == "darwin":
                adb.chmod(adb.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
                fastboot.chmod(fastboot.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
            _verified_probe(probe, adb, ["version"])
            _verified_probe(probe, fastboot, ["--version"])

            backup = destination.parent / f".{destination.name}.previous"
            if backup.is_symlink() or (backup.exists() and not backup.is_dir()):
                backup.unlink()
            elif backup.exists():
                shutil.rmtree(backup)
            moved_old = False
            try:
                if destination.exists():
                    destination.rename(backup)
                    moved_old = True
                extracted_root.rename(destination)
                if moved_old:
                    shutil.rmtree(backup)
            except Exception:
                if moved_old and not destination.exists() and backup.exists():
                    backup.rename(destination)
                raise

        return {
            **platform_tools_status(platform_name=platform_name, install_dir=destination),
            "already_installed": False,
            "download_bytes": download_bytes,
        }
