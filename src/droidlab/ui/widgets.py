"""Reusable Tk/ttk style setup and widget helpers."""
from __future__ import annotations

import os
import tkinter as tk
from tkinter import font as tkfont
from tkinter import ttk

from .ui_metrics import tree_row_height


class WidgetSupport:
    def _configure_widget_styles(self):
        s=ttk.Style(self)
        try:s.theme_use("clam")
        except tk.TclError:pass
        font = self._ui_font
        # Shared palette and control states adapted from the supplied React design.
        # Keep all styling in ttk so the native desktop build stays self-contained.
        s.configure("TFrame", background="#0F1117")
        s.configure("Panel.TFrame", background="#1f2937", relief="solid",
                    borderwidth=1, bordercolor="#374151")
        s.configure("TLabel", background="#0F1117", foreground="#F3F4F6",
                    font=(font, 10 if os.name == "nt" else 13))
        s.configure("Title.TLabel", font=(font, 20, "bold"), foreground="#f8fafc")
        s.configure("Muted.TLabel", foreground="#cbd5e1")
        s.configure("TButton", background="#374151", foreground="#f8fafc",
                    bordercolor="#475569", lightcolor="#475569", darkcolor="#263449",
                    relief="flat", padding=(8, 4),
                    font=(font, 10 if os.name == "nt" else 12))
        s.map("TButton",
              background=[("disabled", "#1f2937"), ("pressed", "#1e40af"),
                          ("active", "#4b5563")],
              foreground=[("disabled", "#64748b"), ("active", "#ffffff")],
              bordercolor=[("focus", "#3b82f6")])
        s.configure("Primary.TButton", background="#1d4ed8", foreground="#ffffff",
                    bordercolor="#2563eb", lightcolor="#2563eb", darkcolor="#1e40af",
                    relief="flat", padding=(9, 5),
                    font=(font, 10 if os.name == "nt" else 12, "bold"))
        s.map("Primary.TButton",
              background=[("disabled", "#334155"), ("pressed", "#1e40af"),
                          ("active", "#2563eb")],
              foreground=[("disabled", "#94a3b8"), ("active", "#ffffff")])
        s.configure("Danger.TButton", background="#991b1b", foreground="#ffffff",
                    bordercolor="#b91c1c", lightcolor="#b91c1c", darkcolor="#7f1d1d",
                    relief="flat", padding=(8, 4),
                    font=(font, 10 if os.name == "nt" else 12, "bold"))
        s.map("Danger.TButton",
              background=[("disabled", "#1f2937"), ("pressed", "#7f1d1d"),
                          ("active", "#b91c1c")])
        s.configure("TCheckbutton", background="#1f2937", foreground="#f8fafc",
                    font=(font, 11 if os.name == "nt" else 13))
        s.map("TCheckbutton", background=[("active", "#1f2937")],
              foreground=[("active", "#ffffff")])
        s.configure("Large.TCheckbutton", background="#1f2937", foreground="#f8fafc",
                    font=(font, 12 if os.name == "nt" else 15), padding=(2, 4))
        s.configure("Large.TButton", background="#1d4ed8", foreground="#ffffff",
                    bordercolor="#2563eb", lightcolor="#2563eb", darkcolor="#1e40af",
                    relief="flat", padding=(9, 6),
                    font=(font, 11 if os.name == "nt" else 14, "bold"))
        s.map("Large.TButton",
              background=[("disabled", "#334155"), ("pressed", "#1e40af"),
                          ("active", "#2563eb")],
              foreground=[("disabled", "#94a3b8"), ("active", "#ffffff")])
        s.configure("TEntry", fieldbackground="#0b1220", foreground="#f1f5f9",
                    insertcolor="#ffffff", bordercolor="#374151", lightcolor="#374151",
                    darkcolor="#0b1220", padding=6,
                    font=(font, 10 if os.name == "nt" else 12))
        s.map("TEntry", bordercolor=[("focus", "#3b82f6")])
        s.configure("TCombobox", fieldbackground="#0b1220", background="#1f2937",
                    foreground="#f1f5f9", arrowcolor="#cbd5e1", bordercolor="#374151",
                    lightcolor="#374151", darkcolor="#0b1220", padding=6,
                    font=(font, 10 if os.name == "nt" else 12))
        s.map("TCombobox",
              fieldbackground=[("readonly", "#0b1220"), ("focus", "#0b1220")],
              foreground=[("readonly", "#f1f5f9")],
              bordercolor=[("focus", "#3b82f6")])
        # Derive raw-pixel row height from Tk font metrics for HiDPI displays.
        self._tree_font = (font, 10 if os.name == "nt" else 12)
        self._tree_heading_font = (font, 10 if os.name == "nt" else 12, "bold")
        s.configure("Treeview", background="#0b1220", fieldbackground="#0b1220",
                    foreground="#f1f5f9", bordercolor="#374151",
                    rowheight=tree_row_height(tkfont.Font(self, font=self._tree_font).metrics("linespace")),
                    font=self._tree_font)
        s.configure("Treeview.Heading", background="#263449", foreground="#f8fafc",
                    font=self._tree_heading_font, padding=(9, 8),
                    relief="flat")
        s.map("Treeview", background=[("selected", "#1d4ed8")],
              foreground=[("selected", "#ffffff")])
        s.configure("TNotebook", background="#111827", borderwidth=0,
                    tabmargins=(3, 5, 3, 0))
        s.configure("TNotebook.Tab", background="#1f2937", foreground="#cbd5e1",
                    padding=(18, 10), borderwidth=0,
                    font=(font, 10 if os.name == "nt" else 12, "bold"))
        s.map("TNotebook.Tab",
              background=[("selected", "#1d4ed8"), ("active", "#334155")],
              foreground=[("selected", "#ffffff"), ("active", "#ffffff")])

