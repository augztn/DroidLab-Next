# Feature Parity Checklist

**Baseline:** `DroidLab-Next` main at `b09da903fbe06a1d296f59f0c44f378573a307e4`.  
**Legend:** [x] observed in source; [ ] not yet migrated/verified in Flutter. An observed legacy feature is not a claim that its Flutter implementation exists.

## Application and platform
- [x] Python 3.10+ Tkinter desktop application and package entrypoints.
- [x] Theme selection with centralized legacy theme palettes.
- [x] User settings persisted to `~/DroidLab/config.json`.
- [x] Windows/Linux portable build workflows; Linux AppImage build script.
- [ ] Flutter Material 3 desktop composition root.
- [ ] Windows, Linux and macOS Flutter runtime validation (Linux x86_64 first).
- [ ] Native drag/drop and file picker parity.
- [ ] Persistent responsive navigation and global console.

## Device manager and diagnostics
- [x] Combined ADB and Fastboot discovery on background workers.
- [x] Device serial/state display for device, recovery, sideload, unauthorized, offline and Fastboot states.
- [x] No automatic first-device selection when multiple targets are returned.
- [x] Device selection synchronization between ADB/Fastboot controls.
- [x] Device metadata lookup and stale-request invalidation.
- [x] Brand, model, product/codename, active slot, bootloader lock state, Android version and battery metadata where available.
- [x] Fastboot/Fastbootd mode detection and post-transition rescans.
- [ ] Flutter device manager with refresh/error/empty/multiple-device states.
- [ ] Device connection monitoring and selection persistence policy.

## ADB toolkit
- [x] Host ADB commands and Android shell command distinction/routing.
- [x] Device-target selector parsing and conflict rejection.
- [x] Fresh ADB state scan before selected-target execution.
- [x] Reboot to normal, bootloader and recovery with confirmation.
- [x] Recovery sideload with ZIP validation, drag/drop, target state checks and explicit confirmation.
- [x] Logcat streaming, filtering, pause/resume and save-to-file.
- [x] Bugreport generation and operation outcome reporting.
- [x] Per-device operation lock.
- [ ] Typed Flutter use cases and UI states for every workflow.

## Fastboot toolkit
- [x] Fastboot device discovery and device metadata.
- [x] Advanced command console with ADB command routing.
- [x] Command preview and explicit warning for advanced commands.
- [x] Fresh Fastboot target presence validation before mutation.
- [x] Filename-based partition suggestions for known image names.
- [x] Image flash with .img and partition-name validation plus target/image/partition/command confirmation.
- [x] Destructive maintenance actions including wipe, partition erase and slot changes.
- [x] Device operation serialization and outcome reporting.
- [ ] Flutter confirmation flow bound to immutable operation intent.
- [ ] Full parity tests against fixtures/mocked binaries.

## Firmware and payload
- [x] OTA ZIP and payload.bin source selection.
- [x] Main-window file drag/drop; payload.bin preference when multiple files are dropped.
- [x] Payload metadata inspection and partition name/size display.
- [x] Search/filter and multi-partition selection; select-all behavior.
- [x] Choose output location and select mounted removable media.
- [x] Extract selected partitions or all partitions.
- [x] Cancellation and bounded inspection/extraction timeouts.
- [x] Isolated staging directory, nonempty artifact verification, no-overwrite publication and rollback of partial publication.
- [x] Optional SHA-256 fingerprints.
- [x] Explicit payload backend diagnostics and known delta-OTA limitations.
- [ ] Flutter firmware explorer and extraction presentation.
- [ ] Python JSONL progress/cancellation protocol.

## Diagnostics and operations
- [x] Structured application logging and bounded process output.
- [x] ADB/Fastboot console output and operation outcome messages.
- [x] Error handling for missing binaries, timeouts, cancellation and disconnects.
- [ ] Unified severity-filterable Flutter application/backend/device console.
- [ ] Persistent operation history with typed timestamps, exit codes and diagnostic references.
- [ ] Structured diagnostics export and privacy warning.

## Settings and distribution
- [x] Tool path discovery/fallback, theme configuration and JSON user settings.
- [x] AppImage script pins payload-dumper-go and checks its SHA-256 before bundling.
- [x] Linux, Windows x64/ARM64 CI packaging workflows for Python app.
- [ ] Flutter app preferences and tool-path settings.
- [ ] Bundled/runtime Python bridge and payload-dumper-go for Linux.
- [ ] Flutter Linux release CI, AppImage and clean-machine startup verification.
- [ ] License/notice aggregation and upgrade-safe user data migration.

## Verification still required

- [ ] Run the source Python test suites and record actual current status (repository CI history is not a substitute for a local run).
- [ ] Port safety contract tests to backend bridge and Dart domain layers.
- [ ] Mock ADB/Fastboot binaries for no-device, multi-device, disconnect, timeout and failed-flash cases.
- [ ] Validate physical-device transitions and recovery sideload on controlled hardware.
- [ ] Validate AppImage on a clean supported Linux environment.
