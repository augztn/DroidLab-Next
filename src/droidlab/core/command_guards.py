"""Pure command safety checks shared by the UI and unit tests."""

from __future__ import annotations

import re
from pathlib import PurePath

_ADB_DESTRUCTIVE_VERBS = {
    "reboot",
    "sideload",
    "root",
    "unroot",
    "remount",
    "disable-verity",
    "enable-verity",
    "uninstall",
    "erase",
    "format",
    "flash",
    "wipe",
}
_SHELL_DESTRUCTIVE_PATTERNS = (
    re.compile(
        r"(?:^|[;&|]\s*)rm\s+(?:-[a-z]*r[a-z]*f\b|-[a-z]*r\s+-[a-z]*f\b|-[a-z]*f\s+-[a-z]*r\b)",
        re.I,
    ),
    re.compile(
        r"(?:^|[;&|]\s*)(?:mkfs(?:\.[\w-]+)?|dd|reboot|poweroff|shutdown|wipe|format)\b", re.I
    ),
    re.compile(r"(?:^|[;&|]\s*)setprop\b", re.I),
    re.compile(r"(?:^|[;&|]\s*)pm\s+(?:uninstall|disable-user)\b", re.I),
    re.compile(r"(?:^|[;&|]\s*)svc\b[^;&|]*\bdisable\b", re.I),
)
_FASTBOOT_DESTRUCTIVE_VERBS = {
    "flash",
    "flashall",
    "erase",
    "format",
    "wipe",
    "set_active",
    "update",
    "delete-logical-partition",
    "create-logical-partition",
    "resize-logical-partition",
}


def _strip_executable(tokens: list[str], names: set[str]) -> list[str]:
    values = list(tokens)
    if values and PurePath(values[0].strip('"')).name.lower() in names:
        values.pop(0)
    return values


def _skip_device_options(tokens: list[str]) -> list[str]:
    values, index = list(tokens), 0
    takes_value = {"-s", "-t", "-H", "-P", "-L", "-i", "-p", "-c"}
    while index < len(values):
        token = values[index].lower()
        if token in takes_value and index + 1 < len(values):
            index += 2
        elif token in {"-d", "-e"}:
            index += 1
        else:
            break
    return values[index:]


def _is_destructive_shell_text(shell_text: str, depth: int = 0) -> bool:
    """Detect risky shell commands, including common nested shell wrappers.

    This is a warning-oriented heuristic, not a shell parser or security boundary.
    Limit recursion so deliberately nested input cannot cause unbounded work.
    """
    text = shell_text.strip()
    if not text:
        return False
    if any(pattern.search(text) for pattern in _SHELL_DESTRUCTIVE_PATTERNS):
        return True
    if depth >= 4:
        return False

    # Common Android shell wrappers can hide the actual command from the
    # top-level patterns (for example: adb shell sh -c "rm -rf /data").
    wrapper = re.search(
        r"(?:^|[;&|]\\s*)(?:(?:/[^\\s;&|]+/)?(?:sh|bash|ash|dash|mksh|ksh|zsh)|su)"
        r"\\s+(?:-[a-z]*c\\s+|--command(?:=|\\s+))(.+)$",
        text,
        re.IGNORECASE,
    )
    if wrapper:
        nested = wrapper.group(1).strip()
        if len(nested) >= 2 and nested[0] == nested[-1] and nested[0] in {"'", '"'}:
            nested = nested[1:-1]
        return _is_destructive_shell_text(nested, depth + 1)
    return False


def is_destructive_adb(tokens: list[str] | tuple[str, ...]) -> bool:
    """Detect destructive ADB commands without relying on fragile raw-text regexes."""
    values = _skip_device_options(_strip_executable(list(tokens), {"adb", "adb.exe"}))
    if not values:
        return False
    verb = values[0].lower()
    if verb in _ADB_DESTRUCTIVE_VERBS:
        return True
    if verb == "shell":
        return _is_destructive_shell_text(" ".join(values[1:]))
    return False


