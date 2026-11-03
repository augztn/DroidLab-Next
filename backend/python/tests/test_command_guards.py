import sys
import unittest
import subprocess
import threading
from unittest.mock import ANY, patch
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from droidlab.core.command_guards import (
    explicit_device_selector,
    is_adb_target_connected,
    is_destructive_adb,
    is_destructive_fastboot,
    is_fastboot_target_connected,
    is_valid_partition_name,
    validate_device_selector,
)
import server


class CommandGuardTests(unittest.TestCase):
    def test_adb_destructive_detection(self):
        self.assertTrue(is_destructive_adb(["shell", "rm", "-rf", "/data"]))
        self.assertTrue(is_destructive_adb(["shell", "sh", "-c", "rm -rf /data"]))
        self.assertTrue(is_destructive_adb(["reboot", "bootloader"]))
        self.assertTrue(is_destructive_adb(["shell", "pm", "clear", "com.example.app"]))
        self.assertTrue(is_destructive_adb(["shell", "cmd", "package", "clear", "com.example.app"]))
        self.assertFalse(is_destructive_adb(["shell", "getprop", "ro.build.version.release"]))

    def test_fastboot_destructive_detection(self):
        self.assertTrue(is_destructive_fastboot(["flash", "boot", "boot.img"]))
        self.assertTrue(is_destructive_fastboot(["-w"]))
        self.assertTrue(is_destructive_fastboot(["flashing", "unlock"]))
        self.assertTrue(is_destructive_fastboot(["oem", "lock"]))
        self.assertTrue(is_destructive_fastboot(["fastboot", "oem", "unlock"]))
        self.assertTrue(is_destructive_fastboot(["--slot", "a", "flash", "boot", "boot.img"]))
        self.assertTrue(is_destructive_fastboot(["--slot=b", "erase", "userdata"]))
        self.assertFalse(is_destructive_fastboot(["--slot", "a", "getvar", "product"]))
        self.assertFalse(is_destructive_fastboot(["getvar", "product"]))

    def test_fastboot_reboot_bootloader_uses_supported_subcommand(self):
        args = {
            "serial": "DEVICE-1",
            "mode": "bootloader",
            "confirmed": True,
            "confirmation": {
                "operation": "fastboot.reboot",
                "serial": "DEVICE-1",
                "mode": "bootloader",
            },
        }
        completed = subprocess.CompletedProcess(["fastboot"], 0, "", "")
        with (
            patch.object(server, "tool_path", return_value="fastboot"),
            patch.object(server, "require_fastboot") as require_fastboot,
            patch.object(server, "run_streaming", return_value=completed) as run_streaming,
        ):
            result = server.execute("reboot-bootloader", "fastboot.reboot", args, threading.Event())

        require_fastboot.assert_called_once_with("DEVICE-1", cancel_event=ANY)
        self.assertEqual(
            run_streaming.call_args.args[0],
            ["fastboot", "-s", "DEVICE-1", "reboot", "bootloader"],
        )
        self.assertEqual(result["exit_code"], 0)

    def test_advanced_adb_commands_use_conservative_mutation_locking(self):
        self.assertTrue(server._device_command_requires_lock(
            "adb.command", {"command_text": "shell getprop ro.build.version.release"}
        ))
        self.assertTrue(server._device_command_requires_lock(
            "adb.command", {"command_text": "install app.apk"}
        ))
        self.assertTrue(server._device_command_requires_lock(
            "adb.command", {"command_text": "future-device-mutating-verb"}
        ))

    def test_advanced_adb_read_only_and_host_commands_skip_device_lock(self):
        for command in ("devices", "version", "logcat -d", "pull /sdcard/log.txt ./"):
            with self.subTest(command=command):
                self.assertFalse(server._device_command_requires_lock(
                    "adb.command", {"command_text": command}
                ))

    def test_fastboot_wipe_flag_never_uses_read_only_lock_classification(self):
        self.assertTrue(server._device_command_requires_lock(
            "fastboot.command", {"command": "-w devices"}
        ))
        self.assertFalse(server._device_command_requires_lock(
            "fastboot.command", {"command": "devices"}
        ))

    def test_fastboot_wipe_flag_requires_target_and_fresh_transport(self):
        args = {
            "serial": "DEVICE-1",
            "command": "-w devices",
            "confirmed": True,
            "confirmation": {
                "operation": "fastboot.command",
                "serial": "DEVICE-1",
                "command": "-w devices",
            },
        }
        completed = subprocess.CompletedProcess(["fastboot"], 0, "ok", "")
        with (
            patch.object(server, "tool_path", return_value="fastboot"),
            patch.object(server, "require_fastboot") as require_fastboot,
            patch.object(server, "run_streaming", return_value=completed) as run_streaming,
            patch.object(server, "response") as emit_response,
        ):
            result = server.execute("wipe-discovery", "fastboot.command", args, threading.Event())

        require_fastboot.assert_called_once_with("DEVICE-1", cancel_event=ANY)
        command = run_streaming.call_args.args[0]
        self.assertEqual(command, ["fastboot", "-s", "DEVICE-1", "-w", "devices"])
        preflight = next(
            call for call in emit_response.call_args_list
            if call.args[1] == "preflight"
        )
        self.assertTrue(preflight.kwargs["destructive"])
        self.assertEqual(result["serial"], "DEVICE-1")

    def test_fastboot_wipe_flag_without_target_is_rejected(self):
        args = {
            "serial": None,
            "command": "-w devices",
            "confirmed": True,
            "confirmation": {
                "operation": "fastboot.command",
                "serial": None,
                "command": "-w devices",
            },
        }
        with self.assertRaisesRegex(ValueError, "Select a Fastboot device"):
            server.execute("wipe-no-target", "fastboot.command", args, threading.Event())

    def test_adb_destructive_detection_covers_shell_wrappers_and_substitutions(self):
        destructive = (
            ["shell", "rm", "--recursive", "--force", "/data"],
            ["shell", "rm", "-r", "-f", "/data"],
            ["shell", "rm", "-f", "-r", "/data"],
            ["shell", "toybox", "rm", "-rf", "/data"],
            ["shell", "busybox", "rm", "-rf", "/data"],
            ["shell", "echo", "$(rm -rf /data)"],
            ["shell", "echo", "`rm -rf /data`"],
            ["shell", "sh", "-c", "echo safe; rm -rf /data"],
            ["shell", "su", "-c", "rm --recursive --force /data"],
            ["shell", "echo", "$(reboot)"],
        )
        for command in destructive:
            with self.subTest(command=command):
                self.assertTrue(is_destructive_adb(command))

        self.assertFalse(is_destructive_adb(["shell", "rm", "-r", "/data/cache"]))
        self.assertFalse(is_destructive_adb(["shell", "getprop", "ro.build.version.release"]))

    def test_partition_validation(self):
        self.assertTrue(is_valid_partition_name("vendor_boot_a"))
        for value in ("", ".", "../userdata", "-boot", "boot/../system"):
            self.assertFalse(is_valid_partition_name(value))

    def test_serial_selector(self):
        self.assertEqual(explicit_device_selector(["-s", "serial-1", "shell"], "adb"), "serial-1")
        with self.assertRaises(ValueError):
            explicit_device_selector(["-s", "one", "-s", "two", "shell"], "adb")
        with self.assertRaises(ValueError):
            validate_device_selector(["-s", "other", "shell"], "adb", "selected")

    def test_transport_states(self):
        adb = "List of devices attached\nSERIAL device product:foo\nRECOVERY recovery\nOFFLINE offline\n"
        self.assertTrue(is_adb_target_connected("SERIAL", adb))
        self.assertFalse(is_adb_target_connected("OFFLINE", adb))
        self.assertTrue(is_adb_target_connected("RECOVERY", adb, allowed_states=("recovery",)))
        self.assertTrue(is_fastboot_target_connected("FB-1", "FB-1 fastboot product:foo\n"))
        self.assertTrue(is_fastboot_target_connected("FB-1", "FB-1 fastbootd usb:3-1\n"))
        self.assertFalse(is_fastboot_target_connected("FB-1", "FB-1 fastboot\n", returncode=1))

    def test_confirmation_is_bound_to_exact_operation_intent(self):
        intent = {"operation": "fastboot.erase", "serial": "DEVICE-1", "partition": "userdata"}
        server.require_confirmation({"confirmed": True, "confirmation": intent}, "Fastboot erase", intent)
        with self.assertRaises(PermissionError):
            server.require_confirmation(
                {"confirmed": True, "confirmation": {**intent, "partition": "boot"}},
                "Fastboot erase",
                intent,
            )

    def test_fastboot_scan_accepts_fastbootd_and_classifies_mode(self):
        devices_output = "1bf3c2b0 fastbootd usb:3-1\n"
        mode_output = subprocess.CompletedProcess(
            ["fastboot"], 0, "", "is-userspace: yes\n"
        )
        with (
            patch.object(server, "tool_path", return_value="fastboot"),
            patch.object(
                server,
                "run_capture",
                side_effect=[
                    subprocess.CompletedProcess(
                        ["fastboot", "devices", "-l"], 0, devices_output, ""
                    ),
                    mode_output,
                ],
            ),
        ):
            devices = server.fastboot_scan()

        self.assertEqual(len(devices), 1)
        self.assertEqual(devices[0]["serial"], "1bf3c2b0")
        self.assertEqual(devices[0]["transport"], "fastboot")
        self.assertEqual(devices[0]["mode"], "fastbootd")

    def test_require_adb_explains_unauthorized_device_without_dispatch(self):
        output = "List of devices attached\n1bf3c2b0 unauthorized usb:1-1\n"
        with (
            patch.object(server, "tool_path", return_value="adb"),
            patch.object(
                server,
                "run_capture",
                return_value=subprocess.CompletedProcess(["adb", "devices", "-l"], 0, output, ""),
            ),
        ):
            with self.assertRaisesRegex(RuntimeError, "accept the.*RSA fingerprint prompt"):
                server.require_adb("1bf3c2b0")


if __name__ == "__main__":
    unittest.main()
