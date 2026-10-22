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
from pathlib import Path, PurePosixPath
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
            "droidlab.ui.main_window",
            "droidlab.ui.ui_metrics",
            "droidlab.controllers",
            "droidlab.controllers.device_controller",
            "droidlab.controllers.adb_controller",
            "droidlab.controllers.fastboot_controller",
            "droidlab.controllers.payload_controller",
        )
        for name in modules:
            with self.subTest(module=name):
                self.assertIsNotNone(importlib.import_module(name))

    def test_theme_widget_walk_supports_instance_call_and_nested_widgets(self):
        from droidlab.ui.theme import ThemeSupport

        class Widget:
            def __init__(self, *children):
                self.children = list(children)

            def winfo_children(self):
                return self.children

        grandchild = Widget()
        child = Widget(grandchild)
        root = Widget(child)
        self.assertEqual(list(ThemeSupport()._walk_widgets(root)), [child, grandchild])

    def test_payload_app_has_expected_view_and_support_mixins(self):
        app_module = importlib.import_module("app")
        from droidlab.controllers.adb_controller import ADBControllerMixin
        from droidlab.controllers.device_controller import DeviceControllerMixin
        from droidlab.controllers.fastboot_controller import FastbootControllerMixin
        from droidlab.controllers.payload_controller import PayloadControllerMixin
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
            DeviceControllerMixin: (
                "_refresh_adb_devices", "_refresh_device_info", "_adb_read_value",
                "_fastboot_getvar", "_set_active_slot",
            ),
            ADBControllerMixin: (
                "_adb_task", "_run_adb_shell", "_run_adb_sideload", "_start_adb_logcat",
                "_create_adb_bugreport", "_stream_process",
            ),
            FastbootControllerMixin: (
                "_run_fastboot_manual", "_flash_image", "_run_fastboot_maintenance",
                "_fastboot_quick_action",
            ),
            PayloadControllerMixin: (
                "_inspect", "_inspect_worker", "_load_parts", "_start", "_extract_worker",
                "_cancel", "_browse_source",
            ),
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


    def test_all_droidlab_modules_are_syntax_valid_and_importable(self):
        import pkgutil
        package = importlib.import_module("droidlab")
        discovered = sorted(
            item.name for item in pkgutil.walk_packages(package.__path__, package.__name__ + ".")
        )
        self.assertIn("droidlab.ui.main_window", discovered)
        for name in discovered:
            with self.subTest(module=name):
                spec = importlib.util.find_spec(name)
                self.assertIsNotNone(spec)
                if spec and spec.origin and spec.origin.endswith(".py"):
                    ast.parse(Path(spec.origin).read_text(encoding="utf-8"), filename=spec.origin)
                self.assertIsNotNone(importlib.import_module(name))

    def test_all_pyinstaller_commands_collect_droidlab_submodules(self):
        project_root = _SRC_ROOT.parent
        candidates = [
            project_root / "scripts" / "build-linux.sh",
            project_root / ".github" / "workflows" / "linux.yml",
            project_root / ".github" / "workflows" / "windows.yml",
            project_root / ".github" / "workflows" / "cross-platform-bundle.yml",
        ]
        for path in candidates:
            source = path.read_text(encoding="utf-8")
            if "PyInstaller" in source:
                with self.subTest(file=str(path.relative_to(project_root))):
                    self.assertIn("--collect-submodules droidlab", source)
                    self.assertIn("--paths src", source)

    def test_tool_path_searches_project_root_after_main_window_move(self):
        from unittest.mock import patch
        main_window = importlib.import_module("droidlab.ui.main_window")
        seen = []
        def record_candidate(candidate):
            seen.append(candidate)
            return False
        with patch.object(main_window.Path, "is_file", record_candidate), patch.object(
            main_window.shutil, "which", return_value=None
        ):
            result = main_window.PayloadDumperApp._tool_path(object(), "adb")
        project_root = _SRC_ROOT.parent
        self.assertIsNone(result)
        self.assertEqual(seen, [project_root / "bin" / "adb", project_root / "platform-tools" / "adb"])


