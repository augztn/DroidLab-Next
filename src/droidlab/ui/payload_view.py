"""Payload dumper tab construction and partition selection widgets."""

from __future__ import annotations

import os
import tkinter as tk
from tkinter import font as tkfont
from tkinter import ttk

from .ui_metrics import column_width


class PayloadViewSupport:
    def _build_payload_view(self, root):
        h = ttk.Frame(root)
        h.pack(fill="x", pady=(0, 10))
        ttk.Label(h, text="Payload inspection", style="Title.TLabel").pack(anchor="w")
        ttk.Label(
            h,
            text="Inspect an OTA package, choose partitions, and extract verified output files.",
            style="Muted.TLabel",
            wraplength=900,
        ).pack(anchor="w", pady=(3, 0))

        # Two-column workspace: paths, partitions and log on the left; options/actions on the right.
        workspace = ttk.Frame(root)
        workspace.pack(fill="both", expand=True)
        workspace.columnconfigure(0, weight=72, minsize=0)
        workspace.columnconfigure(1, weight=28, minsize=250)
        workspace.rowconfigure(0, weight=1)

        left = ttk.Frame(workspace)
        left.grid(row=0, column=0, sticky="nsew", padx=(0, 10))
        left.columnconfigure(0, weight=1)
        left.rowconfigure(2, weight=1)

        src = ttk.Frame(left, style="Panel.TFrame", padding=8)
        src.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        ttk.Label(src, text="INPUT FILE PATH", style="PanelHeading.TLabel").pack(anchor="w")
        row = ttk.Frame(src, style="Panel.TFrame")
        row.pack(fill="x", pady=(6, 0))
        self.source_entry = ttk.Entry(row, textvariable=self.source)
        self.source_entry.pack(side="left", fill="x", expand=True, ipady=4)
        self.source_entry.bind("<Return>", lambda _event: self._apply_manual_source_path())
        ttk.Button(row, text="Browse…", command=self._browse_source).pack(side="left", padx=(7, 0))
        ttk.Button(
            row, text="Inspect partitions", command=self._inspect, style="Primary.TButton"
        ).pack(side="left", padx=(7, 0))

        out = ttk.Frame(left, style="Panel.TFrame", padding=8)
        out.grid(row=1, column=0, sticky="ew", pady=(0, 8))
        ttk.Label(out, text="OUTPUT DIRECTORY", style="PanelHeading.TLabel").pack(anchor="w")
        row = ttk.Frame(out, style="Panel.TFrame")
        row.pack(fill="x", pady=(6, 0))
        ttk.Entry(row, textvariable=self.output).pack(side="left", fill="x", expand=True, ipady=4)
        ttk.Button(row, text="Choose…", command=self._browse_output).pack(side="left", padx=(7, 0))
        ttk.Button(row, text="Open folder", command=self._open_output_directory).pack(
            side="left", padx=(7, 0)
        )
        drive_row = ttk.Frame(out, style="Panel.TFrame")
        drive_row.pack(fill="x", pady=(7, 0))
        ttk.Label(drive_row, text="Mounted drive", style="PanelMuted.TLabel").pack(
            side="left", padx=(0, 8)
        )
        self.storage_var = tk.StringVar()
        self.storage_combo = ttk.Combobox(
            drive_row, textvariable=self.storage_var, state="readonly"
        )
        self.storage_combo.pack(side="left", fill="x", expand=True)
        ttk.Button(drive_row, text="Refresh", command=self._refresh_storage_locations).pack(
            side="left", padx=(7, 0)
        )
        ttk.Button(
            drive_row,
            text="Use for output",
            command=self._use_selected_storage,
            style="Primary.TButton",
        ).pack(side="left", padx=(7, 0))

        panel = ttk.Frame(left, style="Panel.TFrame", padding=8)
        panel.grid(row=2, column=0, sticky="nsew", pady=(0, 8))
        panel.columnconfigure(0, weight=1)
        panel.rowconfigure(2, weight=1)
        ttk.Label(panel, text="PARTITIONS", style="PanelHeading.TLabel").grid(
            row=0, column=0, sticky="w", pady=(0, 5)
        )
        filter_row = ttk.Frame(panel, style="Panel.TFrame")
        filter_row.grid(row=1, column=0, sticky="ew", pady=(0, 7))
        self.partition_filter = tk.StringVar()
        self.partition_filter.trace_add("write", lambda *_: self._refresh_partition_tree())
        self.partition_filter_entry = ttk.Entry(filter_row, textvariable=self.partition_filter)
        self.partition_filter_entry.pack(side="left", fill="x", expand=True)
        ttk.Button(filter_row, text="Clear", command=lambda: self.partition_filter.set("")).pack(
            side="left", padx=(6, 0)
        )
        ttk.Button(filter_row, text="Select all", command=lambda: self._select_all(True)).pack(
            side="left", padx=(6, 0)
        )
        ttk.Button(filter_row, text="Select none", command=lambda: self._select_all(False)).pack(
            side="left", padx=(6, 0)
        )
        self.partition_summary = tk.StringVar(value="0 partitions · 0 selected · 0 B selected")
        ttk.Label(filter_row, textvariable=self.partition_summary, style="PanelMuted.TLabel").pack(
            side="right", padx=(8, 0)
        )
        # Tkinter Treeview uses the tree column (#0) plus the declared data
        # columns. Keep headers and row values aligned: Partition is #0 and
        # Size is the single declared data column.
        self.tree = ttk.Treeview(panel, columns=("size",), show="tree headings", selectmode="none")
        self.tree.heading("#0", text="Partition", anchor="w")
        self.tree.heading("size", text="Size", anchor="e")
        # Let partition names use available space, with a useful initial width.
        self.tree.column("#0", width=320, minwidth=200, stretch=True, anchor="w")
        # Tkinter has no ResizeToContents mode; use a compact fixed-width,
        # right-aligned size column and prevent it from taking extra space.
        # Size values and their heading must fit even when display scaling is high.
        size_font = tkfont.Font(self, font=self._tree_font)
        heading_font = tkfont.Font(self, font=self._tree_heading_font)
        size_width = column_width(
            max(size_font.measure("1023.9 MB"), heading_font.measure("Size")), minimum=100
        )
        self.tree.column("size", width=size_width, minwidth=size_width, anchor="e", stretch=False)
        tree_scroll = ttk.Scrollbar(panel, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=tree_scroll.set)
        self.tree.grid(row=2, column=0, sticky="nsew")
        tree_scroll.grid(row=2, column=1, sticky="ns")
        self.tree.bind("<Button-1>", self._toggle)

        logbox = ttk.Frame(left, style="Panel.TFrame", padding=8)
        logbox.grid(row=3, column=0, sticky="ew")
        ttk.Label(logbox, text="ACTIVITY LOG", style="PanelHeading.TLabel").pack(anchor="w")
        log_frame = ttk.Frame(logbox, style="Panel.TFrame")
        log_frame.pack(fill="x", expand=False, pady=6)
        self.log = tk.Text(
            log_frame,
            bg="#0b1220",
            fg="#d1d5db",
            insertbackground="white",
            relief="flat",
            wrap="word",
            font=(self._mono_font, 10),
            height=4,
            padx=8,
            pady=6,
        )
        log_scroll = ttk.Scrollbar(log_frame, orient="vertical", command=self.log.yview)
        self.log.configure(yscrollcommand=log_scroll.set)
        log_scroll.pack(side="right", fill="y")
        self.log.pack(side="left", fill="both", expand=True)
        self.log.configure(state="disabled")
        self.progress = ttk.Progressbar(logbox, mode="indeterminate")
        self.progress.pack(fill="x", pady=(2, 0))

        side = ttk.Frame(workspace, style="Panel.TFrame", padding=12)
        side.grid(row=0, column=1, sticky="nsew")
        side.columnconfigure(0, weight=1)
        ttk.Label(
            side, text="OPTIONS", style="PanelHeading.TLabel", font=("Sans", 16, "bold")
        ).grid(row=0, column=0, sticky="w", pady=(0, 8))
        ttk.Separator(side).grid(row=1, column=0, sticky="ew", pady=(0, 10))
        ttk.Checkbutton(
            side,
            text="Generate SHA-256 Checksum",
            variable=self.fingerprint,
            style="Large.TCheckbutton",
        ).grid(row=2, column=0, sticky="w", pady=(10, 8))
        ttk.Label(
            side,
            text="Creates a SHA-256 checksum for each extracted partition. This is separate from the backend’s OTA verification.",
            style="PanelMuted.TLabel",
            justify="left",
            wraplength=205,
            font=(self._ui_font, 10 if os.name == "nt" else 12),
        ).grid(row=3, column=0, sticky="ew", pady=(4, 0))
        # Consume spare height so the extraction controls remain pinned to the card bottom.
        side.rowconfigure(4, weight=1)
        ttk.Frame(side, style="Panel.TFrame").grid(row=4, column=0, sticky="nsew")
        action_row = ttk.Frame(side, style="Panel.TFrame")
        action_row.grid(row=5, column=0, sticky="ew", pady=(12, 0))
        action_row.columnconfigure(0, weight=1)
        self.start_button = ttk.Button(
            action_row, text="Extract payload", command=self._start, style="Large.TButton"
        )
        self.start_button.grid(row=0, column=0, sticky="ew", pady=(0, 7), ipady=5)
        self.cancel_button = ttk.Button(
            action_row,
            text="Cancel",
            command=self._cancel,
            state="disabled",
            style="Danger.TButton",
        )
        self.cancel_button.grid(row=1, column=0, sticky="ew", ipady=4)
        self._apply_theme(self.theme_name)
        self._refresh_storage_locations()
        self._enable_drop(self)
        self._enable_drop(src)
        self._enable_drop(self.source_entry)
        self._enable_drop(root)
        self._append(
            "Drag payload.bin or an OTA .zip onto the window, or type/paste its full path and choose Use typed path. Inspect to select individual partitions."
        )
        self._append(
            "Backend: payload-dumper-go (Apache-2.0). Some delta OTA operations are unsupported."
        )
