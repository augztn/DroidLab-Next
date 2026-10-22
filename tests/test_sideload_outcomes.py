import sys
import unittest
from pathlib import Path

_SRC_ROOT = Path(__file__).resolve().parent.parent / "src"
if str(_SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(_SRC_ROOT))

from droidlab.core.operation_outcomes import sideload_result_message  # noqa: E402


class SideloadOutcomeMessageTests(unittest.TestCase):
    def test_success_does_not_claim_device_verified_update(self):
        title, message = sideload_result_message(0, "Total xfer: 1.00x")

        self.assertEqual(title, "Sideload complete")
        self.assertIn("does not verify", message)
        self.assertIn("Total xfer: 1.00x", message)

    def test_nonzero_exit_warns_against_immediate_retry(self):
        title, message = sideload_result_message(1, "device disconnected")

        self.assertEqual(title, "Sideload outcome uncertain")
        self.assertIn("does not prove that no changes were made", message)
        self.assertIn("Do not immediately retry", message)
        self.assertIn("device disconnected", message)

    def test_empty_output_is_reported_explicitly(self):
        title, message = sideload_result_message(-1, "  ")

        self.assertEqual(title, "Sideload outcome uncertain")
        self.assertIn("No command output was captured", message)
        self.assertIn("exit status -1", message)


if __name__ == "__main__":
    unittest.main()
