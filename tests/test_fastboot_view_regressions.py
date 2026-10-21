"""Regression checks for Fastboot view event wiring."""
from __future__ import annotations

import ast
from pathlib import Path
import unittest


_SOURCE = (
    Path(__file__).resolve().parent.parent
    / "src"
    / "droidlab"
    / "ui"
    / "fastboot_view.py"
)


class FastbootViewWiringTests(unittest.TestCase):
    def test_flash_preview_variables_have_single_trace_registration(self):
        tree = ast.parse(_SOURCE.read_text(encoding="utf-8"))
        builder = next(
            node
            for node in ast.walk(tree)
            if isinstance(node, ast.FunctionDef) and node.name == "_build_flash_tab"
        )
        registrations: dict[str, int] = {}
        for node in ast.walk(builder):
            if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
                continue
            if node.func.attr != "trace_add" or not isinstance(node.func.value, ast.Attribute):
                continue
            variable = node.func.value
            if isinstance(variable.value, ast.Name) and variable.value.id == "self":
                registrations[variable.attr] = registrations.get(variable.attr, 0) + 1

        self.assertEqual(registrations.get("flash_image"), 1)
        self.assertEqual(registrations.get("flash_partition"), 1)
        self.assertEqual(registrations.get("fastboot_device"), 1)


if __name__ == "__main__":
    unittest.main()
