import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import ANY, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server


def result(stdout="", returncode=0):
    return type("Result", (), {"stdout": stdout, "returncode": returncode})()


class AppManagerProtocolTests(unittest.TestCase):
    def test_apk_install_requires_exact_confirmation(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "sample.apk"
            apk.write_bytes(b"not-a-real-apk")
            with patch.object(server, "require_adb") as require_adb:
                with self.assertRaises(PermissionError):
                    server.execute("request-1", "apps.install", {
                        "serial": "DEVICE-1", "apk_path": str(apk), "replace": True,
                        "confirmed": True,
                    }, threading.Event())
            require_adb.assert_not_called()

    def test_apk_install_uses_argument_vector_and_requires_success(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "sample.apk"
            apk.write_bytes(b"fixture")
            cancel = threading.Event()
            intent = {
                "operation": "apps.install",
                "serial": "DEVICE-1",
                "apk_path": str(apk.resolve()),
                "replace": True,
            }
            with patch.object(server, "require_adb") as require_adb, \
                 patch.object(server, "tool_path", return_value="adb"), \
                 patch.object(server, "run_streaming", return_value=result("Success\n")) as run, \
                 patch.object(server, "response"):
                value = server.execute("request-1", "apps.install", {
                    **intent, "confirmed": True, "confirmation": intent,
                }, cancel)
            self.assertEqual(value["serial"], "DEVICE-1")
            self.assertEqual(value["output"], "Success")
            require_adb.assert_called_once_with("DEVICE-1", cancel_event=cancel)
            run.assert_called_once_with(
                ["adb", "-s", "DEVICE-1", "install", "-r", str(apk.resolve())],
                timeout=300, cancel_event=cancel, on_line=ANY,
            )

    def test_apk_install_rejects_non_apk_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            file_path = Path(directory) / "payload.zip"
            file_path.write_bytes(b"fixture")
            with self.assertRaisesRegex(ValueError, "Android .apk"):
                server.execute("request-1", "apps.install", {
                    "serial": "DEVICE-1", "apk_path": str(file_path),
                    "replace": True, "confirmed": True,
                    "confirmation": {
                        "operation": "apps.install", "serial": "DEVICE-1",
                        "apk_path": str(file_path.resolve()), "replace": True,
                    },
                }, threading.Event())


if __name__ == "__main__":
    unittest.main()
