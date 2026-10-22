"""Compatibility re-exports for legacy flat-module imports."""

try:
    from droidlab.ui.ui_metrics import column_width, tree_row_height
except ModuleNotFoundError:  # legacy test/import path where only repository root is on sys.path
    from src.droidlab.ui.ui_metrics import column_width, tree_row_height

__all__ = ["column_width", "tree_row_height"]
