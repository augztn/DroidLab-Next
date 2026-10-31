# DroidLab

DroidLab is a cross-platform desktop engineering workstation for Android device diagnostics, OTA inspection, payload extraction and guarded Fastboot operations.

## Architecture

- Flutter desktop UI: Material 3, Riverpod state and GoRouter navigation.
- Domain package: platform-independent contracts and models.
- Dart backend bridge: managed `Process.start` lifecycle and versioned JSON Lines protocol.
- Python backend: headless process execution, fresh device preflight, payload extraction and guarded device operations.
- Design system: centralized dark theme tokens.

The original Tkinter implementation remains in [DroidLab-Next](https://github.com/augztn/DroidLab-Next) as the behavioral reference. Development takes place on `rewrite/flutter-desktop`.

## Development

Requires Flutter stable with desktop support, Python 3.10+, Android platform tools (`adb` and `fastboot`) and `payload-dumper-go` for the corresponding workflows.

```sh
cd apps/desktop
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```

Set `DROIDLAB_PYTHON`, `DROIDLAB_BACKEND_SCRIPT`, `DROIDLAB_ADB_PATH`, `DROIDLAB_FASTBOOT_PATH`, or `DROIDLAB_PAYLOAD_DUMPER_GO_PATH` when tools are not on PATH.

Run backend tests from the repository root:

```sh
python -m unittest discover -s backend/python/tests -v
```

## Safety

Every device mutation requires an explicit serial, a fresh transport scan, validated arguments, and confirmation in both UI and backend. Multiple devices are never implicitly resolved by selecting the first result. Host cancellation is not a device rollback guarantee. Bugreports and logs can contain private device data; review them before sharing.

GitHub Actions runs Flutter analysis, widget/unit tests and native desktop builds on Linux, Windows and macOS, plus Python backend tests.
