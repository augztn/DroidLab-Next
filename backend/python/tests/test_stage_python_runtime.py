import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from scripts.stage_python_runtime import discover_install_root


class StagePythonRuntimeTests(unittest.TestCase):
    def test_windows_install_only_layout_uses_python_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "python"
            root.mkdir()
            executable = root / "python.exe"
            executable.write_bytes(b"stub")

            install_root, resolved = discover_install_root(Path(temporary), "win32")

            self.assertEqual(install_root, root)
            self.assertEqual(resolved, executable)

    def test_macos_install_only_layout_uses_bin_python3(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "python"
            binary_dir = root / "bin"
            binary_dir.mkdir(parents=True)
            executable = binary_dir / "python3"
            executable.write_bytes(b"stub")

            install_root, resolved = discover_install_root(Path(temporary), "darwin")

            self.assertEqual(install_root, root)
            self.assertEqual(resolved, executable)

    def test_unexpected_archive_layout_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            nested = Path(temporary) / "python" / "install"
            nested.mkdir(parents=True)
            (nested / "python.exe").write_bytes(b"stub")

            with self.assertRaisesRegex(RuntimeError, "install-only archive layout"):
                discover_install_root(Path(temporary), "win32")


if __name__ == "__main__":
    unittest.main()
