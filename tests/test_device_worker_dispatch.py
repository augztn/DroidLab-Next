import sys
import unittest
from pathlib import Path
from unittest.mock import Mock

_SRC_ROOT = Path(__file__).resolve().parent.parent / "src"
if str(_SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(_SRC_ROOT))

from droidlab.controllers.device_controller import DeviceControllerMixin  # noqa: E402


class DeviceWorkerDispatchTests(unittest.TestCase):
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
        controller.adb_info_loading = Mock()

        result = ({"Codename": "new"}, "ADB", "#16a34a")
        DeviceControllerMixin._apply_device_info_result(controller, 4, result)

        controller._set_device_info.assert_called_once_with(*result)
        controller.adb_info_loading.set.assert_called_once_with("")

    def test_successful_slot_result_writes_lines_and_refreshes_info(self):
        controller = Mock()
        controller._closing = False
        controller.fastboot_console = object()

        DeviceControllerMixin._finish_slot_switch(
            controller, ["requested slot B", "slot switch succeeded"], True
        )

        self.assertEqual(controller._console_write.call_count, 2)
        controller._console_write.assert_any_call(
            controller.fastboot_console, "requested slot B\n"
        )
        controller._refresh_device_info.assert_called_once_with()

    def test_failed_slot_result_reenables_slot_buttons(self):
        button_a = Mock()
        button_b = Mock()
        controller = Mock()
        controller._closing = False
        controller.fastboot_console = object()
        controller.header_slot_buttons = {"a": button_a, "b": button_b}

        DeviceControllerMixin._finish_slot_switch(
            controller, ["slot switch failed"], False
        )

        button_a.configure.assert_called_once_with(state="normal")
        button_b.configure.assert_called_once_with(state="normal")
        controller._refresh_device_info.assert_not_called()

    def test_slot_result_is_ignored_during_shutdown(self):
        controller = Mock()
        controller._closing = True

        DeviceControllerMixin._finish_slot_switch(
            controller, ["late worker result"], True
        )

        controller._console_write.assert_not_called()
        controller._refresh_device_info.assert_not_called()


if __name__ == "__main__":
    unittest.main()
