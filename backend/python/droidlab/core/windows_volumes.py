"""Windows removable-volume discovery using the documented Win32 drive APIs."""
from __future__ import annotations

import ctypes
import os
from typing import Any

DRIVE_REMOVABLE = 2


def list_removable_drives(*, kernel32: Any | None = None) -> list[dict[str, str]]:
    """Return only logical volumes whose GetDriveTypeW value is DRIVE_REMOVABLE.

    Fixed disks connected over USB intentionally remain excluded: Windows reports
    those as DRIVE_FIXED, and the UI asks specifically for removable media.
    The injectable kernel32 argument keeps the Win32 boundary unit-testable on
    non-Windows CI hosts.
    """
    if kernel32 is None:
        if os.name != "nt":
            raise OSError("Removable-drive discovery is only available on Windows.")
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

    get_logical_drives = kernel32.GetLogicalDriveStringsW
    get_logical_drives.argtypes = [ctypes.c_uint32, ctypes.POINTER(ctypes.c_wchar)]
    get_logical_drives.restype = ctypes.c_uint32

    required = get_logical_drives(0, None)
    if required == 0:
        raise ctypes.WinError(ctypes.get_last_error())

    buffer = ctypes.create_unicode_buffer(required + 1)
    copied = get_logical_drives(len(buffer), buffer)
    if copied == 0 or copied >= len(buffer):
        raise ctypes.WinError(ctypes.get_last_error())

    get_drive_type = kernel32.GetDriveTypeW
    get_drive_type.argtypes = [ctypes.c_wchar_p]
    get_drive_type.restype = ctypes.c_uint32

    roots = (entry for entry in buffer[:copied].split("\0") if entry)
    drives: list[dict[str, str]] = []
    for root in roots:
        if get_drive_type(root) != DRIVE_REMOVABLE:
            continue
        letter = root[:2].rstrip("\\")
        drives.append({
            "path": root,
            "label": f"Removable drive ({letter})",
        })
    return sorted(drives, key=lambda item: item["path"].casefold())
