import json
import os
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from droidlab.core import tool_resolver
import server


def result(stdout="", returncode=0, stderr=""):
    return type("Result", (), {
        "stdout": stdout,
        "returncode": returncode,
        "stderr": stderr,
    })()


class ProtocolTests(unittest.TestCase):
    def test_ping(self):
        value = server.execute("id", "system.ping", {}, threading.Event())
        self.assertEqual(value["status"], "ok")
        self.assertEqual(value["protocol_version"], 1)

    def test_platform_tools_install_requires_exact_license_confirmation(self):
        with patch.object(server, "install_platform_tools") as install:
            with self.assertRaises(PermissionError):
                server.execute(
                    "id",
                    "system.platform_tools.install",
                    {"confirmed": True, "license_accepted": True},
                    threading.Event(),
                )
            install.assert_not_called()

    def test_platform_tools_install_runs_after_explicit_license_confirmation(self):
        intent = {
            "operation": "system.platform_tools.install",
            "version": server.PLATFORM_TOOLS_VERSION,
            "license_accepted": True,
        }
        expected = {"installed": True, "version": server.PLATFORM_TOOLS_VERSION}
        with patch.object(server, "install_platform_tools", return_value=expected) as install:
            result = server.execute(
                "id",
                "system.platform_tools.install",
                {**intent, "confirmed": True, "confirmation": intent},
                threading.Event(),
            )
        self.assertEqual(result, expected)
        install.assert_called_once_with(license_accepted=True)

    def test_configured_tool_path(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "adb"
            executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            executable.chmod(0o755)
            with patch.dict(os.environ, {"DROIDLAB_ADB_PATH": str(executable)}):
                self.assertEqual(server.tool_path("adb"), str(executable))

    def test_tool_path_reads_legacy_settings_json(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = home / "DroidLab" / "config.json"
            config.parent.mkdir()
            executable = home / "adb"
            executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            executable.chmod(0o755)
            config.write_text(json.dumps({"adb_path": str(executable)}), encoding="utf-8")
            environment = {"HOME": directory, "DROIDLAB_ADB_PATH": ""}
            with patch.dict(os.environ, environment, clear=False):
                with patch.object(tool_resolver.shutil, "which", return_value=None):
                    self.assertEqual(server.tool_path("adb"), str(executable))


    def test_advanced_adb_discovery_command_runs_without_device(self):
        command_text = "devices -l"
        args = {
            "serial": None,
            "command_text": command_text,
            "confirmed": True,
            "confirmation": {
                "operation": "adb.command",
                "serial": None,
                "command_text": command_text,
            },
        }
        with patch.object(server, "tool_path", return_value="adb"):
            with patch.object(server, "run_streaming", return_value=result("SERIAL device\n")) as run:
                with patch.object(server, "response"):
                    value = server.execute("id", "adb.command", args, threading.Event())
        self.assertEqual(value["output"], "SERIAL device\n")
        self.assertEqual(run.call_args.args[0], ["adb", "devices", "-l"])

    def test_advanced_adb_command_injects_selected_serial(self):
        command_text = "install -r app.apk"
        args = {
            "serial": "SERIAL",
            "command_text": command_text,
            "confirmed": True,
            "confirmation": {
                "operation": "adb.command",
                "serial": "SERIAL",
                "command_text": command_text,
            },
        }
        with patch.object(server, "tool_path", return_value="adb"):
            with patch.object(server, "run_capture", return_value=result("List of devices attached\nSERIAL device\n")):
                with patch.object(server, "run_streaming", return_value=result("Success\n")) as run:
                    with patch.object(server, "response"):
                        value = server.execute("id", "adb.command", args, threading.Event())
        self.assertEqual(value["serial"], "SERIAL")
        self.assertEqual(run.call_args.args[0], ["adb", "-s", "SERIAL", "install", "-r", "app.apk"])

    def test_advanced_adb_command_rejects_conflicting_serial(self):
        command_text = "-s OTHER install app.apk"
        args = {
            "serial": "SERIAL",
            "command_text": command_text,
            "confirmed": True,
            "confirmation": {
                "operation": "adb.command",
                "serial": "SERIAL",
                "command_text": command_text,
            },
        }
        with self.assertRaises(ValueError):
            server.execute("id", "adb.command", args, threading.Event())

    def test_advanced_adb_targeted_command_requires_selected_device(self):
        command_text = "install app.apk"
        args = {
            "serial": None,
            "command_text": command_text,
            "confirmed": True,
            "confirmation": {
                "operation": "adb.command",
                "serial": None,
                "command_text": command_text,
            },
        }
        with self.assertRaises(ValueError):
            server.execute("id", "adb.command", args, threading.Event())

    def test_advanced_adb_command_requires_exact_confirmation(self):
        with self.assertRaises(PermissionError):
            server.execute("id", "adb.command", {
                "serial": None,
                "command_text": "devices",
                "confirmed": True,
            }, threading.Event())

    def test_adb_shell_parses_multi_argument_command_text(self):
        command_text = 'getprop ro.build.version.release'
        args = {
            "serial": "SERIAL",
            "command_text": command_text,
            "confirmed": True,
            "confirmation": {
                "operation": "adb.shell",
                "serial": "SERIAL",
                "command_text": command_text,
            },
        }
        with patch.object(server, "tool_path", return_value="adb"):
            with patch.object(server, "run_capture", return_value=result("List of devices attached\nSERIAL device\n")):
                with patch.object(server, "run_streaming", return_value=result("15\n")) as run:
                    with patch.object(server, "response"):
                        value = server.execute("id", "adb.shell", args, threading.Event())
        self.assertEqual(value["output"], "15\n")
        self.assertEqual(run.call_args.args[0], ["adb", "-s", "SERIAL", "shell", "getprop", "ro.build.version.release"])


    def test_fastboot_scan_identifies_fastbootd_from_userspace_flag(self):
        with patch.object(server, "tool_path", return_value="fastboot"):
            with patch.object(server, "run_capture", side_effect=[
                result("FASTBOOT-1 fastboot product:unit\n"),
                result("", 0, "(bootloader) is-userspace: yes\n"),
            ]) as run:
                devices = server.fastboot_scan(threading.Event())
        self.assertEqual(devices[0]["mode"], "fastbootd")
        self.assertEqual(devices[0]["transport"], "fastboot")
        self.assertEqual(run.call_args_list[1].args[0], [
            "fastboot", "-s", "FASTBOOT-1", "getvar", "is-userspace",
        ])

    def test_fastboot_scan_identifies_bootloader_mode(self):
        with patch.object(server, "tool_path", return_value="fastboot"):
            with patch.object(server, "run_capture", side_effect=[
                result("FASTBOOT-1 fastboot\n"),
                result("", 0, "is-userspace: no\n"),
            ]):
                devices = server.fastboot_scan(threading.Event())
        self.assertEqual(devices[0]["mode"], "bootloader")

    def test_fastboot_scan_keeps_device_when_userspace_flag_is_unavailable(self):
        with patch.object(server, "tool_path", return_value="fastboot"):
            with patch.object(server, "run_capture", side_effect=[
                result("FASTBOOT-1 fastboot\n"),
                result("", 1, "FAILED (remote: unknown variable)\n"),
            ]):
                devices = server.fastboot_scan(threading.Event())
        self.assertEqual(len(devices), 1)
        self.assertEqual(devices[0]["mode"], "unknown")

    def test_fastboot_discovery_command_runs_without_device(self):
        command_text = "devices"
        args = {
            "serial": None,
            "command": command_text,
            "confirmed": True,
            "confirmation": {
                "operation": "fastboot.command",
                "serial": None,
                "command": command_text,
            },
        }
        with patch.object(server, "tool_path", return_value="fastboot"):
            with patch.object(server, "run_streaming", return_value=result("FASTBOOT-1 fastboot\n")) as run:
                with patch.object(server, "response"):
                    value = server.execute("id", "fastboot.command", args, threading.Event())
        self.assertIsNone(value["serial"])
        self.assertEqual(run.call_args.args[0], ["fastboot", "devices"])

    def test_fastboot_command_injects_selected_serial(self):
        command_text = "getvar all"
        args = {
            "serial": "FASTBOOT-1",
            "command": command_text,
            "confirmed": True,
            "confirmation": {
                "operation": "fastboot.command",
                "serial": "FASTBOOT-1",
                "command": command_text,
            },
        }
        with patch.object(server, "tool_path", return_value="fastboot"):
            with patch.object(server, "run_capture", return_value=result("FASTBOOT-1 fastboot\n")):
                with patch.object(server, "run_streaming", return_value=result("(bootloader) product: unit\n")) as run:
                    with patch.object(server, "response"):
                        value = server.execute("id", "fastboot.command", args, threading.Event())
        self.assertEqual(value["serial"], "FASTBOOT-1")
        self.assertEqual(run.call_args.args[0], ["fastboot", "-s", "FASTBOOT-1", "getvar", "all"])

    def test_fastbootd_reboot_uses_fastboot_reboot_fastboot(self):
        args = {
            "serial": "SERIAL", "mode": "fastbootd", "confirmed": True,
            "confirmation": {"operation": "fastboot.reboot", "serial": "SERIAL", "mode": "fastbootd"},
        }
        with patch.object(server, "tool_path", return_value="fastboot"):
            with patch.object(server, "run_capture", return_value=result("SERIAL fastboot\n")):
                with patch.object(server, "run_streaming", return_value=result("OKAY\n")) as run:
                    value = server.execute("id", "fastboot.reboot", args, threading.Event())
        self.assertEqual(run.call_args.args[0], ["fastboot", "-s", "SERIAL", "reboot", "fastboot"])
        self.assertIn("fastbootd", value["message"])

    def test_other_active_slot_uses_bootloader_other_selector(self):
        args = {
            "serial": "SERIAL", "slot": "other", "confirmed": True,
            "confirmation": {"operation": "fastboot.set_active", "serial": "SERIAL", "slot": "other"},
        }
        with patch.object(server, "tool_path", return_value="fastboot"):
            with patch.object(server, "run_capture", return_value=result("SERIAL fastboot\n")):
                with patch.object(server, "run_streaming", return_value=result("Setting current slot to 'b'\n")) as run:
                    value = server.execute("id", "fastboot.set_active", args, threading.Event())
        self.assertEqual(run.call_args.args[0], ["fastboot", "-s", "SERIAL", "set_active", "other"])
        self.assertEqual(value["slot"], "other")

    def test_adb_reboot_fastboot_uses_adb_reboot_fastboot(self):
        args = {
            "serial": "SERIAL", "mode": "fastboot", "confirmed": True,
            "confirmation": {"operation": "adb.reboot", "serial": "SERIAL", "mode": "fastboot"},
        }
        with patch.object(server, "tool_path", side_effect=lambda name: name):
            with patch.object(server, "run_capture", return_value=result("List of devices attached\nSERIAL device\n")):
                with patch.object(server, "run_streaming", return_value=result("rebooting into bootloader\n")) as run:
                    server.execute("id", "adb.reboot", args, threading.Event())
        self.assertEqual(run.call_args.args[0], ["adb", "-s", "SERIAL", "reboot", "fastboot"])

    def test_fastboot_partition_discovery_parses_partition_metadata(self):
        args = {"serial": "SERIAL"}
        output = "(bootloader) partition-size:boot_a: 0x04000000\npartition-type:boot_a: raw\n(bootloader) has-slot:boot: yes\n"
        with patch.object(server, "tool_path", return_value="fastboot"):
            with patch.object(server, "run_capture", return_value=result("SERIAL fastboot\n")):
                with patch.object(server, "run_streaming", return_value=result(output)):
                    value = server.execute("id", "fastboot.partitions", args, threading.Event())
        by_name = {item["name"]: item for item in value["partitions"]}
        self.assertEqual(by_name["boot_a"]["size"], "0x04000000")
        self.assertEqual(by_name["boot_a"]["type"], "raw")
        self.assertEqual(by_name["boot"]["has_slot"], "yes")

    def test_fastboot_partition_discovery_requires_connected_device(self):
        with patch.object(server, "tool_path", return_value="fastboot"):
            with patch.object(server, "run_capture", return_value=result("List of devices attached\n")):
                with self.assertRaises(RuntimeError):
                    server.execute("id", "fastboot.partitions", {"serial": "MISSING"}, threading.Event())

    def test_fastboot_targeted_command_requires_selected_device(self):
        with self.assertRaises(ValueError):
            server.execute("id", "fastboot.command", {
                "serial": None,
                "command": "getvar all",
                "confirmed": True,
                "confirmation": {
                    "operation": "fastboot.command",
                    "serial": None,
                    "command": "getvar all",
                },
            }, threading.Event())

    def test_advanced_fastboot_read_only_command_is_not_serialized(self):
        args = {
            "serial": "FASTBOOT-1",
            "command": "getvar product",
            "confirmed": True,
            "confirmation": {
                "operation": "fastboot.command",
                "serial": "FASTBOOT-1",
                "command": "getvar product",
            },
        }
        with patch.object(server, "execute", return_value={"output": "product: unit"}):
            server._DEVICE_LOCKS.clear()
            message = {"id": "readonly", "operation": "fastboot.command", "args": args}
            with patch.object(server, "response"):
                server.handle(message, threading.Event())
        self.assertEqual(server._DEVICE_LOCKS, {})

    def test_advanced_fastboot_mutation_uses_device_lock(self):
        args = {
            "serial": "FASTBOOT-1",
            "command": "erase userdata",
            "confirmed": True,
            "confirmation": {
                "operation": "fastboot.command",
                "serial": "FASTBOOT-1",
                "command": "erase userdata",
            },
        }
        with patch.object(server, "execute", return_value={"exit_code": 0}):
            server._DEVICE_LOCKS.clear()
            message = {"id": "mutation", "operation": "fastboot.command", "args": args}
            with patch.object(server, "response"):
                server.handle(message, threading.Event())
        self.assertIn("FASTBOOT-1", server._DEVICE_LOCKS)

    def test_advanced_adb_read_only_command_is_not_serialized(self):
        args = {
            "serial": "SERIAL",
            "command_text": "pull /sdcard/log.txt ./log.txt",
            "confirmed": True,
            "confirmation": {
                "operation": "adb.command",
                "serial": "SERIAL",
                "command_text": "pull /sdcard/log.txt ./log.txt",
            },
        }
        with patch.object(server, "execute", return_value={"exit_code": 0}):
            server._DEVICE_LOCKS.clear()
            message = {"id": "readonly-adb", "operation": "adb.command", "args": args}
            with patch.object(server, "response"):
                server.handle(message, threading.Event())
        self.assertEqual(server._DEVICE_LOCKS, {})

    def test_advanced_adb_mutating_command_uses_device_lock(self):
        args = {
            "serial": "SERIAL",
            "command_text": "install app.apk",
            "confirmed": True,
            "confirmation": {
                "operation": "adb.command",
                "serial": "SERIAL",
                "command_text": "install app.apk",
            },
        }
        with patch.object(server, "execute", return_value={"exit_code": 0}):
            server._DEVICE_LOCKS.clear()
            message = {"id": "mutation-adb", "operation": "adb.command", "args": args}
            with patch.object(server, "response"):
                server.handle(message, threading.Event())
        self.assertIn("SERIAL", server._DEVICE_LOCKS)

    def test_fastboot_host_discovery_is_not_serialized(self):
        command_text = "devices"
        args = {
            "serial": None,
            "command": command_text,
            "confirmed": True,
            "confirmation": {
                "operation": "fastboot.command",
                "serial": None,
                "command": command_text,
            },
        }
        with patch.object(server, "execute", return_value={"devices": []}):
            server._DEVICE_LOCKS.clear()
            message = {"id": "id", "operation": "fastboot.command", "args": args}
            with patch.object(server, "response"):
                server.handle(message, threading.Event())
        self.assertEqual(server._DEVICE_LOCKS, {})

    def test_logcat_duration_limit_completes_as_success(self):
        args = {
            "serial": "SERIAL",
            "filters": [],
            "timeout_seconds": 3600,
        }
        with patch.object(server, "tool_path", return_value="adb"):
            with patch.object(server, "run_capture", return_value=result("List of devices attached\nSERIAL device\n")):
                with patch.object(server, "run_streaming", side_effect=server.subprocess.TimeoutExpired(["adb"], 3600)) as run:
                    with patch.object(server, "response"):
                        value = server.execute("id", "adb.logcat.start", args, threading.Event())
        self.assertTrue(value["duration_limit_reached"])
        self.assertEqual(value["duration_seconds"], 3600)
        self.assertEqual(run.call_args.kwargs["timeout"], 3600)

    def test_invalid_partition_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "boot.img"
            image.write_bytes(b"image")
            args = {
                "serial": "SERIAL",
                "partition": "../userdata",
                "image_path": str(image),
                "confirmed": True,
            }
            with self.assertRaises(ValueError):
                server.execute("id", "fastboot.flash", args, threading.Event())

    def test_mutation_requires_confirmation(self):
        with self.assertRaises(PermissionError):
            server.require_confirmation({}, "Fastboot flash")

    def test_fastboot_reboot_rejects_unknown_mode(self):
        with self.assertRaises(ValueError):
            server.execute(
                "id", "fastboot.reboot",
                {"serial": "SERIAL", "mode": "unsupported"},
                threading.Event(),
            )

    def test_fastboot_wipe_requires_exact_confirmation(self):
        with self.assertRaises(PermissionError):
            server.execute(
                "id", "fastboot.wipe",
                {"serial": "SERIAL", "confirmed": True},
                threading.Event(),
            )

    def test_fastboot_wipe_is_serialized_as_mutation(self):
        self.assertIn("fastboot.wipe", server._MUTATING)

    def test_advanced_fastboot_command_requires_confirmation(self):
        with self.assertRaises(PermissionError):
            server.execute(
                "id", "fastboot.command",
                {"serial": "SERIAL", "command": "getvar all", "confirmed": True},
                threading.Event(),
            )

    def test_advanced_fastboot_command_rejects_target_override(self):
        with self.assertRaises(ValueError):
            server.execute(
                "id", "fastboot.command",
                {"serial": "SERIAL", "command": "-s OTHER devices"},
                threading.Event(),
            )

    def test_advanced_fastboot_command_locking_is_classified_per_command(self):
        self.assertTrue(server._device_command_requires_lock(
            "fastboot.command",
            {"command": "erase userdata"},
        ))
        self.assertFalse(server._device_command_requires_lock(
            "fastboot.command",
            {"command": "getvar product"},
        ))

    def test_adb_reboot_routes_to_fastboot_in_bootloader(self):
        args = {
            "serial": "SERIAL",
            "mode": "recovery",
            "confirmed": True,
            "confirmation": {
                "operation": "adb.reboot",
                "serial": "SERIAL",
                "mode": "recovery",
            },
        }
        with patch.object(server, "tool_path", side_effect=lambda name: name):
            with patch.object(
                server, "run_capture",
                side_effect=[
                    result("List of devices attached\n"),
                    result("SERIAL fastboot\n"),
                ],
            ):
                with patch.object(server, "run_streaming", return_value=result("OKAY\n")) as run:
                    with patch.object(server, "response"):
                        value = server.execute("id", "adb.reboot", args, threading.Event())
        self.assertEqual(value["transport"], "fastboot")
        self.assertEqual(
            run.call_args.args[0],
            ["fastboot", "-s", "SERIAL", "reboot", "recovery"],
        )

    def test_device_info_reads_adb_and_battery_metadata(self):
        device_list = {
            "devices": [{"serial": "SERIAL", "transport": "adb", "state": "device"}],
            "warnings": [],
        }
        properties = (
            "[ro.product.manufacturer]: [Example]\n"
            "[ro.product.model]: [Unit X]\n"
            "[ro.product.device]: [unitx]\n"
            "[ro.build.version.release]: [15]\n"
            "[ro.build.version.sdk]: [35]\n"
            "[ro.boot.slot_suffix]: [_a]\n"
        )
        battery = "Current Battery Service state:\n  level: 87\n"
        original_execute = server.execute
        def execute_with_device_scan(request_id, operation, args, cancel):
            if operation == "devices.list":
                return device_list
            return original_execute(request_id, operation, args, cancel)

        with patch.object(server, "execute", side_effect=execute_with_device_scan):
            with patch.object(server, "tool_path", return_value="adb"):
                with patch.object(
                    server, "run_streaming",
                    side_effect=[result(properties), result(battery)],
                ):
                    value = original_execute(
                        "id", "device.info", {"serial": "SERIAL"}, threading.Event()
                    )
        metadata = value["metadata"]
        self.assertEqual(metadata["Brand / Manufacturer"], "Example")
        self.assertEqual(metadata["Device name / Model"], "Unit X")
        self.assertEqual(metadata["Codename"], "unitx")
        self.assertEqual(metadata["Active slot"], "_a")
        self.assertEqual(metadata["Android Version"], "15")
        self.assertEqual(metadata["Battery"], "87%")

    def test_device_info_reads_fastboot_metadata_and_detects_fastbootd(self):
        device_list = {
            "devices": [{"serial": "FASTBOOT-1", "transport": "fastboot", "state": "fastboot"}],
            "warnings": [],
        }
        outputs = {
            "product": result("", 0, "product: unitx\n"),
            "manufacturer": result("manufacturer: Example\n"),
            "current-slot": result("", 0, "(bootloader) current-slot: b\n"),
            "unlocked": result("", 0, "unlocked: yes\n"),
            "is-userspace": result("", 0, "is-userspace: yes\n"),
        }
        original_execute = server.execute

        def execute_with_device_scan(request_id, operation, args, cancel):
            if operation == "devices.list":
                return device_list
            return original_execute(request_id, operation, args, cancel)

        with patch.object(server, "execute", side_effect=execute_with_device_scan):
            with patch.object(server, "tool_path", return_value="fastboot"):
                with patch.object(
                    server, "run_streaming",
                    side_effect=lambda command, **kwargs: outputs[command[-1]],
                ):
                    value = original_execute(
                        "id", "device.info", {"serial": "FASTBOOT-1"}, threading.Event()
                    )
        metadata = value["metadata"]
        self.assertEqual(metadata["Model code"], "unitx")
        self.assertEqual(metadata["Brand / Manufacturer"], "Example")
        self.assertEqual(metadata["Active slot"], "b")
        self.assertEqual(metadata["Bootloader"], "Unlocked")
        self.assertEqual(metadata["Mode"], "Fastbootd (userspace Fastboot)")

    def test_fastboot_set_active_requires_exact_confirmation(self):
        with self.assertRaises(PermissionError):
            server.execute(
                "id", "fastboot.set_active",
                {"serial": "SERIAL", "slot": "a", "confirmed": True},
                threading.Event(),
            )

    def test_fastboot_set_active_uses_fallback_syntax(self):
        args = {
            "serial": "SERIAL",
            "slot": "b",
            "confirmed": True,
            "confirmation": {
                "operation": "fastboot.set_active",
                "serial": "SERIAL",
                "slot": "b",
            },
        }
        with patch.object(server, "tool_path", return_value="fastboot"):
            with patch.object(server, "run_capture", return_value=result("SERIAL fastboot\n")):
                with patch.object(
                    server, "run_streaming",
                    side_effect=[result("unknown command\n", 1), result("OKAY\n")],
                ) as run:
                    with patch.object(server, "response"):
                        value = server.execute("id", "fastboot.set_active", args, threading.Event())
        self.assertEqual(value["slot"], "b")
        self.assertEqual(
            run.call_args_list[1].args[0],
            ["fastboot", "-s", "SERIAL", "set_active", "b"],
        )

    def test_fastboot_set_active_is_serialized(self):
        self.assertIn("fastboot.set_active", server._MUTATING)

    def test_backend_has_a_bounded_active_request_limit(self):
        self.assertEqual(server.MAX_ACTIVE_REQUESTS, 8)
        self.assertIsInstance(server._WORKER_SLOTS, threading.BoundedSemaphore)

    def test_device_discovery_does_not_swallow_cancellation(self):
        with patch.object(server, "adb_scan", side_effect=server.ProcessCancelledError("cancelled")):
            with self.assertRaises(server.ProcessCancelledError):
                server.execute("id", "devices.list", {}, threading.Event())

    def test_direct_handle_does_not_release_unacquired_worker_slot(self):
        message = {"id": "direct-handle", "operation": "system.ping", "args": {}}
        with patch.object(server, "response"):
            server.handle(message, threading.Event())
        self.assertEqual(server._WORKER_SLOTS._value, server.MAX_ACTIVE_REQUESTS)


    def test_advanced_adb_command_preserves_quoted_windows_paths(self):
        command_text = 'install -r "C:\\Users\\me\\My Phone\\app.apk"'
        args = {
            "serial": "SERIAL",
            "command_text": command_text,
            "confirmed": True,
            "confirmation": {
                "operation": "adb.command",
                "serial": "SERIAL",
                "command_text": command_text,
            },
        }
        with patch.object(server.os, "name", "nt"):
            with patch.object(server, "tool_path", return_value="adb.exe"):
                with patch.object(server, "run_capture", return_value=result("List of devices attached\nSERIAL device\n")):
                    with patch.object(server, "run_streaming", return_value=result("Success\n")) as run:
                        with patch.object(server, "response"):
                            server.execute("id", "adb.command", args, threading.Event())
        self.assertEqual(
            run.call_args.args[0],
            ["adb.exe", "-s", "SERIAL", "install", "-r", r"C:\Users\me\My Phone\app.apk"],
        )

    def test_debloat_inventory_parses_valid_package_ids_and_system_paths(self):
        output = "package:/system/app/Example/Example.apk=com.example.app\npackage:com.example.user\npackage:invalid package\n"
        disabled = "package:com.example.user\n"
        with patch.object(server, "tool_path", return_value="adb"):
            with patch.object(server, "require_adb"):
                with patch.object(server, "run_streaming", side_effect=[
                    result(output),
                    result(disabled),
                    result(output),
                    result(disabled),
                ]) as run:
                    value = server.execute("id", "debloat.packages.list", {"serial": "SERIAL", "user_id": 0}, threading.Event())
        self.assertEqual([item["package"] for item in value["packages"]], ["com.example.app", "com.example.user"])
        self.assertTrue(value["packages"][0]["system"])
        self.assertFalse(value["packages"][1]["system"])
        self.assertTrue(value["packages"][1]["disabled"])
        self.assertEqual(len(run.call_args_list), 2)

    def test_debloat_apply_requires_exact_confirmation(self):
        with self.assertRaises(PermissionError):
            server.execute("id", "debloat.package.apply", {
                "serial": "SERIAL", "package": "com.example.app", "action": "disable", "user_id": 0, "confirmed": True,
            }, threading.Event())

    def test_debloat_apply_rejects_invalid_package(self):
        with self.assertRaises(ValueError):
            server.execute("id", "debloat.package.apply", {
                "serial": "SERIAL", "package": "com.example;reboot", "action": "disable", "user_id": 0,
            }, threading.Event())

    def test_debloat_operation_is_serialized_per_device(self):
        self.assertIn("debloat.package.apply", server._MUTATING)



class DebloatCatalogTests(unittest.TestCase):
    def test_catalog_has_explanations_and_unique_package_ids(self):
        from droidlab.core.debloat_catalog import load_catalog
        entries, recommendations = load_catalog()
        self.assertGreaterEqual(len(entries), 150)
        self.assertIn("com.android.systemui", entries)
        self.assertIn("com.google.android.gms", entries)
        self.assertIn("org.lineageos.aperture", recommendations)
        for package, entry in entries.items():
            with self.subTest(package=package):
                self.assertTrue(entry.app.strip())
                self.assertTrue(entry.function.strip())
                self.assertTrue(entry.risk.strip())
                self.assertTrue(entry.impact.strip())
        from droidlab.core.debloat_catalog import lookup_guidance
        self.assertEqual(
            lookup_guidance("com.oneplus.membership")["recommendation"],
            "Not recommended — review first",
        )
        self.assertEqual(
            lookup_guidance("org.lineageos.jelly")["recommendation"],
            "Optional — review first",
        )

    def test_core_packages_are_not_recommended_for_removal(self):
        from droidlab.core.debloat_catalog import lookup_guidance
        for package in (
            "com.android.systemui",
            "com.android.settings",
            "com.android.providers.telephony",
            "com.google.android.gms",
            "com.android.phone",
        ):
            value = lookup_guidance(package)
            risk = value["risk"].casefold()
            self.assertTrue("critical" in risk or "high" in risk or "keep" in risk)
            self.assertNotIn("low — optional", value["recommendation"].casefold())

    def test_unlisted_package_is_not_silently_marked_safe(self):
        from droidlab.core.debloat_catalog import lookup_guidance
        value = lookup_guidance("com.example.unknown")
        self.assertFalse(value["listed"])
        self.assertIn("not listed", value["risk"].casefold())
        self.assertIn("not mean safe", value["impact"].casefold())

    def test_catalog_protocol_returns_explainable_entries(self):
        value = server.execute("id", "debloat.catalog.list", {}, threading.Event())
        self.assertEqual(value["schema_version"], 1)
        self.assertGreaterEqual(len(value["entries"]), 150)
        self.assertTrue({"package", "app", "function", "risk", "impact"}.issubset(value["entries"][0]))

    def test_guidance_protocol_returns_exact_package(self):
        value = server.execute("id", "debloat.package.guidance", {"package": "com.android.systemui"}, threading.Event())
        self.assertEqual(value["package"], "com.android.systemui")
        self.assertIn("Critical", value["risk"])

    def test_guidance_protocol_rejects_invalid_package(self):
        with self.assertRaises(ValueError):
            server.execute("id", "debloat.package.guidance", {"package": "com.example;reboot"}, threading.Event())

if __name__ == "__main__":
    unittest.main()
