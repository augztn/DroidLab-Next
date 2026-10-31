#!/usr/bin/env python3
"""Copy the headless Python backend beside the native Flutter desktop bundle."""
from __future__ import annotations
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if sys.platform == "linux":
    bundle = ROOT / "apps/desktop/build/linux/x64/release/bundle"
    destination = bundle / "backend/python"
elif sys.platform == "win32":
    bundle = ROOT / "apps/desktop/build/windows/x64/runner/Release"
    destination = bundle / "backend/python"
elif sys.platform == "darwin":
    products = ROOT / "apps/desktop/build/macos/Build/Products/Release"
    applications = sorted(products.glob("*.app"))
    if not applications:
        raise SystemExit(f"macOS application bundle not found under: {products}")
    bundle = applications[0] / "Contents/Resources"
    destination = bundle / "backend/python"
else:
    raise SystemExit(f"Unsupported staging platform: {sys.platform}")

source = ROOT / "backend/python"
if not bundle.is_dir():
    raise SystemExit(f"Flutter release bundle not found: {bundle}")
destination.parent.mkdir(parents=True, exist_ok=True)
if destination.exists():
    shutil.rmtree(destination)
shutil.copytree(source, destination, ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "tests"))
print(f"Staged backend: {destination}")
