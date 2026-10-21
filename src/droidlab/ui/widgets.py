"""Reusable Tk/ttk style setup and widget helpers."""
from __future__ import annotations
import os
import tkinter as tk
from tkinter import font as tkfont, ttk
from droidlab.config.constants import THEME_TOKENS
from .ui_metrics import column_width, tree_row_height

class WidgetSupport:
    def _configure_widget_styles(self):
        """Configure shared native styles from the active design-token palette."""
        s = ttk.Style(self)
        try:
            s.theme_use("clam")
        except tk.TclError:
            pass
        t = getattr(self, "theme_tokens", THEME_TOKENS["cyberpunk_glass"])
        font = self._ui_font
        size = 10 if os.name == "nt" else 12
        s.configure(".", background=t["bg"], foreground=t["text"])
        s.configure("TFrame", background=t["bg"])
        s.configure("Panel.TFrame", background=t["panel"], relief="flat", borderwidth=1, bordercolor=t["border"])
        s.configure("TLabel", background=t["bg"], foreground=t["text"], font=(font, size))
        s.configure("Title.TLabel", background=t["bg"], foreground=t["text"], font=(font, 20, "bold"))
        s.configure("Muted.TLabel", background=t["bg"], foreground=t["muted"])
        s.configure("PanelHeading.TLabel", background=t["panel"], foreground=t["accent"], font=(font, size, "bold"))
        s.configure("PanelMuted.TLabel", background=t["panel"], foreground=t["muted"])
        s.configure("TButton", background=t["button"], foreground=t["text"], bordercolor=t["border"], lightcolor=t["border"], darkcolor=t["panel"], relief="flat", padding=(10, 6), font=(font, size))
        s.map("TButton", background=[("disabled", t["panel"]), ("pressed", t["accent2"]), ("active", t["panel_alt"])], foreground=[("disabled", t["muted"]), ("active", t["text"])], bordercolor=[("focus", t["accent"])])
        s.configure("Primary.TButton", background=t["accent"], foreground="#FFFFFF", bordercolor=t["accent"], lightcolor=t["accent"], darkcolor=t["accent2"], relief="flat", padding=(11, 6), font=(font, size, "bold"))
        s.map("Primary.TButton", background=[("disabled", t["panel_alt"]), ("pressed", t["accent2"]), ("active", t["accent2"])], foreground=[("disabled", t["muted"]), ("active", "#FFFFFF")])
        s.configure("Danger.TButton", background=t["danger"], foreground="#FFFFFF", bordercolor=t["danger"], lightcolor=t["danger"], darkcolor=t["danger"], relief="flat", padding=(10, 6), font=(font, size, "bold"))
        s.map("Danger.TButton", background=[("disabled", t["panel"]), ("pressed", t["danger"]), ("active", t["danger"])], foreground=[("disabled", t["muted"]), ("active", "#FFFFFF")])
        s.configure("TCheckbutton", background=t["panel"], foreground=t["text"], font=(font, size))
        s.map("TCheckbutton", background=[("active", t["panel_alt"])], foreground=[("active", t["text"])])
        s.configure("Large.TCheckbutton", background=t["panel"], foreground=t["text"], font=(font, size + 2), padding=(2, 4))
        s.configure("Large.TButton", background=t["accent"], foreground="#FFFFFF", bordercolor=t["accent"], lightcolor=t["accent"], darkcolor=t["accent2"], relief="flat", padding=(11, 7), font=(font, size + 1, "bold"))
        s.map("Large.TButton", background=[("disabled", t["panel_alt"]), ("pressed", t["accent2"]), ("active", t["accent2"])], foreground=[("disabled", t["muted"]), ("active", "#FFFFFF")])
        s.configure("TEntry", fieldbackground=t["input"], foreground=t["text"], insertcolor=t["text"], bordercolor=t["border"], lightcolor=t["border"], darkcolor=t["input"], padding=6, font=(font, size))
        s.map("TEntry", bordercolor=[("focus", t["accent"])])
        s.configure("TCombobox", fieldbackground=t["input"], background=t["button"], foreground=t["text"], arrowcolor=t["muted"], bordercolor=t["border"], lightcolor=t["border"], darkcolor=t["input"], padding=6, font=(font, size))
        s.map("TCombobox", fieldbackground=[("readonly", t["input"]), ("focus", t["input"])], foreground=[("readonly", t["text"])], bordercolor=[("focus", t["accent"])])
        self._tree_font = (font, size)
        self._tree_heading_font = (font, size, "bold")
        row_height = tree_row_height(tkfont.Font(self, font=self._tree_font).metrics("linespace"))
        s.configure("Treeview", background=t["input"], fieldbackground=t["input"], foreground=t["text"], bordercolor=t["border"], rowheight=row_height, font=self._tree_font)
        s.configure("Treeview.Heading", background=t["panel_alt"], foreground=t["text"], font=self._tree_heading_font, padding=(9, 7), relief="flat")
        s.map("Treeview", background=[("selected", t["accent"])], foreground=[("selected", "#FFFFFF")])
        s.configure("TNotebook", background=t["bg"], borderwidth=0, tabmargins=(3, 5, 3, 0))
        s.configure("TNotebook.Tab", background=t["panel"], foreground=t["muted"], padding=(16, 8), borderwidth=0, font=(font, size, "bold"))
        s.map("TNotebook.Tab", background=[("selected", t["panel_alt"]), ("active", t["button"])], foreground=[("selected", t["accent"]), ("active", t["text"])])
