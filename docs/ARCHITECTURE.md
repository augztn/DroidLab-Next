# DroidLab Architecture

**Status:** Initial migration architecture (Phase 1)  
**Source audited:** `augztn/DroidLab-Next` at `b09da903fbe06a1d296f59f0c44f378573a307e4`  
**Target:** Linux x86_64 first; Windows and macOS portability is retained as a design constraint.

## Current system

The source is a Python 3.10+ Tkinter desktop application. The package is separated into:
- `droidlab.config`: constants, settings persistence and logging.
- `droidlab.core`: pure command guards, operation outcomes, bounded process runner and payload-dumper adapter.
- `droidlab.controllers`: ADB, device discovery, Fastboot and payload workflows (Tk mixins).
- `droidlab.ui`: application window, layout, views, dialogs, widgets, theme tokens and UI sizing.
- `tests`: eight test modules covering backend behavior, guards, worker dispatch, Fastboot preflight, package wiring, process runner, sideload outcomes, theme tokens and UI metrics.

The existing architecture deliberately preserves legacy import shims and widget/controller callbacks. The new app must not carry Tkinter into its presentation layer.

## Target architecture

Use a feature-oriented monorepo with these boundaries:

```text
apps/desktop/                 Flutter desktop composition root
packages/droidlab_domain/     Entities, value objects, repository contracts, failure types
packages/droidlab_application/ Use cases, orchestration, Riverpod providers
packages/droidlab_backend_bridge/ Versioned JSONL transport and process lifecycle
packages/droidlab_design_system/ Theme tokens and shared components
backend/python/droidlab/      Independently executable Python compatibility backend
tests/                        Contract and migration tests
integration_test/              Desktop integration tests
docs/                          Architecture, parity, safety and migration records
scripts/                       Development and packaging automation
assets/                        Icons and static resources
```

The Flutter desktop app uses Material 3, Riverpod, GoRouter and typed immutable models where they add value. Presentation widgets call application use cases/providers; they never launch ADB, Fastboot or payload binaries directly. Domain contracts do not depend on Flutter, Riverpod, Python or operating-system process APIs.

## Backend boundary

During migration, Python remains the authoritative implementation for existing workflows. Flutter communicates with one managed Python subprocess using UTF-8 JSON Lines over stdin/stdout:
- stdout is protocol-only; diagnostics go to stderr;
- every message carries protocol version and request ID;
- request IDs correlate accepted/progress/completed/failed/cancelled responses;
- the protocol validates envelopes and operation-specific arguments;
- bounded line and message sizes prevent unbounded input/output retention;
- cancellation is a request, not proof of device rollback;
- graceful shutdown is followed by bounded process cleanup;
- conflicting mutating operations are serialized per device, with explicit concurrency policies.

The Python package stays independently testable and contains no Flutter dependency. During transition, the existing Tk UI may be retained only in the source repository until parity is demonstrated; it is not embedded or wrapped by Flutter.

## Execution model

Dart's bridge owns the backend process lifecycle and consumes stdout/stderr as streams. Process start, write, decode, timeout, exit and shutdown errors become typed failures. Python owns tool resolution, argument construction, preflight checks, process groups, output bounds and structured outcomes until individual execution primitives are deliberately ported and equivalence-tested.

No user-provided command string is interpolated into a shell. Commands are represented as validated argument arrays. ADB/Fastboot paths, target serials, device state and image/partition arguments are revalidated immediately before mutating operations.

## UI composition

The shell consists of:
- responsive/collapsible navigation;
- global header with current device state and operation status;
- feature workspace;
- optional contextual details pane;
- persistent, bounded bottom console.

The console is an application-level stream consumer, not a widget-owned process. Theme colors, spacing, typography and radii are centralized in design tokens. Breakpoints are based on available window width; 4K screens use additional workspace density without forcing oversized controls.

## Security and safety boundaries

The backend is the only component permitted to request external device commands. The frontend can request a named operation, but cannot bypass backend validation by submitting an arbitrary executable or raw shell fragment. Destructive actions must bind confirmation to the exact target serial, operation, partition, image path and command preview which are rechecked at dispatch.

See [SAFETY_REQUIREMENTS.md](SAFETY_REQUIREMENTS.md) for the normative migration contract.

## Decisions and open questions

1. **Riverpod** is selected for testable dependency injection and state orchestration.
2. **GoRouter** is selected for typed feature navigation and deep-link-ready route organization.
3. **Python JSONL subprocess** is the first bridge implementation to minimize behavioral risk while modernizing the desktop UI.
4. **Linux AppImage** is the primary release target. Platform tool dependencies remain external or optionally bundled and must be clearly diagnosed.
5. The source repository's existing CI and AppImage workflow are references, not assumed portable Flutter build steps.
6. Backend packaging layout, bundled Python runtime strategy, and exact JSON schema versioning are finalized in Phase 3 after inspecting executable behavior and fixtures.
