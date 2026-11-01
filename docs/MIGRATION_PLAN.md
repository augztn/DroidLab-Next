# Migration plan and status

Target branch: `rewrite/flutter-desktop`. The original `DroidLab-Next` repository remains unchanged as the behavioral reference.

| Phase | Status |
|---|---|
| 1. Repository audit and architecture | Source audit and safety contracts documented |
| 2. Flutter foundation and design system | Material 3 shell, responsive sidebar, routing, Riverpod and native build bootstrap implemented |
| 3. Backend bridge and protocol | Dart Process.start client, Python JSONL service, request correlation, cancellation and tests implemented |
| 4. Device discovery | ADB/Fastboot discovery implemented; legacy metadata and selection parity remain |
| 5. ADB toolkit | Shell, reboot, device info, logcat, bugreport and sideload implemented; full parity remains |
| 6. Fastboot toolkit | Flash, erase and reboot implemented with target-bound confirmation; additional maintenance parity remains |
| 7. Payload extraction | Inspect/extract implemented with staging, verification and no-overwrite publication |
| 8. Diagnostics and history | Live console and local operation history implemented; full export/redaction remains |
| 9. Settings and integration | Routes, drag/drop and backend runtime integrated; editable persistent settings remain |
| 10. Testing and release | Fake-tool tests, cross-platform CI builds and AppImage script added; hardware and clean-machine release validation remain |

## Definition of done

- Flutter analysis, unit/widget tests and native Linux/Windows/macOS builds pass in CI.
- Python backend unit and JSONL integration tests pass with fake executables.
- No device operation is available without an explicit target serial and backend preflight.
- Destructive confirmation is bound to the exact operation intent and revalidated before dispatch.
- Process cancellation/shutdown does not orphan child processes or claim device rollback.
- Payload extraction never overwrites existing output and rolls back partial publication.
- Controlled-device and clean-machine release checks are completed before production release.

Do not mark the project production-ready solely because CI passes.
