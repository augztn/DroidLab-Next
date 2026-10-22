from __future__ import annotations

import os
import shlex
import subprocess
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from droidlab.core.command_guards import (
    is_fastboot_target_connected,
    is_valid_partition_name,
    validate_device_selector,
)


def _windows_process_options():
    """Keep ADB/Fastboot subprocesses from flashing console windows on Windows."""
    if os.name != "nt":
        return {}
    startupinfo = subprocess.STARTUPINFO()
    startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startupinfo.wShowWindow = 0
    return {
        "creationflags": getattr(subprocess, "CREATE_NO_WINDOW", 0),
        "startupinfo": startupinfo,
    }


class FastbootControllerMixin:
    def _ensure_fastboot_target_connected(self, binary, serial):
        """Require a successful, fresh Fastboot scan before device-mutating commands."""
        try:
            result = subprocess.run(
                [binary, "devices", "-l"],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=4,
                check=False,
                **_windows_process_options(),
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            messagebox.showerror(
                "Fastboot device check failed",
                "Could not verify the selected device immediately before execution. "
                "No command was sent.\n\n" + str(exc),
            )
            return False
        if not is_fastboot_target_connected(serial, result.stdout, result.returncode):
            messagebox.showerror(
                "Fastboot device unavailable",
                "The selected device "
                + repr(serial)
                + " was not present in a successful fresh Fastboot scan. "
                "No command was sent. Refresh devices and try again.",
            )
            return False
        return True

    def _fastboot_quick_action(self, args):
        """Run a confirmed Fastboot reboot action through the live streaming runner."""
        serial = self.fastboot_device.get().strip()
        binary = self._tool_path(
            "fastboot.exe" if os.name == "nt" else "fastboot"
        ) or self._tool_path("fastboot")
        if not binary:
            messagebox.showerror(
                "Fastboot not found", "Install Android Platform-Tools or add fastboot to PATH."
            )
            return
        if not serial or serial not in self.device_combo["values"]:
            messagebox.showwarning(
                "Select Fastboot device",
                "Refresh devices and select a connected Fastboot device first.",
            )
            return
        command = [binary, "-s", serial] + list(args)
        rendered = " ".join(shlex.quote(part) for part in command)
        if not messagebox.askyesno(
            "Confirm reboot", "Execute this command on " + serial + "?\n\n" + rendered
        ):
            self._console_write(self.fastboot_console, "[DroidLab] Cancelled: " + rendered + "\n")
            return
        if not self._ensure_fastboot_target_connected(binary, serial):
            return
        self._append("Executing Fastboot action: " + rendered)
        self._console_write(self.fastboot_console, "[DroidLab] $ " + rendered + "\n")
        self.status.set("Running Fastboot command…")
        self._rescan_after_mode_change = True
        threading.Thread(
            target=self._adb_task, args=(command, 90, "fastboot_manual"), daemon=True
        ).start()
        # USB mode transitions are asynchronous; scan again after Android/bootloader reconnects.
        for delay in (2000, 5000, 9000, 14000):
            self.after(delay, self._refresh_adb_devices)

    def _run_fastboot_manual(self):
        text = self.fastboot_manual_command.get().strip()
        if not text:
            messagebox.showwarning("Command required", "Enter a Fastboot command.")
            return
        try:
            tokens = shlex.split(text, posix=(os.name != "nt"))
        except ValueError as exc:
            messagebox.showerror("Invalid command", "Check the command quoting:\n" + str(exc))
            return
        if not tokens:
            return
        first = Path(tokens[0]).name.lower()
        # The Fastboot command field is a convenience console, but it must not
        # run ADB commands through fastboot.exe (e.g. "adb devices"). Delegate
        # ADB-prefixed input to the host-side ADB runner, which handles device
        # selection, output streaming, and errors correctly.
        if first in ("adb", "adb.exe"):
            self.adb_shell_command.set(text)
            self._append("Routing ADB command from Fastboot console to the host ADB runner.")
            self._run_adb_shell()
            return
        if first in ("fastboot", "fastboot.exe"):
            tokens = tokens[1:]
        binary = self._tool_path(
            "fastboot.exe" if os.name == "nt" else "fastboot"
        ) or self._tool_path("fastboot")
        if not binary:
            messagebox.showerror(
                "Fastboot not found",
                "Bundle platform-tools or install Fastboot and add it to PATH.",
            )
            return
        if not tokens:
            tokens = ["devices"]
        serial = self.fastboot_device.get().strip()
        # If the dedicated Fastboot selector is empty, reuse the shared ADB &
        # Sideload selector only when it currently identifies a Fastboot device.
        if not serial:
            shared = getattr(self, "_adb_targets", {}).get(self.adb_device.get())
            if shared and shared[1] == "fastboot":
                serial = shared[0]
        discovery = tokens[0] in ("devices", "help", "--help", "--version", "version")
        if not discovery:
            if not serial:
                messagebox.showerror(
                    "Device required", "Select a Fastboot device before running a device command."
                )
                return
            try:
                explicit = validate_device_selector(tokens, "fastboot", serial)
            except ValueError as exc:
                messagebox.showerror("Device target conflict", str(exc))
                self._append("Fastboot command rejected: " + str(exc))
                return
            if explicit is None:
                tokens = ["-s", serial] + tokens
        command = [binary] + tokens
        rendered = " ".join(shlex.quote(x) for x in command)
        if not messagebox.askyesno(
            "Confirm advanced Fastboot command",
            "Advanced Fastboot commands are unrestricted and cannot be proven safe.\n\n"
            + "Executable: "
            + binary
            + "\nTarget: "
            + (serial or "no device (discovery/help command)")
            + "\nArguments: "
            + " ".join(shlex.quote(x) for x in tokens)
            + "\n\nCommands may erase data or make the device unbootable. Continue?",
            icon="warning",
        ):
            self._append("Manual Fastboot command cancelled: " + rendered)
            return
        if not discovery and serial and not self._ensure_fastboot_target_connected(binary, serial):
            return
        self._append("Executing manual Fastboot command: " + rendered)
        self.status.set("Running Fastboot command…")
        # Only reboot changes USB mode. Do not trigger repeated device scans
        # for harmless commands such as getvar, devices, or flashing.
        self._rescan_after_mode_change = bool(tokens and tokens[0].lower() == "reboot")
        threading.Thread(
            target=self._adb_task, args=(command, 900, "fastboot_manual"), daemon=True
        ).start()

    def _run_fastboot_maintenance(self, operation, partition=None):
        binary = self._tool_path(
            "fastboot.exe" if os.name == "nt" else "fastboot"
        ) or self._tool_path("fastboot")
        if not binary:
            messagebox.showerror(
                "Fastboot not found",
                "Install Android SDK Platform-Tools and ensure fastboot is on PATH.",
            )
            return
        serial = self.fastboot_device.get().strip()
        if not serial or serial not in self.device_combo["values"]:
            messagebox.showwarning(
                "Select Fastboot device",
                "Click Refresh devices and select a connected Fastboot device first.",
            )
            return
        if operation == "-w":
            command = [binary, "-s", serial, "-w"]
            label = "Wipe user data and cache (fastboot -w)"
            warning = (
                "This will wipe user data and cache on device "
                + serial
                + ". This is destructive and may remove your apps, accounts, photos, and files. Continue only if you have a backup and intend to factory-reset this device."
            )
        else:
            command = [binary, "-s", serial, operation, partition]
            label = "Erase " + partition
            if partition == "cache":
                warning = (
                    "This will erase the cache partition on "
                    + serial
                    + ", if this device has one. Some devices do not have a separate cache partition. Continue?"
                )
            else:
                warning = (
                    "This will erase the userdata partition on "
                    + serial
                    + " and permanently delete user data. This can make data unrecoverable. Ensure you have a backup. Continue?"
                )
        rendered = " ".join(shlex.quote(part) for part in command)
        self.maintenance_command.set(rendered)
        if not messagebox.askyesno(
            "Confirm destructive Fastboot operation",
            warning + "\n\nCommand to execute:\n" + rendered,
            icon="warning",
        ):
            self.maintenance_status.set("Cancelled: " + label)
            self._append("Fastboot maintenance cancelled: " + rendered)
            return
        if not self._ensure_fastboot_target_connected(binary, serial):
            return
        self.maintenance_status.set("Running: " + label + "…")
        self._append("Executing Fastboot maintenance: " + rendered)
        threading.Thread(
            target=self._adb_task, args=(command, 900, "fastboot_maintenance"), daemon=True
        ).start()

    def _on_flash_image_changed(self):
        path = Path(self.flash_image.get().strip().strip(chr(34)).strip(chr(39)))
        mapping = {
            "boot.img": "boot",
            "vendor.img": "vendor",
            "vendor_boot.img": "vendor_boot",
            "init_boot.img": "init_boot",
            "dtbo.img": "dtbo",
            "vbmeta.img": "vbmeta",
            "recovery.img": "recovery",
            "system.img": "system",
            "product.img": "product",
            "odm.img": "odm",
            "system_ext.img": "system_ext",
            "vbmeta_system.img": "vbmeta_system",
            "vbmeta_vendor.img": "vbmeta_vendor",
        }
        if path.name.lower() in mapping:
            self.flash_partition.set(mapping[path.name.lower()])
            self._append(
                "Filename suggests partition "
                + mapping[path.name.lower()]
                + "; verify compatibility before flashing."
            )
        self._update_flash_preview()

    def _browse_flash_image(self):
        path = filedialog.askopenfilename(
            parent=self,
            title="Choose image to flash",
            initialdir=str(Path.home()),
            filetypes=[("Android image", "*.img"), ("All files", "*.*")],
        )
        if path:
            self.flash_image.set(path)

    def _refresh_fastboot_devices(self):
        """Refresh both selectors using the shared background device scanner."""
        self._refresh_adb_devices()

    def _update_flash_preview(self):
        image = self.flash_image.get().strip().strip(chr(34)).strip(chr(39))
        part = self.flash_partition.get().strip()
        serial = self.fastboot_device.get().strip()
        self.flash_command.set(
            "Select an image, partition, and one Fastboot device."
            if not (image and part and serial)
            else "fastboot -s " + serial + " flash " + part + " " + shlex.quote(image)
        )

    def _flash_image(self):
        image = Path(self.flash_image.get().strip().strip(chr(34)).strip(chr(39))).expanduser()
        part = self.flash_partition.get().strip()
        serial = self.fastboot_device.get().strip()
        binary = self._tool_path(
            "fastboot.exe" if os.name == "nt" else "fastboot"
        ) or self._tool_path("fastboot")
        if not binary:
            messagebox.showerror(
                "Fastboot not found",
                "Install Android platform-tools and ensure fastboot is on PATH.",
            )
            return
        if not image.is_file() or image.suffix.lower() != ".img":
            messagebox.showerror("Invalid image", "Choose an existing .img file.")
            return
        if not is_valid_partition_name(part):
            messagebox.showerror(
                "Invalid partition",
                "Enter a valid partition name beginning with a letter or number.",
            )
            return
        if not serial:
            messagebox.showwarning(
                "Select device", "Refresh devices and select exactly one Fastboot device."
            )
            return
        command = [binary, "-s", serial, "flash", part, str(image.resolve())]
        rendered_command = " ".join(shlex.quote(x) for x in command)
        if not self._confirm_flash_dialog(serial, image.resolve(), part, rendered_command):
            self._append("Flash cancelled before execution.")
            return
        if not self._ensure_fastboot_target_connected(binary, serial):
            return
        self._append("Executing: " + " ".join(shlex.quote(x) for x in command))
        self.status.set("Flashing image…")
        self.update_idletasks()
        threading.Thread(
            target=self._adb_task, args=(command, 900, "fastboot_flash"), daemon=True
        ).start()

    def _confirm_flash_dialog(self, serial, image, partition, rendered_command):
        """Show a compact, bounded confirmation dialog before any Fastboot flash."""
        dialog = tk.Toplevel(self)
        dialog.title("Confirm flashing")
        dialog.configure(bg=self.theme_tokens["bg"])
        dialog.transient(self)
        dialog.resizable(False, False)
        dialog.withdraw()

        surface = self.theme_tokens["panel"]
        border = self.theme_tokens["border"]
        text = self.theme_tokens["text"]
        muted = self.theme_tokens["muted"]
        mono = getattr(self, "_mono_font", "Consolas")
        body = tk.Frame(dialog, bg=self.theme_tokens["bg"], padx=18, pady=16)
        body.pack(fill="both", expand=True)

        heading = tk.Frame(body, bg=self.theme_tokens["bg"])
        heading.pack(fill="x", pady=(0, 14))
        tk.Label(
            heading,
            text="⚠  Confirm flashing",
            bg=self.theme_tokens["bg"],
            fg=text,
            font=("Sans", 15, "bold"),
        ).pack(side="left")
        tk.Label(
            heading,
            text="VERIFY TARGET",
            bg=self.theme_tokens["panel_alt"],
            fg=self.theme_tokens["accent"],
            padx=8,
            pady=3,
            font=("Sans", 8, "bold"),
        ).pack(side="right")

        details = tk.Frame(
            body, bg=surface, highlightthickness=1, highlightbackground=border, padx=12, pady=10
        )
        details.pack(fill="x")

        def detail_row(row, label, value, *, value_font=None, value_color=text):
            tk.Label(
                details,
                text=label.upper(),
                bg=surface,
                fg=muted,
                font=("Sans", 8, "bold"),
                anchor="w",
            ).grid(row=row, column=0, sticky="nw", padx=(0, 16), pady=5)
            tk.Label(
                details,
                text=value,
                bg=surface,
                fg=value_color,
                font=value_font or ("Sans", 10, "normal"),
                anchor="w",
                justify="left",
                wraplength=420,
            ).grid(row=row, column=1, sticky="ew", pady=5)

        details.columnconfigure(1, weight=1)
        detail_row(0, "Device", serial, value_font=(mono, 10, "bold"))
        tk.Label(
            details,
            text="TARGET PARTITION",
            bg=surface,
            fg=muted,
            font=("Sans", 8, "bold"),
            anchor="w",
        ).grid(row=1, column=0, sticky="w", padx=(0, 16), pady=5)
        tk.Label(
            details,
            text="[" + partition + "]",
            bg=self.theme_tokens["panel_alt"],
            fg=self.theme_tokens["accent"],
            padx=7,
            pady=3,
            font=(mono, 10, "bold"),
        ).grid(row=1, column=1, sticky="w", pady=5)
        detail_row(2, "File name", image.name, value_font=(mono, 10, "bold"))

        tk.Label(
            details, text="FULL PATH", bg=surface, fg=muted, font=("Sans", 8, "bold"), anchor="w"
        ).grid(row=3, column=0, sticky="nw", padx=(0, 16), pady=5)
        path_entry = tk.Entry(
            details,
            bg=self.theme_tokens["input"],
            fg=muted,
            insertbackground=text,
            readonlybackground=self.theme_tokens["input"],
            relief="flat",
            font=(mono, 9),
            state="readonly",
        )
        path_entry.configure(state="normal")
        path_entry.insert(0, str(image))
        path_entry.configure(state="readonly")
        path_entry.grid(row=3, column=1, sticky="ew", pady=5, ipady=5)

        tk.Label(
            body,
            text="COMMAND PREVIEW",
            bg=self.theme_tokens["bg"],
            fg=muted,
            font=("Sans", 8, "bold"),
        ).pack(anchor="w", pady=(12, 5))
        command_box = tk.Frame(
            body,
            bg=self.theme_tokens["console"],
            highlightthickness=1,
            highlightbackground=border,
            padx=8,
            pady=7,
        )
        command_box.pack(fill="x")
        command_entry = tk.Entry(
            command_box,
            bg=self.theme_tokens["console"],
            fg=self.theme_tokens["accent"],
            insertbackground=text,
            relief="flat",
            font=(mono, 9),
            state="normal",
            readonlybackground=self.theme_tokens["input"],
        )
        command_entry.insert(0, rendered_command)
        command_entry.configure(state="readonly")
        command_entry.grid(row=0, column=0, sticky="ew", ipady=3)
        command_scroll = ttk.Scrollbar(
            command_box, orient="horizontal", command=command_entry.xview
        )
        command_scroll.grid(row=1, column=0, sticky="ew", pady=(5, 0))
        command_entry.configure(xscrollcommand=command_scroll.set)
        command_box.columnconfigure(0, weight=1)

        warning = tk.Frame(
            body,
            bg=self.theme_tokens["panel_alt"],
            highlightthickness=1,
            highlightbackground=self.theme_tokens["border"],
            padx=10,
            pady=8,
        )
        warning.pack(fill="x", pady=(12, 0))
        tk.Label(
            warning,
            text="⚠",
            bg=self.theme_tokens["panel_alt"],
            fg=self.theme_tokens["accent"],
            font=("Sans", 13, "bold"),
        ).pack(side="left", anchor="n", padx=(0, 9))
        tk.Label(
            warning,
            text="An incompatible image or wrong partition can make the device unbootable. Verify the image matches this exact device and partition.",
            bg=self.theme_tokens["panel_alt"],
            fg=self.theme_tokens["text"],
            font=("Sans", 9),
            justify="left",
            wraplength=440,
        ).pack(side="left", fill="x", expand=True)

        actions = tk.Frame(body, bg=self.theme_tokens["bg"])
        actions.pack(fill="x", pady=(14, 0))
        result = {"confirmed": False}

        def close(confirmed=False):
            result["confirmed"] = confirmed
            try:
                dialog.grab_release()
            except tk.TclError:
                pass
            dialog.destroy()

        tk.Button(
            actions,
            text="Cancel",
            command=lambda: close(False),
            bg=self.theme_tokens["button"],
            fg=text,
            activebackground=self.theme_tokens["panel_alt"],
            activeforeground=text,
            relief="flat",
            padx=18,
            pady=7,
            font=("Sans", 10),
        ).pack(side="right", padx=(8, 0))
        tk.Button(
            actions,
            text="Flash Partition",
            command=lambda: close(True),
            bg=self.theme_tokens["accent2"],
            fg="#FFFFFF",
            activebackground=self.theme_tokens["accent"],
            activeforeground="#FFFFFF",
            relief="flat",
            padx=18,
            pady=7,
            font=("Sans", 10, "bold"),
        ).pack(side="right")

        dialog.bind("<Escape>", lambda _event: close(False))
        dialog.bind("<Return>", lambda _event: close(False))
        dialog.update_idletasks()
        screen_w, screen_h = dialog.winfo_screenwidth(), dialog.winfo_screenheight()
        requested_w = min(620, max(500, dialog.winfo_reqwidth()))
        requested_h = min(dialog.winfo_reqheight(), max(360, screen_h - 100))
        x = max(0, (screen_w - requested_w) // 2)
        y = max(0, (screen_h - requested_h) // 2)
        dialog.geometry(f"{requested_w}x{requested_h}+{x}+{y}")
        dialog.minsize(500, min(300, requested_h))
        dialog.deiconify()
        dialog.grab_set()
        dialog.focus_force()
        self.wait_window(dialog)
        return result["confirmed"]
