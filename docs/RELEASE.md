# Release and packaging

## Desktop bundles

The CI pipeline generates the Flutter native runner projects, resolves packages, analyzes and tests the app, builds Linux/Windows/macOS release bundles, then stages `backend/python` beside each native executable. Linux bundles also include the pinned `payload-dumper-go` executable beside the native app, so payload inspection and extraction work in both the AppImage and extracted tarball. The backend requires Python 3.10+ on the host and the Android platform-tools installation for ADB/Fastboot.

## Linux AppImage

Run `bash scripts/build-linux-appimage.sh` with Flutter stable, Python 3.10+, `wget`, `tar`, `xz`, `sha256sum` and `appimagetool` installed. The build pins payload-dumper-go 2.1.0 and verifies the release archive SHA-256 before inclusion. It also includes the payload-dumper license and xz runtime libraries while intentionally relying on the host glibc.

The Linux CI job builds and uploads `DroidLab-0.1.0-x86_64.AppImage` alongside the Linux tarball as part of the `droidlab-linux` workflow artifact. Download that artifact from the successful Desktop CI run. The AppImage uses the host Python 3 runtime and host ADB/Fastboot. These are explicit runtime requirements; this packaging step does not bundle a Python interpreter or Android platform tools. A clean-machine AppImage smoke test is required before calling the artifact production-ready.
