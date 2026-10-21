import subprocess
import sys
import threading
import unittest

from src.process_runner import ProcessCancelledError, run_streaming


class ProcessRunnerTests(unittest.TestCase):
    def test_streams_output_and_returns_exit_code(self):
        result = run_streaming(
            [sys.executable, "-c", "print('hello'); print('world')"],
            timeout=5,
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("hello", result.stdout)
        self.assertIn("world", result.stdout)

    def test_timeout_terminates_quiet_process(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            run_streaming(
                [sys.executable, "-c", "import time; time.sleep(10)"],
                timeout=0.2,
            )

    def test_cancel_before_launch_does_not_spawn_process(self):
        cancelled = threading.Event()
        cancelled.set()
        with self.assertRaises(ProcessCancelledError):
            run_streaming(
                [sys.executable, "-c", "print('should not run')"],
                cancel_event=cancelled,
            )

    def test_cancellation_terminates_quiet_process(self):
        cancelled = threading.Event()
        timer = threading.Timer(0.2, cancelled.set)
        timer.start()
        try:
            with self.assertRaises(ProcessCancelledError):
                run_streaming(
                    [sys.executable, "-c", "import time; time.sleep(10)"],
                    timeout=5,
                    cancel_event=cancelled,
                )
        finally:
            timer.cancel()

    def test_retained_output_is_bounded(self):
        result = run_streaming(
            [sys.executable, "-c", "print('x' * 2000)"],
            timeout=5,
            max_output_chars=100,
        )
        self.assertLess(len(result.stdout), 250)
        self.assertIn("additional output line(s) omitted", result.stdout)

    def test_empty_command_is_rejected_before_launch(self):
        with self.assertRaisesRegex(ValueError, "executable"):
            run_streaming([])

    def test_non_finite_or_negative_timeout_is_rejected(self):
        for timeout in (float("nan"), float("inf"), -1):
            with self.subTest(timeout=timeout), self.assertRaises(ValueError):
                run_streaming([sys.executable, "-c", "pass"], timeout=timeout)

    def test_negative_output_limit_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "max_output_chars"):
            run_streaming([sys.executable, "-c", "pass"], max_output_chars=-1)

    def test_non_positive_queue_limit_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "max_queue_lines"):
            run_streaming([sys.executable, "-c", "pass"], max_queue_lines=0)

    def test_non_string_command_argument_is_rejected(self):
        with self.assertRaisesRegex(TypeError, "strings"):
            run_streaming([sys.executable, 1])  # type: ignore[list-item]


if __name__ == "__main__":
    unittest.main()
