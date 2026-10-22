from __future__ import annotations

import os
import re
import shlex
import subprocess
import threading
import tkinter as tk

from droidlab.core.command_guards import (
    is_fastboot_target_connected,
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



class DeviceControllerMixin:
        def _refresh_adb_devices(self):
            """Scan ADB and Fastboot in a worker so a missing device cannot freeze Tk."""
            if getattr(self, "_closing", False):
                return
            if getattr(self, "_device_scan_running", False):
                self._device_scan_again = True
                return

            self._device_scan_running = True
            self._device_scan_again = False
            request_id = getattr(self, "_device_scan_request_id", 0) + 1
            self._device_scan_request_id = request_id
            previous = self.adb_device.get()
            previous_fastboot = self.fastboot_device.get()
            self.adb_device_status.set("Scanning ADB and Fastboot devices…")

            def worker():
                adb_binary = (
                    self._tool_path("adb.exe" if os.name == "nt" else "adb")
                    or self._tool_path("adb")
                )
                fastboot_binary = (
                    self._tool_path("fastboot.exe" if os.name == "nt" else "fastboot")
                    or self._tool_path("fastboot")
                )
                targets = {}
                status_lines = []

                if adb_binary:
                    try:
                        result = subprocess.run(
                            [adb_binary, "devices", "-l"],
                            capture_output=True,
                            text=True,
                            encoding="utf-8",
                            errors="replace",
                            timeout=10,
                            check=False,
                            **_windows_process_options(),
                        )
                        for line in result.stdout.splitlines()[1:]:
                            fields = line.split()
                            if len(fields) >= 2 and fields[1] in (
                                "device", "sideload", "recovery", "unauthorized", "offline"
                            ):
                                targets[fields[0] + " [ADB: " + fields[1] + "]"] = (
                                    fields[0], "adb:" + fields[1]
                                )
                        adb_labels = [
                            label for label, target in targets.items()
                            if target[1].startswith("adb:")
                        ]
                        status_lines.append("ADB: " + (", ".join(adb_labels) or "no devices"))
                    except (OSError, subprocess.TimeoutExpired) as exc:
                        status_lines.append("ADB scan failed: " + str(exc))
                else:
                    status_lines.append("ADB tools not found")

                if fastboot_binary:
                    try:
                        result = subprocess.run(
                            [fastboot_binary, "devices", "-l"],
                            capture_output=True,
                            text=True,
                            encoding="utf-8",
                            errors="replace",
                            timeout=8,
                            check=False,
                            **_windows_process_options(),
                        )
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

                if not getattr(self, "_closing", False):
                    self.events.put(
                        (
                            "device_scan_result",
                            (request_id, targets, status_lines, previous, previous_fastboot),
                        )
                    )

            threading.Thread(target=worker, name="DroidLab-DeviceScan", daemon=True).start()

        def _apply_device_scan_result(
            self, request_id, targets, status_lines, previous, previous_fastboot
        ):
            """Apply a completed background device scan on the Tk main thread."""
            if request_id != getattr(self, "_device_scan_request_id", None):
                return
            self._device_scan_running = False
            self._adb_targets = targets
            labels = list(targets)
            self.adb_device_combo["values"] = labels
            self.adb_device.set(
                previous if previous in targets else (labels[0] if len(labels) == 1 else "")
            )

            fastboot_devices = [
                serial for serial, state in targets.values() if state == "fastboot"
            ]
            self.device_combo["values"] = fastboot_devices
            self.fastboot_device.set(
                previous_fastboot
                if previous_fastboot in fastboot_devices
                else (fastboot_devices[0] if len(fastboot_devices) == 1 else "")
            )

            self._on_shared_device_selected()
            self.adb_device_status.set(" | ".join(status_lines))
            selected = targets.get(self.adb_device.get())
            if selected and selected[1] == "fastboot":
                self.device_mode_status.set(
                    "MODE DETECTOR: Fastboot (checking mode) · Serial: " + selected[0]
                )
            elif selected and selected[1].startswith("adb:"):
                adb_state = selected[1].split(":", 1)[1]
                mode = {
                    "device": "ADB / Android",
                    "recovery": "ADB Recovery",
                    "sideload": "ADB Sideload",
                    "unauthorized": "ADB Unauthorized",
                    "offline": "ADB Offline",
                }.get(adb_state, "ADB (" + adb_state + ")")
                self.device_mode_status.set(
                    "MODE DETECTOR: " + mode + " · Serial: " + selected[0]
                )
            else:
                self.device_mode_status.set(
                    "MODE DETECTOR: No device detected · Check USB, drivers/udev rules, and Platform-Tools"
                )
            self._append(
                "Combined device scan: "
                + (", ".join(labels) if labels else "no ADB or Fastboot devices found")
            )

            if getattr(self, "_device_scan_again", False) and not getattr(self, "_closing", False):
                self._device_scan_again = False
                self.after(0, self._refresh_adb_devices)

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
            request_id = getattr(self, "_device_info_request_id", 0) + 1
            self._device_info_request_id = request_id
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
                # Worker threads must not call Tkinter APIs, including after().
                # Hand results to the main thread's existing event-queue poller.
                if not getattr(self, "_closing", False):
                    self.events.put(("device_info_result", (request_id, result)))
            threading.Thread(target=worker, name="DroidLab-DeviceInfo", daemon=True).start()

        def _apply_device_info_result(self, request_id, result):
            if request_id != getattr(self, "_device_info_request_id", None):
                return
            values, mode, color = result
            self._set_device_info(values, mode, color)
            selected = getattr(self, "_adb_targets", {}).get(self.adb_device.get())
            if selected:
                self.device_mode_status.set(
                    "MODE DETECTOR: " + mode + " · Serial: " + selected[0]
                )
            else:
                self.device_mode_status.set(
                    "MODE DETECTOR: No device detected · Check USB, drivers/udev rules, and Platform-Tools"
                )
            if hasattr(self, "adb_info_loading"):
                self.adb_info_loading.set("")

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
                # Do not schedule Tk callbacks from this worker. The UI thread
                # consumes the result and performs all widget updates.
                if not getattr(self, "_closing", False):
                    self.events.put(("slot_switch_result", (lines, success)))
            threading.Thread(target=worker, name="DroidLab-SetActiveSlot", daemon=True).start()

        def _finish_slot_switch(self, lines, success):
            """Apply a completed slot-switch result on the Tk main thread."""
            if getattr(self, "_closing", False):
                return
            for line in lines:
                self._console_write(self.fastboot_console, line + "\n")
            if success:
                self._refresh_device_info()
            else:
                for button in self.header_slot_buttons.values():
                    button.configure(state="normal")

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

