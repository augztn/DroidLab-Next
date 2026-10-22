from __future__ import annotations

import logging
import os
import subprocess
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox

from tkinterdnd2 import DND_FILES

from droidlab.core.payload_dumper import BackendError, extract, inspect_source, sha256_file


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


class PayloadControllerMixin:
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
            self.flash_image.set(str(images[0].resolve()))
            self.status.set("Flash image selected: " + images[0].name)
            self._append("Flash image dropped: " + str(images[0]))
            return "break"
        candidates = [p for p in paths if p.is_file() and p.suffix.lower() in (".bin", ".zip")]
        if not candidates:
            self.status.set("Unsupported dropped file")
            self._append("Drop a valid payload .bin or OTA .zip file.")
            messagebox.showwarning(
                "Unsupported file", "Drop a payload .bin or Android OTA .zip file."
            )
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

        # Drag-and-drop can fail during widget construction, before the log
        # widget exists. Keep the diagnostic in the logger without letting
        # an unavailable UI widget turn startup recovery into another error.
        log_widget = getattr(self, "log", None)
        if log_widget is None:
            return
        try:
            log_widget.configure(state="normal")
            log_widget.insert("end", message + "\n")
            log_widget.see("end")
            log_widget.configure(state="disabled")
        except (tk.TclError, AttributeError):
            # The widget may also have been destroyed during shutdown.
            logging.debug("Could not write message to the UI log widget", exc_info=True)

    def _busy(self, value):
        self.start_button.configure(state="disabled" if value else "normal")
        self.cancel_button.configure(state="normal" if value else "disabled")
        self.progress.start(12) if value else self.progress.stop()

    def _browse_source(self):
        """Open the native file picker with a valid starting folder and owner."""
        current = (
            Path(self.source.get().strip().strip('"').strip("'")).expanduser()
            if self.source.get().strip()
            else None
        )
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
            messagebox.showerror(
                "File picker error",
                f"Windows could not open the file picker. You can paste the full path into "
                f"the input field instead.\n\n{exc}",
                parent=self,
            )
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
            messagebox.showwarning(
                "Input path required",
                "Type or paste the full path to payload.bin or an Android OTA .zip file.",
            )
            self.source_entry.focus_set()
            return
        path = Path(raw).expanduser()
        if not path.is_file():
            messagebox.showerror(
                "File not found", "The input path is not an existing file:\n" + str(path)
            )
            self.source_entry.focus_set()
            return
        if path.suffix.lower() not in {".bin", ".zip"}:
            messagebox.showerror(
                "Unsupported file", "Choose a payload .bin file or Android OTA .zip file."
            )
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
            self._append(
                f"GIO volume discovery unavailable; scanning mounted media folders instead: {exc}"
            )

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
        return next(
            (path for label, path in getattr(self, "_storage_locations", []) if label == selected),
            "",
        )

    def _browse_selected_storage(self):
        directory = self._selected_storage_path()
        if not directory:
            messagebox.showwarning(
                "Storage location", "Select an accessible storage location first."
            )
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
            messagebox.showwarning(
                "Storage location", "Select an accessible storage location first."
            )
            return
        self.output.set(directory)
        self.status.set(f"Output directory: {directory}")
        self._append(f"Output directory set to: {directory}")

    def _open_output_directory(self):
        """Open the current output directory in the platform file manager."""
        raw = self.output.get().strip()
        if not raw:
            messagebox.showwarning(
                "Output required", "Choose an output directory first.", parent=self
            )
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
            messagebox.showerror(
                "Open folder failed", f"Could not open this folder:\n{path}\n\n{exc}", parent=self
            )

    def _browse_output(self):
        """Choose an output directory without passing an invalid Windows path."""
        raw = self.output.get().strip().strip('"').strip("'")
        initial = Path(raw).expanduser() if raw else Path.home()
        if not initial.is_dir():
            initial = initial.parent if initial.parent.is_dir() else Path.home()
        try:
            path = filedialog.askdirectory(
                parent=self,
                title="Choose output directory",
                initialdir=str(initial),
                mustexist=True,
            )
        except tk.TclError as exc:
            self._append(f"Output folder picker failed: {exc}")
            messagebox.showerror(
                "Folder picker error",
                f"Could not open the folder picker. Enter the output path "
                f"manually instead.\n\n{exc}",
                parent=self,
            )
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
        self.payload_cancel_event.clear()
        self._busy(True)
        self.status.set("Inspecting payload…")
        self.worker = threading.Thread(target=self._inspect_worker, args=(src,), daemon=True)
        self.worker.start()

    def _inspect_worker(self, src):
        try:
            parts = inspect_source(
                src,
                progress=lambda line: self.events.put(("log", line)),
                cancel_event=self.payload_cancel_event,
            )
            self.events.put(("parts", parts))
            self.events.put(("info_done", "Inspection complete."))
        except BackendError as exc:
            kind = "cancelled" if self.payload_cancel_event.is_set() else "error"
            self.events.put((kind, str(exc)))
        except Exception as exc:
            logging.exception("Unexpected payload inspection failure")
            self.events.put(("error", f"Unexpected inspection error: {exc}"))

    def _load_parts(self, parts):
        self.parts.clear()
        self.part_vars.clear()
        for part in parts:
            n = str(part["name"])
            self.parts[n] = part
            self.part_vars[n] = tk.BooleanVar(value=False)
        self._refresh_partition_tree()
        self._append(f"Found {len(parts)} partitions.")

    @staticmethod
    def _size(n):
        v = float(n)
        for unit in ("B", "KB", "MB", "GB", "TB"):
            if v < 1024 or unit == "TB":
                return f"{v:.1f} {unit}"
            v /= 1024

    def _refresh_partition_tree(self):
        if not hasattr(self, "tree"):
            return
        query = (
            self.partition_filter.get().strip().casefold()
            if hasattr(self, "partition_filter")
            else ""
        )
        for item in self.tree.get_children():
            self.tree.delete(item)
        for name, part in self.parts.items():
            if query and query not in name.casefold():
                continue
            selected = self.part_vars[name].get()
            self.tree.insert(
                "",
                "end",
                iid=name,
                text=("☑  " if selected else "☐  ") + name,
                values=(self._size(int(part.get("size_bytes") or 0)),),
            )
        self._update_partition_summary()

    def _update_partition_summary(self):
        if not hasattr(self, "partition_summary"):
            return
        total = len(self.parts)
        selected = [name for name, var in self.part_vars.items() if var.get()]
        selected_bytes = sum(int(self.parts[name].get("size_bytes") or 0) for name in selected)
        visible = len(self.tree.get_children())
        self.partition_summary.set(
            f"{visible}/{total} shown · {len(selected)} selected · "
            f"{self._size(selected_bytes)} selected"
        )

    def _toggle(self, event):
        n = self.tree.identify_row(event.y)
        if n not in self.part_vars:
            return
        v = not self.part_vars[n].get()
        self.part_vars[n].set(v)
        self.tree.item(n, text=("☑  " if v else "☐  ") + n)
        self._update_partition_summary()
        return "break"

    def _select_all(self, yes):
        query = self.partition_filter.get().strip().casefold()
        for n, var in self.part_vars.items():
            if not query or query in n.casefold():
                var.set(yes)
        self._refresh_partition_tree()

    def _start(self):
        if self.worker and self.worker.is_alive():
            return
        src = self.source.get().strip()
        out = self.output.get().strip()
        if not src:
            messagebox.showwarning("Input required", "Choose a payload .bin or OTA .zip file.")
            return
        if not out:
            messagebox.showwarning("Output required", "Choose an output directory.")
            return
        selected = [n for n, v in self.part_vars.items() if v.get()]
        self.payload_cancel_event.clear()
        self._busy(True)
        self.status.set("Extracting…")
        self._append("Input: " + src)
        self._append("Output: " + out)
        self.worker = threading.Thread(
            target=self._extract_worker,
            args=(src, out, self.fingerprint.get(), selected),
            daemon=True,
        )
        self.worker.start()

    def _extract_worker(self, src, out, fingerprint, selected):
        try:
            outputs = extract(
                src,
                out,
                selected or None,
                progress=lambda line: self.events.put(("log", line)),
                cancel_event=self.payload_cancel_event,
            )
            for path in outputs:
                self.events.put(("log", f"Created: {path}"))
                if fingerprint:
                    try:
                        digest = sha256_file(str(path))
                    except OSError as exc:
                        # Fingerprinting is optional; a read error must not turn
                        # successfully published images into a reported extraction failure.
                        self.events.put(
                            (
                                "log",
                                f"Warning: could not calculate SHA-256 for {path.name}: {exc}",
                            )
                        )
                    else:
                        self.events.put(("log", f"SHA-256 fingerprint: {digest}  {path.name}"))
            if not outputs:
                self.events.put(("log", "No new files were detected in the output directory."))
            self.events.put(("done", f"Finished. Output files detected: {len(outputs)}"))
        except BackendError as e:
            self.events.put(
                ("cancelled" if self.payload_cancel_event.is_set() else "error", str(e))
            )
        except Exception as e:
            self.events.put(("error", f"Unexpected error: {e}"))

    def _cancel(self):
        self.payload_cancel_event.set()
        self.status.set("Cancelling…")
        self._append("Cancellation requested.")
