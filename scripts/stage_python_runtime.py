#!/usr/bin/env python3
"""Stage a checksum-pinned, relocatable CPython runtime into Windows/macOS bundles."""
from __future__ import annotations

import hashlib
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
RELEASE_TAG = "20261026"
PYTHON_VERSION = "3.11.18"
RELEASE_BASE = (
    "https://github.com/astral-sh/python-build-standalone/releases/download/"
    + RELEASE_TAG
)

# Digests are published by the immutable python-build-standalone release.
ASSETS = {
    ("win32", "AMD64"): (
        "cpython-3.11.18+20261026-x86_64-pc-windows-msvc-install_only.tar.gz",
        "75cb501dc11c7b55c6b447c58e4910bce5b1f609f1017328b4f3a858dfaf5428",
    ),
    ("win32", "x86_64"): (
        "cpython-3.11.18+20261026-x86_64-pc-windows-msvc-install_only.tar.gz",
        "75cb501dc11c7b55c6b447c58e4910bce5b1f609f1017328b4f3a858dfaf5428",
    ),
    ("darwin", "arm64"): (
        "cpython-3.11.18+20261026-aarch64-apple-darwin-install_only.tar.gz",
        "cba3455e18516fbe8668cff2820c9b6a53447c552d612443c2b2fb60d390a908",
    ),
    ("darwin", "aarch64"): (
        "cpython-3.11.18+20261026-aarch64-apple-darwin-install_only.tar.gz",
        "cba3455e18516fbe8668cff2820c9b6a53447c552d612443c2b2fb60d390a908",
    ),
    ("darwin", "x86_64"): (
        "cpython-3.11.18+20261026-x86_64-apple-darwin-install_only.tar.gz",
        "a85474bcc78a98ca6b0070d8d615b0494b912b960239e6f18cc12d648f2dc270",
    ),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bundle_destination() -> Path:
    if sys.platform == "win32":
        return (
            ROOT
            / "apps/desktop/build/windows/x64/runner/Release/python"
        )
    if sys.platform == "darwin":
        products = ROOT / "apps/desktop/build/macos/Build/Products/Release"
        applications = sorted(products.glob("*.app"))
        if len(applications) != 1:
            raise SystemExit(
                f"Expected exactly one macOS application under {products}; "
                f"found {len(applications)}."
            )
        return applications[0] / "Contents/Resources/python"
    raise SystemExit(
        "Bundled CPython staging is supported only on Windows and macOS."
    )


def discover_install_root(extraction: Path, platform_name: str) -> tuple[Path, Path]:
    """Resolve the documented install-only archive layout."""
    install_root = extraction / "python"
    executable = (
        install_root / "python.exe"
        if platform_name == "win32"
        else install_root / "bin/python3"
    )
    if not install_root.is_dir() or not executable.is_file():
        raise RuntimeError(
            f"Unexpected CPython install-only archive layout; missing {executable}."
        )
    return install_root, executable


def main() -> None:
    machine = platform.machine()
    asset = ASSETS.get((sys.platform, machine))
    if asset is None:
        raise SystemExit(
            f"No verified CPython {PYTHON_VERSION} runtime for "
            f"{sys.platform}/{machine}."
        )
    filename, expected_digest = asset
    destination = bundle_destination()
    if not destination.parent.is_dir():
        raise SystemExit(f"Application bundle directory is missing: {destination.parent}")

    work_root = ROOT / "build/python-runtime"
    work_root.mkdir(parents=True, exist_ok=True)
    archive = work_root / filename
    url = f"{RELEASE_BASE}/{quote(filename, safe='')}"

    if not archive.is_file() or sha256(archive) != expected_digest:
        partial = archive.with_suffix(archive.suffix + ".download")
        last_error: Exception | None = None
        try:
            for attempt in range(8):
                try:
                    request = urllib.request.Request(
                        url, headers={"User-Agent": "DroidLab-runtime-stager"}
                    )
                    with urllib.request.urlopen(request, timeout=180) as response:
                        with partial.open("wb") as output:
                            shutil.copyfileobj(response, output)
                    actual_digest = sha256(partial)
                    if actual_digest != expected_digest:
                        raise RuntimeError(
                            f"CPython archive checksum mismatch: expected "
                            f"{expected_digest}, got {actual_digest}"
                        )
                    partial.replace(archive)
                    last_error = None
                    break
                except urllib.error.HTTPError as error:
                    if error.code < 500 and error.code != 429:
                        raise
                    last_error = error
                except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
                    last_error = error
                finally:
                    if partial.exists():
                        partial.unlink()
                if last_error is not None and attempt < 7:
                    delay = min((attempt + 1) * 5, 30)
                    print(
                        f"CPython download attempt {attempt + 1}/8 failed "
                        f"({last_error}); retrying in {delay}s.",
                        file=sys.stderr,
                    )
                    time.sleep(delay)
            if last_error is not None:
                raise RuntimeError(
                    f"Unable to download verified CPython runtime after 8 attempts: "
                    f"{last_error}"
                ) from last_error
        finally:
            if partial.exists():
                partial.unlink()

    with tempfile.TemporaryDirectory(prefix="droidlab-python-") as temporary:
        extraction = Path(temporary)
        subprocess.run(
            ["tar", "-xzf", str(archive), "-C", str(extraction)],
            check=True,
        )
        install_root, executable = discover_install_root(extraction, sys.platform)
        probe = subprocess.run(
            [
                str(executable),
                "-c",
                "import json, ssl, subprocess, sys; "
                "assert sys.version_info >= (3, 11); "
                "print(sys.version.split()[0])",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        staged = destination.with_name(destination.name + ".staging")
        backup = destination.with_name(destination.name + ".previous")
        if staged.exists():
            shutil.rmtree(staged)
        if backup.exists():
            shutil.rmtree(backup)
        shutil.copytree(install_root, staged)
        moved_existing = False
        try:
            if destination.exists():
                destination.rename(backup)
                moved_existing = True
            staged.rename(destination)
        except Exception:
            if moved_existing and not destination.exists() and backup.exists():
                backup.rename(destination)
            raise
        finally:
            if staged.exists():
                shutil.rmtree(staged)
        if backup.exists():
            shutil.rmtree(backup)

    print(
        f"Staged CPython {probe.stdout.strip()} for {sys.platform}/{machine}: "
        f"{destination}"
    )


if __name__ == "__main__":
    main()
