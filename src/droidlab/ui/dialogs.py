"""Standalone informational dialogs used by the main application window."""
from __future__ import annotations

import tkinter as tk
import webbrowser
from tkinter import ttk


class DialogSupport:
    """Mixin containing self-contained application dialogs."""
    def _show_about(self):
        """Show a responsive, scrollable About dialog."""
        dialog = tk.Toplevel(self)
        dialog.title("About DroidLab")
        dialog.configure(bg="#111827")
        dialog.transient(self)
        dialog.resizable(True, True)

        self.update_idletasks()
        width = min(620, max(440, self.winfo_screenwidth() - 80))
        height = min(680, max(420, self.winfo_screenheight() - 100))
        x = self.winfo_rootx() + max(0, (self.winfo_width() - width) // 2)
        y = self.winfo_rooty() + max(0, (self.winfo_height() - height) // 2)
        dialog.geometry(f"{width}x{height}+{x}+{y}")
        dialog.minsize(min(420, width), min(360, height))

        # Keep the title and close action fixed; scroll the complete content area.
        outer = ttk.Frame(dialog, padding=(14, 12))
        outer.pack(fill="both", expand=True)
        header = ttk.Frame(outer)
        header.pack(fill="x", pady=(0, 10))
        ttk.Label(header, text="About DroidLab", font=("Sans", 14, "bold")).pack(side="left")
        ttk.Button(header, text="Close", command=dialog.destroy).pack(side="right")

        body = ttk.Frame(outer)
        body.pack(fill="both", expand=True)
        canvas = tk.Canvas(body, bg="#111827", highlightthickness=0, borderwidth=0)
        scrollbar = ttk.Scrollbar(body, orient="vertical", command=canvas.yview)
        canvas.configure(yscrollcommand=scrollbar.set)
        scrollbar.pack(side="right", fill="y")
        canvas.pack(side="left", fill="both", expand=True)
        content_frame = ttk.Frame(canvas, padding=(2, 2, 10, 14))
        content_window = canvas.create_window((0, 0), window=content_frame, anchor="nw")

        def update_scroll_region(_event=None):
            canvas.configure(scrollregion=canvas.bbox("all"))

        def fit_content_width(event):
            canvas.itemconfigure(content_window, width=event.width)

        content_frame.bind("<Configure>", update_scroll_region)
        canvas.bind("<Configure>", fit_content_width)

        hero = tk.Frame(content_frame, bg="#1d4ed8", padx=18, pady=22)
        hero.pack(fill="x")
        tk.Label(hero, text="DL", bg="#1d4ed8", fg="#ffffff",
                 font=("Sans", 18, "bold")).pack(pady=(0, 6))
        tk.Label(hero, text="DroidLab", bg="#1d4ed8", fg="#ffffff",
                 font=("Sans", 25, "bold")).pack()
        tk.Label(hero, text="Android firmware toolkit", bg="#1d4ed8", fg="#dbeafe",
                 font=("Sans", 12)).pack(pady=(5, 0))

        intro = ttk.Frame(content_frame, style="Panel.TFrame", padding=16)
        intro.pack(fill="x", pady=(12, 0))
        ttk.Label(intro, text="A toolkit for Android firmware workflows",
                  background="#1f2937", foreground="#f9fafb",
                  font=("Sans", 13, "bold"), wraplength=500).pack(anchor="w")
        ttk.Label(intro,
                  text="Inspect and extract OTA payloads, review partition images, manage connected devices with ADB, and preview guarded Fastboot operations.",
                  background="#1f2937", foreground="#cbd5e1",
                  font=("Sans", 11), wraplength=500, justify="left").pack(
                      anchor="w", fill="x", pady=(7, 0))

        features = ttk.Frame(content_frame, style="Panel.TFrame", padding=16)
        features.pack(fill="x", pady=(10, 0))
        ttk.Label(features, text="WHAT YOU CAN DO", background="#1f2937",
                  foreground="#93c5fd", font=("Sans", 10, "bold")).pack(anchor="w")
        for item in (
            "Extract all or selected partitions from OTA payloads",
            "Generate optional SHA-256 fingerprints",
            "Inspect images and preview Fastboot commands",
            "Reboot, collect logs, run diagnostics, and sideload OTA ZIPs",
        ):
            ttk.Label(features, text="•  " + item, background="#1f2937",
                      foreground="#e5e7eb", font=("Sans", 11),
                      wraplength=500, justify="left").pack(anchor="w", pady=(7, 0))

        tech = ttk.Frame(content_frame, style="Panel.TFrame", padding=16)
        tech.pack(fill="x", pady=(10, 0))
        ttk.Label(tech, text="TOOLS & TECHNOLOGY", background="#1f2937",
                  foreground="#93c5fd", font=("Sans", 10, "bold")).pack(anchor="w")
        for label, value in (
            ("Desktop UI", "Python · Tkinter"),
            ("Payload backend", "payload-dumper-go"),
            ("Device tools", "Android SDK Platform-Tools · ADB & Fastboot"),
        ):
            line = ttk.Frame(tech, style="Panel.TFrame")
            line.pack(fill="x", pady=(7, 0))
            ttk.Label(line, text=label, background="#1f2937",
                      foreground="#9ca3af", font=("Sans", 10)).pack(anchor="w")
            ttk.Label(line, text=value, background="#1f2937",
                      foreground="#e5e7eb", font=("Sans", 11),
                      wraplength=500, justify="left").pack(anchor="w", pady=(2, 0))

        details = ttk.Frame(content_frame, style="Panel.TFrame", padding=16)
        details.pack(fill="x", pady=(10, 0))
        ttk.Label(details, text="CREATED BY", background="#1f2937",
                  foreground="#93c5fd", font=("Sans", 9, "bold")).pack(anchor="w")
        ttk.Label(details, text="nightx24 (augztn)", background="#1f2937",
                  foreground="#f9fafb", font=("Sans", 15, "bold")).pack(
                      anchor="w", pady=(4, 10))
        links = ttk.Frame(details, style="Panel.TFrame")
        links.pack(fill="x")
        instagram = ttk.Label(links, text="Instagram  ↗", background="#1f2937",
                              foreground="#60a5fa", cursor="hand2",
                              font=("Sans", 11, "underline"))
        instagram.pack(side="left", padx=(0, 18))
        instagram.bind("<Button-1>", lambda _event: webbrowser.open("https://www.instagram.com/augztn/"))
        github = ttk.Label(links, text="GitHub  ↗", background="#1f2937",
                           foreground="#60a5fa", cursor="hand2",
                           font=("Sans", 11, "underline"))
        github.pack(side="left")
        github.bind("<Button-1>", lambda _event: webbrowser.open("https://github.com/nightx24"))

        ttk.Label(content_frame, text="DroidLab · Community firmware utility",
                  style="Muted.TLabel", font=("Sans", 10)).pack(
                      anchor="center", pady=(14, 4))

        # Trackpad and mouse-wheel scrolling: support Linux/X11 wheel events,
        # Windows/macOS delta events, and smooth touchpad deltas.
        def on_mousewheel(event):
            delta = getattr(event, "delta", 0) or 0
            if delta:
                if abs(delta) >= 120:
                    units = int(-delta / 120)
                else:
                    # Linux touchpads often send small deltas instead of 120-step wheel events.
                    units = -1 if delta > 0 else 1
                canvas.yview_scroll(units, "units")
            elif getattr(event, "num", None) == 4:
                canvas.yview_scroll(-1, "units")
            elif getattr(event, "num", None) == 5:
                canvas.yview_scroll(1, "units")
            return "break"

        # Bind wheel events to the canvas and every child in the scrollable area,
        # since Tk widgets under the pointer otherwise consume the event.
        def bind_scroll_events(widget):
            for sequence in ("<MouseWheel>", "<Button-4>", "<Button-5>",
                             "<Shift-MouseWheel>"):
                widget.bind(sequence, on_mousewheel, add="+")
            for child in widget.winfo_children():
                bind_scroll_events(child)

        bind_scroll_events(content_frame)
        bind_scroll_events(hero)
        canvas.bind("<MouseWheel>", on_mousewheel, add="+")
        canvas.bind("<Button-4>", on_mousewheel, add="+")
        canvas.bind("<Button-5>", on_mousewheel, add="+")
        # Some desktop environments report touchpad gestures as XInput/Touchpad
        # events; keeping focus on the scrollable surface helps keyboard navigation.
        canvas.configure(takefocus=True)
        canvas.bind("<Up>", lambda _e: canvas.yview_scroll(-1, "units"))
        canvas.bind("<Down>", lambda _e: canvas.yview_scroll(1, "units"))
        canvas.bind("<Prior>", lambda _e: canvas.yview_scroll(-1, "pages"))
        canvas.bind("<Next>", lambda _e: canvas.yview_scroll(1, "pages"))
        dialog.grab_set()
