#!/usr/bin/env python3
"""Cross-platform DroidLab desktop UI for Android firmware workflows."""
from __future__ import annotations
import os, queue, threading, tkinter as tk, shutil, re, shlex, sys, json
import subprocess, webbrowser, logging, platform
from tkinter import filedialog, font as tkfont, messagebox, ttk
from tkinterdnd2 import DND_FILES, TkinterDnD
from pathlib import Path
from droidlab.config.constants import APP_NAME, THEME_TOKENS
from droidlab.config.logging_config import configure_logging as _configure_logging, log_directory as _log_directory, log_uncaught_exception as _log_uncaught_exception
from droidlab.config.settings import load_settings
from droidlab.core.payload_dumper import BackendError, extract, inspect_source, sha256_file
from droidlab.core.command_guards import (is_destructive_adb, is_destructive_fastboot, is_valid_partition_name,
                            validate_device_selector, is_fastboot_target_connected)
from droidlab.core.process_runner import ProcessCancelledError, run_streaming, terminate_process
from droidlab.ui.theme import ThemeSupport
from droidlab.ui.dialogs import DialogSupport
from droidlab.ui.widgets import WidgetSupport
from droidlab.ui.layout import LayoutSupport
from droidlab.ui.payload_view import PayloadViewSupport
from droidlab.ui.adb_view import ADBViewSupport
from droidlab.ui.fastboot_view import FastbootViewSupport

# Compatibility note: UI sizing now lives in ui/widgets.py and ui/payload_view.py;
# it still derives rowheight via tree_row_height(tkfont.Font(self, font=self._tree_font).metrics("linespace"))
# and wires the partition tree scrollbar with yscrollcommand=tree_scroll.set.
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









