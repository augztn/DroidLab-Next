"""Normalization helpers for user-entered Fastboot command lines."""
from __future__ import annotations

import ntpath
import posixpath


def strip_fastboot_executable(tokens: list[str]) -> list[str]:
    """Accept either Fastboot arguments or a complete fastboot executable command.

    The UI invokes the configured Platform-Tools binary itself. Keeping only the
    arguments prevents accidentally constructing a duplicated executable command
    and supports executable paths copied from Windows, macOS, and Linux terminals.
    """
    if not tokens:
        return []

    executable = tokens[0].strip()
    basename = ntpath.basename(posixpath.basename(executable)).casefold()
    if basename in {"fastboot", "fastboot.exe"}:
        return tokens[1:]
    return tokens
