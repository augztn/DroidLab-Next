"""Stable application metadata and visual defaults."""

APP_NAME = "DroidLab"  # Canonical product name.

# Charcoal / Linear-inspired palettes. Keep semantic status colors distinct from
# neutral surfaces so device state and destructive actions remain easy to read.
THEME_TOKENS = {
    "cyberpunk_glass": {
        "label": "Charcoal Blue",
        "bg": "#10151c",
        "panel": "#171f29",
        "panel_alt": "#202c39",
        "border": "#304253",
        "text": "#edf4fb",
        "muted": "#9aabba",
        "input": "#0b1118",
        "accent": "#59c7ff",
        "accent2": "#1679b8",
        "button": "#243444",
        "console": "#080d13",
        "success": "#35c98a",
        "warning": "#f2b84b",
        "danger": "#f87171",
    },
    "standard_dark": {
        "label": "Charcoal",
        "bg": "#111113",
        "panel": "#19191d",
        "panel_alt": "#222228",
        "border": "#303038",
        "text": "#f2f2f5",
        "muted": "#9696a3",
        "input": "#101014",
        "accent": "#4b8dff",
        "accent2": "#2868d7",
        "button": "#26262d",
        "console": "#0b0b0e",
        "success": "#35c98a",
        "warning": "#f2b84b",
        "danger": "#f87171",
    },
    "oled_black": {
        "label": "OLED Black",
        "bg": "#050506",
        "panel": "#0e0e11",
        "panel_alt": "#19191d",
        "border": "#29292f",
        "text": "#f5f5f7",
        "muted": "#9696a3",
        "input": "#08080a",
        "accent": "#78aaff",
        "accent2": "#386fda",
        "button": "#1b1b20",
        "console": "#030304",
        "success": "#35c98a",
        "warning": "#f2b84b",
        "danger": "#f87171",
    },
}
