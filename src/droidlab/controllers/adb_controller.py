from __future__ import annotations

import logging
import os
import queue
import shlex
import subprocess
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from tkinterdnd2 import DND_FILES

from droidlab.core.command_guards import (
    is_adb_target_connected,
    is_fastboot_target_connected,
    validate_device_selector,
)
from droidlab.core.process_runner import ProcessCancelledError, run_streaming, terminate_process


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



class ADBControllerMixin:
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

            rendered = subprocess.list2cmdline(command) if os.name == "nt" else shlex.join(command)
            self.events.put(("console_line", (kind, "[DroidLab] $ " + rendered + "\n")))
            process = None
            console_lines_sent = 0
            try:
                # Device lists can become stale between selection/confirmation and
                # execution. Revalidate a targeted Fastboot command immediately
                # before spawning it, especially for flash/erase/unlock operations.
                executable = Path(command[0]).name.lower() if command else ""
                selector_index = next(
                    (
                        index for index, token in enumerate(command)
                        if token == "-s" or token.startswith("-s=")
                    ),
                    None,
                )
                if executable in ("adb", "adb.exe") and selector_index is not None:
                    selector = command[selector_index]
                    if selector == "-s":
                        if selector_index + 1 >= len(command) or not command[selector_index + 1]:
                            raise ValueError("ADB command has a malformed -s selector.")
                        target_serial = command[selector_index + 1]
                        args_after_target = command[selector_index + 2:]
                    else:
                        target_serial = selector[3:]
                        if not target_serial:
                            raise ValueError("ADB command has a malformed -s selector.")
                        args_after_target = command[selector_index + 1:]
                    verb = args_after_target[0].lower() if args_after_target else ""
                    allowed_states = (
                        ("sideload",) if verb == "sideload"
                        else ("device", "recovery") if verb == "reboot"
                        else ("device",)
                    )
                    probe = subprocess.run(
                        [command[0], "devices", "-l"],
                        capture_output=True,
                        text=True,
                        encoding="utf-8",
                        errors="replace",
                        timeout=8,
                        check=False,
                        **_windows_process_options(),
                    )
                    if not is_adb_target_connected(
                        target_serial, probe.stdout, probe.returncode, allowed_states
                    ):
                        raise RuntimeError(
                            "ADB target %r is not present in an allowed state in a successful "
                            "fresh device scan. No command was sent. Refresh devices, verify "
                            "the target/mode, and retry. Probe output: %s"
                            % (target_serial, (probe.stdout + "\\n" + probe.stderr).strip())
                        )
                if executable in ("fastboot", "fastboot.exe") and selector_index is not None:
                    selector = command[selector_index]
                    if selector == "-s":
                        if selector_index + 1 >= len(command) or not command[selector_index + 1]:
                            raise ValueError("Fastboot command has a malformed -s selector.")
                        target_serial = command[selector_index + 1]
                        args_after_target = command[selector_index + 2:]
                    else:
                        target_serial = selector[3:]
                        if not target_serial:
                            raise ValueError("Fastboot command has a malformed -s selector.")
                        args_after_target = command[selector_index + 1:]
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
                    cancel_event=self.command_cancel_event,
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
            operation_id = threading.get_ident()
            with self._active_operations_guard:
                self._active_operations[operation_id] = kind
            operation_lock = None
            lock_acquired = False
            try:
                serial = None
                selector_index = next(
                    (
                        index for index, token in enumerate(command)
                        if token == "-s" or token.startswith("-s=")
                    ),
                    None,
                )
                if selector_index is not None:
                    selector = command[selector_index]
                    if selector == "-s":
                        if selector_index + 1 < len(command):
                            serial = command[selector_index + 1]
                    else:
                        serial = selector[3:] or None
                if serial:
                    with self._device_operation_locks_guard:
                        operation_lock = self._device_operation_locks.setdefault(serial, threading.Lock())
                    lock_acquired = operation_lock.acquire(blocking=False)
                    if not lock_acquired:
                        message = "Another DroidLab operation is already running for device %s; this command was not started." % serial
                        self.events.put(("console_line", (kind, "[DroidLab] ERROR: " + message + "\n")))
                        self.events.put(("adb_result", (kind, -1, message)))
                        return
                self._stream_process(command, timeout, kind)
            finally:
                if operation_lock is not None and lock_acquired:
                    operation_lock.release()
                with self._active_operations_guard:
                    self._active_operations.pop(operation_id, None)

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
                    encoding="utf-8", errors="replace", bufsize=1, **_windows_process_options(),
                    **({"start_new_session": True} if os.name == "posix" else {}))
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
                    process=subprocess.Popen(
                        [binary, "-s", serial, "logcat"],
                        stdout=output,
                        stderr=subprocess.PIPE,
                        text=True,
                        encoding="utf-8",
                        errors="replace",
                        **_windows_process_options(),
                        **({"start_new_session": True} if os.name == "posix" else {}),
                    )
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

