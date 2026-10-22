import hashlib
import io
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from subprocess import CompletedProcess
from unittest.mock import patch

from src.payload_dumper import (
    BackendError,
    _bundle_root,
    _find_cli,
    _run_process,
    extract,
    inspect_source,
    sha256_file,
)


class BackendTests(unittest.TestCase):
    def test_sha256_matches_known_value(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "sample.img"
            path.write_bytes(b"payload")
            self.assertEqual(sha256_file(str(path)), hashlib.sha256(b"payload").hexdigest())

    def test_missing_input_is_reported_before_backend_lookup(self):
        with tempfile.TemporaryDirectory() as temp:
            missing = Path(temp) / "missing.bin"
            with patch("src.payload_dumper._find_cli", return_value=None) as find_cli:
                with self.assertRaisesRegex(BackendError, "does not exist"):
                    inspect_source(str(missing))
                find_cli.assert_not_called()

    def test_partition_machine_output_parsed_as_kib(self):
        with tempfile.TemporaryDirectory() as temp:
            src = Path(temp) / "payload.bin"
            src.write_bytes(b"stub")
            result = CompletedProcess(
                ["payload-dumper-go"], 0, "boot:65536\nsystem:1024\n", ""
            )
            with patch("src.payload_dumper._run", return_value=result):
                parts = inspect_source(str(src))
        self.assertEqual(
            parts,
            [
                {"name": "boot", "size_bytes": 65536 * 1024, "hash": ""},
                {"name": "system", "size_bytes": 1024 * 1024, "hash": ""},
            ],
        )

    def test_partition_parser_skips_malformed_lines(self):
        with tempfile.TemporaryDirectory() as temp:
            src = Path(temp) / "payload.bin"
            src.write_bytes(b"stub")
            result = CompletedProcess(
                ["payload-dumper-go"],
                0,
                "header text\nboot:2048\nvendor:not-a-size\n:512\nboot,system:1024\n--help:512\n",
                "",
            )
            with patch("src.payload_dumper._run", return_value=result):
                parts = inspect_source(str(src))
        self.assertEqual(
            parts, [{"name": "boot", "size_bytes": 2048 * 1024, "hash": ""}]
        )

    def test_partition_parser_rejects_output_without_valid_partitions(self):
        with tempfile.TemporaryDirectory() as temp:
            src = Path(temp) / "payload.bin"
            src.write_bytes(b"stub")
            result = CompletedProcess(
                ["payload-dumper-go"], 0, "header text\nvendor:not-a-size\n", ""
            )
            with patch("src.payload_dumper._run", return_value=result):
                with self.assertRaisesRegex(BackendError, "no valid partition metadata"):
                    inspect_source(str(src))

    def test_inspect_source_reports_backend_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            src = Path(temp) / "payload.bin"
            src.write_bytes(b"stub")
            result = CompletedProcess(
                ["payload-dumper-go"], 2, "unsupported delta operation", ""
            )
            with patch("src.payload_dumper._run", return_value=result):
                with self.assertRaisesRegex(BackendError, "unsupported delta operation"):
                    inspect_source(str(src))

    def test_extract_rejects_unsupported_extension_before_backend_lookup(self):
        with tempfile.TemporaryDirectory() as temp:
            src = Path(temp) / "firmware.tar"
            src.write_bytes(b"stub")
            with patch("src.payload_dumper._find_cli", return_value=None) as find_cli:
                with self.assertRaisesRegex(BackendError, "payload .bin file or OTA .zip"):
                    extract(str(src), str(Path(temp) / "out"))
                find_cli.assert_not_called()

    def test_extract_missing_input_is_reported_before_backend_lookup(self):
        with tempfile.TemporaryDirectory() as temp:
            missing = Path(temp) / "missing.bin"
            with patch("src.payload_dumper._find_cli", return_value=None) as find_cli:
                with self.assertRaisesRegex(BackendError, "does not exist"):
                    extract(str(missing), str(Path(temp) / "out"))
                find_cli.assert_not_called()

    def test_extract_reports_missing_backend(self):
        with tempfile.TemporaryDirectory() as temp:
            src = Path(temp) / "payload.bin"
            src.write_bytes(b"stub")
            with patch("src.payload_dumper._find_cli", return_value=None):
                with self.assertRaisesRegex(BackendError, "payload-dumper-go was not found"):
                    extract(str(src), str(Path(temp) / "out"))

    def test_extract_reports_backend_exit_code(self):
        class FakeProcess:
            stdout = io.StringIO("backend started\n")
            def wait(self, timeout=None):
                return 3
            def poll(self):
                return 3

        with tempfile.TemporaryDirectory() as temp:
            src = Path(temp) / "payload.bin"
            src.write_bytes(b"stub")
            with patch("src.payload_dumper._find_cli", return_value=["payload-dumper-go"]):
                with patch("src.payload_dumper.subprocess.Popen", return_value=FakeProcess()):
                    with self.assertRaisesRegex(BackendError, "exited with status 3"):
                        extract(str(src), str(Path(temp) / "out"))

    def test_backend_timeout_is_reported_as_backend_error(self):
        timeout = subprocess.TimeoutExpired(["payload-dumper-go"], 12)
        with patch("src.payload_dumper.run_streaming", side_effect=timeout) as runner:
            with self.assertRaisesRegex(BackendError, r"Extraction timed out after 12 seconds"):
                _run_process(["payload-dumper-go"], ["payload.bin"], operation="Extraction", timeout=12)
        self.assertEqual(runner.call_args.kwargs["timeout"], 12)

    def test_timeout_environment_override_is_validated(self):
        from src.payload_dumper import _configured_timeout

        with patch.dict(os.environ, {"DROIDLAB_TEST_TIMEOUT": "42.5"}):
            self.assertEqual(_configured_timeout("DROIDLAB_TEST_TIMEOUT", 10), 42.5)
        with patch.dict(os.environ, {"DROIDLAB_TEST_TIMEOUT": "nan"}):
            self.assertEqual(_configured_timeout("DROIDLAB_TEST_TIMEOUT", 10), 10)
        with patch.dict(os.environ, {"DROIDLAB_TEST_TIMEOUT": "999999"}):
            self.assertEqual(_configured_timeout("DROIDLAB_TEST_TIMEOUT", 10), 86400)

    def test_extract_rejects_empty_output_directory(self):
        with tempfile.TemporaryDirectory() as temp:
            src = Path(temp) / "payload.bin"
            src.write_bytes(b"stub")
            with self.assertRaisesRegex(BackendError, "Choose an output directory"):
                extract(str(src), "   ")

    def test_extract_rejects_invalid_partition_selection(self):
        with tempfile.TemporaryDirectory() as temp:
            src = Path(temp) / "payload.bin"
            src.write_bytes(b"stub")
            with patch("src.payload_dumper._find_cli", return_value=["payload-dumper-go"]):
                with self.assertRaisesRegex(BackendError, "Invalid partition selection"):
                    extract(str(src), str(Path(temp) / "out"), ["boot,system"])

    @unittest.skipIf(os.name == "nt", "AppImage path resolution is Linux-specific")
    def test_frozen_appimage_resolves_appdir_root(self):
        with patch("src.payload_dumper.sys.frozen", True, create=True):
            with patch(
                "src.payload_dumper.sys.executable",
                "/tmp/Payload.AppDir/usr/bin/droidlab-gui-bin",
            ):
                self.assertEqual(_bundle_root(), Path("/tmp/Payload.AppDir"))

    def test_development_bundle_root_is_project_root(self):
        with patch("src.payload_dumper.sys.frozen", False, create=True):
            self.assertEqual(_bundle_root(), Path(__file__).resolve().parent.parent)

    def test_cli_lookup_does_not_claim_uninstalled_backend(self):
        with patch("src.payload_dumper.shutil.which", return_value=None):
            with patch("src.payload_dumper.Path.is_file", return_value=False):
                self.assertIsNone(_find_cli())


class ExtractIsolationTests(unittest.TestCase):
    def test_extract_uses_isolated_outputs_and_ignores_stale_images(self):
        class FakeProcess:
            stdout = io.StringIO("extracted boot\\n")
            def wait(self, timeout=None): return 0
            def poll(self): return 0

        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            src = root / "payload.bin"
            src.write_bytes(b"stub")
            out = root / "out"
            out.mkdir()
            stale = out / "stale.img"
            stale.write_bytes(b"old")
            def fake_popen(command, **kwargs):
                stage = Path(command[command.index("-o") + 1])
                (stage / "boot.img").write_bytes(b"new-image")
                return FakeProcess()
            with patch("src.payload_dumper._find_cli", return_value=["payload-dumper-go"]):
                with patch("src.payload_dumper.subprocess.Popen", side_effect=fake_popen):
                    result = extract(str(src), str(out))
            self.assertEqual(result, [out.resolve() / "boot.img"])
            self.assertEqual((out / "boot.img").read_bytes(), b"new-image")
            self.assertEqual(stale.read_bytes(), b"old")
            self.assertNotIn(stale, result)

    def test_extract_never_overwrites_existing_image(self):
        class FakeProcess:
            stdout = io.StringIO("extracted boot\\n")
            def wait(self, timeout=None): return 0
            def poll(self): return 0

        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            src = root / "payload.bin"
            src.write_bytes(b"stub")
            out = root / "out"
            out.mkdir()
            existing = out / "boot.img"
            existing.write_bytes(b"keep-me")
            def fake_popen(command, **kwargs):
                stage = Path(command[command.index("-o") + 1])
                (stage / "boot.img").write_bytes(b"new-image")
                return FakeProcess()
            with patch("src.payload_dumper._find_cli", return_value=["payload-dumper-go"]):
                with patch("src.payload_dumper.subprocess.Popen", side_effect=fake_popen):
                    with self.assertRaisesRegex(BackendError, "will not be overwritten"):
                        extract(str(src), str(out))
            self.assertEqual(existing.read_bytes(), b"keep-me")


    def test_extract_timeout_is_reported_and_staging_directory_is_removed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            src = root / "payload.bin"
            src.write_bytes(b"stub")
            out = root / "out"
            with patch("src.payload_dumper._find_cli", return_value=["payload-dumper-go"]):
                with patch("src.payload_dumper.run_streaming", side_effect=subprocess.TimeoutExpired(["payload-dumper-go"], 3600)):
                    with self.assertRaisesRegex(BackendError, "Extraction timed out after 3600 seconds"):
                        extract(str(src), str(out))
            self.assertEqual(list(root.glob(".droidlab-extract-*")), [])
            self.assertEqual(list(out.glob("*.img")), [])

    def test_cleanup_failure_does_not_mask_extraction_failure(self):
        class FakeProcess:
            stdout = io.StringIO("backend failed\n")
            def wait(self, timeout=None): return 3
            def poll(self): return 3

        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            src = root / "payload.bin"
            src.write_bytes(b"stub")
            with patch("src.payload_dumper._find_cli", return_value=["payload-dumper-go"]):
                with patch("src.payload_dumper.subprocess.Popen", return_value=FakeProcess()):
                    with patch("src.payload_dumper.shutil.rmtree", side_effect=PermissionError("denied")):
                        with self.assertRaisesRegex(BackendError, "exited with status 3"):
                            extract(str(src), str(root / "out"))

    def test_cleanup_failure_does_not_mask_successful_publication(self):
        class FakeProcess:
            stdout = io.StringIO("extracted boot\n")
            def wait(self, timeout=None): return 0
            def poll(self): return 0

        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            src = root / "payload.bin"
            src.write_bytes(b"stub")
            out = root / "out"
            def fake_popen(command, **kwargs):
                stage = Path(command[command.index("-o") + 1])
                (stage / "boot.img").write_bytes(b"new-image")
                return FakeProcess()
            progress = []
            with patch("src.payload_dumper._find_cli", return_value=["payload-dumper-go"]):
                with patch("src.payload_dumper.subprocess.Popen", side_effect=fake_popen):
                    with patch("src.payload_dumper.shutil.rmtree", side_effect=PermissionError("denied")):
                        result = extract(str(src), str(out), progress=progress.append)
            self.assertEqual(result, [out.resolve() / "boot.img"])
            self.assertTrue(any("Warning: could not remove temporary staging directory" in line for line in progress))


if __name__ == "__main__":
    unittest.main()
