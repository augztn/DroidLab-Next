"""Resolve tools from explicit configuration, app bundles, then PATH."""
from __future__ import annotations

import json
import os
import shutil
from pathlib import Path
from typing import Any, Iterable


def user_settings() -> dict[str, Any]:
    home = Path(os.environ.get("USERPROFILE") or os.environ.get("HOME") or Path.home())
    config = home / "DroidLab" / "config.json"
    try:
        value = json.loads(config.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def _bundle_roots(bundle_root: Path | None) -> list[Path]:
    """Find plausible bundle roots without assuming a fixed install depth."""
    roots: list[Path] = []
    configured_root = os.environ.get("DROIDLAB_BUNDLE_ROOT", "").strip()
    if configured_root:
        roots.append(Path(configured_root).expanduser())
    if bundle_root is not None:
        roots.append(Path(bundle_root).expanduser())
        roots.extend(Path(bundle_root).expanduser().parents)
    else:
        module = Path(__file__).resolve()
        # The backend is staged at different depths in source, AppImage and
        # macOS app bundles. Walk a bounded number of ancestors instead of
        # relying on a single parents[n] layout assumption.
        roots.extend(list(module.parents)[:9])

    unique: list[Path] = []
    seen: set[str] = set()
    for root in roots:
        try:
            normalized = str(root.resolve())
        except OSError:
            normalized = str(root)
        if normalized not in seen:
            seen.add(normalized)
            unique.append(root)
    return unique


def _bundled_candidates(
    executable_names: Iterable[str],
    roots: Iterable[Path],
) -> list[Path]:
    candidates: list[Path] = []
    for root in roots:
        for executable in executable_names:
            candidates.extend((
                root / executable,
                root / "bin" / executable,
                root / "platform-tools" / executable,
                root / "usr" / "bin" / executable,
                root / "Contents" / "Resources" / "platform-tools" / executable,
                root.parent / "bin" / executable,
                root.parent / "usr" / "bin" / executable,
            ))
    return candidates


def resolve_tool_path(name: str, *, bundle_root: Path | None = None) -> str:
    normalized = name.lower().removesuffix(".exe")
    setting_keys = {
        "python": ("python_path", "python"),
        "python3": ("python_path", "python"),
        "adb": ("adb_path", "adb"),
        "fastboot": ("fastboot_path", "fastboot"),
        "payload-dumper-go": ("payload_dumper_path", "payload_dumper_go"),
    }
    env_keys = {
        "python": ("DROIDLAB_PYTHON", "DROIDLAB_PYTHON_PATH"),
        "python3": ("DROIDLAB_PYTHON", "DROIDLAB_PYTHON_PATH"),
    }.get(
        normalized,
        ("DROIDLAB_" + normalized.upper().replace("-", "_") + "_PATH",),
    )
    configured = next(
        (os.environ.get(key, "").strip() for key in env_keys if os.environ.get(key, "").strip()),
        "",
    )
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

    executable_names = [name]
    if os.name == "nt" and not name.lower().endswith(".exe"):
        executable_names = [name + ".exe", name]
    for candidate in _bundled_candidates(
        executable_names,
        _bundle_roots(bundle_root),
    ):
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
