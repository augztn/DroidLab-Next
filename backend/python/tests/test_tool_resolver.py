import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from droidlab.core.tool_resolver import resolve_tool_path


class ToolResolverTests(unittest.TestCase):
    def test_explicit_environment_path_has_precedence(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "adb"
            executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            executable.chmod(0o755)
            with patch.dict(os.environ, {"DROIDLAB_ADB_PATH": str(executable)}):
                self.assertEqual(resolve_tool_path("adb"), str(executable.resolve()))

    def test_settings_path_is_used_when_environment_override_is_blank(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / "platform-tools" / "fastboot"
            executable.parent.mkdir()
            executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            executable.chmod(0o755)
            config_dir = root / "home" / "DroidLab"
            config_dir.mkdir(parents=True)
            (config_dir / "config.json").write_text(
                json.dumps({"fastboot_path": str(executable)}), encoding="utf-8"
            )
            with patch.dict(os.environ, {
                "HOME": str(root / "home"),
                "DROIDLAB_FASTBOOT_PATH": "",
            }):
                self.assertEqual(
                    resolve_tool_path("fastboot"),
                    str(executable.resolve()),
                )

    def test_invalid_explicit_path_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            missing = str(Path(directory) / "missing-adb")
            with patch.dict(os.environ, {"DROIDLAB_ADB_PATH": missing}):
                with self.assertRaisesRegex(RuntimeError, "Configured adb path"):
                    resolve_tool_path("adb")

    def test_appimage_usr_bin_is_found_from_usr_lib_backend(self):
        with tempfile.TemporaryDirectory() as directory:
            appdir = Path(directory) / "AppDir"
            backend_root = appdir / "usr" / "lib"
            executable = appdir / "usr" / "bin" / "adb"
            executable.parent.mkdir(parents=True)
            executable.write_text("#!/bin/sh\\nexit 0\\n", encoding="utf-8")
            executable.chmod(0o755)
            with patch.dict(os.environ, {"DROIDLAB_ADB_PATH": "", "PATH": ""}):
                self.assertEqual(
                    resolve_tool_path("adb", bundle_root=backend_root),
                    str(executable.resolve()),
                )

    def test_bundle_candidates_precede_path_lookup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / "platform-tools" / "adb"
            executable.parent.mkdir()
            executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            executable.chmod(0o755)
            with patch.dict(os.environ, {"DROIDLAB_ADB_PATH": "", "PATH": ""}):
                self.assertEqual(
                    resolve_tool_path("adb", bundle_root=root),
                    str(executable.resolve()),
                )


if __name__ == "__main__":
    unittest.main()
