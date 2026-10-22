import subprocess
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

_SRC_ROOT = Path(__file__).resolve().parent.parent / "src"
if str(_SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(_SRC_ROOT))

from droidlab.controllers.fastboot_controller import FastbootControllerMixin


class FastbootPreflightTests(unittest.TestCase):
    def setUp(self):
        self.controller = object()

    @patch("droidlab.controllers.fastboot_controller.messagebox.showerror")
    @patch("droidlab.controllers.fastboot_controller.subprocess.run")
    def test_current_selected_target_is_accepted(self, run, showerror):
        run.return_value = SimpleNamespace(
            stdout="SERIAL-1 fastboot product:device\n",
            returncode=0,
        )

        result = FastbootControllerMixin._ensure_fastboot_target_connected(
            self.controller, "fastboot", "SERIAL-1"
        )

        self.assertTrue(result)
        showerror.assert_not_called()
        run.assert_called_once()
        self.assertEqual(run.call_args.args[0], ["fastboot", "devices", "-l"])
        self.assertEqual(run.call_args.kwargs["timeout"], 4)

    @patch("droidlab.controllers.fastboot_controller.messagebox.showerror")
    @patch("droidlab.controllers.fastboot_controller.subprocess.run")
    def test_missing_target_is_rejected(self, run, showerror):
        run.return_value = SimpleNamespace(
            stdout="OTHER fastboot product:device\n",
            returncode=0,
        )

        result = FastbootControllerMixin._ensure_fastboot_target_connected(
            self.controller, "fastboot", "SERIAL-1"
        )

        self.assertFalse(result)
        showerror.assert_called_once()

    @patch("droidlab.controllers.fastboot_controller.messagebox.showerror")
    @patch("droidlab.controllers.fastboot_controller.subprocess.run")
    def test_failed_scan_is_rejected_even_if_output_contains_target(self, run, showerror):
        run.return_value = SimpleNamespace(
            stdout="SERIAL-1 fastboot product:device\n",
            returncode=1,
        )

        result = FastbootControllerMixin._ensure_fastboot_target_connected(
            self.controller, "fastboot", "SERIAL-1"
        )

        self.assertFalse(result)
        showerror.assert_called_once()

    @patch("droidlab.controllers.fastboot_controller.messagebox.showerror")
    @patch("droidlab.controllers.fastboot_controller.subprocess.run")
    def test_scan_timeout_prevents_command(self, run, showerror):
        run.side_effect = subprocess.TimeoutExpired(["fastboot", "devices", "-l"], 4)

        result = FastbootControllerMixin._ensure_fastboot_target_connected(
            self.controller, "fastboot", "SERIAL-1"
        )

        self.assertFalse(result)
        showerror.assert_called_once()


if __name__ == "__main__":
    unittest.main()