def is_destructive_fastboot(tokens: list[str] | tuple[str, ...]) -> bool:
    """Detect destructive Fastboot operations, including global flags and unlocks."""
    values = _strip_executable(list(tokens), {"fastboot", "fastboot.exe"})
    if "-w" in (token.lower() for token in values):
        return True
    values = _skip_device_options(values)
    lowered = [token.lower() for token in values]
    if not lowered:
        return False
    verb = lowered[0]
    if verb in _FASTBOOT_DESTRUCTIVE_VERBS:
        return True
    if verb == "oem" and len(lowered) > 1 and lowered[1] == "unlock":
        return True
    return (
        verb == "flashing"
        and len(lowered) > 1
        and lowered[1] in {"unlock", "unlock_critical", "lock", "lock_critical"}
    )


def is_valid_partition_name(name: str) -> bool:
    """Partition names must begin with an ASCII letter or digit."""
    return bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", name))


def explicit_device_selector(tokens: list[str] | tuple[str, ...], tool: str) -> str | None:
    """Return a host-side -s serial selector, rejecting malformed or ambiguous selectors.

    Only leading host options are parsed. Tokens after the subcommand (including
    tokens passed to adb shell) are not interpreted as host options.
    """
    values = list(tokens)
    if values and PurePath(values[0].strip('"')).name.lower() in {
        "adb",
        "adb.exe",
        "fastboot",
        "fastboot.exe",
    }:
        values.pop(0)
    tool_name = tool.lower()
    if tool_name not in {"adb", "fastboot"}:
        raise ValueError("tool must be 'adb' or 'fastboot'")
    selector = None
    index = 0
    takes_value = {"-s"}
    if tool_name == "adb":
        takes_value |= {"-t", "-H", "-P", "-L"}
        no_value = {"-d", "-e"}
    else:
        takes_value |= {"-i", "-p", "-c", "--slot"}
        no_value = {"-w", "-l", "--set-active"}
    while index < len(values):
        token = values[index]
        if token == "--":
            break
        if token.startswith("-s="):
            candidate = token[3:]
            if not candidate:
                raise ValueError("Missing serial after -s")
            index += 1
        elif token == "-s":
            if (
                index + 1 >= len(values)
                or not values[index + 1]
                or values[index + 1].startswith("-")
            ):
                raise ValueError("Missing serial after -s")
            candidate = values[index + 1]
            index += 2
        elif token in takes_value:
            if index + 1 >= len(values) or not values[index + 1]:
                raise ValueError(f"Missing value after {token}")
            index += 2
            continue
        elif token in no_value:
            index += 1
            continue
        elif token.startswith("-"):
            # Unknown host option: stop rather than guessing whether it takes a value.
            break
        else:
            break
        if selector is not None and selector != candidate:
            raise ValueError("Conflicting repeated device serial selectors")
        if selector is not None:
            raise ValueError("Repeated device serial selector is ambiguous")
        selector = candidate
    return selector


def validate_device_selector(
    tokens: list[str] | tuple[str, ...], tool: str, selected_serial: str | None
) -> str | None:
    """Reject explicit target conflicts; return the explicit selector if present."""
    explicit = explicit_device_selector(tokens, tool)
    if explicit is not None and selected_serial and explicit != selected_serial:
        raise ValueError(
            f"Command targets serial {explicit!r}, but the selected device is "
            f"{selected_serial!r}. Select that device explicitly before running the command."
        )
    if explicit is not None and not selected_serial:
        raise ValueError(
            f"Command explicitly targets {explicit!r}, but no matching device is selected."
        )
    return explicit


def is_adb_target_connected(
    serial: str,
    devices_output: str,
    returncode: int = 0,
    allowed_states: tuple[str, ...] = ("device",),
) -> bool:
    """Return whether a successful ADB scan lists serial in an allowed state."""
    if returncode != 0 or not serial:
        return False
    allowed = set(allowed_states)
    for line in devices_output.splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[0] == serial and fields[1] in allowed:
            return True
    return False


def is_fastboot_target_connected(serial: str, devices_output: str, returncode: int = 0) -> bool:
    """Return whether a successful fresh 'fastboot devices -l' scan lists serial."""
    if returncode != 0 or not serial:
        return False
    for line in devices_output.splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[0] == serial and fields[1].lower() == "fastboot":
            return True
    return False
