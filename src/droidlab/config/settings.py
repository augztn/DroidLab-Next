"""Settings paths and compatible JSON persistence helpers."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def settings_path() -> Path:
    """Return the existing per-user settings file path."""
    return Path.home() / "DroidLab" / "config.json"


def load_settings() -> dict[str, Any]:
    """Load settings, falling back to an empty mapping on invalid or missing files."""
    try:
        value = json.loads(settings_path().read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError, AttributeError):
        return {}


def save_settings(values: dict[str, Any]) -> None:
    """Persist settings to the established path, creating its parent directory."""
    path = settings_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(values, indent=2), encoding="utf-8")


# Legacy-compatible name retained for callers migrating from src/app.py.
_settings_path = settings_path
