import unittest

from droidlab.core.fastboot_command import strip_fastboot_executable


class FastbootCommandTests(unittest.TestCase):
    def test_arguments_without_executable_are_preserved(self):
        self.assertEqual(
            strip_fastboot_executable(["getvar", "all"]),
            ["getvar", "all"],
        )

    def test_full_fastboot_command_is_normalized(self):
        self.assertEqual(
            strip_fastboot_executable(["fastboot", "getvar", "all"]),
            ["getvar", "all"],
        )

    def test_windows_executable_path_is_normalized(self):
        self.assertEqual(
            strip_fastboot_executable(
                [r"C:\Android\platform-tools\fastboot.exe", "-s", "ABC", "devices"]
            ),
            ["-s", "ABC", "devices"],
        )

    def test_unrelated_executable_is_not_silently_removed(self):
        self.assertEqual(
            strip_fastboot_executable(["adb", "devices"]),
            ["adb", "devices"],
        )

    def test_empty_input_is_safe(self):
        self.assertEqual(strip_fastboot_executable([]), [])


if __name__ == "__main__":
    unittest.main()
