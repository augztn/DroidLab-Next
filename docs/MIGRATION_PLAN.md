# DroidLab Migration Plan

**Target branch:** `rewrite/flutter-desktop`  
**Protected baseline:** target repository `main` remains unchanged.  
**Primary platform:** Linux x86_64. Windows/macOS remain supported design targets, but are not release-pipeline scope for this phase.

## Baseline audit summary

The source is a Python/Tkinter desktop application with 54 tracked files. It is not a Flutter application today. Its implementation is split across configuration, core execution/safety primitives, controllers and Tk views. Existing automated tests cover core backend, safety guards, workers, packaging/import wiring, process execution, sideload outcomes and theme/UI metrics.

The source repository contains valuable operational hardening; the rewrite must port behavior, not merely feature labels. Refer to [FEATURE_PARITY.md](FEATURE_PARITY.md) and [SAFETY_REQUIREMENTS.md](SAFETY_REQUIREMENTS.md).

## Phases and exit criteria

### Phase 1 — Repository audit and architecture
- [x] Inspect tracked tree, README, package metadata, controllers, core execution/guards, tests, packaging and CI.
- [x] Record architecture, parity checklist, safety invariants and migration phases.
- [ ] Execute source test suites and capture results in the audit (the GitHub connector does not execute repository code).
- Exit: reviewed architecture, documented unknowns and baseline feature checklist.

### Phase 2 — Flutter project foundation and design system
- [ ] Generate the desktop Flutter workspace.
- [ ] Add a modular Dart app shell, Riverpod composition root and GoRouter navigation.
- [ ] Establish Material 3 dark tokens, responsive collapsible sidebar, global device status and persistent console.
- [ ] Build testable empty/error/loading dashboard and feature route scaffolds without fake operational controls.
- Exit: `flutter analyze` and widget/unit tests pass; no device operations exposed before backend contract exists.

### Phase 3 — Python backend bridge and protocol
- [ ] Freeze and document existing backend operation semantics.
- [ ] Define versioned request/response/event JSON Schemas with request IDs and bounded messages.
- [ ] Implement managed Python process startup, stdout JSONL decoder, stderr diagnostics, cancellation, timeouts and shutdown.
- [ ] Add protocol conformance and crash/partial-line tests in Python and Dart.
- Exit: bridge can execute a harmless health/info operation and recover cleanly from backend failure.

### Phase 4 — Device discovery and Device Manager
- [ ] Implement ADB/Fastboot discovery as backend operations.
- [ ] Preserve ambiguous selection behavior, states and fresh-scan validation.
- [ ] Add metadata queries, request correlation and connection refresh.
- Exit: no-device/multiple-device/disconnect cases are tested with fake tools.

### Phase 5 — ADB toolkit
- [ ] Port host/shell command distinction, safe argument parsing, reboot confirmation, sideload ZIP checks, logcat streaming/filter/pause/save and bugreport outcomes.
- [ ] Define safe operation allowlists and explicit device-mutating concurrency.
- Exit: parity tests against existing outcomes and mocked ADB executable.

### Phase 6 — Fastboot toolkit
- [ ] Port target selection, metadata, fastbootd detection, image partition suggestion, slot actions and supported maintenance.
- [ ] Bind command preview and destructive confirmation to exact target and arguments.
- [ ] Preserve advanced command warning and explicit target semantics; no arbitrary UI shell.
- Exit: guard and mocked Fastboot tests cover rejection and nonzero outcomes.

### Phase 7 — Firmware Explorer and Payload Extractor
- [ ] Port inspect, partition metadata, filtering/selection, all/selected extraction, progress, cancellation and fingerprints.
- [ ] Retain payload-dumper-go version/checksum and delta-OTA limitations.
- [ ] Preserve staged publication, no-overwrite and rollback behavior.
- Exit: payload fixtures and failure/cancellation tests pass.

### Phase 8 — Logs, Diagnostics and Operation History
- [ ] Consolidate Flutter/backend/tool logs in bounded streams.
- [ ] Persist typed operation metadata and non-sensitive summaries.
- [ ] Export diagnostics with sensitive-data warnings.
- Exit: filter/search/export/history tests pass.

### Phase 9 — Settings and Application Integration
- [ ] Port tool paths, backend config, themes, output folders and preferences.
- [ ] Integrate navigation, file drops, console, operation routing and lifecycle cleanup.
- Exit: end-to-end desktop workflows operate without legacy Tkinter UI.

### Phase 10 — Testing, reliability hardening and Linux AppImage
- [ ] Port all relevant legacy safety/backend tests.
- [ ] Run Flutter analyze/test, Python pytest/unittest, integration tests and packaging smoke tests.
- [ ] Build AppImage; bundle Python runtime/backend and pinned payload-dumper-go.
- [ ] Verify clean startup, missing optional tools, permissions, upgrade/data-directory handling and licenses.
- Exit: definition of done in project brief is satisfied; no critical safety/reliability issues remain.

## Working rules

- Work only on `rewrite/flutter-desktop`; never merge or push work to `main`.
- Each phase is an independently reviewable commit with tests and documentation.
- Retain the original `DroidLab-Next` repository unchanged as a behavioral reference until the migration has feature parity.
- Do not claim tests or hardware checks ran unless their output was actually observed.
- Do not introduce inert controls or simulated device outcomes.
