"""Fastboot flashing workspace construction."""
from __future__ import annotations
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

class FastbootViewSupport:
    def _build_flash_tab(self, tab):
        """Build the Fastboot workspace with device-first selection and a live console."""
        tab.columnconfigure(0, weight=13, uniform="fastboot_workspace")
        tab.columnconfigure(1, weight=7, uniform="fastboot_workspace")
        tab.rowconfigure(2, weight=0, minsize=0)
        tab.rowconfigure(3, weight=1)

        modebar = ttk.Frame(tab)
        modebar.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 6))
        ttk.Label(modebar, text="Device mode", font=(self._ui_font, 16, "bold")).pack(side="left", padx=(0, 12))
        self.fastboot_header_mode_button = ttk.Button(modebar, text="Fastboot & Flashing",
            command=lambda: self._show_device_workspace("fastboot", manual=True), style="Primary.TButton")
        self.fastboot_header_mode_button.pack(side="left", padx=(0, 5))
        self.adb_header_mode_button = ttk.Button(modebar, text="ADB & Sideload",
            command=lambda: self._show_device_workspace("adb", manual=True))
        self.adb_header_mode_button.pack(side="left")
        ttk.Label(tab, text="Choose a device, then select a maintenance or flashing action.",
                  style="Muted.TLabel").grid(row=1, column=0, columnspan=2, sticky="w", pady=(0, 5))

        # Device selector comes first so every later operation has a clear target.
        device = ttk.Frame(tab, style="Panel.TFrame", padding=5)
        device.grid(row=2, column=0, columnspan=2, sticky="ew", pady=(0, 5))
        device.columnconfigure(0, weight=0)
        # Device details live beside the console, not beside the compact device picker.
        self.device_info_vars = {}
        self.device_info_mode = tk.StringVar(value="NO DEVICE")
        ttk.Label(device, text="FASTBOOT DEVICE", background="#1f2937", foreground="#93c5fd",
                  font=("Sans", 10, "bold")).grid(row=0, column=0, sticky="w")
        self.fastboot_device = tk.StringVar()
        self.device_combo = ttk.Combobox(device, textvariable=self.fastboot_device, state="readonly")
        self.device_combo.configure(width=18)
        self.device_combo.grid(row=1, column=0, sticky="w", pady=(3, 0))
        ttk.Button(device, text="Refresh devices", command=self._refresh_fastboot_devices).grid(
            row=1, column=1, padx=(5, 0), pady=(3, 0))

        # Scrollable left workspace keeps every control reachable on short displays.
        left_scroll = ttk.Frame(tab)
        left_scroll.grid(row=3, column=0, sticky="nsew", padx=(0, 5))
        left_scroll.columnconfigure(0, weight=1)
        left_scroll.rowconfigure(0, weight=1)
        controls_canvas = tk.Canvas(left_scroll, bg="#111827", highlightthickness=0, borderwidth=0)
        controls_scrollbar = ttk.Scrollbar(left_scroll, orient="vertical", command=controls_canvas.yview)
        controls_canvas.configure(yscrollcommand=controls_scrollbar.set)
        controls_scrollbar.grid(row=0, column=1, sticky="ns")
        controls_canvas.grid(row=0, column=0, sticky="nsew")
        controls = ttk.Frame(controls_canvas)
        controls_window = controls_canvas.create_window((0, 0), window=controls, anchor="nw")
        controls.columnconfigure(0, weight=1)
        def _sync_controls_scrollregion(_event=None):
            controls_canvas.configure(scrollregion=controls_canvas.bbox("all"))
        def _fit_controls_width(event):
            controls_canvas.itemconfigure(controls_window, width=event.width)
        controls.bind("<Configure>", _sync_controls_scrollregion)
        controls_canvas.bind("<Configure>", _fit_controls_width)
        def _controls_mousewheel(event):
            if getattr(event, "delta", 0):
                controls_canvas.yview_scroll(int(-event.delta / 120), "units")
            elif getattr(event, "num", None) == 4:
                controls_canvas.yview_scroll(-1, "units")
            elif getattr(event, "num", None) == 5:
                controls_canvas.yview_scroll(1, "units")
        controls_canvas.bind_all("<MouseWheel>", _controls_mousewheel)
        controls_canvas.bind_all("<Button-4>", _controls_mousewheel)
        controls_canvas.bind_all("<Button-5>", _controls_mousewheel)

        action_row = ttk.Frame(controls)
        action_row.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        action_row.columnconfigure(0, weight=1, uniform="fastboot_actions")
        action_row.columnconfigure(1, weight=1, uniform="fastboot_actions")
        reboot = ttk.Frame(action_row, style="Panel.TFrame", padding=10)
        reboot.grid(row=0, column=0, sticky="nsew", padx=(0, 5))
        ttk.Label(reboot, text="REBOOT CONTROLS", background="#1f2937", foreground="#93c5fd",
                  font=("Sans", 11, "bold")).pack(anchor="w", pady=(0, 5))
        ttk.Button(reboot, text="Reboot system", command=lambda: self._fastboot_quick_action(["reboot"])).pack(fill="x", pady=2)
        ttk.Button(reboot, text="Reboot recovery", command=lambda: self._fastboot_quick_action(["reboot", "recovery"])).pack(fill="x", pady=2)
        ttk.Button(reboot, text="Reboot bootloader", command=lambda: self._fastboot_quick_action(["reboot-bootloader"])).pack(fill="x", pady=2)
        reference = ttk.Frame(action_row, style="Panel.TFrame", padding=10)
        reference.grid(row=0, column=1, sticky="nsew", padx=(5, 0))
        ttk.Label(reference, text="ERASE & FORMAT", background="#1f2937", foreground="#fb923c",
                  font=("Sans", 11, "bold")).pack(anchor="w", pady=(0, 5))
        ttk.Button(reference, text="Erase cache", command=lambda: self._run_fastboot_maintenance("erase", "cache")).pack(fill="x", pady=2)
        ttk.Button(reference, text="Erase userdata", command=lambda: self._run_fastboot_maintenance("erase", "userdata")).pack(fill="x", pady=2)
        ttk.Button(reference, text="Wipe data (fastboot -w)", command=lambda: self._run_fastboot_maintenance("-w")).pack(fill="x", pady=2)
        self.maintenance_command = tk.StringVar(value="Select an operation to preview its command.")
        ttk.Label(reference, textvariable=self.maintenance_command, background="#0b1220", foreground="#f1f5f9",
                  padding=7, justify="left", wraplength=320, font=("Monospace", 9)).pack(fill="x", pady=(5, 0))
        self.maintenance_status = tk.StringVar(value="No maintenance command executed.")
        ttk.Label(reference, textvariable=self.maintenance_status, background="#1f2937", foreground="#cbd5e1",
                  wraplength=320, justify="left", font=("Sans", 9)).pack(anchor="w", pady=(5, 0))

        # Compact two-row flashing pipeline: file/partition/flash, then command/preview/run.
        pipeline = ttk.Frame(controls, style="Panel.TFrame", padding=10)
        pipeline.grid(row=1, column=0, sticky="ew", pady=(0, 12))
        # Keep the action column wide enough for complete button labels.
        pipeline.columnconfigure(0, weight=3, minsize=300, uniform="flash_pipeline")
        pipeline.columnconfigure(1, weight=1, minsize=160, uniform="flash_pipeline")
        pipeline.columnconfigure(2, weight=0, minsize=148, uniform="flash_pipeline")

        def pipeline_label(parent, text):
            ttk.Label(parent, text=text, background="#1f2937", foreground="#93c5fd",
                      font=("Sans", 9, "bold")).pack(anchor="w", pady=(0, 4))

        # Row 1 / column 1: single-line path field and adjacent Browse button.
        image_cell = ttk.Frame(pipeline, style="Panel.TFrame")
        image_cell.grid(row=0, column=0, sticky="ew", padx=(0, 8), pady=(0, 12))
        pipeline_label(image_cell, "IMAGE FILE")
        image_row = ttk.Frame(image_cell, style="Panel.TFrame")
        image_row.pack(fill="x")
        self.flash_image = tk.StringVar()
        self.flash_entry = ttk.Entry(image_row, textvariable=self.flash_image)
        self.flash_entry.pack(side="left", fill="x", expand=True, ipady=4)
        ttk.Button(image_row, text="Browse…", command=self._browse_flash_image,
                   width=10).pack(side="left", padx=(6, 0), ipady=2)
        self._enable_drop(image_cell)
        self._enable_drop(self.flash_entry)

        # Row 1 / column 2: deliberately fixed-width target selector.
        partition_cell = ttk.Frame(pipeline, style="Panel.TFrame")
        partition_cell.grid(row=0, column=1, sticky="ew", padx=(0, 8), pady=(0, 12))
        pipeline_label(partition_cell, "TARGET PARTITION")
        self.flash_partition = tk.StringVar()
        self.partition_combo = ttk.Combobox(
            partition_cell, textvariable=self.flash_partition,
            values=("boot", "vendor", "vendor_boot", "init_boot", "dtbo", "vbmeta", "recovery",
                    "system", "product", "odm", "system_ext", "vbmeta_system", "vbmeta_vendor"),
            state="readonly", width=18)
        self.partition_combo.pack(fill="x", ipady=2)
        # Only explicit dropdown selection may change the flash target; scrolling must not.
        def _block_partition_wheel(_event):
            return "break"
        # X11/Tk only defines wheel buttons 4 and 5; buttons 6/7 raise
        # TclError on Linux and prevent the frozen AppImage from starting.
        for _wheel_event in ("<MouseWheel>", "<Shift-MouseWheel>", "<Button-4>", "<Button-5>"):
            self.partition_combo.bind(_wheel_event, _block_partition_wheel)

        # Row 1 / column 3: primary action, aligned with the controls.
        flash_cell = ttk.Frame(pipeline, style="Panel.TFrame")
        flash_cell.grid(row=0, column=2, sticky="ew", pady=(18, 12))
        ttk.Button(flash_cell, text="Flash image…", command=self._flash_image,
                   style="Primary.TButton", width=16).pack(fill="x", ipady=4)

        # Row 2 / column 1: custom host-side Fastboot command.
        command_cell = ttk.Frame(pipeline, style="Panel.TFrame")
        command_cell.grid(row=1, column=0, sticky="ew", padx=(0, 8))
        pipeline_label(command_cell, "ADVANCED FASTBOOT COMMAND")
        self.fastboot_manual_command = tk.StringVar(value="fastboot devices")
        self.fastboot_manual_entry = ttk.Entry(command_cell, textvariable=self.fastboot_manual_command)
        self.fastboot_manual_entry.pack(fill="x", ipady=4)
        self._enable_command_drop(self.fastboot_manual_entry, self.fastboot_manual_command, "fastboot")

        # Row 2 / column 2: preview action and compact status.
        preview_cell = ttk.Frame(pipeline, style="Panel.TFrame")
        preview_cell.grid(row=1, column=1, sticky="ew", padx=(0, 8))
        pipeline_label(preview_cell, "COMMAND PREVIEW")
        ttk.Button(preview_cell, text="Preview command",
                   command=self._update_flash_preview, width=16).pack(fill="x", ipady=4)

        # Row 2 / column 3: execute the entered host-side command.
        run_cell = ttk.Frame(pipeline, style="Panel.TFrame")
        run_cell.grid(row=1, column=2, sticky="ew")
        pipeline_label(run_cell, "RUN")
        manual_buttons = ttk.Frame(run_cell, style="Panel.TFrame")
        manual_buttons.pack(fill="x")
        ttk.Button(manual_buttons, text="Run command", command=self._run_fastboot_manual,
                   style="Primary.TButton", width=16).pack(fill="x", ipady=4)
        ttk.Button(run_cell, text="Clear command",
                   command=lambda: self.fastboot_manual_command.set(""),
                   width=16).pack(fill="x", pady=(4, 0), ipady=2)

        # Read-only preview stays separate from command execution and console output.
        self.flash_command = tk.StringVar(value="Select an image, partition, and Fastboot device.")
        preview_output = ttk.Label(controls, textvariable=self.flash_command,
                                   background="#0b1220", foreground="#cbd5e1",
                                   padding=(8, 5), font=("Monospace", 9), anchor="w")
        preview_output.grid(row=2, column=0, sticky="ew", pady=(0, 8))

        ttk.Label(controls,
                  text="⚠ FLASHING RISK · An incompatible image or incorrect partition can prevent Android from booting. Verify compatibility before flashing.",
                  foreground="#fecaca", background="#2a1d27", wraplength=850, justify="left",
                  font=("Sans", 9), padding=8).grid(row=3, column=0, sticky="ew", pady=(0, 8))

        self.flash_image.trace_add("write", lambda *_: self._on_flash_image_changed())
        self._enable_drop(tab)

        # The console owns the full right workspace height for continuous output visibility.
        right = ttk.Frame(tab, style="Panel.TFrame", padding=5)
        right.grid(row=3, column=1, sticky="nsew")
        right.columnconfigure(0, weight=1)
        right.rowconfigure(1, weight=1)

        # Telemetry moved to the app header; the live console fills the right pane.
        console_panel = ttk.Frame(right, style="Panel.TFrame", padding=2)
        console_panel.grid(row=1, column=0, sticky="nsew")
        ttk.Label(console_panel, text="REAL-TIME CONSOLE / ACTIVITY", background="#1f2937",
                  foreground="#93c5fd", font=("Sans", 11, "bold")).pack(anchor="w", pady=(0, 5))
        fast_console_frame = ttk.Frame(console_panel, style="Panel.TFrame")
        fast_console_frame.pack(fill="both", expand=True)
        self.fastboot_console = tk.Text(fast_console_frame, height=12, bg="#0b1220", fg="#d1d5db",
            insertbackground="white", relief="flat", wrap="word", font=(self._mono_font, 9), state="disabled")
        fast_console_scroll = ttk.Scrollbar(fast_console_frame, orient="vertical", command=self.fastboot_console.yview)
        self.fastboot_console.configure(yscrollcommand=fast_console_scroll.set)
        fast_console_scroll.pack(side="right", fill="y")
        self.fastboot_console.pack(side="left", fill="both", expand=True)
        self._console_write(self.fastboot_console, "[DroidLab] Fastboot console ready. Commands and activity will appear here.\n")

        self.flash_image.trace_add("write", lambda *_: self._on_flash_image_changed())
        self.flash_partition.trace_add("write", lambda *_: self._update_flash_preview())
        self.fastboot_device.trace_add("write", lambda *_: self._update_flash_preview())

