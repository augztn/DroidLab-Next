# Feature parity

The legacy Python/Tkinter implementation in `DroidLab-Next` is the behavior reference. This checklist is based on the legacy controllers, views, settings loader, command guards and payload workflows, and records the current Flutter implementation separately from remaining validation work.

## Implemented in the Flutter rewrite

- Material 3 desktop shell, responsive navigation, Dashboard, Device Manager, Firmware & Payload, ADB, Fastboot, Logs, Operation History and Settings routes.
- Managed Dart backend process bridge, JSONL protocol, bounded streaming output, cancellation, timeout and process cleanup.
- Python backend with fresh ADB/Fastboot scans, explicit target requirements, exact destructive-operation confirmation and per-device mutation serialization.
- ADB and Fastboot targets displayed in the shared ADB selector; dedicated Fastboot selector and refresh control.
- ADB shell command execution, online/authorization-state gating, reboot, recovery reboot, bootloader reboot, logcat start/stop/pause/filter/export, bugreport and OTA ZIP sideload.
- Mode-aware reboot dispatch: ADB is used while the target is in ADB/recovery; Fastboot is used when the same serial is already in bootloader mode. Device rediscovery is retried after the transition.
- Device metadata for manufacturer, model, model code/codename, active slot, bootloader lock state, Android version/SDK and battery where the transport exposes the values.
- Device details available from Device Manager and both device-tool views.
- Fastboot flash, erase, cache/userdata erase, factory wipe, reboot system/recovery/bootloader, advanced command preview and exact destructive confirmation.
- Fastboot active-slot A/B switching using the primary `--set-active` syntax and legacy `set_active` fallback, with fresh target validation. Unlock/lock remain available only through the confirmed advanced Fastboot command rather than dedicated buttons.
- Native file pickers for OTA/payload input, output directory, Fastboot image and recovery ZIP, plus drag-and-drop.
- User-mounted/available storage selection: Linux user media roots, macOS `/Volumes`, and Windows volume roots, with refresh and use-as-output controls.
- OTA ZIP/BIN inspection and selected/all partition extraction with isolated staging, nonempty artifact checks, no-overwrite publication, rollback and optional SHA-256.
- Persistent appearance settings compatible with the legacy `~/DroidLab/config.json` path, including `cyberpunk_glass`, `standard_dark` and `oled_black`.
- Editable tool executable settings for Python, backend script, ADB, Fastboot and payload-dumper-go; tool paths are read from saved settings by the backend.
- Bundled-tool-first, configured-path-second and PATH-fallback tool resolution.
- Live bounded operation console, local operation history, backend diagnostics, About dialog and Help navigation.
- Linux AppImage packaging and Linux TAR, Windows and macOS CI artifacts.

## Remaining parity and release validation

- Full legacy appearance palette verification at pixel/detail level; the Flutter themes preserve the three legacy theme identities but are not a pixel-perfect Tk rendering clone.
- Bundled Python runtime and Android platform-tools for Windows/macOS; these builds still depend on host Python and ADB/Fastboot installation.
- Native discovery of only removable devices on Windows; the current selector enumerates available drive roots there. Linux and macOS scans use their standard user media mount directories.
- Persistent diagnostics report export/redaction matching the complete legacy report format and a dedicated log-folder opener.
- Full advanced ADB host-command workflows and every legacy drag/drop entrypoint.
- Controlled physical-device validation for different OEMs, recovery implementations, Fastbootd vs bootloader Fastboot and A/B slot behavior.
- Clean-machine smoke tests covering the AppImage on supported Linux distributions and runtime library combinations.

CI uses fake executables only. Passing tests/builds do not prove device mutation safety on every OEM or release readiness.
