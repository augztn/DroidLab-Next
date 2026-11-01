# Feature parity

The legacy Python/Tkinter implementation in `DroidLab-Next` is the behavior reference. This checklist is based on the legacy controllers, views, settings loader, command guards and payload workflows, and records the current Flutter implementation separately from remaining validation work.

## Implemented in the Flutter rewrite

- Material 3 desktop shell, responsive navigation, Dashboard, Device Manager, Firmware & Payload, ADB, Fastboot, Logs, Operation History and Settings routes.
- Managed Dart backend process bridge, JSONL protocol, bounded streaming output, cancellation, timeout and process cleanup.
- Python backend with fresh ADB/Fastboot scans, explicit target requirements, exact destructive-operation confirmation and per-device mutation serialization.
- ADB and Fastboot targets displayed in the shared ADB selector; dedicated Fastboot selector and refresh control.
- ADB shell and advanced host ADB command execution (including device discovery and app install/transfer commands), online/authorization-state gating, explicit device refresh/selection, ADB/Fastboot-aware reboot routing, recovery reboot, bootloader reboot, logcat start/stop/pause/filter/export, bugreport and OTA ZIP sideload.
- Mode-aware reboot dispatch: ADB is used while the target is in ADB/recovery; Fastboot is used when the same serial is already in bootloader mode. Device rediscovery is retried after the transition.
- Device metadata for manufacturer, model, model code/codename, active slot, bootloader lock state, Android version/SDK and battery where the transport exposes the values. Fastboot metadata distinguishes bootloader Fastboot from userspace Fastbootd via `getvar is-userspace` and parses combined output.
- Device details available from Device Manager and both device-tool views.
- Fastboot flash, erase, cache/userdata erase, factory wipe, reboot system/recovery/bootloader, advanced command preview and exact destructive confirmation.
- Fastboot active-slot A/B switching using the primary `--set-active` syntax and legacy `set_active` fallback, with fresh target validation. Advanced Fastboot accepts device-targeted commands and no-target discovery/help/version commands; unlock/lock remain available through explicit command entry and confirmation rather than dedicated buttons.
- Native file pickers for OTA/payload input, output directory, Fastboot image, logcat output path, bugreport output path and recovery ZIP, plus drag-and-drop. ADB Toolkit also provides confirmed single-file push and pull workflows; pull stages to a private sibling directory and publishes without overwriting (atomic hard-link where supported, exclusive-create copy fallback otherwise).
- User-mounted/available storage selection: Linux user media roots and macOS `/Volumes`; Windows uses `GetLogicalDriveStringsW` plus `GetDriveTypeW` and lists only `DRIVE_REMOVABLE` volumes (fixed disks and optical drives are excluded).
- OTA ZIP/BIN inspection and selected/all partition extraction with isolated staging, nonempty artifact checks, no-overwrite publication, rollback and optional SHA-256.
- Persistent appearance settings compatible with the legacy `~/DroidLab/config.json` path, including `cyberpunk_glass`, `standard_dark` and `oled_black`. Light and dark presentations follow the operating-system appearance while retaining the selected accent palette.
- Editable tool executable settings for Python, backend script, ADB, Fastboot and payload-dumper-go; Python/backend settings configure process startup, while saved ADB/Fastboot/payload paths remain in the shared config and are resolved by the Python backend for each tool lookup.
- Explicit environment or saved executable paths take precedence; with blank overrides, the backend searches beside the app/in its bundled tool folders and then falls back to system `PATH`.
- Live bounded operation console, local operation history, backend stderr diagnostics, About dialog and Help navigation. An additional one-hour full-stream-to-file capture is provided separately from the bounded display buffer.
- Linux AppImage packaging and Linux TAR, Windows and macOS CI artifacts. CI smoke-tests bundled CPython/backend imports on fresh Windows and macOS runners and extracts/verifies the Linux AppImage.
- Windows and macOS bundles stage checksum-verified CPython 3.11.18; backend startup prefers the bundled interpreter unless an explicit Python override is configured.

## Remaining parity and release validation

- Full legacy appearance palette verification at pixel/detail level; the Flutter themes preserve the three legacy theme identities but are not a pixel-perfect Tk rendering clone.
- Bundled Android platform-tools for Windows/macOS; ADB/Fastboot still depend on host installation.
 Linux and macOS scans use their standard user media mount directories.
- Diagnostic report export and log-folder opening are implemented. Exports apply centralized best-effort redaction for credentials, device identifiers, MAC/IMEI-like values and host paths; users must still review reports before sharing. Existing pre-upgrade operations.log files may contain unredacted historical output.
- Additional ADB workflows beyond guarded single-file push/pull, including remaining legacy host-command variants and legacy drag/drop entrypoints.
- Controlled physical-device validation for different OEMs, recovery implementations, Fastbootd vs bootloader Fastboot and A/B slot behavior. Automated CI uses fake ADB/Fastboot executables and cannot validate USB/RSA authorization on a physical phone.
- Manual clean-machine installation and launch testing across supported Linux distributions/runtime-library combinations and Windows/macOS installer environments; CI runner smoke tests are not a substitute.

CI uses fake executables only. Passing tests/builds do not prove device mutation safety on every OEM or release readiness.