class ControllerSafetyCharacterizationTests(unittest.TestCase):
    def test_payload_log_append_is_safe_before_log_widget_initialization(self):
        from droidlab.controllers.payload_controller import PayloadControllerMixin

        # During startup, DnD registration can fail before the UI creates self.log.
        PayloadControllerMixin._append(object(), "early startup diagnostic")

    def test_fastboot_destructive_validation_precedes_confirmation_and_spawn(self):
        source = (_SRC_ROOT / "droidlab" / "controllers" / "fastboot_controller.py").read_text(encoding="utf-8")
        tree = ast.parse(source)
        cls = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "FastbootControllerMixin")
        for method_name in ("_run_fastboot_manual", "_flash_image", "_run_fastboot_maintenance"):
            node = next(node for node in cls.body if isinstance(node, ast.FunctionDef) and node.name == method_name)
            text = ast.get_source_segment(source, node)
            # Preserve the existing command guard / confirmation flow before a command can start.
            spawn_positions = [pos for token in ("subprocess.Popen(", "threading.Thread(") if (pos := text.find(token)) >= 0]
            if not spawn_positions:
                continue
            spawn = min(spawn_positions)
            guard_positions = [pos for token in ("is_destructive_fastboot(", "validate_device_selector(", "is_fastboot_target_connected(") if (pos := text.find(token)) >= 0]
            confirmation_positions = [pos for token in ("messagebox.askyesno(", "messagebox.askokcancel(", "self._confirm_flash_dialog(") if (pos := text.find(token)) >= 0]
            with self.subTest(method=method_name):
                if guard_positions:
                    self.assertLess(min(guard_positions), spawn, "guard must precede process spawn")
                if confirmation_positions:
                    self.assertLess(min(confirmation_positions), spawn, "confirmation must precede process spawn")

    def test_event_pump_remains_in_app_and_worker_event_shapes_are_characterized(self):
        app_source = (_SRC_ROOT / "droidlab" / "ui" / "main_window.py").read_text(encoding="utf-8")
        app_tree = ast.parse(app_source)
        app_class = next(node for node in app_tree.body if isinstance(node, ast.ClassDef) and node.name == "PayloadDumperApp")
        poll_method = next(
            node for node in app_class.body
            if isinstance(node, ast.FunctionDef) and node.name == "_poll_events"
        )
        poll_source = ast.get_source_segment(app_source, poll_method)
        self.assertIsNotNone(poll_source)
        self.assertLess(
            poll_source.index("self.after(100, self._poll_events)"),
            poll_source.index("self.events.get_nowait()"),
            "schedule the next poll before dispatching events so one bad event cannot stop polling",
        )
        payload_source = (_SRC_ROOT / "droidlab" / "controllers" / "payload_controller.py").read_text(encoding="utf-8")
        self.assertIn('self.events.put(("parts", parts))', payload_source)
        self.assertIn('self.events.put(("done",', payload_source)
        self.assertIn('self.events.put(("log",', payload_source)


    def test_view_button_and_event_bindings_resolve_to_app_callables(self):
        app_class = importlib.import_module("app").PayloadDumperApp
        source_root = _SRC_ROOT / "droidlab" / "ui"
        view_files = ("layout.py", "payload_view.py", "adb_view.py", "fastboot_view.py")
        bindings = []
        for filename in view_files:
            source = (source_root / filename).read_text(encoding="utf-8")
            tree = ast.parse(source)
            for call in (node for node in ast.walk(tree) if isinstance(node, ast.Call)):
                callback_nodes = []
                for keyword in call.keywords:
                    if keyword.arg == "command":
                        callback_nodes.append(keyword.value)
                if isinstance(call.func, ast.Attribute) and call.func.attr in {"bind", "protocol"}:
                    callback_nodes.extend(call.args[1:])
                    callback_nodes.extend(keyword.value for keyword in call.keywords)
                for callback_node in callback_nodes:
                    if (
                        isinstance(callback_node, ast.Attribute)
                        and isinstance(callback_node.value, ast.Name)
                        and callback_node.value.id == "self"
                        and callback_node.attr.startswith("_")
                    ):
                        bindings.append((filename, callback_node.attr))
        self.assertTrue(bindings, "expected to discover callback bindings in view modules")
        for filename, callback in bindings:
            with self.subTest(view=filename, callback=callback):
                self.assertTrue(callable(getattr(app_class, callback, None)), callback)


class BackendPathWiringTests(unittest.TestCase):
    def test_development_bundle_root_remains_project_root(self):
        from droidlab.core.payload_dumper import _bundle_root

        with patch("droidlab.core.payload_dumper.sys.frozen", False, create=True):
            self.assertEqual(_bundle_root(), Path(__file__).resolve().parent.parent)

    def test_appimage_bundle_root_remains_appdir(self):
        from droidlab.core import payload_dumper

        # AppImage uses POSIX paths even when this wiring test runs on Windows.
        # Keep POSIX path semantics while providing Path.resolve() for the code under test.
        class ResolvedPurePosixPath(PurePosixPath):
            def resolve(self, *args, **kwargs):
                return self

        executable = ResolvedPurePosixPath("/tmp/Payload.AppDir/usr/bin/droidlab-gui-bin")
        with patch.object(payload_dumper, "Path", ResolvedPurePosixPath):
            with patch("droidlab.core.payload_dumper.sys.frozen", True, create=True):
                with patch("droidlab.core.payload_dumper.sys.executable", str(executable)):
                    self.assertEqual(payload_dumper._bundle_root(), PurePosixPath("/tmp/Payload.AppDir"))

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
