import unittest

from src.command_guards import is_destructive_adb, is_destructive_fastboot, is_valid_partition_name


class AdbGuardTests(unittest.TestCase):
    def test_destructive_adb_commands_are_flagged(self):
        cases = (
            ["adb", "reboot", "bootloader"],
            ["adb", "sideload", "ota.zip"],
            ["adb", "root"],
            ["adb", "remount"],
            ["adb", "uninstall", "com.example.app"],
            ["adb", "-s", "serial", "shell", "rm", "-rf", "/data"],
            ["adb", "shell", "pm", "uninstall", "com.example.app"],
            ["shell", "setprop", "ro.debuggable", "1"],
        )
        for command in cases:
            with self.subTest(command=command):
                self.assertTrue(is_destructive_adb(command))

    def test_safe_adb_commands_are_not_flagged(self):
        for command in (
            ["adb", "devices", "-l"],
            ["adb", "version"],
            ["adb", "shell", "getprop", "ro.build.version.release"],
            ["shell", "ls", "/sdcard"],
        ):
            with self.subTest(command=command):
                self.assertFalse(is_destructive_adb(command))

    def test_nested_shell_wrappers_do_not_hide_destructive_commands(self):
        cases = (
            ["adb", "shell", "sh", "-c", "rm -rf /data"],
            ["adb", "shell", "bash", "-c", "mkfs.ext4 /dev/block/example"],
            ["adb", "shell", "su", "-c", "pm uninstall com.example.app"],
            ["shell", "sh", "-c", "setprop ro.debuggable 1"],
        )
        for command in cases:
            with self.subTest(command=command):
                self.assertTrue(is_destructive_adb(command))

    def test_nested_shell_wrappers_allow_safe_commands(self):
        for command in (
            ["adb", "shell", "sh", "-c", "getprop ro.build.version.release"],
            ["adb", "shell", "su", "-c", "ls /sdcard"],
        ):
            with self.subTest(command=command):
                self.assertFalse(is_destructive_adb(command))


class FastbootGuardTests(unittest.TestCase):
    def test_destructive_fastboot_commands_are_flagged(self):
        cases = (
            ["flash", "boot", "boot.img"],
            ["-w"],
            ["flashall"],
            ["update", "update.zip"],
            ["oem", "unlock"],
            ["flashing", "unlock_critical"],
            ["-s", "serial", "create-logical-partition", "product", "1024"],
            ["erase", "userdata"],
            ["delete-logical-partition", "product"],
        )
        for command in cases:
            with self.subTest(command=command):
                self.assertTrue(is_destructive_fastboot(command))

    def test_safe_fastboot_commands_are_not_flagged(self):
        for command in (["devices"], ["getvar", "product"], ["-s", "serial", "getvar", "all"]):
            with self.subTest(command=command):
                self.assertFalse(is_destructive_fastboot(command))


class PartitionNameTests(unittest.TestCase):
    def test_partition_names_require_alphanumeric_first_character(self):
        self.assertTrue(is_valid_partition_name("boot_a"))
        self.assertTrue(is_valid_partition_name("vendor.img"))
        self.assertFalse(is_valid_partition_name("-userdata"))
        self.assertFalse(is_valid_partition_name("."))
        self.assertFalse(is_valid_partition_name(""))


class DeviceSelectorTests(unittest.TestCase):
    def test_matching_selector_is_returned(self):
        from src.command_guards import explicit_device_selector, validate_device_selector

        self.assertEqual(
            explicit_device_selector(["-s", "device-1", "shell", "getprop"], "adb"), "device-1"
        )
        self.assertEqual(
            validate_device_selector(
                ["-s", "device-1", "flash", "boot", "boot.img"], "fastboot", "device-1"
            ),
            "device-1",
        )

    def test_conflicting_selector_is_rejected(self):
        from src.command_guards import validate_device_selector

        with self.assertRaisesRegex(ValueError, "targets serial"):
            validate_device_selector(["-s", "other", "shell", "getprop"], "adb", "selected")

    def test_repeated_and_malformed_selectors_are_rejected(self):
        from src.command_guards import explicit_device_selector

        for command in (["-s", "one", "-s", "two", "shell"], ["-s"], ["-s", "-d", "shell"]):
            with self.subTest(command=command):
                with self.assertRaises(ValueError):
                    explicit_device_selector(command, "adb")

    def test_shell_arguments_are_not_host_selectors(self):
        from src.command_guards import explicit_device_selector

        self.assertIsNone(
            explicit_device_selector(["shell", "echo", "-s", "not-a-host-selector"], "adb")
        )


class AdbTargetValidationTests(unittest.TestCase):
    def test_target_must_be_present_in_an_allowed_state(self):
        from src.command_guards import is_adb_target_connected

        output = (
            "List of devices attached\n"
            "SERIAL-1 device product:device\n"
            "SERIAL-2 sideload\n"
            "SERIAL-3 unauthorized\n"
            "SERIAL-4 offline\n"
        )
        self.assertTrue(is_adb_target_connected("SERIAL-1", output))
        self.assertTrue(is_adb_target_connected("SERIAL-2", output, allowed_states=("sideload",)))
        self.assertFalse(is_adb_target_connected("SERIAL-3", output))
        self.assertFalse(is_adb_target_connected("SERIAL-4", output))
        self.assertFalse(is_adb_target_connected("SERIAL-1", output, returncode=1))

    def test_missing_or_empty_serial_is_rejected(self):
        from src.command_guards import is_adb_target_connected

        self.assertFalse(is_adb_target_connected("", "SERIAL-1 device"))
        self.assertFalse(is_adb_target_connected("MISSING", "SERIAL-1 device"))


class FastbootTargetValidationTests(unittest.TestCase):
    def test_target_must_be_present_in_successful_fresh_scan(self):
        from src.command_guards import is_fastboot_target_connected

        output = "SERIAL-1 fastboot product:device\nSERIAL-2 fastboot product:other\n"
        self.assertTrue(is_fastboot_target_connected("SERIAL-1", output, 0))
        self.assertFalse(is_fastboot_target_connected("MISSING", output, 0))
        self.assertFalse(is_fastboot_target_connected("SERIAL-1", output, 1))

    def test_other_transport_and_malformed_lines_are_ignored(self):
        from src.command_guards import is_fastboot_target_connected

        output = "SERIAL-1\nSERIAL-2 adb product:device\n"
        self.assertFalse(is_fastboot_target_connected("SERIAL-1", output, 0))
        self.assertFalse(is_fastboot_target_connected("SERIAL-2", output, 0))
