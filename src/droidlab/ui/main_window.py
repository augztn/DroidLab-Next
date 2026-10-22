#!/usr/bin/env python3
"""Cross-platform DroidLab desktop UI for Android firmware workflows."""
from __future__ import annotations

import logging
import os
import platform
import queue
import shutil
import subprocess
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox

from tkinterdnd2 import TkinterDnD

from droidlab.config.constants import APP_NAME, THEME_TOKENS
from droidlab.config.logging_config import configure_logging as _configure_logging
from droidlab.config.logging_config import log_directory as _log_directory
from droidlab.config.logging_config import log_uncaught_exception as _log_uncaught_exception
from droidlab.config.settings import load_settings
from droidlab.core.operation_outcomes import sideload_result_message
from droidlab.controllers.adb_controller import ADBControllerMixin
from droidlab.controllers.device_controller import DeviceControllerMixin
from droidlab.controllers.fastboot_controller import FastbootControllerMixin
from droidlab.controllers.payload_controller import PayloadControllerMixin
from droidlab.ui.adb_view import ADBViewSupport
from droidlab.ui.dialogs import DialogSupport
from droidlab.ui.fastboot_view import FastbootViewSupport
from droidlab.ui.layout import LayoutSupport
from droidlab.ui.payload_view import PayloadViewSupport
from droidlab.ui.theme import ThemeSupport
from droidlab.ui.widgets import WidgetSupport


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









class PayloadDumperApp(DeviceControllerMixin, ADBControllerMixin, FastbootControllerMixin, PayloadControllerMixin, DialogSupport, ThemeSupport, WidgetSupport, LayoutSupport, PayloadViewSupport, ADBViewSupport, FastbootViewSupport, TkinterDnD.Tk):
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
        self.events=queue.Queue(); self.worker=None; self.payload_cancel_event=threading.Event(); self.cancel_event=self.payload_cancel_event; self.command_cancel_event=threading.Event(); self._closing=False; self._active_operations={}; self._active_operations_guard=threading.Lock()
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
        self.protocol("WM_DELETE_WINDOW", self._on_close)
        logging.info("UI initialized")
        self.after(100,self._poll_events)

    def _on_close(self):
        """Stop active subprocess work before destroying the Tk interpreter."""
        with self._active_operations_guard:
            active = list(self._active_operations.values())
        destructive = [kind for kind in active if kind in ("fastboot_flash", "fastboot_maintenance", "fastboot_manual", "sideload")]
        if destructive:
            answer = messagebox.askyesno(
                "Operation in progress",
                "A potentially destructive device operation is still running ("
                + ", ".join(sorted(set(destructive)))
                + "). Closing DroidLab will request cancellation and may leave the device in an incomplete state. Close anyway?",
                icon="warning",
                parent=self,
            )
            if not answer:
                return
        elif active and not messagebox.askyesno(
            "Operations in progress",
            "DroidLab still has device commands running. Request cancellation and close?",
            icon="warning",
            parent=self,
        ):
            return
        self._closing = True
        self.payload_cancel_event.set()
        self.command_cancel_event.set()
        try:
            self._stop_adb_logcat()
        except (AttributeError, tk.TclError, OSError):
            logging.debug("Could not stop logcat cleanly during shutdown", exc_info=True)
        worker = getattr(self, "worker", None)
        if worker is not None and worker.is_alive() and worker is not threading.current_thread():
            worker.join(timeout=0.75)
        try:
            self.destroy()
        except tk.TclError:
            pass

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
            root = Path(__file__).resolve().parent.parent.parent.parent
            candidates.extend([root / "bin" / name, root / "platform-tools" / name])
        for candidate in candidates:
            if candidate.is_file():
                return str(candidate)
        return shutil.which(name)















































    def _poll_events(self):
        # Schedule the next poll before dispatching queued work. A malformed event
        # or unexpected widget error must not permanently stop result delivery.
        if getattr(self, "_closing", False):
            return
        self.after(100, self._poll_events)
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
                        title, message = sideload_result_message(code, output)
                        if code == 0:
                            self.adb_device_status.set(
                                "Sideload command finished. Verify device state before retrying."
                            )
                            messagebox.showinfo(title, message)
                        else:
                            self.adb_device_status.set(
                                "Sideload outcome uncertain. Verify device state before retrying."
                            )
                            messagebox.showwarning(title, message)
                    elif kind_name=="logcat_file":
                        if code==0:messagebox.showinfo("Logcat saved",output)
                        else:messagebox.showerror("Save logcat failed",output)
                elif kind=="device_info_result":
                    request_id, result = payload
                    self._apply_device_info_result(request_id, result)
                elif kind=="slot_switch_result":
                    lines, success = payload
                    self._finish_slot_switch(lines, success)
                elif kind=="parts":self._load_parts(payload)
                elif kind=="info_done":self._busy(False);self.status.set(payload)
                elif kind=="done":self._busy(False);self.status.set(payload);messagebox.showinfo("Extraction finished",payload)
                elif kind in ("error","cancelled"):
                    self._busy(False);self.status.set("Extraction failed" if kind=="error" else "Cancelled");self._append(("ERROR: " if kind=="error" else "CANCELLED: ")+payload)
                    if kind=="error":messagebox.showerror("Operation failed",payload)
        except queue.Empty:pass
        if logcat_changed and not self.adb_log_paused:
            self._render_adb_logcat()
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
