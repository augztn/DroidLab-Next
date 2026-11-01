# Architecture

DroidLab is a Flutter desktop application with a separately executable Python backend. The Flutter layer owns presentation, navigation, user confirmation and application state. The Python service owns external process execution, target preflight, command construction, payload staging and structured outcomes.

## Workspace

- `apps/desktop`: Flutter composition root and generated native runner projects.
- `packages/droidlab_domain`: platform-independent immutable device and partition models plus repository contracts. `packages/droidlab_application/src/data` adapts backend protocol responses into domain entities; feature screens are migrating incrementally from raw JSON maps.
- `packages/droidlab_application`: Riverpod providers, navigation, feature pages and operation history. Feature-page source is split into dashboard, devices, ADB, Fastboot, payload, logs, about, settings and shared-widget part files within the feature-pages library; this preserves existing private widget contracts while reducing the monolithic source file.
- `packages/droidlab_backend_bridge`: Dart process lifecycle and JSONL protocol client.
- `packages/droidlab_design_system`: Material 3 theme tokens.
- `backend/python`: headless Python process and device operations. Executable discovery is isolated in `droidlab.core.tool_resolver`; subprocess management and pure command guards remain separate core services.
- `docs`: architecture, protocol, safety, parity and release records.
- `scripts`: Flutter bootstrap, backend staging and AppImage packaging.

## Process boundary

Dart starts the backend with `Process.start` and consumes stdout/stderr as streams. Stdout is UTF-8 JSON Lines only. Each request includes protocol version, unique ID, named operation and typed arguments. Backend events are correlated by request ID and include accepted, output, preflight and terminal result events.

The Python process never accepts a UI-supplied executable or raw host shell command. The UI requests named operations; Python validates arguments, resolves tool paths and constructs executable-plus-argument arrays. Child processes have timeouts, bounded output retention, cancellation and process-tree cleanup. The JSONL server admits at most eight active requests, rejects duplicate active request IDs and returns a busy error under load. Device discovery propagates cancellation instead of reporting it as a transport warning.

## State and UI

Riverpod owns backend readiness, device discovery and local operation history. A typed `DeviceRepository` boundary and `DeviceDescriptor`/`PartitionDescriptor` models now isolate feature code from backend JSON field names; the legacy map provider remains temporarily for unmigrated screens. Backend startup waits for asynchronous settings loading; changing Python or backend paths invalidates and recreates the backend client. ADB/Fastboot/payload tool paths remain dynamically resolved from the shared settings file by Python. GoRouter owns feature routes. Material 3 theme tokens are centralized. The shell has a responsive/collapsible sidebar, live device/backend status and a bounded operation console. Feature pages do not launch external processes directly.

## Device safety

Operation history is deliberately privacy-minimized: operation labels are allowlisted, targets are generalized, and success/failure summaries are fixed strings. Legacy records are sanitized and rewritten on load. Settings parsing preserves malformed or unsupported-schema files under a timestamped `.corrupt.*` recovery name and exposes a warning instead of silently overwriting the only copy. Diagnostic exports apply centralized credential, device-identifier and host-path redaction, while still requiring user review. Every device operation names a serial. ADB/Fastboot state is rescanned immediately before dispatch. Destructive operations require an explicit confirmation envelope matching the exact serial and relevant operation arguments. Mutating work is serialized per device. Cancellation terminates host work where possible but cannot roll back changes accepted by device firmware.

## Packaging

CI generates Linux, Windows and macOS runner projects and builds native bundles. The Python backend is staged beside the executable (macOS: app Resources). Tool discovery resolves explicit environment overrides, the shared `~/DroidLab/config.json` settings, platform bundle locations, then PATH. The Linux AppImage stores the backend under `usr/lib/droidlab/backend` and host tools under `usr/bin`; the resolver accounts for that split layout. The AppImage pins payload-dumper-go 2.1.0 and verifies its SHA-256. Python and Android platform-tools are not currently bundled into Windows/macOS release outputs, so those runtimes must be installed on the target host.
