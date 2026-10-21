# DroidLab

DroidLab is a cross-platform desktop toolkit for Android firmware inspection, payload extraction, ADB diagnostics, and guarded Fastboot workflows. It is a desktop application—not an Android app manager or debloating utility.

DroidLab can inspect OTA `payload.bin` files and OTA ZIP packages, extract all or selected partition images, collect ADB diagnostics, stream and save logcat, sideload compatible ZIPs, and perform Fastboot maintenance and image flashing with explicit destructive-action confirmation.

## Capabilities

- **Payload inspection and extraction:** inspect OTA metadata, view partition names and sizes, filter/select partitions, choose an output directory, cancel extraction, and optionally calculate SHA-256 fingerprints for output files.
- **ADB diagnostics:** discover connected devices and their states; run shell diagnostics; reboot to normal, bootloader, or recovery; sideload compatible ZIP packages; stream, filter, pause, and save logcat; and create bugreport archives.
- **Guarded Fastboot workflows:** detect Fastboot devices, preview commands, suggest partitions from image filenames, flash images, switch slots, and run supported maintenance actions. Destructive commands are validated and require confirmation.
- **Portable packaging:** Linux AppImage and Windows portable ZIP bundles can include the payload extraction backend and compatible Android platform-tools binaries. If a bundled ADB/Fastboot binary is not available, DroidLab falls back to the user's `PATH`.

Bugreports and device logs can contain sensitive personal or device information. Review their contents before sharing them. SHA-256 output fingerprints are useful for comparison but do not replace the OTA backend's own integrity checks.

## Architecture

The application keeps a compatibility bootstrap at `src/app.py`; the package implementation is organized by responsibility:

```text
src/
├── app.py                         # Legacy-compatible entrypoint
├── command_guards.py              # Legacy import shim
├── payload_dumper.py              # Legacy import shim
├── process_runner.py              # Legacy import shim
├── ui_metrics.py                  # Legacy import shim
└── droidlab/
    ├── __init__.py
    ├── __main__.py                # python -m droidlab
    ├── config/                    # App constants, settings, logging
    ├── core/                      # UI-independent command guards, process runner,
    │                              # and payload backend adapter
    ├── controllers/               # Device, ADB, Fastboot, payload workflows
    └── ui/                        # Main window, layout, views, dialogs, widgets,
                                   # theme support, and UI sizing
```

Controller mixins preserve the existing `PayloadDumperApp` widget attributes, callback names, worker signatures, cancellation state, and UI event queue protocol. The core package is intentionally free of Tkinter dependencies. Legacy flat-module shims remain for existing tests, callers, and frozen-build compatibility.

## Requirements

- Python 3.10 or newer.
- Tkinter support for the Python installation (on Debian/Ubuntu, install the matching `python3-tk` package).
- `tkinterdnd2`, installed automatically by the project package.
- Android `adb` and `fastboot` on `PATH`, unless a platform bundle supplies them.
- A compatible `payload-dumper-go` backend for payload extraction; the portable build workflows package this backend.

## Install and launch

From the repository root, create and activate a virtual environment if desired, then install the project:

```bash
python -m pip install -e .
```

Launch using any of the supported entrypoints:

```bash
python src/app.py       # compatibility entrypoint
python -m droidlab      # package entrypoint (after installation)
```

For development and test dependencies:

```bash
python -m pip install -e ".[dev,build]"
```

## Tests and code checks

Run both supported test suites from the repository root:

```bash
python -m pytest -q
python -m unittest discover -s tests
```

The package-wiring tests validate module imports, controller/view mixin wiring, legacy entrypoints, tool/backend path discovery, worker event characteristics, and PyInstaller submodule collection settings. A headless test run may stub `tkinterdnd2` for import-only checks; that is not a substitute for launching the actual GUI or smoke-testing a frozen executable.

If Ruff is installed, run:

```bash
ruff check src tests
```

## Portable builds

### Linux AppImage

The build script requires Python/Tkinter, PyInstaller, `wget`, `tar`, `xz`, and the AppImage packaging tools. On Ubuntu/Debian, install the system Tk package first. Then install the project's build dependencies and run:

```bash
python -m pip install -e ".[dev,build]"
VERSION=0.1.0 bash scripts/build-linux.sh
```

The script downloads the pinned payload backend, verifies its SHA-256 checksum, freezes the GUI with PyInstaller, and assembles an AppDir/AppImage. The build workflow documents the exact CI environment and performs a startup smoke test. AppImages should still be tested on supported target distributions before publishing a release.

### Windows portable ZIP

Windows bundles are produced by the `Windows build` and `All-platforms bundle` GitHub Actions workflows. They package the GUI executable, payload backend, and compatible Android platform-tools when available. To build locally, use a supported Windows Python/Tkinter environment, install `.[dev,build]`, and run the PyInstaller command in `.github/workflows/windows.yml` or `.github/workflows/cross-platform-bundle.yml`; the workflows also assemble the portable ZIP layout.

CI build outputs are useful validation artifacts, but should not be treated as a production release until startup and representative OTA/device workflows have been smoke-tested on clean systems.

## Known limitations

The payload backend has inherited limitations for some delta operations, including `PUFFDIFF`, `ZUCCHINI`, and `LZ4DIFF_*`. Incremental OTA packages may require base images, and `xz` may be needed for applicable payloads. Read the upstream backend documentation before relying on extracted images for device flashing.

## License

DroidLab is distributed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
