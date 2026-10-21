"""Reusable Tk/ttk styles driven by the shared design tokens."""
from __future__ import annotations

import os
import tkinter as tk
from tkinter import font as tkfont, ttk

from droidlab.config.constants import THEME_TOKENS
from .ui_metrics import tree_row_height


class WidgetSupport:
    """Configure the existing controls without changing their layout or behavior."""

    def _configure_widget_styles(self):
        style = ttk.Style(self)
        try:
            if "clam" in style.theme_names():
                style.theme_use("clam")
        except tk.TclError:
            pass

        t = getattr(self, "theme_tokens", THEME_TOKENS["cyberpunk_glass"])
        font = self._ui_font
        size = 10 if os.name == "nt" else 12
        small_size = 9 if os.name == "nt" else 10
        heading_size = 10 if os.name == "nt" else 11

        style.configure(".", background=t["bg"], foreground=t["text"], font=(font, size))
        style.configure("TFrame", background=t["bg"])
        style.configure("Panel.TFrame", background=t["panel"], relief="flat",
                        borderwidth=1, bordercolor=t["border"])
        style.configure("TLabel", background=t["bg"], foreground=t["text"], font=(font, size))
        style.configure("Title.TLabel", background=t["bg"], foreground=t["text"],
                        font=(font, 20, "bold"))
        style.configure("PanelHeading.TLabel", background=t["panel"], foreground=t["accent"],
                        font=(font, heading_size, "bold"))
        style.configure("PanelMuted.TLabel", background=t["panel"], foreground=t["muted"])
        style.configure("Muted.TLabel", background=t["bg"], foreground=t["muted"])

        style.configure("TButton", background=t["button"], foreground=t["text"],
                        bordercolor=t["border"], lightcolor=t["border"], darkcolor=t["panel"],
                        relief="flat", padding=(10, 6), font=(font, size))
        style.map("TButton",
                  background=[("disabled", t["panel"]), ("pressed", t["accent2"]),
                              ("active", t["panel_alt"])],
                  foreground=[("disabled", t["muted"]), ("active", t["text"])],
                  bordercolor=[("focus", t["accent"])])
        style.configure("Primary.TButton", background=t["accent"], foreground="#FFFFFF",
                        bordercolor=t["accent"], lightcolor=t["accent"], darkcolor=t["accent2"],
                        relief="flat", padding=(12, 6), font=(font, size, "bold"))
        style.map("Primary.TButton",
                  background=[("disabled", t["panel_alt"]), ("pressed", t["accent2"]),
                              ("active", t["accent2"])],
                  foreground=[("disabled", t["muted"]), ("active", "#FFFFFF")])
        # Keep destructive operations visually distinct from routine actions.
        style.configure("Danger.TButton", background=t["danger"], foreground="#FFFFFF",
                        bordercolor=t["danger"], lightcolor=t["danger"], darkcolor=t["danger"],
                        relief="flat", padding=(10, 6), font=(font, size, "bold"))
        style.map("Danger.TButton",
                  background=[("disabled", t["panel"]), ("pressed", t["danger"]),
                              ("active", t["danger"])],
                  foreground=[("disabled", t["muted"]), ("active", "#FFFFFF")])
        style.configure("Large.TButton", background=t["accent"], foreground="#FFFFFF",
                        bordercolor=t["accent"], lightcolor=t["accent"], darkcolor=t["accent2"],
                        relief="flat", padding=(10, 6), font=(font, size, "bold"))
        style.map("Large.TButton",
                  background=[("disabled", t["panel_alt"]), ("pressed", t["accent2"]),
                              ("active", t["accent2"])],
                  foreground=[("disabled", t["muted"]), ("active", "#FFFFFF")])

        style.configure("TEntry", fieldbackground=t["input"], foreground=t["text"],
                        insertcolor=t["text"], bordercolor=t["border"], lightcolor=t["border"],
                        darkcolor=t["input"], padding=6, font=(font, size))
        style.map("TEntry", bordercolor=[("focus", t["accent"])],
                  lightcolor=[("focus", t["accent"])])
        style.configure("TCombobox", fieldbackground=t["input"], background=t["button"],
                        foreground=t["text"], arrowcolor=t["muted"], bordercolor=t["border"],
                        lightcolor=t["border"], darkcolor=t["input"], padding=6,
                        font=(font, size))
        style.map("TCombobox",
                  fieldbackground=[("readonly", t["input"]), ("focus", t["input"])],
                  foreground=[("readonly", t["text"]), ("disabled", t["muted"])],
                  bordercolor=[("focus", t["accent"])], lightcolor=[("focus", t["accent"])])
        style.configure("TCheckbutton", background=t["panel"], foreground=t["text"],
                        font=(font, size), padding=(2, 3))
        style.map("TCheckbutton", background=[("active", t["panel"])],
                  foreground=[("active", t["text"]), ("disabled", t["muted"])])
        style.configure("Large.TCheckbutton", background=t["panel"], foreground=t["text"],
                        font=(font, size, "bold"), padding=(2, 4))
        style.map("Large.TCheckbutton", background=[("active", t["panel"])])
        style.configure("TRadiobutton", background=t["panel"], foreground=t["text"],
                        font=(font, size))
        style.map("TRadiobutton", background=[("active", t["panel"])])

        self._tree_font = (font, small_size)
        self._tree_heading_font = (font, small_size, "bold")
        line_height = tkfont.Font(self, font=self._tree_font).metrics("linespace")
        style.configure("Treeview", background=t["input"], fieldbackground=t["input"],
                        foreground=t["text"], bordercolor=t["border"],
                        rowheight=tree_row_height(line_height), font=self._tree_font)
        style.configure("Treeview.Heading", background=t["panel_alt"], foreground=t["text"],
                        font=self._tree_heading_font, padding=(9, 7), relief="flat")
        style.map("Treeview", background=[("selected", t["accent2"])],
                  foreground=[("selected", "#FFFFFF")])

        style.configure("TNotebook", background=t["bg"], borderwidth=0,
                        tabmargins=(3, 5, 3, 0))
        style.configure("TNotebook.Tab", background=t["panel"], foreground=t["muted"],
                        padding=(14, 8), borderwidth=0, font=(font, size, "bold"))
        style.map("TNotebook.Tab",
                  background=[("selected", t["panel_alt"]), ("active", t["button"])],
                  foreground=[("selected", t["accent"]), ("active", t["text"])])
