"""Smoke tests for the package extraction boundaries and legacy entrypoints."""
from __future__ import annotations

import ast
import importlib
import importlib.util
import os
import sys
import tkinter as tk
import types
import unittest
from pathlib import Path
from unittest.mock import patch


# Make package imports work from an uninstalled source checkout as well.
_SRC_ROOT = Path(__file__).resolve().parent.parent / "src"
if str(_SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(_SRC_ROOT))


def _install_tkinterdnd2_stub_if_missing() -> None:
    """Allow importing the app class in minimal/headless environments."""
    if "tkinterdnd2" in sys.modules:
        return
    if importlib.util.find_spec("tkinterdnd2") is not None:
        return
    stub = types.ModuleType("tkinterdnd2")
    stub.DND_FILES = "DND_Files"
    stub.TkinterDnD = types.SimpleNamespace(Tk=tk.Tk)
    sys.modules.setdefault("tkinterdnd2", stub)


_install_tkinterdnd2_stub_if_missing()


class PackageImportTests(unittest.TestCase):
    def test_config_core_and_ui_modules_import(self):
        modules = (
            "droidlab.config",
            "droidlab.config.constants",
            "droidlab.config.logging_config",
            "droidlab.config.settings",
            "droidlab.core",
            "droidlab.core.command_guards",
            "droidlab.core.process_runner",
            "droidlab.core.payload_dumper",
            "droidlab.ui",
            "droidlab.ui.theme",
            "droidlab.ui.dialogs",
            "droidlab.ui.widgets",
            "droidlab.ui.layout",
            "droidlab.ui.payload_view",
            "droidlab.ui.adb_view",
            "droidlab.ui.fastboot_view",
            "droidlab.ui.ui_metrics",
        )
        for name in modules:
            with self.subTest(module=name):
                self.assertIsNotNone(importlib.import_module(name))

    def test_payload_app_has_expected_view_and_support_mixins(self):
        app_module = importlib.import_module("app")
        from droidlab.ui.adb_view import ADBViewSupport
        from droidlab.ui.dialogs import DialogSupport
        from droidlab.ui.fastboot_view import FastbootViewSupport
        from droidlab.ui.layout import LayoutSupport
        from droidlab.ui.payload_view import PayloadViewSupport
        from droidlab.ui.theme import ThemeSupport
        from droidlab.ui.widgets import WidgetSupport

        app_class = app_module.PayloadDumperApp
        expected = {
            ThemeSupport: ("_apply_theme", "_walk_widgets", "_open_theme_picker"),
            DialogSupport: ("_show_about",),
            WidgetSupport: ("_configure_widget_styles",),
            LayoutSupport: ("_build", "_show_device_workspace", "_on_shared_device_selected"),
            PayloadViewSupport: ("_build_payload_view",),
            ADBViewSupport: ("_build_adb_tab",),
            FastbootViewSupport: ("_build_flash_tab",),
        }
        for mixin, methods in expected.items():
            with self.subTest(mixin=mixin.__name__):
                self.assertIn(mixin, app_class.__mro__)
                for method in methods:
                    self.assertTrue(callable(getattr(app_class, method, None)), method)
                    self.assertIs(getattr(app_class, method), getattr(mixin, method))

    def test_all_private_callbacks_referenced_by_view_builders_resolve(self):
        app_class = importlib.import_module("app").PayloadDumperApp
        source_root = _SRC_ROOT / "droidlab" / "ui"
        builder_names = {
            "_configure_widget_styles", "_build", "_build_payload_view",
            "_build_adb_tab", "_build_flash_tab",
        }
        for path in source_root.glob("*.py"):
            tree = ast.parse(path.read_text(encoding="utf-8"))
            for node in ast.walk(tree):
                if not isinstance(node, ast.FunctionDef) or node.name not in builder_names:
                    continue
                callbacks = {
                    item.func.attr
                    for item in ast.walk(node)
                    if isinstance(item, ast.Call)
                    and isinstance(item.func, ast.Attribute)
                    and isinstance(item.func.value, ast.Name)
                    and item.func.value.id == "self"
                    and item.func.attr.startswith("_")
                }
                for callback in callbacks:
                    with self.subTest(builder=node.name, callback=callback):
                        self.assertTrue(callable(getattr(app_class, callback, None)), callback)


class BackendPathWiringTests(unittest.TestCase):
    def test_development_bundle_root_remains_project_root(self):
        from droidlab.core.payload_dumper import _bundle_root

        with patch("droidlab.core.payload_dumper.sys.frozen", False, create=True):
            self.assertEqual(_bundle_root(), Path(__file__).resolve().parent.parent)

    def test_appimage_bundle_root_remains_appdir(self):
        from droidlab.core.payload_dumper import _bundle_root

        executable = Path("/tmp/Payload.AppDir/usr/bin/droidlab-gui-bin")
        with patch("droidlab.core.payload_dumper.sys.frozen", True, create=True):
            with patch("droidlab.core.payload_dumper.sys.executable", str(executable)):
                self.assertEqual(_bundle_root(), Path("/tmp/Payload.AppDir"))

    def test_binary_discovery_checks_project_bundle_locations(self):
        from droidlab.core import payload_dumper

        root = Path(__file__).resolve().parent.parent
        binary = root / "opt" / "payload-dumper" / "bin" / "payload-dumper-go"
        with patch.object(payload_dumper, "_bundle_root", return_value=root):
            with patch.object(Path, "is_file", autospec=True, side_effect=lambda path: path == binary):
                with patch.object(os, "access", return_value=True):
                    self.assertEqual(payload_dumper._find_cli(), [str(binary)])


if __name__ == "__main__":
    unittest.main()
