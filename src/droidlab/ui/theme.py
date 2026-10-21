"""Theme palette application and appearance picker for the Tk UI."""
from __future__ import annotations
import logging
import tkinter as tk
from tkinter import ttk
from droidlab.config.constants import THEME_TOKENS
from droidlab.config.settings import load_settings, save_settings

class ThemeSupport:
    """Mixin providing the existing theme behavior to the main window."""
    def _apply_theme(self, name):
        """Apply a palette live; intentionally does not touch device/backend logic."""
        if name not in THEME_TOKENS:
            return
        old_tokens = getattr(self, "theme_tokens", THEME_TOKENS[name])
        self.theme_name = name
        self.theme_tokens = t = THEME_TOKENS[name]
        # Rebuild shared ttk styles from the active tokens before recoloring widgets.
        self._configure_widget_styles()
        self.configure(bg=t["bg"])
        style = ttk.Style(self)
        try:
            if "clam" in style.theme_names():
                style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure(".", background=t["bg"], foreground=t["text"])
        style.configure("TFrame", background=t["bg"])
        style.configure("Panel.TFrame", background=t["panel"], bordercolor=t["border"], relief="flat")
        style.configure("TLabel", background=t["bg"], foreground=t["text"])
        style.configure("PanelHeading.TLabel", background=t["panel"], foreground=t["accent"],
                        font=(self._ui_font, 10, "bold"))
        style.configure("PanelMuted.TLabel", background=t["panel"], foreground=t["muted"])
        style.configure("Title.TLabel", background=t["bg"], foreground=t["text"])
        style.configure("Muted.TLabel", background=t["bg"], foreground=t["muted"])
        style.configure("TButton", background=t["button"], foreground=t["text"],
                        padding=(12, 7), bordercolor=t["border"], relief="flat")
        style.map("TButton", background=[("pressed", t["accent2"]), ("active", t["panel_alt"])],
                  foreground=[("disabled", t["muted"]), ("active", t["text"])],
                  bordercolor=[("focus", t["accent"])])
        style.configure("Primary.TButton", background=t["accent"], foreground="#ffffff",
                        padding=(14, 7), bordercolor=t["accent"])
        style.map("Primary.TButton", background=[("active", t["accent2"]), ("disabled", t["panel_alt"])])
        style.configure("TEntry", fieldbackground=t["input"], foreground=t["text"],
                        insertcolor=t["text"], bordercolor=t["border"], padding=6)
        style.configure("TCombobox", fieldbackground=t["input"], background=t["button"],
                        foreground=t["text"], arrowcolor=t["accent"], padding=5)
        style.map("TCombobox", fieldbackground=[("readonly", t["input"])],
                  foreground=[("readonly", t["text"])])
        style.configure("TCheckbutton", background=t["panel"], foreground=t["text"])
        style.configure("TRadiobutton", background=t["panel"], foreground=t["text"])
        style.configure("Treeview", background=t["input"], fieldbackground=t["input"],
                        foreground=t["text"], bordercolor=t["border"])
        style.configure("Treeview.Heading", background=t["panel_alt"], foreground=t["text"])
        style.map("Treeview", background=[("selected", t["accent2"])],
                  foreground=[("selected", "#ffffff")])
        style.configure("TNotebook", background=t["bg"], borderwidth=0, tabmargins=(3, 5, 3, 0))
        style.configure("TNotebook.Tab", background=t["panel"], foreground=t["muted"],
                        padding=(16, 9), borderwidth=0)
        style.map("TNotebook.Tab", background=[("selected", t["panel_alt"]), ("active", t["button"])],
                  foreground=[("selected", t["accent"]), ("active", t["text"])])
    
        # Recolor native Tk widgets as well as ttk. Preserve semantic colors
        # (green/red/amber status indicators) and only replace known surfaces.
        # Re-map legacy colors and the previous theme's token colors so repeated
        # live theme switches continue to recolor existing native Tk widgets.
        color_roles = ("bg", "panel", "panel_alt", "border", "text", "muted",
                       "input", "accent", "accent2", "button", "console")
        old_token_colors = {str(old_tokens[key]).lower(): t[key]
                            for key in color_roles if key in old_tokens and key in t}
        old_surface = {
            "#161922": t["panel"], "#161b22": t["panel"], "#1e222d": t["panel"],
            "#1f2937": t["panel"], "#111827": t["bg"], "#0b1220": t["console"],
            "#0d1117": t["bg"], "#2a3040": t["border"], "#30363d": t["border"],
            "#334155": t["panel_alt"], "#263449": t["button"],
        }
        old_surface.update({str(old_tokens[key]).lower(): t[key]
                            for key in ("bg", "panel", "panel_alt", "border", "input", "console", "button")
                            if key in old_tokens and key in t})
        for widget in self._walk_widgets(self):
            try:
                kind = widget.winfo_class()
                if kind in ("Frame", "Labelframe", "Toplevel"):
                    current = str(widget.cget("bg")).lower()
                    if current in old_surface:
                        widget.configure(bg=old_surface[current])
                    try:
                        widget.configure(highlightbackground=t["border"])
                    except tk.TclError:
                        pass
                elif kind == "Label":
                    bg = str(widget.cget("bg")).lower()
                    fg = str(widget.cget("fg")).lower()
                    if bg in old_surface:
                        widget.configure(bg=old_surface[bg])
                    if fg in old_token_colors:
                        widget.configure(fg=old_token_colors[fg])
                    elif fg in ("#f3f4f6", "#f8fafc", "#e6edf3", "#d1d5db", "#cbd5e1"):
                        widget.configure(fg=t["text"])
                    elif fg in ("#94a3b8", "#8b949e"):
                        widget.configure(fg=t["muted"])
                elif kind == "Button":
                    options = {}
                    for option, mapping in (("bg", old_surface), ("activebackground", old_surface),
                                            ("fg", old_token_colors), ("activeforeground", old_token_colors)):
                        try:
                            current = str(widget.cget(option)).lower()
                            if current in mapping:
                                options[option] = mapping[current]
                        except tk.TclError:
                            pass
                    if options:
                        widget.configure(**options)
                elif kind in ("Text", "Entry", "Listbox"):
                    try:
                        widget.configure(
                            bg=t["console"] if widget in (
                                getattr(self, "log", None), getattr(self, "fastboot_console", None),
                                getattr(self, "adb_console", None),
                            ) else t["input"],
                            fg=t["text"], insertbackground=t["accent"],
                        )
                    except tk.TclError:
                        pass
            except (tk.TclError, TypeError):
                continue
    
        for attr in ("log", "fastboot_console", "adb_console"):
            widget = getattr(self, attr, None)
            if widget:
                try:
                    widget.configure(bg=t["console"], fg=t["text"], insertbackground=t["accent"])
                except tk.TclError:
                    pass
        if hasattr(self, "header_telemetry"):
            try:
                self.header_telemetry.configure(bg=t["panel"], highlightbackground=t["border"])
            except tk.TclError:
                pass
        if hasattr(self, "header_status_label"):
            try:
                self.header_status_label.configure(bg=t["panel"], fg=t["text"])
            except tk.TclError:
                pass
        if hasattr(self, "theme_button"):
            try:
                self.theme_button.configure(bg=t["panel"], fg=t["muted"],
                                            activebackground=t["panel_alt"], activeforeground=t["accent"])
            except tk.TclError:
                pass
        for slot, button in getattr(self, "header_slot_buttons", {}).items():
            try:
                active = getattr(self, "header_device_vars", {}).get("slot", tk.StringVar(value="")).get().lower().endswith(slot)
                button.configure(bg=t["accent"] if active else t["button"],
                                 fg="#07111B" if active and name == "cyberpunk_glass" else t["text"],
                                 activebackground=t["accent2"])
            except tk.TclError:
                pass
        try:
            config = load_settings()
            config["theme"] = name
            save_settings(config)
        except OSError as exc:
            logging.warning("Unable to save theme preference: %s", exc)
    
    @staticmethod
    def _walk_widgets(parent):
        """Yield descendants safely; never alter callbacks or device operations."""
        for child in parent.winfo_children():
            yield child
            yield from ThemeSupport._walk_widgets(child)
    
    def _open_theme_picker(self):
        t = self.theme_tokens
        dialog = tk.Toplevel(self)
        dialog.title("DroidLab appearance")
        dialog.transient(self)
        dialog.configure(bg=t["bg"])
        dialog.resizable(False, False)
        panel = tk.Frame(dialog, bg=t["panel"], padx=18, pady=16, highlightthickness=1, highlightbackground=t["border"])
        panel.pack(fill="both", expand=True, padx=12, pady=12)
        tk.Label(panel, text="APPEARANCE", bg=t["panel"], fg=t["text"], font=(self._ui_font, 13, "bold")).pack(anchor="w")
        tk.Label(panel, text="Changes apply immediately and persist across launches.", bg=t["panel"], fg=t["muted"]).pack(anchor="w", pady=(3, 12))
        for name, tokens in THEME_TOKENS.items():
            desc = tokens["label"]
            tk.Button(panel, text=("✓  " if name == self.theme_name else "    ") + desc,
                      command=lambda n=name, d=dialog: (self._apply_theme(n), d.destroy()),
                      anchor="w", bg=t["button"], fg=t["text"], activebackground=t["accent2"],
                      activeforeground="#ffffff", relief="flat", bd=0, padx=10, pady=9).pack(fill="x", pady=3)
        ttk.Button(panel, text="Close", command=dialog.destroy).pack(anchor="e", pady=(10, 0))
        dialog.update_idletasks()
        dialog.geometry(f"+{self.winfo_rootx()+80}+{self.winfo_rooty()+80}")
        dialog.grab_set()
