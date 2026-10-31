# Architecture

DroidLab is a Flutter desktop application with a separately executable Python backend. The Flutter layer owns presentation, navigation, user confirmation and application state. The Python service owns external process execution, target preflight, command construction, payload staging and structured outcomes.

## Workspace

- `apps/desktop`: Flutter composition root and generated native runner projects.
- `packages/droidlab_domain`: platform-independent domain contracts.
- `packages/droidlab_application`: Riverpod providers, navigation, feature pages and operation history.
- `packages/droidlab_backend_bridge`: Dart process lifecycle and JSONL protocol client.
- `packages/droidlab_design_system`: Material 3 theme tokens.
- `backend/python`: headless Python process and device operations.
- `docs`: architecture, protocol, safety, parity and release records.
- `scripts`: Flutter bootstrap, backend staging and AppImage packaging.

## Process boundary

Dart starts the backend with `Process.start` and consumes stdout/stderr as streams. Stdout is UTF-8 JSON Lines only. Each request includes protocol version, unique ID, named operation and typed arguments. Backend events are correlated by request ID and include accepted, output, preflight and terminal result events.

The Python process never accepts a UI-supplied executable or raw host shell command. The UI requests named operations; Python validates arguments, resolves tool paths and constructs executable-plus-argument arrays. Child processes have timeouts, bounded output retention, cancellation and process-tree cleanup.

## State and UI

Riverpod owns backend readiness, device discovery and local operation history. GoRouter owns feature routes. Material 3 theme tokens are centralized. The shell has a responsive/collapsible sidebar, live device/backend status and a bounded operation console. Feature pages do not launch external processes directly.

## Device safety

Every device operation names a serial. ADB/Fastboot state is rescanned immediately before dispatch. Destructive operations require an explicit confirmation envelope matching the exact serial and relevant operation arguments. Mutating work is serialized per device. Cancellation terminates host work where possible but cannot roll back changes accepted by device firmware.

## Packaging

CI generates Linux, Windows and macOS runner projects and builds native bundles. The Python backend is staged beside the executable (macOS: app Resources). The Linux AppImage script pins payload-dumper-go 2.1.0 and verifies its SHA-256; it requires host Python 3 and ADB/Fastboot. Python and Android platform-tools are not currently bundled into Windows/macOS release outputs.
