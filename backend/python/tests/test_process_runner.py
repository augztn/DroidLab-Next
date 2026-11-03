"""Regression tests for bounded subprocess execution."""
import sys
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from droidlab.core.process_runner import ProcessCancelledError, run_streaming


class ProcessRunnerTests(unittest.TestCase):
    def test_capture_output(self):
        result = run_streaming([sys.executable, "-c", "print('ready')"], timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertIn("ready", result.stdout)

    def test_popen_kwargs_cannot_override_protocol_streams_or_session(self):
        with self.assertRaisesRegex(ValueError, "reserved Popen option"):
            run_streaming(
                [sys.executable, "-c", "print('no')"],
                popen_kwargs={"stdout": None},
            )

    def test_popen_kwargs_cannot_override_stdin(self):
        with self.assertRaisesRegex(ValueError, "reserved Popen option"):
            run_streaming(
                [sys.executable, "-c", "print('no')"],
                popen_kwargs={"stdin": None},
            )

    def test_popen_kwargs_cannot_override_text_decoding(self):
        with self.assertRaisesRegex(ValueError, "reserved Popen option"):
            run_streaming(
                [sys.executable, "-c", "print('no')"],
                popen_kwargs={"text": False},
            )

    def test_popen_kwargs_cannot_override_process_session(self):
        with self.assertRaisesRegex(ValueError, "reserved Popen option"):
            run_streaming(
                [sys.executable, "-c", "print('no')"],
                popen_kwargs={"start_new_session": False},
            )

    def test_cancel_before_launch(self):
        event = threading.Event()
        event.set()
        with self.assertRaises(ProcessCancelledError):
            run_streaming([sys.executable, "-c", "print('no')"], cancel_event=event)

    def test_cancellation_terminates_running_process(self):
        event = threading.Event()
        timer = threading.Timer(0.2, event.set)
        timer.start()
        try:
            with self.assertRaises(ProcessCancelledError):
                run_streaming(
                    [sys.executable, "-c", "import time; time.sleep(20)"],
                    timeout=5,
                    cancel_event=event,
                )
        finally:
            timer.cancel()
            timer.join(timeout=1)

    def test_output_retention_is_bounded(self):
        result = run_streaming(
            [sys.executable, "-c", "print('x' * 10000)"],
            timeout=5,
            max_output_chars=128,
        )
        self.assertLess(len(result.stdout), 256)
        self.assertIn("omitted", result.stdout)

    def test_default_output_retention_fits_backend_protocol_budget(self):
        result = run_streaming(
            [sys.executable, "-c", "import sys; sys.stdout.write('\\\\x01' * (256 * 1024))"],
            timeout=5,
        )
        self.assertLessEqual(len(result.stdout), 64 * 1024 + 128)
        self.assertIn("additional output chunk(s) omitted", result.stdout)

    def test_long_output_line_is_read_in_bounded_chunks(self):
        result = run_streaming(
            [sys.executable, "-c", "import sys; sys.stdout.write('x' * 50000)"],
            timeout=5,
            max_output_chars=60000,
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(len(result.stdout), 50000)

    def test_queue_overflow_is_reported(self):
        result = run_streaming(
            [
                sys.executable,
                "-c",
                "import sys; [sys.stdout.write(str(i) + '\\n') for i in range(20000)]",
            ],
            timeout=5,
            max_queue_lines=4,
            max_output_chars=2 * 1024 * 1024,
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("omitted", result.stdout)

    def test_callback_exception_terminates_process(self):
        def fail(_line):
            raise RuntimeError("consumer failed")

        with self.assertRaisesRegex(RuntimeError, "consumer failed"):
            run_streaming(
                [sys.executable, "-c", "import time; print('start', flush=True); time.sleep(20)"],
                timeout=5,
                on_line=fail,
            )


if __name__ == "__main__":
    unittest.main()
