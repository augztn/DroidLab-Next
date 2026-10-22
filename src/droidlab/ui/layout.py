"""Top-level window shell, header, status bar, and shared device workspace."""

from __future__ import annotations

import tkinter as tk
from tkinter import ttk


class LayoutSupport:
    def _build(self):
        self._configure_widget_styles()
        font = self._ui_font
        # App-wide header keeps identity and current operation status visible on every tab.
        app_header = tk.Frame(
            self, bg="#19191d", padx=12, pady=7, highlightthickness=1, highlightbackground="#303038"
        )
        app_header.pack(fill="x", padx=6, pady=(6, 0))
        brand_mark = tk.Label(
            app_header,
            text="DL",
            bg="#2563eb",
            fg="#ffffff",
            font=(font, 13, "bold"),
            width=4,
            pady=7,
        )
        brand_mark.pack(side="left", padx=(0, 12))
        brand_text = tk.Frame(app_header, bg="#19191d")
        brand_text.pack(side="left", fill="x", expand=True)
        tk.Label(
            brand_text, text="DroidLab", bg="#19191d", fg="#f2f2f5", font=(font, 15, "bold")
        ).pack(side="left", anchor="center")
        tk.Label(
            brand_text,
            text="Android firmware toolkit  ·  Extract · Diagnose · Maintain",
            bg="#19191d",
            fg="#9696a3",
            font=(font, 9),
        ).pack(side="left", anchor="center", padx=(12, 0))
        # Compact app-wide device telemetry in the navigation header.
        telemetry = tk.Frame(
            app_header,
            bg="#19191d",
            padx=10,
            pady=2,
            highlightthickness=1,
            highlightbackground="#303038",
        )
        telemetry.pack(side="right", padx=(8, 0), anchor="center")
        self.header_device_vars = {
            name: tk.StringVar(value="—") for name in ("mode", "serial", "codename", "bootloader")
        }
        self.header_device_vars["mode"].set("NO DEVICE")
        self.header_mode_label = tk.Label(
            telemetry,
            textvariable=self.header_device_vars["mode"],
            bg="#19191d",
            fg="#F97316",
            font=(self._ui_font, 8, "bold"),
        )
        self.header_mode_label.pack(side="left", padx=(0, 9))
        for label, key in (("DEVICE", "serial"), ("CODENAME", "codename")):
            tk.Label(
                telemetry, text=label, bg="#19191d", fg="#9696a3", font=(self._ui_font, 7, "bold")
            ).pack(side="left", padx=(0, 3))
            tk.Label(
                telemetry,
                textvariable=self.header_device_vars[key],
                bg="#19191d",
                fg="#f2f2f5",
                font=(self._mono_font, 8),
            ).pack(side="left", padx=(0, 8))
        tk.Label(
            telemetry, text="SLOT", bg="#19191d", fg="#9696a3", font=(self._ui_font, 7, "bold")
        ).pack(side="left", padx=(0, 4))
        self.header_slot_buttons = {}
        for slot in ("a", "b"):
            button = tk.Button(
                telemetry,
                text=slot.upper(),
                command=lambda value=slot: self._set_active_slot(value),
                bg="#303038",
                fg="#f2f2f5",
                activebackground="#2868d7",
                activeforeground="#FFFFFF",
                relief="flat",
                bd=0,
                padx=6,
                pady=1,
                font=(self._ui_font, 8, "bold"),
                cursor="hand2",
                state="disabled",
            )
            button.pack(side="left", padx=(0, 2))
            self.header_slot_buttons[slot] = button
        self.header_bootloader_label = tk.Label(
            telemetry,
            textvariable=self.header_device_vars["bootloader"],
            bg="#19191d",
            fg="#F59E0B",
            font=(self._ui_font, 8, "bold"),
        )
        self.header_bootloader_label.pack(side="left", padx=(5, 0))
        self.header_telemetry = telemetry

        status_card = tk.Frame(
            app_header,
            bg="#222228",
            padx=10,
            pady=5,
            highlightthickness=1,
            highlightbackground="#303038",
        )
        status_card.pack(side="right", padx=(12, 0), anchor="center")
        tk.Label(status_card, text="●", bg="#222228", fg="#35c98a", font=(font, 10, "bold")).pack(
            side="left", padx=(0, 6)
        )
        self.header_status_label = tk.Label(
            status_card,
            textvariable=self.status,
            bg="#222228",
            fg="#f2f2f5",
            font=(font, 9, "bold"),
            wraplength=0,
            justify="left",
        )
        self.header_status_label.pack(side="left")
        self.theme_button = tk.Button(
            app_header,
            text="⚙",
            command=self._open_theme_picker,
            bg="#19191d",
            fg="#9696a3",
            activebackground="#26262d",
            activeforeground="#4b8dff",
            relief="flat",
            bd=0,
            padx=9,
            pady=5,
            cursor="hand2",
            font=(font, 12, "bold"),
        )
        self.theme_button.pack(side="right", padx=(8, 0))

        # Persistent app shell: compact navigation rail + focused workspace.
        shell = ttk.Frame(self)
        shell.pack(fill="both", expand=True, padx=6, pady=(0, 6))
        shell.columnconfigure(1, weight=1)
        shell.rowconfigure(0, weight=1)

        sidebar = tk.Frame(
            shell,
            bg="#19191d",
            width=208,
            padx=10,
            pady=14,
            highlightthickness=1,
            highlightbackground="#303038",
        )
        sidebar.grid(row=0, column=0, sticky="nsw", padx=(0, 1))
        sidebar.grid_propagate(False)
        tk.Label(
            sidebar,
            text="WORKSPACE",
            bg="#19191d",
            fg="#777783",
            font=(font, 8, "bold"),
            anchor="w",
        ).pack(fill="x", padx=8, pady=(4, 9))

        content = ttk.Frame(shell)
        content.grid(row=0, column=1, sticky="nsew")
        content.columnconfigure(0, weight=1)
        content.rowconfigure(0, weight=1)

        # The sidebar is the single source of workspace navigation. Hide the
        # Notebook tab strip to avoid duplicate navigation and reclaim vertical space.
        style = ttk.Style(self)
        style.layout("Workspace.TNotebook", [("Notebook.client", {"sticky": "nswe"})])
        notebook = ttk.Notebook(content, style="Workspace.TNotebook")
        notebook.grid(row=0, column=0, sticky="nsew")
        self.workspace_notebook = notebook
        root = ttk.Frame(notebook, padding=8)
        notebook.add(root, text="Payload Extractor")
        device_tab = ttk.Frame(notebook, padding=0)
        notebook.add(device_tab, text="Device Control & Flashing")

        def add_navigation(label, index, hint):
            button = tk.Button(
                sidebar,
                text=label,
                anchor="w",
                padx=10,
                pady=9,
                command=lambda: select_workspace(index),
                bg="#2868d7" if index == 0 else "#19191d",
                fg="#ffffff" if index == 0 else "#c4c4ce",
                activebackground="#26262d",
                activeforeground="#ffffff",
                relief="flat",
                bd=0,
                cursor="hand2",
                font=(font, 10),
            )
            button.pack(fill="x", pady=2)
            tk.Label(
                sidebar,
                text=hint,
                anchor="w",
                bg="#19191d",
                fg="#777783",
                font=(font, 8),
            ).pack(fill="x", padx=(12, 4), pady=(0, 7))
            return button

        def select_workspace(index):
            notebook.select(index)
            for nav_index, nav_button in enumerate(self.workspace_nav_buttons):
                selected = nav_index == index
                nav_button.configure(
                    bg="#2868d7" if selected else "#19191d",
                    fg="#ffffff" if selected else "#c4c4ce",
                )

        self.workspace_nav_buttons = [
            add_navigation("▤  Payload Extractor", 0, "Inspect and extract OTA images"),
            add_navigation("▣  Device Control", 1, "ADB, sideload and Fastboot"),
        ]
        tk.Frame(sidebar, bg="#303038", height=1).pack(fill="x", padx=7, pady=(14, 10))
        tk.Label(
            sidebar,
            text="ANDROID TOOLKIT",
            bg="#19191d",
            fg="#777783",
            font=(font, 8, "bold"),
            anchor="w",
        ).pack(fill="x", padx=8)
        tk.Label(
            sidebar,
            text="Extract  ·  Diagnose\nMaintain  ·  Recover",
            bg="#19191d",
            fg="#9696a3",
            justify="left",
            anchor="nw",
            font=(font, 9),
            pady=8,
        ).pack(fill="x", padx=8)
        self._select_workspace = select_workspace

        self.device_mode = tk.StringVar(value="adb")
        self.device_workspace = ttk.Frame(device_tab)
        self.device_workspace.pack(fill="both", expand=True)
        self.flash_workspace = ttk.Frame(self.device_workspace, padding=8)
        self.adb_workspace = ttk.Frame(self.device_workspace, padding=6)
        self.flash_workspace.grid(row=0, column=0, sticky="nsew")
        self.adb_workspace.grid(row=0, column=0, sticky="nsew")
        self.device_workspace.columnconfigure(0, weight=1)
        self.device_workspace.rowconfigure(0, weight=1)
        self._build_flash_tab(self.flash_workspace)
        self._build_adb_tab(self.adb_workspace)
        self._show_device_workspace("adb")
        self._build_payload_view(root)

    def _show_device_workspace(self, mode, manual=False):
        """Show selected workspace and synchronize the inline mode toggle."""
        mode = "fastboot" if mode == "fastboot" else "adb"
        self.device_mode.set(mode)
        self._manual_mode_override = bool(manual)
        if mode == "fastboot":
            self.flash_workspace.tkraise()
        else:
            self.adb_workspace.tkraise()
        for attr, selected in (
            ("fastboot_header_mode_button", mode == "fastboot"),
            ("adb_header_mode_button", mode == "adb"),
            ("fastboot_workspace_mode_button", mode == "fastboot"),
            ("adb_workspace_mode_button", mode == "adb"),
        ):
            button = getattr(self, attr, None)
            if button:
                button.configure(style="Primary.TButton" if selected else "TButton")

    def _on_shared_device_selected(self):
        target = getattr(self, "_adb_targets", {}).get(self.adb_device.get())
        if not target:
            self._update_reboot_actions()
            if hasattr(self, "device_info_vars"):
                self._set_device_info(
                    {
                        "Brand / Manufacturer": "—",
                        "Device name / Model": "—",
                        "Model code": "—",
                        "Codename": "—",
                        "Active slot": "—",
                        "Bootloader": "—",
                        "Battery": "—",
                    },
                    "NO DEVICE",
                    "#4b5563",
                )
            return
        serial, state = target
        if state == "fastboot":
            self.fastboot_device.set(serial)
            self._show_device_workspace("fastboot")
        else:
            self._show_device_workspace("adb")
            if hasattr(self, "device_mode_status"):
                adb_state = state.split(":", 1)[1] if state.startswith("adb:") else state
                mode = {
                    "device": "ADB / Android",
                    "recovery": "ADB Recovery",
                    "sideload": "ADB Sideload",
                    "unauthorized": "ADB Unauthorized",
                    "offline": "ADB Offline",
                }.get(adb_state, "ADB (" + adb_state + ")")
                self.device_mode_status.set("MODE DETECTOR: " + mode + " · Serial: " + serial)
        self._update_reboot_actions()
        if hasattr(self, "device_info_vars"):
            self._refresh_device_info()
