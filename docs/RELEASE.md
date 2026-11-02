# Release and packaging

## Desktop bundles

The CI pipeline uses Flutter 3.47.9 and GitHub Actions pinned to reviewed commit SHAs; Linux artifacts are built on Ubuntu 22.04 to establish an older glibc baseline, generates the Flutter native runner projects, resolves packages, analyzes and tests the app, builds Linux/Windows/macOS release bundles, then stages `backend/python` beside each native executable. Windows and macOS bundles include checksum-verified CPython 3.11.18 from the immutable python-build-standalone 20261026 release; Linux AppImage builds continue to use the host Python 3.10+ runtime. Google Android Platform-Tools are not redistributed in application bundles because Google's SDK license restricts redistribution. Windows and macOS provide an explicit, license-gated installer that downloads the official Google archive over HTTPS, verifies pinned SHA-256 digests, ZIP CRCs and both executable version reports (37.0.1), and installs to a versioned per-user application-data directory. Linux continues to use distribution packages or the Android SDK Manager. Windows storage selection uses Win32 removable-volume APIs and excludes fixed volumes. Tagged production releases require Windows Authenticode signing and macOS Developer ID signing plus Apple notarization; the release workflow fails closed when required secrets are missing. Use Desktop CI artifacts for unsigned development builds. Dependency resolution uses the committed lockfile with `--enforce-lockfile`.

## Linux AppImage

Run `bash scripts/build-linux-appimage.sh` with Flutter stable, Python 3.10+, `wget`, `tar`, `xz`, `sha256sum` and `appimagetool` installed. The build pins payload-dumper-go 2.1.0 and verifies the release archive SHA-256 before inclusion. It also includes the payload-dumper license and xz runtime libraries while intentionally relying on the host glibc.

The Linux CI job builds and uploads `DroidLab-0.1.0-x86_64.AppImage` alongside the Linux tarball as part of the `droidlab-linux` workflow artifact. Download that artifact from the successful Desktop CI run. The AppImage is a single portable Linux executable with its own AppRun launcher, desktop entry, icon, Flutter application, Python backend source, and pinned `payload-dumper-go` executable. CI also extracts the generated AppImage and verifies these files and executable permissions before publishing a dedicated `droidlab-linux-appimage` artifact.

Download the `droidlab-linux-appimage` artifact from the successful Desktop CI run, extract the artifact ZIP, then run:

```bash
chmod +x DroidLab-0.1.0-x86_64.AppImage
./DroidLab-0.1.0-x86_64.AppImage
```

No package installation is required. The current backend still uses the host Python 3.10+ runtime; the launcher checks Python and prints a direct diagnostic if it is missing or too old. Windows and macOS can install ADB/Fastboot per-user through the explicit Google license acceptance flow; Linux uses host-installed Android SDK Platform-Tools. The AppImage relies on the target system's compatible glibc and desktop/GTK runtime libraries, as is normal for Linux AppImages. Physical-device workflows require Android platform-tools on the host.

## Signing and notarization secrets

- Windows: `WINDOWS_SIGNING_CERTIFICATE_BASE64` and `WINDOWS_SIGNING_CERTIFICATE_PASSWORD`.
- macOS Developer ID signing: `MACOS_SIGNING_CERTIFICATE_BASE64`, `MACOS_SIGNING_CERTIFICATE_PASSWORD`, and `MACOS_SIGNING_IDENTITY`.
- Apple notarization: `APPLE_NOTARIZATION_KEY_BASE64`, `APPLE_NOTARIZATION_KEY_ID`, and `APPLE_NOTARIZATION_ISSUER_ID`.

Add these values as protected GitHub Actions secrets; never commit certificates, passwords, or API keys. A tagged production release fails until the platform-specific secrets are configured. Verify all assets on clean machines and complete physical-device acceptance tests before distribution. CI runner smoke tests cover staged runtime imports and AppImage structure, not installer behavior on arbitrary user machines or USB/Fastboot behavior.


Platform-Tools checksum provenance: the Windows archive digest is pinned from the [Microsoft winget package manifest](https://github.com/microsoft/winget-pkgs/blob/master/manifests/g/Google/PlatformTools/37.0.1/Google.PlatformTools.installer.yaml); the macOS archive digest is pinned from the [Homebrew Cask definition](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/a/android-platform-tools.rb). Both manifests reference versioned archives hosted by Google. Update the versioned URLs and digests together when adopting a newer upstream release.
