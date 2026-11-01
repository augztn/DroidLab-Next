"""Resolve Android and Python executables from settings, bundle, then PATH."""
from __future__ import annotations

import json
import os
import shutil
from pathlib import Path
from typing import Any


def user_settings() -> dict[str, Any]:
    home = Path(os.environ.get("USERPROFILE") or os.environ.get("HOME") or Path.home())
    config = home / "DroidLab" / "config.json"
    try:
        value = json.loads(config.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def resolve_tool_path(name: str, *, bundle_root: Path | None = None) -> str:
    normalized = name.lower().removesuffix(".exe")
    setting_keys = {
        "python": ("python_path", "python"),
        "python3": ("python_path", "python"),
        "adb": ("adb_path", "adb"),
        "fastboot": ("fastboot_path", "fastboot"),
        "payload-dumper-go": ("payload_dumper_path", "payload_dumper_go"),
    }
    env_key = "DROIDLAB_" + normalized.upper().replace("-", "_") + "_PATH"
    configured = os.environ.get(env_key, "").strip()
    if not configured:
        settings = user_settings()
        configured = next(
            (
                str(settings.get(key, "")).strip()
                for key in setting_keys.get(normalized, ())
                if isinstance(settings.get(key), str) and settings.get(key, "").strip()
            ),
            "",
        )
    if configured:
        path = Path(configured).expanduser()
        if path.is_file() and (os.name == "nt" or os.access(path, os.X_OK)):
            return str(path.resolve())
        if not path.is_absolute() and len(path.parts) == 1:
            found_configured = shutil.which(configured)
            if found_configured:
                return found_configured
        raise RuntimeError(
            f"Configured {name} path is not an executable file or command on PATH: {path}"
        )

    root = bundle_root or Path(__file__).resolve().parents[4]
    executable_names = [name]
    if os.name == "nt" and not name.lower().endswith(".exe"):
        executable_names = [name + ".exe", name]
    candidates = []
    for executable in executable_names:
        candidates.extend([
            root / executable,
            root / "bin" / executable,
            root / "platform-tools" / executable,
            root / "usr" / "bin" / executable,
        ])
    for candidate in candidates:
        if candidate.is_file() and (os.name == "nt" or os.access(candidate, os.X_OK)):
            return str(candidate.resolve())
    found = shutil.which(name) or (
        shutil.which(name + ".exe") if os.name == "nt" else None
    )
    if not found:
        raise RuntimeError(
            f"{name} was not found in the application bundle, Settings, or PATH."
        )
    return found
