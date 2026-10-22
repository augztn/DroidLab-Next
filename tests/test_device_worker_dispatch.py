import subprocess
import sys
import threading
import unittest
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch

_SRC_ROOT = Path(__file__).resolve().parent.parent / "src"
if str(_SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(_SRC_ROOT))

from droidlab.controllers.adb_controller import ADBControllerMixin  # noqa: E402
from droidlab.controllers.device_controller import DeviceControllerMixin  # noqa: E402


class DeviceWorkerDispatchTests(unittest.TestCase):
    def test_adb_command_is_blocked_when_fresh_scan_loses_target(self):
        from droidlab.controllers import adb_controller

        controller = Mock()
        controller.events = Mock()
        controller.command_cancel_event = threading.Event()
        probe = subprocess.CompletedProcess(
            ["adb", "devices", "-l"], 0, "List of devices attached\nOTHER device\n", ""
        )
        with (
            patch.object(adb_controller.subprocess, "run", return_value=probe),
            patch.object(adb_controller, "run_streaming") as runner,
        ):
            ADBControllerMixin._stream_process(
                controller, ["adb", "-s", "SERIAL", "shell", "getprop"], 10, "shell"
            )

        runner.assert_not_called()
        self.assertTrue(
            any(
                call.args[0][0] == "adb_result" and call.args[0][1][1] == -1
                for call in controller.events.put.call_args_list
            )
        )

    def test_adb_sideload_preflight_requires_sideload_mode(self):
        from droidlab.controllers import adb_controller

        controller = Mock()
        controller.events = Mock()
        controller.command_cancel_event = threading.Event()
        probe = subprocess.CompletedProcess(
            ["adb", "devices", "-l"], 0, "List of devices attached\nSERIAL device\n", ""
        )
        with (
            patch.object(adb_controller.subprocess, "run", return_value=probe),
            patch.object(adb_controller, "run_streaming") as runner,
        ):
            ADBControllerMixin._stream_process(
                controller, ["adb", "-s", "SERIAL", "sideload", "update.zip"], 10, "sideload"
            )

        runner.assert_not_called()

    def test_device_operation_lock_is_released_when_worker_raises(self):
        lock = threading.Lock()
        controller = Mock()
        controller._active_operations_guard = threading.Lock()
        controller._active_operations = {}
        controller._device_operation_locks_guard = threading.Lock()
        controller._device_operation_locks = {"SERIAL": lock}
        controller._stream_process.side_effect = RuntimeError("simulated worker failure")

        with self.assertRaisesRegex(RuntimeError, "simulated worker failure"):
            ADBControllerMixin._adb_task(
                controller, ["adb", "-s", "SERIAL", "shell", "id"], 5, "shell"
            )

        self.assertTrue(lock.acquire(blocking=False))
        lock.release()
        self.assertEqual(controller._active_operations, {})

    def test_stale_device_info_result_is_ignored(self):
        controller = Mock()
        controller._device_info_request_id = 4

        DeviceControllerMixin._apply_device_info_result(
            controller, 3, ({"Codename": "old"}, "ADB", "#16a34a")
        )

        controller._set_device_info.assert_not_called()

    def test_current_device_info_result_is_applied(self):
        controller = Mock()
        controller._device_info_request_id = 4
        controller._adb_targets = {}
        controller.adb_device.get.return_value = ""
        controller.adb_info_loading = Mock()

        result = ({"Codename": "new"}, "ADB", "#16a34a")
        DeviceControllerMixin._apply_device_info_result(controller, 4, result)

        controller._set_device_info.assert_called_once_with(*result)
        controller.adb_info_loading.set.assert_called_once_with("")

    def test_missing_device_invalidates_inflight_metadata_result(self):
        controller = Mock()
        controller._device_info_request_id = 4
        controller._adb_targets = {}
        controller.adb_device.get.return_value = ""
        controller.adb_info_loading = Mock()

        DeviceControllerMixin._refresh_device_info(controller)

        self.assertEqual(controller._device_info_request_id, 5)
        controller._set_device_info.assert_called_once()
        controller.adb_info_loading.set.assert_called_once_with("")

    def test_device_scan_starts_in_worker_instead_of_blocking_ui(self):
        controller = Mock()
        controller._closing = False
        controller._device_scan_running = False
        controller._device_scan_request_id = 0
        controller.adb_device.get.return_value = "old-adb"
        controller.fastboot_device.get.return_value = "old-fastboot"
        controller.events = Mock()
        controller.adb_device_status = Mock()

        with patch("droidlab.controllers.device_controller.threading.Thread") as thread:
            DeviceControllerMixin._refresh_adb_devices(controller)

        self.assertTrue(controller._device_scan_running)
        thread.assert_called_once()
        thread.return_value.start.assert_called_once_with()

    def test_device_scan_result_updates_both_selectors_and_invalidates_old_info(self):
        controller = Mock()
        controller._device_scan_request_id = 7
        controller._device_scan_running = True
        controller._device_info_request_id = 3
        controller._device_scan_again = False
        controller._closing = False
        controller._adb_targets = {}
        controller.adb_device.get.return_value = ""
        controller.fastboot_device.get.return_value = ""
        controller.adb_device_combo = MagicMock()
        controller.device_combo = MagicMock()
        controller.adb_device_status = Mock()
        controller.device_mode_status = Mock()

        targets = {"serial-1 [Fastboot]": ("serial-1", "fastboot")}
        DeviceControllerMixin._apply_device_scan_result(
            controller, 7, targets, ["ADB: no devices", "Fastboot: serial-1"]
        )

        self.assertFalse(controller._device_scan_running)
        self.assertEqual(controller._device_info_request_id, 4)
        controller.adb_device_combo.__setitem__.assert_called_once_with(
            "values", ["serial-1 [Fastboot]"]
        )
        controller.device_combo.__setitem__.assert_called_once_with("values", ["serial-1"])
        controller._on_shared_device_selected.assert_called_once_with()

    def test_successful_slot_result_writes_lines_and_refreshes_info(self):
        controller = Mock()
        controller._closing = False
        controller.fastboot_console = object()

        DeviceControllerMixin._finish_slot_switch(
            controller, ["requested slot B", "slot switch succeeded"], True
        )

        self.assertEqual(controller._console_write.call_count, 2)
        controller._console_write.assert_any_call(controller.fastboot_console, "requested slot B\n")
        controller._refresh_device_info.assert_called_once_with()

    def test_failed_slot_result_reenables_slot_buttons(self):
        button_a = Mock()
        button_b = Mock()
        controller = Mock()
        controller._closing = False
        controller.fastboot_console = object()
        controller.header_slot_buttons = {"a": button_a, "b": button_b}

        DeviceControllerMixin._finish_slot_switch(controller, ["slot switch failed"], False)

        button_a.configure.assert_called_once_with(state="normal")
        button_b.configure.assert_called_once_with(state="normal")
        controller._refresh_device_info.assert_not_called()

    def test_slot_result_is_ignored_during_shutdown(self):
        controller = Mock()
        controller._closing = True

        DeviceControllerMixin._finish_slot_switch(controller, ["late worker result"], True)

        controller._console_write.assert_not_called()
        controller._refresh_device_info.assert_not_called()


if __name__ == "__main__":
    unittest.main()
