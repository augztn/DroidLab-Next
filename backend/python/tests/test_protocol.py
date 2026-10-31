import json
import os
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
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
                with patch.object(server.shutil, "which", return_value=None):
                    self.assertEqual(server.tool_path("adb"), str(executable))

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

    def test_advanced_fastboot_command_is_serialized_as_mutation(self):
        self.assertIn("fastboot.command", server._MUTATING)

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
        with patch.object(server, "execute", return_value=device_list):
            with patch.object(server, "tool_path", return_value="adb"):
                with patch.object(
                    server, "run_streaming",
                    side_effect=[result(properties), result(battery)],
                ):
                    value = server.execute(
                        "id", "device.info", {"serial": "SERIAL"}, threading.Event()
                    )
        metadata = value["metadata"]
        self.assertEqual(metadata["Brand / Manufacturer"], "Example")
        self.assertEqual(metadata["Device name / Model"], "Unit X")
        self.assertEqual(metadata["Codename"], "unitx")
        self.assertEqual(metadata["Active slot"], "_a")
        self.assertEqual(metadata["Android Version"], "15")
        self.assertEqual(metadata["Battery"], "87%")

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


if __name__ == "__main__":
    unittest.main()
