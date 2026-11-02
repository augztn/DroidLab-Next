import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from droidlab.core.windows_volumes import DRIVE_REMOVABLE, list_removable_drives


class FakeFunction:
    def __init__(self, callback):
        self.callback = callback
        self.argtypes = None
        self.restype = None

    def __call__(self, *args):
        return self.callback(*args)


class FakeKernel32:
    def __init__(self, drive_types):
        self.drive_types = drive_types
        self.GetLogicalDriveStringsW = FakeFunction(self._get_logical_drives)
        self.GetDriveTypeW = FakeFunction(lambda root: drive_types[root])

    def _get_logical_drives(self, size, buffer):
        value = chr(0).join(self.drive_types) + chr(0) + chr(0)
        if buffer is None:
            return len(value) - 1
        for index, character in enumerate(value):
            buffer[index] = character
        return len(value) - 1


class WindowsVolumeTests(unittest.TestCase):
    def test_only_drive_removable_volumes_are_returned(self):
        api = FakeKernel32({
            "C:\\": 3,  # DRIVE_FIXED
            "E:\\": DRIVE_REMOVABLE,
            "F:\\": 5,  # DRIVE_CDROM
        })
        self.assertEqual(
            list_removable_drives(kernel32=api),
            [{"path": "E:\\", "label": "Removable drive (E:)"}],
        )

    def test_empty_removable_result_is_valid(self):
        api = FakeKernel32({"C:\\": 3, "D:\\": 4})
        self.assertEqual(list_removable_drives(kernel32=api), [])


if __name__ == "__main__":
    unittest.main()
