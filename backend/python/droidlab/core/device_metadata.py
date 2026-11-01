"""Pure parsers for Android property and Fastboot metadata output."""
from __future__ import annotations

import re


def parse_getprop_output(output: str) -> dict[str, str]:
    """Parse Android getprop's bracketed key/value lines."""
    properties: dict[str, str] = {}
    for line in output.splitlines():
        if not line.startswith("[") or "]: [" not in line:
            continue
        key, value = line[1:].split("]: [", 1)
        properties[key] = value[:-1] if value.endswith("]") else value
    return properties


def first_property(properties: dict[str, str], *keys: str) -> str:
    """Return the first non-empty property in priority order."""
    return next((properties.get(key, "") for key in keys if properties.get(key)), "")


def parse_battery_level(output: str) -> int | None:
    """Return a valid Android battery percentage, if present."""
    match = re.search(r"(?m)^\s*level:\s*(\d+)\s*$", output)
    if match is None:
        return None
    level = int(match.group(1))
    return level if 0 <= level <= 100 else None


def parse_fastboot_getvar(output: str, key: str) -> str:
    """Extract a Fastboot getvar value across common platform-tools output formats.

    Fastboot versions and vendor implementations vary in how they decorate
    informational lines. Accept the standard bootloader prefix, INFO prefix,
    and timestamp prefix while still requiring the requested key at the start
    of the metadata payload.
    """
    pattern = re.compile(
        r"(?im)^\s*(?:(?:\(bootloader\)|INFO:?)\s*)?"
        r"(?:\[[^\]]+\]\s*)?"
        + re.escape(key)
        + r"\s*:\s*(.*?)\s*$"
    )
    match = pattern.search(output)
    return match.group(1).strip() if match else ""
