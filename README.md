# DroidLab

DroidLab is a cross-platform desktop engineering workstation for Android device diagnostics, OTA inspection, payload extraction and guarded Fastboot operations.

## Architecture

- Flutter desktop UI: Material 3, Riverpod state and GoRouter navigation.
- Domain package: immutable device and partition models plus repository contracts, independent of Flutter UI and Python protocol details.
- Dart backend bridge: managed `Process.start` lifecycle and versioned JSON Lines protocol.
- Python backend: headless process execution, fresh device preflight, payload extraction and guarded device operations.
- Design system: centralized dark theme tokens.

The original Tkinter implementation remains in [DroidLab-Next](https://github.com/augztn/DroidLab-Next) as the behavioral reference. Development takes place on `hardening/backend-modularization` and is proposed to `main` through pull request #6.

## Development

Requires Flutter 3.47.9 (or compatible stable), Python 3.10+, Android platform-tools (`adb` and `fastboot`), and `payload-dumper-go` for payload workflows. Windows and macOS release bundles include a checksum-verified Python runtime. Android Platform-Tools are installed per-user through the explicit Google license-acceptance flow; Linux uses the host Python runtime and distribution/SDK-managed ADB and Fastboot.

```sh
bash scripts/bootstrap-flutter.sh
cd apps/desktop
flutter analyze
flutter test
flutter run -d linux
```

Run `flutter run` from `apps/desktop`; the development backend resolver locates `../backend/python/server.py` from that working directory (and also supports launching from the repository root). Set `DROIDLAB_PYTHON`, `DROIDLAB_BACKEND_SCRIPT`, `DROIDLAB_ADB_PATH`, `DROIDLAB_FASTBOOT_PATH`, or `DROIDLAB_PAYLOAD_DUMPER_GO_PATH` when tools are not on PATH.

Run backend tests from the repository root:

```sh
python -m unittest discover -s backend/python/tests -v
```

Architecture and implementation records: [Architecture](docs/ARCHITECTURE.md) · [Backend protocol](docs/BACKEND_PROTOCOL.md) · [Feature parity](docs/FEATURE_PARITY.md) · [Migration plan](docs/MIGRATION_PLAN.md) · [Safety requirements](docs/SAFETY_REQUIREMENTS.md) · [Release](docs/RELEASE.md) · [Physical device validation](docs/DEVICE_VALIDATION.md) · [Release signing](docs/RELEASE_SIGNING.md).

## Safety

Every device mutation requires an explicit serial, a fresh transport scan, validated arguments, and confirmation in both UI and backend. Multiple devices are never implicitly resolved by selecting the first result. Host cancellation is not a device rollback guarantee. Bugreports and logs can contain private device data; review them before sharing.

## Linux AppImage

Install `appimagetool`, Flutter stable, Python 3.10+, `wget`, and `sha256sum`, then run:

```sh
bash scripts/build-linux-appimage.sh
```

The script pins and verifies payload-dumper-go 2.1.0 before bundling it. The AppImage uses the host's Python 3 runtime and Android platform tools; install `python3`, `adb`, and `fastboot` on the target machine. The Python backend is staged beside the app in CI bundles and embedded in the AppImage. Windows and macOS bundles include a checksum-verified Python runtime. Tool discovery checks environment overrides, shared DroidLab settings, bundled candidates, managed Platform-Tools, then PATH.

GitHub Actions runs Flutter analysis, widget/unit tests and native desktop builds on Linux, Windows and macOS, stages the backend beside each build, and runs Python backend tests.

## License

Apache-2.0. See [LICENSE](LICENSE).
