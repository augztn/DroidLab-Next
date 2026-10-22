"""Reusable Tk/ttk style setup and widget helpers."""

from __future__ import annotations

import os
import tkinter as tk
from tkinter import font as tkfont
from tkinter import ttk

from .ui_metrics import tree_row_height


class WidgetSupport:
    def _configure_widget_styles(self):
        s = ttk.Style(self)
        try:
            s.theme_use("clam")
        except tk.TclError:
            pass
        font = self._ui_font
        # Shared palette and control states adapted from the supplied React design.
        # Keep all styling in ttk so the native desktop build stays self-contained.
        s.configure("TFrame", background="#111113")
        s.configure(
            "Panel.TFrame",
            background="#19191d",
            relief="solid",
            borderwidth=1,
            bordercolor="#26262d",
        )
        s.configure(
            "TLabel",
            background="#111113",
            foreground="#f2f2f5",
            font=(font, 10 if os.name == "nt" else 13),
        )
        s.configure("Title.TLabel", font=(font, 20, "bold"), foreground="#f2f2f5")
        s.configure("Muted.TLabel", foreground="#9696a3")
        s.configure(
            "TButton",
            background="#26262d",
            foreground="#f2f2f5",
            bordercolor="#303038",
            lightcolor="#303038",
            darkcolor="#222228",
            relief="flat",
            padding=(8, 4),
            font=(font, 10 if os.name == "nt" else 12),
        )
        s.map(
            "TButton",
            background=[("disabled", "#19191d"), ("pressed", "#245dbb"), ("active", "#4b5563")],
            foreground=[("disabled", "#686875"), ("active", "#ffffff")],
            bordercolor=[("focus", "#3b82f6")],
        )
        s.configure(
            "Primary.TButton",
            background="#2868d7",
            foreground="#ffffff",
            bordercolor="#4b8dff",
            lightcolor="#4b8dff",
            darkcolor="#245dbb",
            relief="flat",
            padding=(9, 5),
            font=(font, 10 if os.name == "nt" else 12, "bold"),
        )
        s.map(
            "Primary.TButton",
            background=[("disabled", "#222228"), ("pressed", "#245dbb"), ("active", "#4b8dff")],
            foreground=[("disabled", "#9696a3"), ("active", "#ffffff")],
        )
        s.configure(
            "Danger.TButton",
            background="#9f3333",
            foreground="#ffffff",
            bordercolor="#dc5555",
            lightcolor="#dc5555",
            darkcolor="#7f2929",
            relief="flat",
            padding=(8, 4),
            font=(font, 10 if os.name == "nt" else 12, "bold"),
        )
        s.map(
            "Danger.TButton",
            background=[("disabled", "#19191d"), ("pressed", "#7f2929"), ("active", "#dc5555")],
        )
        s.configure(
            "TCheckbutton",
            background="#19191d",
            foreground="#f2f2f5",
            font=(font, 11 if os.name == "nt" else 13),
        )
        s.map(
            "TCheckbutton", background=[("active", "#19191d")], foreground=[("active", "#ffffff")]
        )
        s.configure(
            "Large.TCheckbutton",
            background="#19191d",
            foreground="#f2f2f5",
            font=(font, 12 if os.name == "nt" else 15),
            padding=(2, 4),
        )
        s.configure(
            "Large.TButton",
            background="#2868d7",
            foreground="#ffffff",
            bordercolor="#4b8dff",
            lightcolor="#4b8dff",
            darkcolor="#245dbb",
            relief="flat",
            padding=(9, 6),
            font=(font, 11 if os.name == "nt" else 14, "bold"),
        )
        s.map(
            "Large.TButton",
            background=[("disabled", "#222228"), ("pressed", "#245dbb"), ("active", "#4b8dff")],
            foreground=[("disabled", "#9696a3"), ("active", "#ffffff")],
        )
        s.configure(
            "TEntry",
            fieldbackground="#0b0b0e",
            foreground="#f2f2f5",
            insertcolor="#ffffff",
            bordercolor="#26262d",
            lightcolor="#26262d",
            darkcolor="#0b0b0e",
            padding=6,
            font=(font, 10 if os.name == "nt" else 12),
        )
        s.map("TEntry", bordercolor=[("focus", "#3b82f6")])
        s.configure(
            "TCombobox",
            fieldbackground="#0b0b0e",
            background="#19191d",
            foreground="#f2f2f5",
            arrowcolor="#9696a3",
            bordercolor="#26262d",
            lightcolor="#26262d",
            darkcolor="#0b0b0e",
            padding=6,
            font=(font, 10 if os.name == "nt" else 12),
        )
        s.map(
            "TCombobox",
            fieldbackground=[("readonly", "#0b0b0e"), ("focus", "#0b0b0e")],
            foreground=[("readonly", "#f2f2f5")],
            bordercolor=[("focus", "#3b82f6")],
        )
        # Derive raw-pixel row height from Tk font metrics for HiDPI displays.
        self._tree_font = (font, 10 if os.name == "nt" else 12)
        self._tree_heading_font = (font, 10 if os.name == "nt" else 12, "bold")
        s.configure(
            "Treeview",
            background="#0b0b0e",
            fieldbackground="#0b0b0e",
            foreground="#f2f2f5",
            bordercolor="#26262d",
            rowheight=tree_row_height(tkfont.Font(self, font=self._tree_font).metrics("linespace")),
            font=self._tree_font,
        )
        s.configure(
            "Treeview.Heading",
            background="#222228",
            foreground="#f2f2f5",
            font=self._tree_heading_font,
            padding=(9, 8),
            relief="flat",
        )
        s.map(
            "Treeview", background=[("selected", "#2868d7")], foreground=[("selected", "#ffffff")]
        )
        s.configure("TNotebook", background="#111113", borderwidth=0, tabmargins=(3, 5, 3, 0))
        s.configure(
            "TNotebook.Tab",
            background="#19191d",
            foreground="#9696a3",
            padding=(18, 10),
            borderwidth=0,
            font=(font, 10 if os.name == "nt" else 12, "bold"),
        )
        s.map(
            "TNotebook.Tab",
            background=[("selected", "#2868d7"), ("active", "#222228")],
            foreground=[("selected", "#ffffff"), ("active", "#ffffff")],
        )
