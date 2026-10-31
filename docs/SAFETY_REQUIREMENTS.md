# DroidLab Safety Requirements

These requirements are normative for the Flutter rewrite and Python backend bridge.

## Device identity and state

1. Every device-mutating operation has an explicit nonempty serial target.
2. Never silently choose the first device when discovery returns multiple targets.
3. Preserve visible ADB states (device, recovery, sideload, unauthorized, offline) and Fastboot state.
4. Re-scan the relevant transport immediately before a mutation and require successful discovery of the exact serial in an allowed state.
5. Reject conflicting explicit `-s` selectors, malformed or repeated selectors, and a selector that differs from the selected device.
6. A disconnect or failed preflight means no command is dispatched. A scan result is not a guarantee that USB remains connected after the scan.

## Command construction and guards

1. Pass executable plus discrete argument list; never interpolate user input into a shell.
2. Flutter widgets never execute commands or construct unrestricted raw executable invocations.
3. Backend APIs expose named operations with operation-specific validated arguments.
4. Partition names must satisfy a strict allowlist/grammar; paths are resolved and checked.
5. Destructive-command pattern detection is defense-in-depth and a warning heuristic, not a security sandbox or proof that an arbitrary command is safe.
6. Advanced commands, if retained, remain visibly marked unrestricted and require a clear warning and exact command preview; the migration must not create a hidden bypass around operation validation.

## Confirmation integrity

For flash, erase, wipe, unlock/lock, sideload and other risky operations:
- require an explicit confirmation step appropriate to risk;
- display target serial, device mode, selected file (where relevant), partition and complete command preview;
- bind acceptance to the exact immutable operation intent shown to the user;
- repeat validation and fresh target checks after confirmation and immediately before dispatch;
- cancellation before dispatch starts no operation;
- stale or changed target/arguments invalidate confirmation and require a new confirmation.

A generic “Are you sure?” dialog without target/operation details is insufficient.

## Process lifecycle

1. Enforce bounded execution time and bounded stdout/stderr buffering.
2. Stream output without blocking Flutter's UI isolate; cap retained console history.
3. On timeout/cancellation, terminate the owned process tree with bounded escalation and reap where possible.
4. Treat process exit status as authoritative; never report success on missing/ambiguous results.
5. Record operation IDs, target, start/end, exit code and structured outcome.
6. Prevent overlapping mutating operations for the same serial; define concurrency classes for read-only work.
7. Device-operation cancellation stops the host operation where possible; it does **not** claim to roll back or safely interrupt a command already accepted by device firmware.

## Payload extraction safety

1. Accept only existing supported `.bin` and `.zip` sources.
2. Validate partition identifiers before constructing backend arguments.
3. Use bounded inspection/extraction timeouts and support cancellation.
4. Extract into an isolated staging directory, verify non-empty regular image artifacts, and reject symlinks/path traversal.
5. Never overwrite existing output. Publish only verified artifacts; roll back files published by a failed multi-file publication.
6. Treat SHA-256 as an output fingerprint, not a substitute for OTA integrity verification.
7. Surface unsupported delta payload operations and backend failures; never report partial output as a successful complete extraction.

## Diagnostics and privacy

Bugreports, logcat and device metadata may contain personal information, account identifiers, network details and tokens. Show a warning before export/share, avoid uploading device output automatically, redact only with explicit transparent rules, and keep diagnostic retention bounded/configurable.

## Shutdown and recovery

- Stop accepting new work during shutdown.
- Request cancellation; wait only within a documented bound.
- Close stdin, then terminate the managed backend process if it does not exit.
- Do not orphan descendants or claim that an in-flight device operation was rolled back.
- After an interrupted flash/sideload/erase, advise inspection of the physical device state before any retry.

## Regression tests required

Cover no device, multiple devices, stale selection, selector conflict, unauthorized/offline state, disconnect after selection, missing tools, process spawn failure, timeout, cancellation, nonzero process exit, backend crash, malformed protocol message, concurrent mutations, failed flash, invalid partition/path, existing destination, symlink artifact, and interrupted publication. CI must use fake executables/fixtures and must never run destructive operations against physical devices.