class PayloadDumperApp(DialogSupport, ThemeSupport, WidgetSupport, LayoutSupport, PayloadViewSupport, ADBViewSupport, FastbootViewSupport, TkinterDnD.Tk):
    def __init__(self):
        super().__init__()
        self.log_path = _configure_logging()
        sys.excepthook = _log_uncaught_exception
        self.title(APP_NAME)
        # Use a practical Windows-first size; ttk layouts and system fonts scale
        # more predictably than the oversized Linux-oriented defaults.
        self.geometry("1180x760")
        self.minsize(900, 600)
        self.theme_name = self._load_theme_name()
        self.theme_tokens = THEME_TOKENS[self.theme_name]
        self.configure(bg=self.theme_tokens["bg"])
        self._ui_font = "Segoe UI" if os.name == "nt" else "Sans"
        self._mono_font = "Consolas" if os.name == "nt" else "Monospace"
        self.events=queue.Queue(); self.worker=None; self.cancel_event=threading.Event()
        # One active device-mutating/diagnostic command per serial. This avoids
        # overlapping operations against the same physical target.
        self._device_operation_locks = {}
        self._device_operation_locks_guard = threading.Lock()
        menu=tk.Menu(self)
        help_menu=tk.Menu(menu, tearoff=False)
        help_menu.add_command(label="Debug Tools / Open Logs", command=self._open_log_folder)
        help_menu.add_command(label="Save Diagnostic Report…", command=self._save_diagnostic_report)
        help_menu.add_separator()
        help_menu.add_command(label="About DroidLab", command=self._show_about)
        menu.add_cascade(label="Help", menu=help_menu)
        self.configure(menu=menu)
        self.source=tk.StringVar(); self.output=tk.StringVar(value=str(Path.home()/APP_NAME)); self.fingerprint=tk.BooleanVar(value=True); self.status=tk.StringVar(value="Ready")
        self.parts={}; self.part_vars={}; self._build()
        self.report_callback_exception = self._report_callback_exception
        logging.info("UI initialized")
        self.after(100,self._poll_events)
    def _load_theme_name(self):
        """Load the saved theme, preserving the original fallback palette."""
        name = load_settings().get("theme")
        return name if name in THEME_TOKENS else "cyberpunk_glass"

    def _report_callback_exception(self, exc_type, exc_value, exc_traceback):
        logging.error("Unhandled Tkinter callback exception", exc_info=(exc_type, exc_value, exc_traceback))
        try:
            messagebox.showerror("DroidLab error", "An unexpected error occurred. Details were saved to the application log.\n\n" + str(self.log_path or _log_directory()), parent=self)
        except tk.TclError:
            pass

    def _open_log_folder(self):
        directory = _log_directory()
        try:
            directory.mkdir(parents=True, exist_ok=True)
            if os.name == "nt":
                os.startfile(str(directory))
            elif sys.platform == "darwin":
                subprocess.Popen(["open", str(directory)])
            else:
                subprocess.Popen(["xdg-open", str(directory)])
            logging.info("Opened log directory")
        except (OSError, tk.TclError) as exc:
            logging.exception("Could not open log directory")
            messagebox.showerror("Cannot open logs", "Log folder: " + str(directory) + "\n\n" + str(exc), parent=self)

    def _save_diagnostic_report(self):
        path = filedialog.asksaveasfilename(parent=self, title="Save DroidLab diagnostic report", defaultextension=".txt", initialfile="droidlab-diagnostics.txt", filetypes=[("Text files", "*.txt"), ("All files", "*.*")])
        if not path:
            return
        try:
            log_path = _log_directory() / "droidlab.log"
            with open(path, "w", encoding="utf-8") as report:
                report.write("DroidLab diagnostic report\n")
                report.write("Platform: " + platform.platform() + "\nPython: " + sys.version + "\n")
                report.write("Executable: " + sys.executable + "\nFrozen build: " + str(bool(getattr(sys, "frozen", False))) + "\n")
                report.write("Log directory: " + str(_log_directory()) + "\n\n--- Application log (latest file) ---\n")
                report.write(log_path.read_text(encoding="utf-8", errors="replace") if log_path.is_file() else "No log file found.\n")
            logging.info("Diagnostic report exported to %s", path)
            messagebox.showinfo("Diagnostics saved", "Report saved to:\n" + path, parent=self)
        except OSError:
            logging.exception("Could not export diagnostic report")
            messagebox.showerror("Export failed", "Could not write the diagnostic report. Check the destination and permissions.", parent=self)

    def _tool_path(self, name):
        """Prefer bundled platform-tools, then fall back to the user's PATH."""
        candidates = []
        if getattr(sys, "frozen", False):
            root = Path(sys.executable).resolve().parent
            candidates.extend([root / "bin" / name, root / "platform-tools" / name])
        else:
            root = Path(__file__).resolve().parent.parent
            candidates.extend([root / "bin" / name, root / "platform-tools" / name])
        for candidate in candidates:
            if candidate.is_file():
                return str(candidate)
        return shutil.which(name)


    def _fastboot_quick_action(self, args):
        """Run a confirmed Fastboot reboot action through the live streaming runner."""
        serial = self.fastboot_device.get().strip()
        binary = self._tool_path("fastboot.exe" if os.name == "nt" else "fastboot") or self._tool_path("fastboot")
        if not binary:
            messagebox.showerror("Fastboot not found", "Install Android Platform-Tools or add fastboot to PATH.")
            return
        if not serial or serial not in self.device_combo["values"]:
            messagebox.showwarning("Select Fastboot device", "Refresh devices and select a connected Fastboot device first.")
            return
        command = [binary, "-s", serial] + list(args)
        rendered = " ".join(shlex.quote(part) for part in command)
        if not messagebox.askyesno("Confirm reboot", "Execute this command on " + serial + "?\n\n" + rendered):
            self._console_write(self.fastboot_console, "[DroidLab] Cancelled: " + rendered + "\n")
            return
        self._append("Executing Fastboot action: " + rendered)
        self._console_write(self.fastboot_console, "[DroidLab] $ " + rendered + "\n")
        self.status.set("Running Fastboot command…")
        self._rescan_after_mode_change = True
        threading.Thread(target=self._adb_task, args=(command, 90, "fastboot_manual"), daemon=True).start()
        # USB mode transitions are asynchronous; scan again after Android/bootloader reconnects.
        for delay in (2000, 5000, 9000, 14000):
            self.after(delay, self._refresh_adb_devices)

    def _refresh_adb_devices(self):
        """Refresh one selector with devices visible to either ADB or Fastboot."""
        adb_binary = self._tool_path("adb.exe" if os.name == "nt" else "adb") or self._tool_path("adb")
        fastboot_binary = self._tool_path("fastboot.exe" if os.name == "nt" else "fastboot") or self._tool_path("fastboot")
        targets = {}
        status_lines = []
        if adb_binary:
            try:
                result = subprocess.run([adb_binary, "devices", "-l"], capture_output=True, text=True,
                    encoding="utf-8", errors="replace", timeout=10, check=False, **_windows_process_options())
                for line in result.stdout.splitlines()[1:]:
                    fields = line.split()
                    if len(fields) >= 2 and fields[1] in ("device", "sideload", "recovery", "unauthorized", "offline"):
                        targets[fields[0] + " [ADB: " + fields[1] + "]"] = (fields[0], "adb:" + fields[1])
                status_lines.append("ADB: " + (", ".join(k for k,v in targets.items() if v[1].startswith("adb:")) or "no devices"))
            except (OSError, subprocess.TimeoutExpired) as exc:
                status_lines.append("ADB scan failed: " + str(exc))
        else:
            status_lines.append("ADB tools not found")
        if fastboot_binary:
            try:
                result = subprocess.run([fastboot_binary, "devices", "-l"], capture_output=True, text=True,
                    encoding="utf-8", errors="replace", timeout=8, check=False, **_windows_process_options())
                found = []
                for line in result.stdout.splitlines():
                    fields = line.split()
                    if len(fields) >= 2 and fields[1].lower() == "fastboot":
                        label = fields[0] + " [Fastboot]"
                        targets[label] = (fields[0], "fastboot")
                        found.append(label)
                status_lines.append("Fastboot: " + (", ".join(found) or "no devices"))
            except (OSError, subprocess.TimeoutExpired) as exc:
                status_lines.append("Fastboot scan failed: " + str(exc))
        else:
            status_lines.append("Fastboot tools not found")
        previous = self.adb_device.get()
        # Classify the selected device before enabling mode-specific actions.
        self._adb_targets = targets
        labels = list(targets)
        self.adb_device_combo["values"] = labels
        self.adb_device.set(previous if previous in targets else (labels[0] if len(labels) == 1 else ""))
        self._on_shared_device_selected()
        self.adb_device_status.set(" | ".join(status_lines))
        selected = targets.get(self.adb_device.get())
        if selected:
            serial, state = selected
            if state == "fastboot":
                mode_detail = self._detect_fastboot_submode(fastboot_binary, serial)
                self.device_mode_status.set("MODE DETECTOR: " + mode_detail + " · Serial: " + serial)
            elif state.startswith("adb:"):
                adb_state = state.split(":", 1)[1]
                mode = {"device": "ADB / Android", "recovery": "ADB Recovery", "sideload": "ADB Sideload", "unauthorized": "ADB Unauthorized", "offline": "ADB Offline"}.get(adb_state, "ADB (" + adb_state + ")")
                self.device_mode_status.set("MODE DETECTOR: " + mode + " · Serial: " + serial)
        else:
            self.device_mode_status.set("MODE DETECTOR: No device detected · Check USB, drivers/udev rules, and Platform-Tools")
        self._refresh_device_info()
        self._append("Combined device scan: " + (", ".join(labels) if labels else "no ADB or Fastboot devices found"))

    def _set_device_info(self, values, mode, color):
        for vars_name, mode_name, label_name in (
            ("device_info_vars", "device_info_mode", "device_info_mode_label"),
            ("adb_device_info_vars", "adb_device_info_mode", "adb_device_info_mode_label")):
            vars_map = getattr(self, vars_name, None)
            if not vars_map:
                continue
            mode_var = getattr(self, mode_name, None)
            mode_label = getattr(self, label_name, None)
            if mode_var:
                mode_var.set(mode)
            if mode_label:
                mode_label.configure(bg=color)
            for key, value in values.items():
                if key in vars_map:
                    vars_map[key].set(value or "—")

        header_vars = getattr(self, "header_device_vars", {})
        targets = getattr(self, "_adb_targets", {})
        selected = targets.get(getattr(self, "adb_device", tk.StringVar()).get())
        serial = selected[0] if selected else ""
        is_fastboot = bool(selected and selected[1] == "fastboot")
        if header_vars:
            header_vars["mode"].set("FASTBOOT" if is_fastboot and "Fastbootd" not in mode else
                                    ("FASTBOOTD" if is_fastboot else (mode if selected else "NO DEVICE")))
            header_vars["serial"].set(serial or "—")
            header_vars["codename"].set(values.get("Codename") or values.get("Model code") or "—")
            bootloader = values.get("Bootloader") or "—"
            header_vars["bootloader"].set(bootloader.upper() if bootloader != "—" else "—")
            self.header_mode_label.configure(fg="#F97316" if is_fastboot else "#8B949E")
            boot_color = "#22C55E" if bootloader.lower() == "unlocked" else (
                "#EF4444" if bootloader.lower() == "locked" else "#F59E0B")
            self.header_bootloader_label.configure(fg=boot_color)
            slot = (values.get("Active slot") or "").strip().lower().replace("_", "")
            slot = slot[-1:] if slot.endswith(("a", "b")) else slot
            for name, button in self.header_slot_buttons.items():
                button.configure(state="normal" if is_fastboot else "disabled",
                                 bg="#2563EB" if is_fastboot and slot == name else "#30363D",
                                 fg="#FFFFFF" if is_fastboot and slot == name else "#8B949E")

    def _refresh_device_info(self):
        """Query selected device metadata asynchronously to keep the UI responsive."""
        target = getattr(self, "_adb_targets", {}).get(self.adb_device.get())
        empty = {"Brand / Manufacturer": "—", "Device name / Model": "—", "Model code": "—",
                 "Codename": "—", "Active slot": "—", "Bootloader": "—",
                 "Android Version": "—", "Battery": "—"}
        if not target:
            self._set_device_info(empty, "NO DEVICE", "#4b5563")
            if hasattr(self, "adb_info_loading"): self.adb_info_loading.set("")
            return
        serial, state = target
        self._set_device_info(empty, "LOADING…", "#4b5563")
        if hasattr(self, "adb_info_loading"): self.adb_info_loading.set("⟳ Reading device…")
        request_id = getattr(self, "_device_info_request_id", 0) + 1
        self._device_info_request_id = request_id
        def worker():
            values = dict(empty)
            if state == "fastboot":
                binary = self._tool_path("fastboot.exe" if os.name == "nt" else "fastboot") or self._tool_path("fastboot")
                mode = self._detect_fastboot_submode(binary, serial) if binary else "Fastboot"
                values["Device name / Model"] = serial
                values["Model code"] = self._fastboot_getvar(binary, serial, "product")
                values["Codename"] = values["Model code"]
                values["Active slot"] = self._fastboot_getvar(binary, serial, "current-slot")
                unlocked = self._fastboot_getvar(binary, serial, "unlocked").lower()
                values["Bootloader"] = {"yes": "Unlocked", "no": "Locked"}.get(unlocked, "Unknown")
                values["Brand / Manufacturer"] = self._fastboot_getvar(binary, serial, "manufacturer")
                result = (values, "FASTBOOTD" if "Fastbootd" in mode else "FASTBOOT",
                          "#2563eb" if "Fastbootd" in mode else "#ea580c")
            else:
                adb = self._tool_path("adb.exe" if os.name == "nt" else "adb") or self._tool_path("adb")
                adb_state = state.split(":", 1)[1] if state.startswith("adb:") else state
                mode, color = {"device": ("ADB", "#16a34a"), "recovery": ("RECOVERY", "#ca8a04"),
                               "sideload": ("SIDELOAD", "#ca8a04"), "unauthorized": ("ADB UNAUTHORIZED", "#ca8a04"),
                               "offline": ("ADB OFFLINE", "#ca8a04")}.get(adb_state, ("ADB", "#16a34a"))
                if adb:
                    def prop(name):
                        return self._adb_read_value(adb, serial, ["shell", "getprop", name])
                    values["Brand / Manufacturer"] = prop("ro.product.manufacturer") or prop("ro.product.brand")
                    values["Device name / Model"] = prop("ro.product.marketname") or prop("ro.product.model")
                    values["Model code"] = prop("ro.product.name") or prop("ro.product.model")
                    values["Codename"] = prop("ro.product.device") or prop("ro.build.product")
                    values["Active slot"] = prop("ro.boot.slot_suffix") or prop("ro.boot.slot")
                    values["Android Version"] = prop("ro.build.version.release") or "Unknown"
                    battery = self._adb_read_value(adb, serial, ["shell", "dumpsys", "battery"])
                    match = re.search(r"(?m)^\s*level:\s*(\d+)", battery)
                    if match: values["Battery"] = match.group(1) + "%"
                result = (values, mode, color)
            try: self.after(0, lambda: self._apply_device_info_result(request_id, result))
            except (RuntimeError, tk.TclError): pass
        threading.Thread(target=worker, name="DroidLab-DeviceInfo", daemon=True).start()

    def _apply_device_info_result(self, request_id, result):
        if request_id != getattr(self, "_device_info_request_id", None): return
        values, mode, color = result
        self._set_device_info(values, mode, color)
        if hasattr(self, "adb_info_loading"): self.adb_info_loading.set("")

    def _set_active_slot(self, slot):
        """Switch the selected Fastboot device's active slot with a legacy fallback."""
        slot = str(slot).lower()
        if slot not in ("a", "b"):
            return
        serial = self.fastboot_device.get().strip()
        binary = self._tool_path("fastboot.exe" if os.name == "nt" else "fastboot") or self._tool_path("fastboot")
        if not serial or not binary:
            self._console_write(self.fastboot_console, "[DroidLab] Select a Fastboot device before changing slots.\n")
            return
        selected = getattr(self, "_adb_targets", {}).get(self.adb_device.get())
        if selected and selected[1] != "fastboot":
            self._console_write(self.fastboot_console, "[DroidLab] Slot switching is only available in Fastboot mode.\n")
            return
        for button in self.header_slot_buttons.values():
            button.configure(state="disabled")

        def worker():
            commands = ([binary, "-s", serial, "--set-active=" + slot],
                        [binary, "-s", serial, "set_active", slot])
            lines = [f"[DroidLab] Request active slot {slot.upper()} on {serial}."]
            success = False
            with self._device_operation_locks_guard:
                operation_lock = self._device_operation_locks.setdefault(serial, threading.Lock())
            if not operation_lock.acquire(blocking=False):
                lines.append("[DroidLab] Another operation is already running for device %s." % serial)
            else:
                try:
                    for index, command in enumerate(commands):
                        rendered = " ".join(shlex.quote(part) for part in command)
                        lines.append("$ " + rendered)
                        try:
                            # Slot switching is a mutation too: serialize it with
                            # other commands and confirm the target is still attached.
                            probe = subprocess.run([binary, "devices", "-l"], capture_output=True,
                                text=True, encoding="utf-8", errors="replace", timeout=8,
                                check=False, **_windows_process_options())
                            if not is_fastboot_target_connected(serial, probe.stdout, probe.returncode):
                                raise RuntimeError(
                                    "Fastboot target %r is no longer present in the fresh device scan."
                                    % serial
                                )
                            result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8",
                                errors="replace", timeout=12, check=False, **_windows_process_options())
                            output = ((result.stdout or "") + (result.stderr or "")).strip()
                            lines.append(output or f"(no output; exit code {result.returncode})")
                            if result.returncode == 0:
                                success = True
                                break
                            if index == 0:
                                lines.append("Primary syntax failed; trying legacy set_active syntax.")
                        except (OSError, subprocess.TimeoutExpired, RuntimeError) as exc:
                            lines.append("ERROR: " + str(exc))
                            # Do not retry a target-validation failure with another
                            # mutating syntax. Retry only a failed Fastboot command.
                            if index == 0 and not isinstance(exc, RuntimeError):
                                lines.append("Trying legacy set_active syntax.")
                            else:
                                break
                finally:
                    operation_lock.release()
            lines.append("[DroidLab] Slot switch " + ("succeeded." if success else "failed."))
            def finish():
                for line in lines:
                    self._console_write(self.fastboot_console, line + "\n")
                if success:
                    self._refresh_device_info()
                else:
                    for button in self.header_slot_buttons.values():
                        button.configure(state="normal")
            try:
                self.after(0, finish)
            except (RuntimeError, tk.TclError):
                pass
        threading.Thread(target=worker, name="DroidLab-SetActiveSlot", daemon=True).start()

    def _adb_read_value(self, binary, serial, args):
        try:
            result = subprocess.run([binary, "-s", serial] + args, capture_output=True, text=True,
                encoding="utf-8", errors="replace", timeout=3, check=False, **_windows_process_options())
            return (result.stdout or "").strip() if result.returncode == 0 else ""
        except (OSError, subprocess.TimeoutExpired):
            return ""

    def _fastboot_getvar(self, binary, serial, name):
        if not binary:
            return ""
        try:
            result = subprocess.run([binary, "-s", serial, "getvar", name], capture_output=True,
                text=True, encoding="utf-8", errors="replace", timeout=3, check=False, **_windows_process_options())
            output = (result.stdout or "") + "\n" + (result.stderr or "")
            match = re.search(r"(?im)^\s*" + re.escape(name) + r"\s*:\s*(.+?)\s*$", output)
            return match.group(1).strip() if match else ""
        except (OSError, subprocess.TimeoutExpired):
            return ""

    def _detect_fastboot_submode(self, binary, serial):
        """Distinguish bootloader Fastboot from userspace Fastbootd when supported."""
        if not binary:
            return "Fastboot"
        try:
            result = subprocess.run([binary, "-s", serial, "getvar", "is-userspace"],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
                timeout=4, check=False, **_windows_process_options())
            output = (result.stdout or "") + "\n" + (result.stderr or "")
            normalized = output.lower()
            if re.search(r"is-userspace\s*:\s*yes|is-userspace\s*=\s*yes", normalized):
                return "Fastbootd (userspace Fastboot)"
            if re.search(r"is-userspace\s*:\s*no|is-userspace\s*=\s*no", normalized):
                return "Bootloader Fastboot"
        except (OSError, subprocess.TimeoutExpired):
            pass
        return "Fastboot (submode unknown)"

    def _update_reboot_actions(self):
        target = getattr(self, "_adb_targets", {}).get(self.adb_device.get())
        is_fastboot = bool(target and target[1] == "fastboot")
        if hasattr(self, "bootloader_button"):
            self.bootloader_button.configure(state="disabled" if is_fastboot else "normal")
        if hasattr(self, "reboot_button"):
            self.reboot_button.configure(text="Fastboot reboot" if is_fastboot else "Reboot")
        if hasattr(self, "recovery_button"):
            self.recovery_button.configure(text="Reboot recovery" if is_fastboot else "Recovery")
        if is_fastboot:
            self.adb_device_status.set("Fastboot/bootloader mode detected. Bootloader action is disabled; reboot actions use Fastboot.")

    def _adb_require(self, states=("device",)):
        binary = self._tool_path("adb.exe" if os.name == "nt" else "adb") or self._tool_path("adb")
        if not binary: messagebox.showerror("ADB not found","Install Android SDK Platform-Tools and ensure adb is on PATH."); return None
        target=getattr(self,"_adb_targets",{}).get(self.adb_device.get())
        if not target: messagebox.showwarning("Select device","Refresh devices and select a device."); return None
        serial,state=target
        if state.startswith("adb:"):
            state = state.split(":", 1)[1]
        if state not in states: messagebox.showwarning("Device not ready","Device state is "+state+". Expected: "+", ".join(states)+"."); return None
        return binary,serial

    def _adb_reboot(self, mode):
        target = getattr(self, "_adb_targets", {}).get(self.adb_device.get())
        if not target:
            messagebox.showwarning("Select device", "Refresh devices and select an ADB or Fastboot device.")
            return
        serial, state = target
        is_fastboot = state == "fastboot"
        if is_fastboot:
            binary = self._tool_path("fastboot.exe" if os.name == "nt" else "fastboot") or self._tool_path("fastboot")
            if not binary:
                messagebox.showerror("Fastboot not found", "Install Android platform-tools and ensure fastboot is on PATH.")
                return
            if mode == "bootloader":
                messagebox.showinfo("Already in Fastboot", "The device is already in bootloader/Fastboot mode.")
                return
            command = [binary, "-s", serial, "reboot"] + (["recovery"] if mode == "recovery" else [])
            label = "recovery" if mode == "recovery" else "normal"
            kind = "fastboot_reboot"
            title = "Fastboot reboot"
        else:
            selected = self._adb_require(("device", "recovery"))
            if not selected:
                return
            binary, serial = selected
            command = [binary, "-s", serial, "reboot"] + ([mode] if mode else [])
            label = mode or "normal"
            kind = "adb_reboot"
            title = "ADB reboot"
        if not messagebox.askyesno("Confirm reboot", "Reboot " + serial + " into " + label + " mode?"):
            self._console_write(self.fastboot_console if is_fastboot else self.adb_console,
                                "[DroidLab] Reboot cancelled by user.\n")
            return
        # Use the same asynchronous streaming runner as manual commands so the
        # command, stdout/stderr, errors, and exit status appear in the live console.
        self.adb_device_status.set(title + " in progress…")
        self._rescan_after_mode_change = True
        threading.Thread(target=self._adb_task, args=(command, 35, kind), daemon=True).start()

    def _enable_sideload_drop(self, widget):
        """Register a drop target that routes OTA ZIPs to the sideload field."""
        try:
            widget.drop_target_register(DND_FILES)
            widget.dnd_bind("<<Drop>>", self._drop_sideload)
        except Exception as exc:
            self._append("ADB sideload drag-and-drop unavailable on this widget: " + str(exc))

    def _drop_sideload(self, event):
        try:
            paths = [Path(p).expanduser() for p in self.tk.splitlist(event.data)]
        except (tk.TclError, TypeError):
            self.adb_device_status.set("Could not read dropped path; use Browse ZIP.")
            return "break"
        packages = [p for p in paths if p.is_file() and p.suffix.lower() == ".zip"]
        if not packages:
            messagebox.showwarning("OTA ZIP required", "Drop an existing .zip update package onto the ADB Sideload area.")
            return "break"
        package = packages[0].resolve()
        self.sideload_file.set(str(package))
        self.adb_device_status.set("OTA ZIP selected: " + package.name + ". Choose Sideload ZIP when the device is in recovery sideload mode.")
        self._append("OTA ZIP dropped for ADB sideload: " + str(package))
        return "break"

    def _browse_sideload_zip(self):
        """Use the operating system's native ZIP picker on Windows and Linux."""
        current = self.sideload_file.get().strip().strip(chr(34)).strip(chr(39))
        try:
            initial_dir = str(Path(current).expanduser().resolve().parent) if current and Path(current).expanduser().exists() else str(Path.home())
        except (OSError, RuntimeError):
            initial_dir = str(Path.home())
        try:
            selected = filedialog.askopenfilename(
                parent=self,
                title="Choose OTA ZIP package for ADB sideload",
                initialdir=initial_dir,
                filetypes=[
                    ("Android update ZIP packages", "*.zip"),
                    ("All files", "*.*"),
                ],
            )
        except (tk.TclError, OSError) as exc:
            logging.exception("Native ADB sideload ZIP picker failed")
            messagebox.showerror(
                "Browse ZIP failed",
                "Windows/Linux could not open the file picker. You can paste the full ZIP path into the package field.\n\n" + str(exc),
                parent=self,
            )
            return
        if not selected:
            return
        package = Path(selected).expanduser()
        if not package.is_file() or package.suffix.lower() != ".zip":
            messagebox.showerror("Invalid update ZIP", "Choose an existing .zip update package.", parent=self)
            return
        resolved = str(package.resolve())
        self.sideload_file.set(resolved)
        self.adb_device_status.set("OTA ZIP selected: " + package.name)
        self._append("OTA ZIP selected for sideload: " + resolved)

    def _run_adb_sideload(self):
        selected=self._adb_require(("sideload",))
        if not selected:return
        binary,serial=selected; package=Path(self.sideload_file.get().strip().strip(chr(34)).strip(chr(39))).expanduser()
        if not package.is_file() or package.suffix.lower()!=".zip":messagebox.showerror("Invalid update ZIP","Choose an existing .zip update package.");return
        command=[binary,"-s",serial,"sideload",str(package.resolve())]
        detail="Device: "+serial+"\nPackage: "+str(package.resolve())+"\nCommand: "+" ".join(shlex.quote(x) for x in command)+"\n\nOnly install a package intended for this exact device. Continue?"
        if not messagebox.askyesno("Confirm ADB sideload",detail,icon="warning"):return
        self._append("Starting ADB sideload: "+" ".join(shlex.quote(x) for x in command)); self.adb_device_status.set("Sideload in progress…")
        threading.Thread(target=self._adb_task,args=(command,1800,"sideload"),daemon=True).start()

    def _console_write(self, widget, text):
        """Append text to a console widget from the Tk/UI thread only."""
        if not widget or not widget.winfo_exists():
            return
        widget.configure(state="normal")
        widget.insert("end", str(text))
        line_count = int(widget.index("end-1c").split(".")[0])
        if line_count > 5000:
            widget.delete("1.0", f"{line_count - 5000}.0")
        widget.see("end")
        widget.configure(state="disabled")

    def _stream_process(self, command, timeout, kind):
        """Run a host command and stream output safely on Windows and POSIX."""
        import time
        from queue import Queue, Empty

        rendered = subprocess.list2cmdline(command) if os.name == "nt" else shlex.join(command)
        self.events.put(("console_line", (kind, "[DroidLab] $ " + rendered + "\n")))
        process = None
        output_lines = []
        retained_output_chars = 0
        max_retained_output_chars = 2 * 1024 * 1024
        console_lines_sent = 0
        dropped_console_lines = 0
        try:
            # Device lists can become stale between selection/confirmation and
            # execution. Revalidate a targeted Fastboot command immediately
            # before spawning it, especially for flash/erase/unlock operations.
            executable = Path(command[0]).name.lower() if command else ""
            if executable in ("fastboot", "fastboot.exe") and "-s" in command:
                selector_index = command.index("-s")
                if selector_index + 1 >= len(command):
                    raise ValueError("Fastboot command has a malformed -s selector.")
                target_serial = command[selector_index + 1]
                args_after_target = command[selector_index + 2:]
                is_discovery = bool(args_after_target and args_after_target[0].lower() in
                                    ("devices", "help", "--help", "--version", "version", "getvar"))
                if not is_discovery:
                    probe = subprocess.run(
                        [command[0], "devices", "-l"], capture_output=True, text=True,
                        encoding="utf-8", errors="replace", timeout=8, check=False,
                        **_windows_process_options()
                    )
                    if not is_fastboot_target_connected(target_serial, probe.stdout, probe.returncode):
                        raise RuntimeError(
                            "Fastboot target %r is no longer present in the fresh device scan. "
                            "Refresh devices, verify the target, and retry. Probe output: %s"
                            % (target_serial, (probe.stdout + "\n" + probe.stderr).strip())
                        )
            console_lines_sent = 0
            def publish_line(line):
                nonlocal console_lines_sent
                if console_lines_sent < 5000:
                    self.events.put(("console_line", (kind, line)))
                    console_lines_sent += 1

            result = run_streaming(
                command,
                timeout=timeout,
                cancel_event=self.cancel_event,
                on_line=publish_line,
                max_output_chars=2 * 1024 * 1024,
                max_queue_lines=1000,
                popen_kwargs=_windows_process_options(),
            )
            code = result.returncode
            output = result.stdout.strip() or "Exit status: " + str(code)
            self.events.put(("console_line", (kind, "[DroidLab] Process exited with code " + str(code) + "\n")))
            self.events.put(("adb_result", (kind, code, output)))
        except (OSError, subprocess.TimeoutExpired, ValueError, RuntimeError, ProcessCancelledError) as exc:
            if process and process.poll() is None:
                process.kill()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    logging.error("Timed out waiting for command process after forced termination")
            message = str(exc)
            self.events.put(("console_line", (kind, "[DroidLab] ERROR: " + message + "\n")))
            self.events.put(("adb_result", (kind, -1, message)))

    def _adb_task(self, command, timeout, kind):
        serial = None
        if "-s" in command:
            selector_index = command.index("-s")
            if selector_index + 1 < len(command):
                serial = command[selector_index + 1]
        if not serial:
            self._stream_process(command, timeout, kind)
            return
        with self._device_operation_locks_guard:
            operation_lock = self._device_operation_locks.setdefault(serial, threading.Lock())
        if not operation_lock.acquire(blocking=False):
            message = "Another DroidLab operation is already running for device %s; this command was not started." % serial
            self.events.put(("console_line", (kind, "[DroidLab] ERROR: " + message + "\n")))
            self.events.put(("adb_result", (kind, -1, message)))
            return
        try:
            self._stream_process(command, timeout, kind)
        finally:
            operation_lock.release()

    def _run_adb_shell(self):
        text = self.adb_shell_command.get().strip()
        if not text:
            messagebox.showwarning("Command required", "Enter a device-shell command (dumpsys battery) or host ADB command (adb devices).")
            return
        # ADB commands run on the computer. Plain commands run on the selected
        # Android device. This avoids sending "adb devices" into Android's shell.
        try:
            tokens = shlex.split(text, posix=(os.name != "nt"))
        except ValueError as exc:
            messagebox.showerror("Invalid command", "Check the command quoting:\n" + str(exc))
            return
        if not tokens:
            return
        first = Path(tokens[0]).name.lower()
        # Fastboot is a host-side executable, never an Android device-shell
        # command. Route it to its own runner and console even when entered in
        # the advanced command field.
        if first in ("fastboot", "fastboot.exe"):
            selected_target = getattr(self, "_adb_targets", {}).get(self.adb_device.get())
            if selected_target and selected_target[1] == "fastboot":
                self.fastboot_device.set(selected_target[0])
            self.fastboot_manual_command.set(text)
            self._run_fastboot_manual()
            return
        if first in ("adb", "adb.exe"):
            binary = self._tool_path("adb.exe" if os.name == "nt" else "adb") or self._tool_path("adb")
            if not binary:
                messagebox.showerror("ADB not found", "Bundle platform-tools or install ADB and add it to PATH.")
                return
            args = tokens[1:]
            if not args:
                args = ["devices", "-l"]
            # If a serial is selected and the command doesn't already select a device,
            # target it automatically for commands other than device discovery.
            discovery = args[0] in ("devices", "version", "help")
            selected = self._adb_require(("device",)) if not discovery else None
            if not discovery:
                if not selected:
                    return
                try:
                    explicit = validate_device_selector(args, "adb", selected[1])
                except ValueError as exc:
                    messagebox.showerror("Device target conflict", str(exc))
                    self._append("ADB command rejected: " + str(exc))
                    return
                if explicit is None:
                    args = ["-s", selected[1]] + args
            command = [binary] + args
            target_label = selected[1] if selected else "no device (discovery/help command)"
            if not messagebox.askyesno(
                "Confirm advanced ADB command",
                "Advanced ADB commands are unrestricted and cannot be proven safe.\n\n"
                + "Executable: " + binary + "\nTarget: " + target_label + "\nArguments: "
                + " ".join(shlex.quote(x) for x in args)
                + "\n\nCommands may irreversibly modify device data. Continue?",
                icon="warning",
            ):
                self._append("ADB command cancelled by user.")
                return
            self._append("Running host ADB command: " + " ".join(shlex.quote(x) for x in command))
            threading.Thread(target=self._adb_task, args=(command, 180, "shell"), daemon=True).start()
            return

        selected = self._adb_require(("device",))
        if not selected:
            return
        binary, serial = selected
        if not messagebox.askyesno(
            "Confirm advanced device-shell command",
            "Device-shell commands are unrestricted and cannot be proven safe.\n\n"
            + "Executable: " + binary + "\nTarget: " + serial + "\nArguments: "
            + " ".join(shlex.quote(x) for x in tokens)
            + "\n\nThis command may irreversibly modify device data. Continue?",
            icon="warning",
        ):
            self._append("Device-shell command cancelled by user.")
            return
        self._append("Running device shell command on " + serial + ": " + text)
        threading.Thread(target=self._adb_task, args=([binary, "-s", serial, "shell"] + tokens, 90, "shell"), daemon=True).start()

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
        binary = self._tool_path("fastboot.exe" if os.name == "nt" else "fastboot") or self._tool_path("fastboot")
        if not binary:
            messagebox.showerror("Fastboot not found", "Bundle platform-tools or install Fastboot and add it to PATH.")
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
                messagebox.showerror("Device required", "Select a Fastboot device before running a device command.")
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
            + "Executable: " + binary + "\nTarget: " + (serial or "no device (discovery/help command)")
            + "\nArguments: " + " ".join(shlex.quote(x) for x in tokens)
            + "\n\nCommands may erase data or make the device unbootable. Continue?",
            icon="warning",
        ):
            self._append("Manual Fastboot command cancelled: " + rendered)
            return
        self._append("Executing manual Fastboot command: " + rendered)
        self.status.set("Running Fastboot command…")
        # Only reboot changes USB mode. Do not trigger repeated device scans
        # for harmless commands such as getvar, devices, or flashing.
        self._rescan_after_mode_change = bool(tokens and tokens[0].lower() == "reboot")
        threading.Thread(target=self._adb_task, args=(command, 900, "fastboot_manual"), daemon=True).start()

    def _enable_command_drop(self, widget, variable, tool):
        """Allow a file path to be dropped into a manual command field."""
        try:
            widget.drop_target_register(DND_FILES)
            widget.dnd_bind("<<Drop>>", lambda event: self._drop_command_path(event, variable, tool))
        except Exception as exc:
            logging.info("Command-field drag-and-drop unavailable (%s): %s", tool, exc)

    def _drop_command_path(self, event, variable, tool):
        try:
            paths = [Path(path) for path in self.tk.splitlist(event.data)]
        except (tk.TclError, TypeError):
            self._append("Could not read dropped path; paste it into the command field instead.")
            return "break"
        if not paths:
            return "break"
        path = paths[0].expanduser()
        # Quote paths containing spaces so they remain one argument on both platforms.
        quoted = subprocess.list2cmdline([str(path)]) if os.name == "nt" else shlex.quote(str(path))
        current = variable.get().strip()
        if current in ("adb", "fastboot", "adb.exe", "fastboot.exe"):
            variable.set(current + " " + quoted)
        elif current:
            variable.set(current + " " + quoted)
        else:
            variable.set(quoted)
        self._append(f"Inserted dropped file path into {tool} command: {path}")
        return "break"

    def _append_adb_output(self, text):
        self.adb_output.configure(state="normal"); self.adb_output.insert("end",text+"\n"); self.adb_output.see("end"); self.adb_output.configure(state="disabled")

    def _start_adb_logcat(self):
        selected = self._adb_require(("device",))
        if not selected:
            return
        if self.adb_log_process and self.adb_log_process.poll() is None:
            messagebox.showinfo("Logcat running", "Stop the current logcat window first.", parent=self)
            return
        binary, serial = selected
        logging.info("Starting live logcat for device %s using %s", serial, binary)
        window = tk.Toplevel(self)
        window.title("DroidLab Live Logcat - " + serial)
        window.geometry("1000x650")
        window.configure(bg="#111827")
        toolbar = ttk.Frame(window)
        toolbar.pack(fill="x", padx=8, pady=(8, 0))
        ttk.Label(toolbar, text="Filter").pack(side="left", padx=(0, 6))
        self.adb_log_filter = tk.StringVar()
        ttk.Entry(toolbar, textvariable=self.adb_log_filter).pack(side="left", fill="x", expand=True)
        text = tk.Text(window, bg="#0b1220", fg="#d1d5db", wrap="none", font=("Monospace", 10), state="disabled")
        text.pack(fill="both", expand=True, padx=8, pady=8)
        self.adb_log_window, self.adb_log_text = window, text
        self.adb_log_lines = []
        self.adb_log_paused = False
        self.adb_log_pause_button = None
        self.adb_log_filter.trace_add("write", lambda *_: self._render_adb_logcat())
        try:
            self.adb_log_process = subprocess.Popen(
                [binary, "-s", serial, "logcat", "-v", "threadtime"],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                encoding="utf-8", errors="replace", bufsize=1, **_windows_process_options())
        except OSError as exc:
            logging.exception("Could not start live logcat for %s", serial)
            window.destroy()
            self.adb_log_window = self.adb_log_text = None
            messagebox.showerror("Logcat failed", str(exc), parent=self)
            return
        buttons = ttk.Frame(window)
        buttons.pack(fill="x", padx=8, pady=(0, 8))
        self.adb_log_pause_button = ttk.Button(buttons, text="Pause display", command=self._toggle_adb_logcat_pause)
        self.adb_log_pause_button.pack(side="left")
        ttk.Button(buttons, text="Save visible log…", command=self._save_visible_adb_logcat).pack(side="left", padx=6)
        ttk.Button(buttons, text="Stop logcat", command=self._stop_adb_logcat).pack(side="right")
        process = self.adb_log_process
        # Keep logcat separate from the app-wide event queue: a noisy device
        # must not grow memory without bound or starve operation-result events.
        log_queue = queue.Queue(maxsize=2000)
        self.adb_log_queue = log_queue
        self.adb_log_dropped = 0
        def reader():
            try:
                if process.stdout:
                    for line in process.stdout:
                        item = line.rstrip("\r\n")
                        try:
                            log_queue.put_nowait(item)
                        except queue.Full:
                            try:
                                log_queue.get_nowait()
                            except queue.Empty:
                                pass
                            self.adb_log_dropped += 1
                            try:
                                log_queue.put_nowait(item)
                            except queue.Full:
                                self.adb_log_dropped += 1
            except (OSError, ValueError):
                logging.exception("Error reading live logcat output")
            finally:
                try:
                    if process.stdout:
                        process.stdout.close()
                except (OSError, ValueError):
                    pass
                self.events.put(("adb_log_end", process.poll()))
        threading.Thread(target=reader, name="DroidLab-LogcatReader", daemon=True).start()
        window.protocol("WM_DELETE_WINDOW", self._stop_adb_logcat)

    def _render_adb_logcat(self):
        if not self.adb_log_text or not self.adb_log_window or not self.adb_log_window.winfo_exists(): return
        needle=self.adb_log_filter.get().casefold().strip()
        visible=[line for line in self.adb_log_lines if not needle or needle in line.casefold()]
        self.adb_log_text.configure(state="normal"); self.adb_log_text.delete("1.0","end")
        if visible: self.adb_log_text.insert("end","\n".join(visible[-5000:])+"\n"); self.adb_log_text.see("end")
        self.adb_log_text.configure(state="disabled")

    def _toggle_adb_logcat_pause(self):
        self.adb_log_paused=not self.adb_log_paused
        self.adb_log_pause_button.configure(text="Resume display" if self.adb_log_paused else "Pause display")

    def _save_visible_adb_logcat(self):
        needle=self.adb_log_filter.get().casefold().strip()
        visible=[line for line in self.adb_log_lines if not needle or needle in line.casefold()]
        path=filedialog.asksaveasfilename(parent=self, title="Save filtered logcat",defaultextension=".txt",initialfile="logcat-filtered.txt",filetypes=[("Text files","*.txt"),("All files","*.*")])
        if not path:return
        try:
            with open(path,"w",encoding="utf-8") as output: output.write("\n".join(visible)+("\n" if visible else ""))
            self._append("Saved "+str(len(visible))+" filtered logcat lines to "+path)
            messagebox.showinfo("Logcat saved","Saved "+str(len(visible))+" lines to:\n"+path)
        except OSError as exc: messagebox.showerror("Logcat save failed",str(exc))

    def _stop_adb_logcat(self):
        process = self.adb_log_process
        self.adb_log_process = None
        if process is not None:
            # The reader thread owns stdout and closes it after termination.
            terminate_process(process, grace_seconds=1.0)
        if self.adb_log_window and self.adb_log_window.winfo_exists():
            self.adb_log_window.destroy()
        self.adb_log_window = self.adb_log_text = None

    def _save_adb_logcat(self):
        selected=self._adb_require(("device",))
        if not selected:return
        path=filedialog.asksaveasfilename(parent=self, title="Save Android logcat",defaultextension=".txt",initialfile="logs.txt",filetypes=[("Text files","*.txt"),("All files","*.*")])
        if not path:return
        binary,serial=selected
        self._append("Starting logcat capture to " + path)
        threading.Thread(target=self._capture_logcat_file,args=(binary,serial,path),daemon=True).start()

    def _capture_logcat_file(self,binary,serial,path):
        process=None
        try:
            with open(path,"w",encoding="utf-8") as output:
                process=subprocess.Popen([binary,"-s",serial,"logcat"],stdout=output,stderr=subprocess.PIPE,text=True,encoding="utf-8",errors="replace",**_windows_process_options())
                try:
                    _stdout,stderr=process.communicate(timeout=3600)
                    self.events.put(("adb_result",("logcat_file",process.returncode,"Saved logcat to "+path+(("\n"+stderr.strip()) if stderr and stderr.strip() else ""))))
                except subprocess.TimeoutExpired:
                    terminate_process(process, grace_seconds=2.0)
                    try:
                        process.communicate(timeout=1)
                    except subprocess.TimeoutExpired:
                        if process.stderr:
                            process.stderr.close()
                    self.events.put(("adb_result",("logcat_file",0,"One-hour capture limit reached. Partial logcat saved to "+path)))
        except (OSError, subprocess.TimeoutExpired) as exc:
            if process is not None:
                terminate_process(process, grace_seconds=2.0)
            self.events.put(("adb_result",("logcat_file",-1,str(exc))))

    def _create_adb_bugreport(self):
        selected=self._adb_require(("device",))
        if not selected:return
        path=filedialog.asksaveasfilename(parent=self, title="Save Android bugreport",defaultextension=".zip",initialfile="bugreport.zip",filetypes=[("ZIP archive","*.zip"),("All files","*.*")])
        if not path:return
        binary,serial=selected
        if not messagebox.askyesno("Create bugreport","The report may include device identifiers, logs, and app activity.\nSave diagnostics from "+serial+" to:\n"+path+"?",icon="warning"):return
        self._bugreport_target_path=path
        threading.Thread(target=self._adb_task,args=([binary,"-s",serial,"bugreport",path],600,"bugreport"),daemon=True).start()

    def _run_fastboot_maintenance(self, operation, partition=None):
        binary = self._tool_path("fastboot.exe" if os.name == "nt" else "fastboot") or self._tool_path("fastboot")
        if not binary:
            messagebox.showerror("Fastboot not found", "Install Android SDK Platform-Tools and ensure fastboot is on PATH.")
            return
        serial = self.fastboot_device.get().strip()
        if not serial or serial not in self.device_combo["values"]:
            messagebox.showwarning("Select Fastboot device", "Click Refresh devices and select a connected Fastboot device first.")
            return
        if operation == "-w":
            command = [binary, "-s", serial, "-w"]
            label = "Wipe user data and cache (fastboot -w)"
            warning = "This will wipe user data and cache on device " + serial + ". This is destructive and may remove your apps, accounts, photos, and files. Continue only if you have a backup and intend to factory-reset this device."
        else:
            command = [binary, "-s", serial, operation, partition]
            label = "Erase " + partition
            if partition == "cache":
                warning = "This will erase the cache partition on " + serial + ", if this device has one. Some devices do not have a separate cache partition. Continue?"
            else:
                warning = "This will erase the userdata partition on " + serial + " and permanently delete user data. This can make data unrecoverable. Ensure you have a backup. Continue?"
        rendered = " ".join(shlex.quote(part) for part in command)
        self.maintenance_command.set(rendered)
        if not messagebox.askyesno("Confirm destructive Fastboot operation", warning + "\n\nCommand to execute:\n" + rendered, icon="warning"):
            self.maintenance_status.set("Cancelled: " + label)
            self._append("Fastboot maintenance cancelled: " + rendered)
            return
        self.maintenance_status.set("Running: " + label + "…")
        self._append("Executing Fastboot maintenance: " + rendered)
        threading.Thread(target=self._adb_task, args=(command, 900, "fastboot_maintenance"), daemon=True).start()

    def _on_flash_image_changed(self):
        path = Path(self.flash_image.get().strip().strip(chr(34)).strip(chr(39)))
        mapping = {"boot.img":"boot", "vendor.img":"vendor", "vendor_boot.img":"vendor_boot", "init_boot.img":"init_boot", "dtbo.img":"dtbo", "vbmeta.img":"vbmeta", "recovery.img":"recovery", "system.img":"system", "product.img":"product", "odm.img":"odm", "system_ext.img":"system_ext", "vbmeta_system.img":"vbmeta_system", "vbmeta_vendor.img":"vbmeta_vendor"}
        if path.name.lower() in mapping: self.flash_partition.set(mapping[path.name.lower()]); self._append("Filename suggests partition " + mapping[path.name.lower()] + "; verify compatibility before flashing.")
        self._update_flash_preview()

    def _browse_flash_image(self):
        path = filedialog.askopenfilename(parent=self, title="Choose image to flash", initialdir=str(Path.home()), filetypes=[("Android image", "*.img"), ("All files", "*.*")])
        if path: self.flash_image.set(path)

    def _refresh_fastboot_devices(self):
        binary = self._tool_path("fastboot.exe" if os.name == "nt" else "fastboot") or self._tool_path("fastboot")
        if not binary: messagebox.showerror("Fastboot not found", "Install Android platform-tools and ensure fastboot is on PATH."); return
        try: result = subprocess.run([binary, "devices", "-l"], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=8, check=False, **_windows_process_options())
        except (OSError, subprocess.TimeoutExpired) as exc: messagebox.showerror("Device detection failed", str(exc)); return
        devices = [line.split()[0] for line in result.stdout.splitlines() if len(line.split()) >= 2 and line.split()[1] == "fastboot"]
        self.device_combo["values"] = devices
        shared = getattr(self, "_adb_targets", {})
        shared_fastboot = next((label for label, target in shared.items() if target[1] == "fastboot" and target[0] in devices), "")
        chosen = shared_fastboot or (devices[0] if len(devices) == 1 else "")
        self.fastboot_device.set(chosen.split(" [Fastboot]")[0] if chosen.endswith(" [Fastboot]") else chosen)
        self._append("Fastboot scan: " + (", ".join(devices) if devices else "no devices found"))
        if devices:
            self._show_device_workspace("fastboot")
        # Refresh telemetry (including fastboot getvar current-slot) after every scan.
        self._refresh_device_info()

    def _update_flash_preview(self):
        image = self.flash_image.get().strip().strip(chr(34)).strip(chr(39)); part = self.flash_partition.get().strip(); serial = self.fastboot_device.get().strip()
        self.flash_command.set("Select an image, partition, and one Fastboot device." if not (image and part and serial) else "fastboot -s " + serial + " flash " + part + " " + shlex.quote(image))

    def _flash_image(self):
        image = Path(self.flash_image.get().strip().strip(chr(34)).strip(chr(39))).expanduser(); part = self.flash_partition.get().strip(); serial = self.fastboot_device.get().strip(); binary = self._tool_path("fastboot.exe" if os.name == "nt" else "fastboot") or self._tool_path("fastboot")
        if not binary: messagebox.showerror("Fastboot not found", "Install Android platform-tools and ensure fastboot is on PATH."); return
        if not image.is_file() or image.suffix.lower() != ".img": messagebox.showerror("Invalid image", "Choose an existing .img file."); return
        if not is_valid_partition_name(part): messagebox.showerror("Invalid partition", "Enter a valid partition name beginning with a letter or number."); return
        if not serial: messagebox.showwarning("Select device", "Refresh devices and select exactly one Fastboot device."); return
        command = [binary, "-s", serial, "flash", part, str(image.resolve())]
        rendered_command = " ".join(shlex.quote(x) for x in command)
        if not self._confirm_flash_dialog(serial, image.resolve(), part, rendered_command):
            self._append("Flash cancelled before execution.")
            return
        self._append("Executing: " + " ".join(shlex.quote(x) for x in command)); self.status.set("Flashing image…"); self.update_idletasks()
        threading.Thread(target=self._adb_task, args=(command, 900, "fastboot_flash"), daemon=True).start()
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
        tk.Label(heading, text="⚠  Confirm flashing", bg=self.theme_tokens["bg"], fg=text,
                 font=("Sans", 15, "bold")).pack(side="left")
        tk.Label(heading, text="VERIFY TARGET", bg=self.theme_tokens["panel_alt"], fg=self.theme_tokens["accent"],
                 padx=8, pady=3, font=("Sans", 8, "bold")).pack(side="right")

        details = tk.Frame(body, bg=surface, highlightthickness=1, highlightbackground=border,
                           padx=12, pady=10)
        details.pack(fill="x")

        def detail_row(row, label, value, *, value_font=None, value_color=text):
            tk.Label(details, text=label.upper(), bg=surface, fg=muted,
                     font=("Sans", 8, "bold"), anchor="w").grid(
                         row=row, column=0, sticky="nw", padx=(0, 16), pady=5)
            tk.Label(details, text=value, bg=surface, fg=value_color,
                     font=value_font or ("Sans", 10, "normal"), anchor="w",
                     justify="left", wraplength=420).grid(
                         row=row, column=1, sticky="ew", pady=5)

        details.columnconfigure(1, weight=1)
        detail_row(0, "Device", serial, value_font=(mono, 10, "bold"))
        tk.Label(details, text="TARGET PARTITION", bg=surface, fg=muted,
                 font=("Sans", 8, "bold"), anchor="w").grid(
                     row=1, column=0, sticky="w", padx=(0, 16), pady=5)
        tk.Label(details, text="[" + partition + "]", bg=self.theme_tokens["panel_alt"], fg=self.theme_tokens["accent"],
                 padx=7, pady=3, font=(mono, 10, "bold")).grid(
                     row=1, column=1, sticky="w", pady=5)
        detail_row(2, "File name", image.name, value_font=(mono, 10, "bold"))

        tk.Label(details, text="FULL PATH", bg=surface, fg=muted,
                 font=("Sans", 8, "bold"), anchor="w").grid(
                     row=3, column=0, sticky="nw", padx=(0, 16), pady=5)
        path_entry = tk.Entry(details, bg=self.theme_tokens["input"], fg=muted, insertbackground=text,
                              readonlybackground=self.theme_tokens["input"], relief="flat",
                              font=(mono, 9), state="readonly")
        path_entry.configure(state="normal")
        path_entry.insert(0, str(image))
        path_entry.configure(state="readonly")
        path_entry.grid(row=3, column=1, sticky="ew", pady=5, ipady=5)

        tk.Label(body, text="COMMAND PREVIEW", bg=self.theme_tokens["bg"], fg=muted,
                 font=("Sans", 8, "bold")).pack(anchor="w", pady=(12, 5))
        command_box = tk.Frame(body, bg=self.theme_tokens["console"], highlightthickness=1,
                               highlightbackground=border, padx=8, pady=7)
        command_box.pack(fill="x")
        command_entry = tk.Entry(command_box, bg=self.theme_tokens["console"], fg=self.theme_tokens["accent"],
                                  insertbackground=text, relief="flat", font=(mono, 9),
                                  state="normal", readonlybackground=self.theme_tokens["input"])
        command_entry.insert(0, rendered_command)
        command_entry.configure(state="readonly")
        command_entry.grid(row=0, column=0, sticky="ew", ipady=3)
        command_scroll = ttk.Scrollbar(command_box, orient="horizontal",
                                        command=command_entry.xview)
        command_scroll.grid(row=1, column=0, sticky="ew", pady=(5, 0))
        command_entry.configure(xscrollcommand=command_scroll.set)
        command_box.columnconfigure(0, weight=1)

        warning = tk.Frame(body, bg=self.theme_tokens["panel_alt"], highlightthickness=1,
                           highlightbackground=self.theme_tokens["border"], padx=10, pady=8)
        warning.pack(fill="x", pady=(12, 0))
        tk.Label(warning, text="⚠", bg=self.theme_tokens["panel_alt"], fg=self.theme_tokens["accent"],
                 font=("Sans", 13, "bold")).pack(side="left", anchor="n", padx=(0, 9))
        tk.Label(warning,
                 text="An incompatible image or wrong partition can make the device unbootable. Verify the image matches this exact device and partition.",
                 bg=self.theme_tokens["panel_alt"], fg=self.theme_tokens["text"], font=("Sans", 9),
                 justify="left", wraplength=440).pack(side="left", fill="x", expand=True)

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

        tk.Button(actions, text="Cancel", command=lambda: close(False),
                  bg=self.theme_tokens["button"], fg=text, activebackground=self.theme_tokens["panel_alt"],
                  activeforeground=text, relief="flat", padx=18, pady=7,
                  font=("Sans", 10)).pack(side="right", padx=(8, 0))
        tk.Button(actions, text="Flash Partition", command=lambda: close(True),
                  bg=self.theme_tokens["accent2"], fg="#FFFFFF", activebackground=self.theme_tokens["accent"],
                  activeforeground="#FFFFFF", relief="flat", padx=18, pady=7,
                  font=("Sans", 10, "bold")).pack(side="right")

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

    def _enable_drop(self, widget):
        """Allow files to be dropped onto the main window and source controls."""
        try:
            widget.drop_target_register(DND_FILES)
            widget.dnd_bind("<<Drop>>", self._drop_source)
        except Exception as exc:
            # Manual path entry and file browsing remain available if DnD fails.
            self._append(f"Drag-and-drop unavailable on this system: {exc}")
    def _drop_source(self, event):
        try:
            paths = [Path(p) for p in self.tk.splitlist(event.data)]
        except (tk.TclError, TypeError):
            self._append("Could not read the dropped file path. Use Browse to select it.")
            return "break"
        images = [p for p in paths if p.is_file() and p.suffix.lower() == ".img"]
        if images:
            self.flash_image.set(str(images[0].resolve())); self.status.set("Flash image selected: " + images[0].name); self._append("Flash image dropped: " + str(images[0])); return "break"
        candidates = [p for p in paths if p.is_file() and p.suffix.lower() in (".bin", ".zip")]
        if not candidates:
            self.status.set("Unsupported dropped file")
            self._append("Drop a valid payload .bin or OTA .zip file.")
            messagebox.showwarning("Unsupported file", "Drop a payload .bin or Android OTA .zip file.")
            return "break"
        # Prefer payload.bin when several files are dropped together.
        chosen = next((p for p in candidates if p.name.lower() == "payload.bin"), candidates[0])
        self.source.set(str(chosen))
        self.parts.clear()
        self.part_vars.clear()
        for item in self.tree.get_children():
            self.tree.delete(item)
        self.status.set(f"Selected: {chosen.name}")
        self._append(f"Selected by drag and drop: {chosen}")
        return "break"
    def _append(self, msg):
        message = str(msg)
        logging.log(logging.ERROR if message.startswith("ERROR:") else logging.INFO, "%s", message)
        self.log.configure(state="normal")
        self.log.insert("end", message + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")
    def _busy(self,value):self.start_button.configure(state="disabled" if value else "normal"); self.cancel_button.configure(state="normal" if value else "disabled"); self.progress.start(12) if value else self.progress.stop()
    def _browse_source(self):
        """Open the native file picker with a valid starting folder and owner."""
        current = Path(self.source.get().strip().strip('"').strip("'")).expanduser() if self.source.get().strip() else None
        initialdir = current.parent if current and current.is_file() else Path.home()
        if not initialdir.is_dir():
            initialdir = Path.home()
        try:
            path = filedialog.askopenfilename(
                parent=self,
                title="Choose Android OTA package",
                initialdir=str(initialdir),
                filetypes=[("Android OTA packages", "*.bin *.zip"), ("All files", "*.*")],
            )
        except tk.TclError as exc:
            self._append(f"File picker failed: {exc}")
            messagebox.showerror("File picker error", f"Windows could not open the file picker. You can paste the full path into the input field instead.\n\n{exc}", parent=self)
            return
        if path:
            self.source.set(str(Path(path).resolve()))
            self.parts.clear()
            self.part_vars.clear()
            for item in self.tree.get_children():
                self.tree.delete(item)
            self.status.set(f"Selected: {Path(path).name}")
            self._append(f"Selected input file: {path}")
    def _apply_manual_source_path(self):
        """Validate a path typed or pasted into the input field."""
        raw = self.source.get().strip().strip('"').strip("'")
        if not raw:
            messagebox.showwarning("Input path required", "Type or paste the full path to payload.bin or an Android OTA .zip file.")
            self.source_entry.focus_set()
            return
        path = Path(raw).expanduser()
        if not path.is_file():
            messagebox.showerror("File not found", "The input path is not an existing file:\n" + str(path))
            self.source_entry.focus_set()
            return
        if path.suffix.lower() not in {".bin", ".zip"}:
            messagebox.showerror("Unsupported file", "Choose a payload .bin file or Android OTA .zip file.")
            return
        resolved = str(path.resolve())
        self.source.set(resolved)
        self.parts.clear()
        self.part_vars.clear()
        for item in self.tree.get_children():
            self.tree.delete(item)
        self.status.set("Input path ready: " + path.name)
        self._append("Input path set manually: " + resolved)

    def _refresh_storage_locations(self):
        """List user-mounted removable drives, not system partitions or virtual filesystems."""
        locations = []
        seen_paths = set()
        user = os.environ.get("USER", "")
        # These are the common desktop mount roots for removable media.
        allowed_roots = [Path("/run/media") / user, Path("/media") / user]
        allowed_roots = [p.resolve() for p in allowed_roots if user]

        def add(path, label):
            try:
                resolved = Path(path).expanduser().resolve()
                # Keep the selector focused on user-mounted removable drives.
                # Do not show /, /home, /boot, /run/user/*/gvfs, or other system mounts.
                if not any(resolved == root or root in resolved.parents for root in allowed_roots):
                    return
                if not resolved.is_dir() or not os.access(resolved, os.R_OK | os.X_OK):
                    return
                key = str(resolved)
                if key not in seen_paths:
                    seen_paths.add(key)
                    locations.append((f"{label} — {key}", key))
            except (OSError, RuntimeError):
                pass

        # GIO provides desktop-managed mount names; only keep paths under the
        # user's conventional removable-media mount roots.
        try:
            import gi
            gi.require_version("Gio", "2.0")
            from gi.repository import Gio
            monitor = Gio.VolumeMonitor.get()
            for mount in monitor.get_mounts():
                try:
                    path = mount.get_root().get_path()
                    if path:
                        add(path, mount.get_name() or Path(path).name or "Mounted drive")
                except Exception:
                    continue
        except (ImportError, ValueError, AttributeError) as exc:
            self._append(f"GIO volume discovery unavailable; scanning mounted media folders instead: {exc}")

        # Filesystem fallback for desktops where GIO bindings are unavailable.
        for root in allowed_roots:
            if not root.is_dir():
                continue
            try:
                for candidate in root.iterdir():
                    if candidate.is_dir():
                        add(candidate, "Mounted removable drive")
            except OSError:
                continue

        locations.sort(key=lambda item: item[1].casefold())
        self._storage_locations = locations
        labels = [label for label, _path in locations]
        self.storage_combo["values"] = labels
        current = self.storage_var.get()
        self.storage_var.set(current if current in labels else (labels[0] if labels else ""))
        if locations:
            self.status.set(f"Found {len(locations)} mounted removable drive(s)")
            self._append(f"Drive list refreshed: {len(locations)} mounted removable drive(s)")
        else:
            self.status.set("No mounted removable drives found. Use Browse or Choose output.")
            self._append("Drive list refreshed: no user-mounted removable drives found.")

    def _selected_storage_path(self):
        selected = self.storage_var.get()
        return next((path for label, path in getattr(self, "_storage_locations", []) if label == selected), "")

    def _browse_selected_storage(self):
        directory = self._selected_storage_path()
        if not directory:
            messagebox.showwarning("Storage location", "Select an accessible storage location first.")
            return
        path = filedialog.askopenfilename(
            title=f"Choose payload from {directory}",
            initialdir=directory,
            filetypes=[("Android OTA", "*.bin *.zip"), ("All files", "*")],
        )
        if path:
            self.source.set(path)
            self.parts.clear()
            self.part_vars.clear()
            for item in self.tree.get_children():
                self.tree.delete(item)
            self.status.set(f"Selected: {Path(path).name}")
            self._append(f"Selected input from storage location: {path}")

    def _use_selected_storage(self):
        directory = self._selected_storage_path()
        if not directory:
            messagebox.showwarning("Storage location", "Select an accessible storage location first.")
            return
        self.output.set(directory)
        self.status.set(f"Output directory: {directory}")
        self._append(f"Output directory set to: {directory}")

    def _open_output_directory(self):
        """Open the current output directory in the platform file manager."""
        raw = self.output.get().strip()
        if not raw:
            messagebox.showwarning("Output required", "Choose an output directory first.", parent=self)
            return
        path = Path(raw).expanduser()
        try:
            path.mkdir(parents=True, exist_ok=True)
            if os.name == "nt":
                os.startfile(str(path))
            elif sys.platform == "darwin":
                subprocess.Popen(["open", str(path)])
            else:
                subprocess.Popen(["xdg-open", str(path)])
            self.status.set(f"Opened output folder: {path.name or path}")
            self._append(f"Opened output directory: {path}")
        except Exception as exc:
            self._append(f"Could not open output directory: {exc}")
            messagebox.showerror("Open folder failed", f"Could not open this folder:\n{path}\n\n{exc}", parent=self)

    def _browse_output(self):
        """Choose an output directory without passing an invalid Windows path."""
        raw = self.output.get().strip().strip('"').strip("'")
        initial = Path(raw).expanduser() if raw else Path.home()
        if not initial.is_dir():
            initial = initial.parent if initial.parent.is_dir() else Path.home()
        try:
            path = filedialog.askdirectory(
                parent=self, title="Choose output directory",
                initialdir=str(initial), mustexist=True,
            )
        except tk.TclError as exc:
            self._append(f"Output folder picker failed: {exc}")
            messagebox.showerror("Folder picker error", f"Could not open the folder picker. Enter the output path manually instead.\n\n{exc}", parent=self)
            return
        if path:
            self.output.set(str(Path(path).resolve()))
            self.status.set(f"Output directory: {path}")
            self._append(f"Output directory selected: {path}")
    def _inspect(self):
        if self.worker and self.worker.is_alive():
            return
        src = self.source.get().strip()
        if not src:
            messagebox.showwarning("Input required", "Choose an OTA .bin or .zip file first.")
            return
        self.cancel_event.clear()
        self._busy(True)
        self.status.set("Inspecting payload…")
        self.worker = threading.Thread(target=self._inspect_worker, args=(src,), daemon=True)
        self.worker.start()

    def _inspect_worker(self, src):
        try:
            parts = inspect_source(
                src,
                progress=lambda line: self.events.put(("log", line)),
                cancel_event=self.cancel_event,
            )
            self.events.put(("parts", parts))
            self.events.put(("info_done", "Inspection complete."))
        except BackendError as exc:
            kind = "cancelled" if self.cancel_event.is_set() else "error"
            self.events.put((kind, str(exc)))
        except Exception as exc:
            logging.exception("Unexpected payload inspection failure")
            self.events.put(("error", f"Unexpected inspection error: {exc}"))
    def _load_parts(self,parts):
        self.parts.clear();self.part_vars.clear()
        for part in parts:
            n=str(part["name"]);self.parts[n]=part;self.part_vars[n]=tk.BooleanVar(value=False)
        self._refresh_partition_tree()
        self._append(f"Found {len(parts)} partitions.")
    @staticmethod
    def _size(n):
        v=float(n)
        for unit in ("B","KB","MB","GB","TB"):
            if v<1024 or unit=="TB":return f"{v:.1f} {unit}"
            v/=1024
    def _refresh_partition_tree(self):
        if not hasattr(self, "tree"):
            return
        query = self.partition_filter.get().strip().casefold() if hasattr(self, "partition_filter") else ""
        for item in self.tree.get_children():
            self.tree.delete(item)
        for name, part in self.parts.items():
            if query and query not in name.casefold():
                continue
            selected = self.part_vars[name].get()
            self.tree.insert("", "end", iid=name, text=("☑  " if selected else "☐  ") + name,
                             values=(self._size(int(part.get("size_bytes") or 0)),))
        self._update_partition_summary()
    def _update_partition_summary(self):
        if not hasattr(self, "partition_summary"):
            return
        total = len(self.parts)
        selected = [name for name, var in self.part_vars.items() if var.get()]
        selected_bytes = sum(int(self.parts[name].get("size_bytes") or 0) for name in selected)
        visible = len(self.tree.get_children())
        self.partition_summary.set(f"{visible}/{total} shown · {len(selected)} selected · {self._size(selected_bytes)} selected")
    def _toggle(self,event):
        n=self.tree.identify_row(event.y)
        if n not in self.part_vars:return
        v=not self.part_vars[n].get();self.part_vars[n].set(v);self.tree.item(n,text=("☑  " if v else "☐  ")+n);self._update_partition_summary();return "break"
    def _select_all(self,yes):
        query = self.partition_filter.get().strip().casefold()
        for n,var in self.part_vars.items():
            if not query or query in n.casefold():
                var.set(yes)
        self._refresh_partition_tree()
    def _start(self):
        if self.worker and self.worker.is_alive():return
        src=self.source.get().strip();out=self.output.get().strip()
        if not src:messagebox.showwarning("Input required","Choose a payload .bin or OTA .zip file.");return
        if not out:messagebox.showwarning("Output required","Choose an output directory.");return
        selected=[n for n,v in self.part_vars.items() if v.get()];self.cancel_event.clear();self._busy(True);self.status.set("Extracting…");self._append("Input: "+src);self._append("Output: "+out)
        self.worker=threading.Thread(target=self._extract_worker,args=(src,out,self.fingerprint.get(),selected),daemon=True);self.worker.start()
    def _extract_worker(self,src,out,fingerprint,selected):
        try:
            outputs=extract(src,out,selected or None,progress=lambda x:self.events.put(("log",x)),cancel_event=self.cancel_event)
            for p in outputs:
                self.events.put(("log",f"Created: {p}"))
                if fingerprint:self.events.put(("log",f"SHA-256 fingerprint: {sha256_file(str(p))}  {p.name}"))
            if not outputs:self.events.put(("log","No new files were detected in the output directory."))
            self.events.put(("done",f"Finished. Output files detected: {len(outputs)}"))
        except BackendError as e:self.events.put(("cancelled" if self.cancel_event.is_set() else "error",str(e)))
        except Exception as e:self.events.put(("error",f"Unexpected error: {e}"))
    def _cancel(self):self.cancel_event.set();self.status.set("Cancelling…");self._append("Cancellation requested.")
    def _poll_events(self):
        logcat_changed = False
        log_queue = getattr(self, "adb_log_queue", None)
        if log_queue is not None and self.adb_log_text and self.adb_log_window and self.adb_log_window.winfo_exists():
            # Bound UI work per tick so high-volume logcat cannot freeze the Tk loop.
            for _ in range(300):
                try:
                    line = log_queue.get_nowait()
                except queue.Empty:
                    break
                self.adb_log_lines.append(line)
                logcat_changed = True
            dropped = getattr(self, "adb_log_dropped", 0)
            if dropped:
                self.adb_log_lines.append("[DroidLab] %s logcat lines dropped because the display queue was full." % dropped)
                self.adb_log_dropped = 0
                logcat_changed = True
            if len(self.adb_log_lines) > 10000:
                del self.adb_log_lines[:-10000]
        try:
            while True:
                kind,payload=self.events.get_nowait()
                if kind=="log":self._append(payload)
                elif kind=="console_line":
                    kind_name, line = payload
                    target = self.fastboot_console if kind_name.startswith("fastboot") else self.adb_console
                    self._console_write(target, line)
                elif kind=="adb_log_end":
                    logging.info("Live logcat reader ended; process return code: %s", payload)
                    if self.adb_log_window and self.adb_log_window.winfo_exists():
                        self.adb_log_lines.append("[DroidLab] Logcat stream ended (return code: %s)" % payload)
                        logcat_changed = True
                elif kind=="adb_result":
                    kind_name,code,output=payload
                    self._append(("Fastboot " if kind_name=="fastboot_manual" else "ADB ")+kind_name+" result:\n"+output)
                    if kind_name in ("shell","fastboot_manual"):
                        self._append_adb_output(output)
                    if kind_name.startswith("fastboot"):
                        self.status.set("Fastboot operation finished (exit code %s)" % code)
                        if kind_name == "fastboot_maintenance":
                            self.maintenance_status.set("Completed" if code == 0 else "Failed")
                        if kind_name == "fastboot_flash":
                            self.status.set("Fastboot flash completed" if code == 0 else "Fastboot flash failed")
                    elif kind_name=="bugreport":
                        report_path=getattr(self,"_bugreport_target_path","")
                        if code==0 and report_path and Path(report_path).is_file():
                            messagebox.showinfo("Bugreport complete","Saved archive ("+str(Path(report_path).stat().st_size)+" bytes):\n"+report_path+"\n\nBugreports may contain sensitive device data.")
                        elif code==0: messagebox.showwarning("Bugreport status","ADB returned success, but the expected archive was not found. Check output:\n"+output)
                        else: messagebox.showerror("Bugreport failed",output)
                    elif kind_name in ("adb_reboot", "fastboot_reboot", "fastboot_manual") and getattr(self, "_rescan_after_mode_change", False):
                        # Reboot commands disconnect USB before the new mode becomes visible.
                        # Retry device discovery rather than leaving a stale serial selected.
                        self._rescan_after_mode_change = False
                        for delay in (1800, 4000, 7500, 12000):
                            self.after(delay, self._refresh_adb_devices)
                    elif kind_name=="sideload":
                        if code==0:messagebox.showinfo("Sideload complete","ADB reported that the sideload command completed.")
                        else:messagebox.showerror("Sideload failed",output)
                    elif kind_name=="logcat_file":
                        if code==0:messagebox.showinfo("Logcat saved",output)
                        else:messagebox.showerror("Save logcat failed",output)
                elif kind=="parts":self._load_parts(payload)
                elif kind=="info_done":self._busy(False);self.status.set(payload)
                elif kind=="done":self._busy(False);self.status.set(payload);messagebox.showinfo("Extraction finished",payload)
                elif kind in ("error","cancelled"):
                    self._busy(False);self.status.set("Extraction failed" if kind=="error" else "Cancelled");self._append(("ERROR: " if kind=="error" else "CANCELLED: ")+payload)
                    if kind=="error":messagebox.showerror("Operation failed",payload)
        except queue.Empty:pass
        if logcat_changed and not self.adb_log_paused:
            self._render_adb_logcat()
        self.after(100,self._poll_events)
def main() -> None:
    """Initialize logging and launch the existing Tk application."""
    _configure_logging()
    sys.excepthook = _log_uncaught_exception
    try:
        PayloadDumperApp().mainloop()
    except Exception:
        logging.exception("Fatal exception in application main loop")
        raise
    finally:
        logging.info("==== %s stopped ====", APP_NAME)
        logging.shutdown()


if __name__ == "__main__":
    main()
