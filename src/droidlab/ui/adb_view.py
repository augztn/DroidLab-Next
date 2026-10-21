"""ADB diagnostics, device information, and logcat workspace construction."""
from __future__ import annotations
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

class ADBViewSupport:
    def _build_adb_tab(self, tab):
        tab.columnconfigure(0, weight=1)
        tab.rowconfigure(2, weight=0, minsize=0)
        tab.rowconfigure(3, weight=1)
        modebar = ttk.Frame(tab)
        modebar.grid(row=0, column=0, sticky="ew", pady=(0, 4))
        ttk.Label(modebar, text="Device mode", font=(self._ui_font, 16, "bold")).pack(side="left", padx=(0, 12))
        self.adb_workspace_mode_button = ttk.Button(modebar, text="ADB & Sideload",
            command=lambda: self._show_device_workspace("adb", manual=True), style="Primary.TButton")
        self.adb_workspace_mode_button.pack(side="left", padx=(0, 5))
        self.fastboot_workspace_mode_button = ttk.Button(modebar, text="Fastboot & Flashing",
            command=lambda: self._show_device_workspace("fastboot", manual=True))
        self.fastboot_workspace_mode_button.pack(side="left")
        ttk.Label(tab, text="Reboot, collect logs and diagnostics, run device shell commands, or sideload an OTA ZIP from recovery.", style="Muted.TLabel", wraplength=900).grid(row=1, column=0, sticky="w", pady=(0, 3))
        device=ttk.Frame(tab,style="Panel.TFrame",padding=6); device.grid(row=2,column=0,sticky="ew",pady=(0,6))
        ttk.Label(device,text="ADB DEVICE",background="#1f2937",foreground="#93c5fd").pack(anchor="w")
        row=ttk.Frame(device,style="Panel.TFrame"); row.pack(fill="x",pady=(5,0))
        self.adb_device=tk.StringVar(); self.adb_device_combo=ttk.Combobox(row,textvariable=self.adb_device,state="readonly"); self.adb_device_combo.configure(width=18); self.adb_device_combo.pack(side="left",anchor="w")
        ttk.Button(row,text="Refresh devices",command=self._refresh_adb_devices).pack(side="left",padx=(8,0))
        self.adb_device_status=tk.StringVar(value="Connect device or enter recovery sideload mode, then refresh.")
        self.device_mode_status = tk.StringVar(value="MODE DETECTOR: Waiting for device scan")
        ttk.Label(device,textvariable=self.device_mode_status,background="#1f2937",foreground="#86efac",
                  wraplength=1000,font=("Sans",10,"bold")).pack(anchor="w",pady=(6,0))
        ttk.Label(device,textvariable=self.adb_device_status,background="#1E222D",foreground="#94A3B8",wraplength=650).pack(anchor="w",pady=(2,0))
        # Controls remain on the left; device info and an expanded console share the right column.
        workspace=ttk.Frame(tab); workspace.grid(row=3,column=0,sticky="nsew"); workspace.columnconfigure(0,weight=13,uniform="adb_workspace"); workspace.columnconfigure(1,weight=7,uniform="adb_workspace"); workspace.rowconfigure(0,weight=1)
        lower=ttk.Frame(workspace); lower.grid(row=0,column=0,sticky="nsew",padx=(0,10)); lower.columnconfigure(0,weight=1); lower.rowconfigure(2,weight=1)
        right=ttk.Frame(workspace); right.grid(row=0,column=1,sticky="nsew"); right.columnconfigure(0,weight=1); right.rowconfigure(1,weight=1)
        adb_info = ttk.Frame(right, style="Panel.TFrame", padding=6)
        adb_info.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        adb_info.columnconfigure(1, weight=1)
        self.adb_device_info_mode = tk.StringVar(value="NO DEVICE")
        self.adb_device_info_mode_label = tk.Label(adb_info, textvariable=self.adb_device_info_mode,
            bg="#065F46", fg="#FFFFFF", padx=7, pady=2, font=("Sans", 8, "bold"))
        self.adb_device_info_mode_label.grid(row=0, column=0, sticky="w", padx=(0, 8))
        self.adb_info_loading = tk.StringVar(value="")
        ttk.Label(adb_info, textvariable=self.adb_info_loading, background="#1E222D",
                  foreground="#FBBF24").grid(row=0, column=6, sticky="e")
        self.adb_device_info_vars = {}
        adb_fields = (("Device", "Device name / Model"), ("Codename", "Codename"),
                      ("Slot", "Active slot"), ("Android", "Android Version"), ("Battery", "Battery"))
        for col, (label, key) in enumerate(adb_fields, start=1):
            cell = ttk.Frame(adb_info, style="Panel.TFrame")
            cell.grid(row=0, column=col, sticky="w", padx=(0, 10))
            ttk.Label(cell, text=label.upper(), background="#1E222D", foreground="#8B949E",
                      font=("Sans", 8, "bold")).pack(side="left", padx=(0, 4))
            var = tk.StringVar(value="—")
            self.adb_device_info_vars[key] = var
            ttk.Label(cell, textvariable=var, background="#1E222D", foreground="#E6EDF3",
                      font=(self._mono_font, 9)).pack(side="left")
        # Left-side controls were created in `lower`; keep the existing workspace and right column.
        adb_console_panel=ttk.Frame(right,style="Panel.TFrame",padding=4); adb_console_panel.grid(row=1,column=0,sticky="nsew"); adb_console_panel.rowconfigure(1,weight=1); adb_console_panel.columnconfigure(0,weight=1)
        ttk.Label(adb_console_panel,text="REAL-TIME CONSOLE / ACTIVITY",background="#1f2937",foreground="#93c5fd",font=("Sans",12,"bold")).grid(row=0,column=0,sticky="w",pady=(0,6))
        self.adb_console=tk.Text(adb_console_panel,bg="#0b1220",fg="#d1d5db",insertbackground="white",relief="flat",wrap="word",font=(self._mono_font,9),state="disabled")
        adb_console_scroll=ttk.Scrollbar(adb_console_panel,orient="vertical",command=self.adb_console.yview); adb_console_scroll.grid(row=1,column=1,sticky="ns"); self.adb_console.configure(yscrollcommand=adb_console_scroll.set); self.adb_console.grid(row=1,column=0,sticky="nsew")
        self._console_write(self.adb_console,"[DroidLab] ADB command output will appear here in real time.\n")
        actions=ttk.Frame(lower); actions.grid(row=0,column=0,sticky="ew",pady=(0,10))
        power=ttk.Frame(actions,style="Panel.TFrame",padding=6); power.pack(side="left",fill="both",expand=True,padx=(0,8))
        ttk.Label(power,text="POWER & REBOOTING",background="#1f2937",foreground="#93c5fd").pack(anchor="w",pady=(0,6))
        row=ttk.Frame(power,style="Panel.TFrame"); row.pack(fill="x")
        for col in range(3): row.columnconfigure(col, weight=1, uniform="power_actions")
        self.reboot_button=ttk.Button(row,text="Reboot",command=lambda:self._adb_reboot(""))
        self.reboot_button.grid(row=0,column=0,sticky="ew",padx=(0,3))
        self.bootloader_button=ttk.Button(row,text="Bootloader",command=lambda:self._adb_reboot("bootloader"))
        self.bootloader_button.grid(row=0,column=1,sticky="ew",padx=3)
        self.recovery_button=ttk.Button(row,text="Recovery",command=lambda:self._adb_reboot("recovery"))
        self.recovery_button.grid(row=0,column=2,sticky="ew",padx=(3,0))
        diag=ttk.Frame(actions,style="Panel.TFrame",padding=6); diag.pack(side="left",fill="both",expand=True)
        ttk.Label(diag,text="LOGS & DIAGNOSTICS",background="#1f2937",foreground="#93c5fd").pack(anchor="w",pady=(0,6))
        row=ttk.Frame(diag,style="Panel.TFrame"); row.pack(fill="x")
        for col in range(3): row.columnconfigure(col, weight=1, uniform="diag_actions")
        ttk.Button(row,text="Live logcat",command=self._start_adb_logcat).grid(row=0,column=0,sticky="ew",padx=(0,3))
        ttk.Button(row,text="Save logcat…",command=self._save_adb_logcat).grid(row=0,column=1,sticky="ew",padx=3)
        ttk.Button(row,text="Bugreport ZIP…",command=self._create_adb_bugreport).grid(row=0,column=2,sticky="ew",padx=(3,0))
        side=ttk.Frame(lower,style="Panel.TFrame",padding=6); side.grid(row=1,column=0,sticky="ew",pady=(0,6))
        ttk.Label(side,text="ADB SIDELOAD — INSTALL ZIP PACKAGE",background="#1f2937",foreground="#93c5fd",font=("Sans",12,"bold")).pack(anchor="w")
        row=ttk.Frame(side,style="Panel.TFrame"); row.pack(fill="x",pady=(5,0))
        self.sideload_file=tk.StringVar(); self.sideload_entry=ttk.Entry(row,textvariable=self.sideload_file); self.sideload_entry.pack(side="left",fill="x",expand=True,ipady=4)
        ttk.Button(row,text="Browse ZIP…",command=self._browse_sideload_zip).pack(side="left",padx=(7,0))
        ttk.Button(row,text="Sideload ZIP…",command=self._run_adb_sideload,style="Primary.TButton").pack(side="left",padx=(7,0))
        drop_hint=ttk.Label(side,text="⬇  Drop a flashable ZIP here or browse for a package.",background="#161922",foreground="#93c5fd",padding=7,wraplength=800); drop_hint.pack(fill="x",pady=(6,0))
        for drop_widget in (side, self.sideload_entry, drop_hint): self._enable_sideload_drop(drop_widget)
        ttk.Label(side,text="Recovery must support ADB sideload. Check package compatibility.",background="#1E222D",foreground="#94A3B8",wraplength=800).pack(anchor="w",pady=(3,0))
        shell=ttk.Frame(lower,style="Panel.TFrame",padding=6); shell.grid(row=2,column=0,sticky="nsew"); shell.columnconfigure(0,weight=1); shell.rowconfigure(2,weight=1)
        ttk.Label(shell,text="ADVANCED DEVICE SHELL",background="#1f2937",foreground="#93c5fd",font=("Sans",12,"bold")).grid(row=0,column=0,sticky="w")
        row=ttk.Frame(shell,style="Panel.TFrame"); row.grid(row=1,column=0,sticky="ew",pady=(5,7))
        self.adb_shell_command=tk.StringVar(value="dumpsys battery")
        self.adb_shell_entry=ttk.Entry(row,textvariable=self.adb_shell_command)
        self.adb_shell_entry.pack(side="left",fill="x",expand=True,ipady=4)
        self.adb_shell_entry.bind("<Return>",lambda _event:self._run_adb_shell())
        ttk.Button(row,text="Run command",command=self._run_adb_shell,style="Primary.TButton").pack(side="left",padx=(7,0))
        self._enable_command_drop(self.adb_shell_entry,self.adb_shell_command,"adb")
        ttk.Label(shell,text="Device shell: dumpsys battery  ·  Use ADB controls for host-side commands.",
                  background="#1E222D",foreground="#94A3B8",wraplength=900,justify="left").grid(row=3,column=0,sticky="w",pady=(4,0))
        self.adb_output=tk.Text(shell,height=7,bg="#0b1220",fg="#d1d5db",insertbackground="white",relief="flat",wrap="word",font=("Monospace",10)); self.adb_output.grid(row=2,column=0,sticky="nsew")
        self.adb_output.insert("end","Select a device, then run dumpsys battery or another trusted shell command.\n"); self.adb_output.configure(state="disabled")
        self.adb_log_process = None
        self.adb_log_window = None
        self.adb_log_text = None
        self.adb_log_filter = tk.StringVar()
        self.adb_log_paused = False
        self.adb_log_lines = []

