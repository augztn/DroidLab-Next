# Safety requirements

These requirements apply to all UI and backend changes.

## Device identity and state

1. Every device operation includes an explicit nonempty serial.
2. Never select the first device implicitly when multiple devices are present.
3. Preserve visible ADB states and Fastboot state.
4. Re-scan the relevant transport immediately before a mutation and require the exact serial in an allowed state.
5. Reject conflicting explicit target selectors and stale target assumptions.

## Command construction

1. Invoke external tools as executable plus discrete arguments; never interpolate UI input into a host shell.
2. Widgets never launch ADB, Fastboot or payload-dumper-go directly.
3. Backend operations are named and validate operation-specific arguments.
4. Partition names use a strict allowlist; file paths are resolved and checked.
5. Destructive-command detection is defense-in-depth, not a sandbox.
6. Every ADB shell command requires explicit user confirmation, including read-only commands, because shell commands are arbitrary device-side programs.

## Confirmation integrity

For shell commands, reboot, sideload, flash, erase and other risky operations:
- display target serial and exact operation arguments before dispatch;
- bind confirmation to an immutable intent envelope containing operation, serial and command/mode/partition/image/package path as applicable;
- backend compares the received confirmation envelope to the dispatched arguments and rejects stale or mismatched intent;
- repeat validation and fresh target checks immediately before mutation;
- cancellation before dispatch starts no operation;
- a changed target or argument requires a new confirmation.

## Process lifecycle

1. Bound execution time, output retention, protocol line size and subprocess read chunks.
2. Stream output without blocking the Flutter UI isolate.
3. On cancellation, timeout or shutdown, terminate the owned process tree with bounded escalation and reap where possible.
4. Treat exit status as authoritative.
5. Serialize mutating operations per device.
6. Host cancellation does not prove device-side rollback. After interrupted flash/sideload/erase, inspect the physical device state before retrying.

## Payload extraction

1. Accept only existing supported BIN/ZIP inputs.
2. Validate partition names before backend invocation.
3. Extract into an isolated staging directory.
4. Reject empty, symlink and path-traversal artifacts.
5. Never overwrite existing output; publish verified files and roll back partial publication.
6. SHA-256 is an output fingerprint, not proof of OTA authenticity.

## Diagnostics and privacy

Bugreports and logcat can contain account, location, network and application data. Warn before bugreport generation, keep history local and bounded, and require users to review diagnostics before sharing.

## Regression tests

Use fake executables for no-device, multiple-device, disconnect, missing tools, timeout, cancellation, protocol failure, confirmation mismatch, invalid partition/path, existing output and interrupted publication. CI must not run destructive commands against physical devices.
