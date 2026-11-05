#!/usr/bin/env python3
"""Apply the supplied DroidLab artwork to generated native desktop runners."""
from pathlib import Path
from PIL import Image
import json

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/branding/droidlab_app_icon.png"
if not SOURCE.is_file():
    raise SystemExit(f"Missing official icon: {SOURCE}")

image = Image.open(SOURCE).convert("RGBA")
if image.width != image.height:
    raise SystemExit("DroidLab application icon must be square")

# Windows: multi-resolution ICO.
windows_icon = ROOT / "apps/desktop/windows/runner/resources/app_icon.ico"
windows_icon.parent.mkdir(parents=True, exist_ok=True)
image.save(windows_icon, format="ICO", sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])

# macOS: complete AppIcon asset catalog.
mac_icon_dir = ROOT / "apps/desktop/macos/Runner/Assets.xcassets/AppIcon.appiconset"
mac_icon_dir.mkdir(parents=True, exist_ok=True)
entries = []
for points, scale in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]:
    pixels = points * scale
    filename = f"app_icon_{pixels}.png"
    image.resize((pixels,pixels), Image.Resampling.LANCZOS).save(mac_icon_dir / filename)
    entries.append({
        "filename": filename,
        "idiom": "universal",
        "platform": "mac",
        "size": f"{points}x{points}",
        "scale": f"{scale}x"
    })
(mac_icon_dir / "Contents.json").write_text(
    json.dumps({"images": entries, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
    encoding="utf-8"
)
print("Applied official DroidLab icon to Windows and macOS runners.")
