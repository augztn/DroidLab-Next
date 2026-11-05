#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VERSION="${VERSION:-0.1.0}"
BACKEND_VERSION="${BACKEND_VERSION:-2.1.0}"
APPDIR="$ROOT/build/AppDir"
WORK="$ROOT/build/appimage"
DIST="$ROOT/dist"
ARCHIVE="payload-dumper-go_${BACKEND_VERSION}_linux_amd64.tar.gz"
command -v flutter >/dev/null || { echo "Flutter stable is required." >&2; exit 1; }
command -v python3 >/dev/null || { echo "Python 3.10+ is required on the target host." >&2; exit 1; }
command -v wget >/dev/null || { echo "wget is required." >&2; exit 1; }
command -v tar >/dev/null || { echo "tar is required." >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "sha256sum is required." >&2; exit 1; }
command -v xz >/dev/null || { echo "xz is required by payload-dumper-go. Install xz-utils (Debian/Ubuntu), xz (Fedora/macOS Homebrew), or the platform equivalent." >&2; exit 1; }
command -v appimagetool >/dev/null || { echo "Install appimagetool before building the AppImage." >&2; exit 1; }
cd apps/desktop
flutter pub get --enforce-lockfile
flutter build linux --release
cd "$ROOT"
python3 scripts/stage_backend.py
rm -rf "$APPDIR" "$WORK"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/scalable/apps" "$APPDIR/usr/share/licenses/payload-dumper-go" "$APPDIR/usr/lib/droidlab/backend" "$APPDIR/opt/payload-dumper/bin" "$APPDIR/opt/payload-dumper/lib"
cp -a apps/desktop/build/linux/x64/release/bundle/. "$APPDIR/usr/bin/"
cp -a backend/python/. "$APPDIR/usr/lib/droidlab/backend/"
install -m 0755 "$(command -v xz)" "$APPDIR/opt/payload-dumper/bin/xz"
mkdir -p "$WORK/download"
wget -q --show-progress "https://github.com/ssut/payload-dumper-go/releases/download/${BACKEND_VERSION}/${ARCHIVE}" -O "$WORK/download/$ARCHIVE"
case "$BACKEND_VERSION" in
  2.1.0) EXPECTED_SHA256="bbbb53a71955c69272afdef7bc7e83a1bb1770f453d0c21dcaf61a3ba0463c11" ;;
  *) echo "No verified payload-dumper-go checksum for version $BACKEND_VERSION." >&2; exit 1 ;;
esac
echo "$EXPECTED_SHA256  $WORK/download/$ARCHIVE" | sha256sum --check --status || { echo "payload-dumper-go checksum verification failed." >&2; exit 1; }
mkdir -p "$WORK/extract"
tar -xzf "$WORK/download/$ARCHIVE" -C "$WORK/extract"
PAYLOAD_DUMPER="$(find "$WORK/extract" -type f -name payload-dumper-go -print -quit)"
[[ -n "$PAYLOAD_DUMPER" ]] || { echo "payload-dumper-go binary not found in release archive." >&2; exit 1; }
install -m 0755 "$PAYLOAD_DUMPER" "$APPDIR/usr/bin/payload-dumper-go"
"$APPDIR/usr/bin/payload-dumper-go" --help >/dev/null 2>&1 || {
  echo "Bundled payload-dumper-go failed its startup smoke test." >&2
  exit 1
}
# Also ship the CLI beside the regular extracted Linux desktop bundle.
install -m 0755 "$PAYLOAD_DUMPER" "apps/desktop/build/linux/x64/release/bundle/payload-dumper-go"
wget -q "https://raw.githubusercontent.com/ssut/payload-dumper-go/${BACKEND_VERSION}/LICENSE" -O "$APPDIR/usr/share/licenses/payload-dumper-go/LICENSE"
if command -v ldd >/dev/null; then
  ldd "$(command -v xz)" | awk '/=> \// {print $3} /^[[:space:]]*\// {print $1}' | sort -u | while read -r dependency; do
    [[ -f "$dependency" ]] || continue
    case "$(basename "$dependency")" in libc.so*|ld-linux*.so*|ld-*.so*) continue ;; esac
    cp -L "$dependency" "$APPDIR/opt/payload-dumper/lib/$(basename "$dependency")"
  done
fi
cat > "$APPDIR/AppRun" <<'RUN'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
export DROIDLAB_BACKEND_SCRIPT="$HERE/usr/lib/droidlab/backend/server.py"
export DROIDLAB_BUNDLE_ROOT="$HERE/usr"
PYTHON_BIN="${DROIDLAB_PYTHON:-python3}"
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "DroidLab requires Python 3.10 or newer on the host. Install Python or set DROIDLAB_PYTHON to its executable." >&2
  exit 127
fi
if ! "$PYTHON_BIN" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)'; then
  echo "DroidLab requires Python 3.10 or newer; found: $("$PYTHON_BIN" --version 2>&1)" >&2
  exit 1
fi
export DROIDLAB_PYTHON="$PYTHON_BIN"
export DROIDLAB_PAYLOAD_DUMPER_GO_PATH="$HERE/usr/bin/payload-dumper-go"
export PATH="$HERE/opt/payload-dumper/bin:$HERE/usr/bin:$PATH"
export LD_LIBRARY_PATH="$HERE/opt/payload-dumper/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$HERE/usr/bin/droidlab_desktop" "$@"
RUN
chmod 0755 "$APPDIR/AppRun"
cat > "$APPDIR/droidlab.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=DroidLab
Comment=Android device engineering workstation
Exec=AppRun
Icon=droidlab
Categories=Utility;Development;System;
Terminal=false
DESKTOP
cp "$APPDIR/droidlab.desktop" "$APPDIR/usr/share/applications/droidlab.desktop"
install -D -m 0644 assets/branding/droidlab_app_icon.png "$APPDIR/droidlab.png"
install -D -m 0644 assets/branding/droidlab_app_icon.png "$APPDIR/usr/share/icons/hicolor/256x256/apps/droidlab.png"
cp "$APPDIR/droidlab.png" "$APPDIR/.DirIcon"
mkdir -p "$DIST"
APPIMAGE_ARGS=()
if [[ -n "${APPIMAGE_RUNTIME_FILE:-}" ]]; then
  [[ -f "$APPIMAGE_RUNTIME_FILE" ]] || { echo "Pinned AppImage runtime not found: $APPIMAGE_RUNTIME_FILE" >&2; exit 1; }
  APPIMAGE_ARGS+=(--runtime-file "$APPIMAGE_RUNTIME_FILE")
fi
ARCH=x86_64 appimagetool "${APPIMAGE_ARGS[@]}" "$APPDIR" "$DIST/DroidLab-${VERSION}-x86_64.AppImage"
echo "Built $DIST/DroidLab-${VERSION}-x86_64.AppImage"
