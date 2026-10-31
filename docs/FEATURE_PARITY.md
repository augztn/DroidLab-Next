# Feature parity

The legacy Python/Tkinter implementation in `DroidLab-Next` is the behavior reference. The checklists below distinguish legacy capabilities from current Flutter rewrite implementation.

## Implemented in the Flutter rewrite

- Material 3 dark desktop shell, responsive collapsible sidebar and feature routes.
- Riverpod providers, GoRouter navigation and centralized theme tokens.
- Managed Dart `Process.start` client with streamed stdout/stderr, request IDs, timeouts, cancellation, bounded diagnostics and shutdown cleanup.
- Python JSONL service with named operations, typed failures, fresh target scans and per-device mutation serialization.
- ADB/Fastboot device discovery with no implicit first-device selection.
- ADB shell with exact target/command confirmation, reboot, device metadata, live logcat, filters, log export, bugreport and recovery sideload.
- Fastboot flash, erase and reboot with exact target/partition/image confirmation.
- OTA BIN/ZIP inspection and selected/all partition extraction with isolated staging, nonempty artifact checks, no-overwrite publication, rollback and optional SHA-256.
- Drag/drop for OTA sources, recovery ZIPs and Fastboot image files.
- Local bounded operation history for completed, failed and cancelled operations.
- Live bounded operation console.
- Python guard/process/protocol/payload tests and cross-platform Flutter CI build/test jobs.
- Linux AppImage build script with pinned payload-dumper-go checksum verification.

## Remaining parity and validation work

- Full legacy device metadata: brand/model/codename, active slot, bootloader lock, Android version and battery metadata across supported states.
- Device selection synchronization, stale-selection invalidation and post-transition refresh parity.
- Additional Fastboot maintenance commands such as slot switching and unlock/lock.
- Advanced host/ADB command workflows and complete legacy ADB feature parity.
- Logcat pause/resume, richer filtering, and persistent diagnostics export/redaction.
- Editable, persistent tool paths and settings migration.
- Native file picker and every legacy drag/drop entrypoint.
- Bundled Python runtime and platform-tools for Windows/macOS; current native bundles stage backend source only.
- Clean-machine AppImage smoke tests and controlled physical-device validation.

CI uses fake executables only. A successful build does not prove hardware safety or release readiness.
