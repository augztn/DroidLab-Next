# Legacy implementation audit

## Scope and method

This audit compares the legacy Python/Tkinter application in `augztn/DroidLab-Next` (default branch `main`) with the native Flutter/Dart application in this repository on `rewrite/flutter-desktop`. The legacy implementation is treated as the behavior reference. The comparison was made against the settings helper, main window, ADB/device/Fastboot/payload controllers and their view builders, then checked against the Flutter application pages, settings store, Riverpod providers and Python JSONL service.

## Settings and executable resolution

| Concern | Legacy implementation | Flutter rewrite |
|---|---|---|
| Settings file | `Path.home()/DroidLab/config.json` | Same per-user `DroidLab/config.json` location in `DroidLabSettingsStore` |
| Missing/malformed config | Returns an empty mapping | Returns default settings; malformed/missing config does not prevent startup |
| Persistence | Creates parent directory and writes JSON | Writes indented JSON through a temporary file, with a backup/restore path |
| Theme | Reads `theme`, falls back to `cyberpunk_glass` | Same key and default; app root watches the settings provider and applies the selected theme |
| Theme identities | `cyberpunk_glass`, `standard_dark`, `oled_black` | All three identities are exposed in Settings and implemented in the design-system theme |
| Tool overrides | Main-window `_tool_path` resolves configured tools | Settings expose Python, backend script, ADB, Fastboot and payload-dumper-go fields; backend reads matching legacy JSON keys |
| Override precedence | Explicit configured/environment path is used when set; otherwise bundled/app-relative paths and then host PATH | Environment override, then saved setting; an explicit value must resolve; when blank, app-relative bundled candidates then PATH |

The Flutter settings model reads legacy aliases as well as the snake-case keys written by the rewrite. Python/backend executable changes require restarting the app because the managed backend process is created once; device tool paths are read for subsequent backend operations.

## Device discovery, mode and metadata

**Legacy sources:** `device_controller.py`, `adb_view.py`, `main_window.py`.

Legacy discovery scans ADB and Fastboot, keeps unauthorized/offline/recovery/sideload states visible, updates a shared device selector and refreshes device metadata asynchronously. Its mode detector changes the available reboot actions depending on the selected transport. It distinguishes bootloader Fastboot from userspace Fastbootd using `fastboot getvar is-userspace`.

**Flutter mapping:** `DeviceManagerPage`, `AdbToolkitPage`, `FastbootToolkitPage`, `devices.list` and `device.info` in the Python backend. The ADB page can display both ADB and Fastboot targets, has an explicit refresh action, and gates commands by the selected transport/state. Metadata includes manufacturer, model, model code/codename, slot, bootloader lock state, Android release/SDK and ADB battery level where available.

The latest audit fix also restores Fastbootd detection and combines stdout/stderr when parsing Fastboot getvar output, matching the legacy parser's behavior. Physical-device verification is still needed because OEM Fastboot implementations differ.

## ADB command and diagnostics workflows

**Legacy sources:** `adb_controller.py`, `adb_view.py`.

The legacy command input accepts three forms: a plain Android shell command, an `adb ...` host command, or a `fastboot ...` host command. Host device-targeted commands inherit the selected serial unless the command explicitly selects the same serial. A conflicting serial is rejected. Reboot and sideload use dedicated guarded actions. The legacy UI also supports live logcat with pause/filter, saving filtered visible output, a separate one-hour logcat-to-file capture, bugreport ZIP output, and OTA ZIP sideload with drag/drop.

**Flutter mapping:** The ADB Toolkit routes plain text to `adb.shell`, an `adb` prefix to the host-side `adb.command` protocol operation, and a `fastboot` prefix to `fastboot.command`. The Python service parses arguments, validates explicit serial selectors, injects the selected target only when appropriate, performs a fresh device scan and requires exact UI confirmation. Host discovery/help/version commands may run without a selected target. Reboot/sideload remain dedicated operations.

The Flutter UI provides live logcat, pause/resume display, client-side text filtering, save of the bounded display buffer, a separate one-hour full-stream-to-file capture, bugreport ZIP generation and sideload. The display buffer and full capture are intentionally separate so the UI stays bounded without truncating the saved capture.

## Fastboot workflows

**Legacy sources:** `fastboot_controller.py`, `fastboot_view.py`.

The legacy app supports reboot system/recovery/bootloader, cache/userdata erase, factory wipe, partition flash, active slot changes, image filename-to-partition hints, command preview, advanced command execution, host discovery/help commands without a device selected, and fresh Fastboot target validation before device mutations. Unlock/lock can be entered through the unrestricted advanced command field after explicit confirmation.

**Flutter mapping:** `FastbootToolkitPage` and the `fastboot.*` backend operations. Flash, erase, wipe, reboot, A/B slot switching, advanced command execution and fresh target checks are implemented. The advanced command field is being aligned to allow `devices`, help and version commands without a selected device. Unlock/lock remain available as explicit advanced commands, not as separate dedicated buttons.

## Firmware and payload

**Legacy sources:** `payload_controller.py`, `payload_view.py`.

The legacy page supports OTA ZIP/BIN browse, typed path validation, drag/drop, output directory selection/opening, removable-drive discovery, browsing a selected mounted drive, selecting a drive as output, partition filtering, selected count/size summary, select all/none, optional SHA-256, activity log and cancel.

**Flutter mapping:** The unified Firmware & Payload page combines firmware inspection and payload extraction instead of exposing two duplicate navigation entries. It includes native file/directory pickers, drag/drop, user-mounted storage selection, partition search/selection, size summary, optional SHA-256, bounded activity log and guarded staged extraction. Linux scans the user's `/run/media/<user>` and `/media/<user>` roots; macOS scans `/Volumes`; Windows currently enumerates drive roots rather than distinguishing only removable volumes.

## Shell, observability and packaging

**Legacy sources:** `main_window.py` has theme loading, callback diagnostics, log-folder opening and diagnostic report saving. The legacy logcat capture has a one-hour limit and writes the full stream to a selected file.

**Flutter mapping:** The Material desktop shell includes a bounded operation console, logs/diagnostics page, operation history, Help and About. Linux AppImage and TAR packaging and Windows/macOS desktop CI artifacts exist. The AppImage includes the Flutter app, Python backend source and payload-dumper-go. It still uses host Python and host ADB/Fastboot tools.

## Remaining gaps confirmed by the comparison

1. Full one-hour logcat stream capture directly to a file (current UI saves the bounded in-memory buffer).
2. Persistent diagnostics report export with the legacy report format/redaction and an explicit log-folder opener.
3. Windows discovery of removable drives specifically; current Windows storage UI enumerates drive roots.
4. Dedicated unlock/lock UI actions (the generic advanced Fastboot command path is available, guarded and confirmed).
5. Complete parity for every legacy host command variant and every drag/drop entrypoint.
6. Bundled Python runtime and Android platform-tools on Windows/macOS; those bundles depend on host Python and ADB/Fastboot.
7. Clean-machine AppImage validation across supported Linux distributions and physical-device validation across OEMs, recovery implementations, Fastbootd/bootloader Fastboot and A/B slots.

CI uses fake executables and validates code/build/package structure only. It does not validate real USB authorization, OEM-specific device responses or firmware mutation outcomes.
