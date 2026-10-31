# Backend protocol v1

Flutter owns one Python subprocess. The service reads UTF-8 JSON Lines from stdin and writes protocol events to stdout; diagnostics are written only to stderr. Requests are limited to 1 MiB and include a protocol version, request ID, named operation and object-valued arguments.

## Request envelope

```json
{"version":1,"id":"request-123","operation":"system.ping","args":{}}
```

## Event types

- `accepted`: request accepted.
- `output`: streamed output line with stream name.
- `preflight`: exact target serial and command argument vector immediately before a mutation.
- `completed`: structured result.
- `failed`: typed error code and message.
- `cancelled`: host-side cancellation. It never implies device-side rollback.

## Supported operations

| Operation | Required arguments | Behavior |
|---|---|---|
| `system.ping` | — | Backend health/version |
| `system.tools` | — | Resolve ADB, Fastboot and payload-dumper-go |
| `devices.list` | — | Fresh ADB and Fastboot discovery |
| `adb.shell` | `serial`, `command[]`, `confirmed`, `confirmation` | Every shell command requires exact target-and-command confirmation; destructive heuristic is additional preflight metadata |
| `adb.device_info` | `serial` | Selected Android getprop metadata |
| `adb.reboot` | `serial`, `mode`, `confirmed` | Guarded system/bootloader/recovery reboot |
| `adb.logcat.start` | `serial`, optional `filters[]` | Long-running streamed logcat; cancel by request ID |
| `adb.bugreport` | `serial`, `output_path` | Generates a report without overwriting an existing file |
| `adb.sideload` | `serial`, `package_path`, `confirmed` | Validates ZIP and recovery-compatible device state |
| `fastboot.flash` | `serial`, `partition`, `image_path`, `confirmed` | Fresh target scan, exact command preview and guarded flash |
| `fastboot.erase` | `serial`, `partition`, `confirmed` | Fresh target scan and guarded erase |
| `fastboot.reboot` | `serial`, `confirmed` | Guarded reboot |
| `payload.inspect` | `source_path` | Lists valid partitions and sizes |
| `payload.extract` | `source_path`, `output_dir`, optional `partitions[]`, `sha256` | Isolated staging, verified nonempty images, no-overwrite publication and rollback |

## Safety and lifecycle

- Every device operation names a serial; no implicit first-device selection.
- Mutations repeat the ADB/Fastboot scan immediately before dispatch.
- Mutating operations serialize per serial.
- Every ADB shell command, reboot, sideload, Fastboot flash/erase/reboot requires UI confirmation bound to the exact serial and operation arguments; the backend rejects stale or mismatched confirmation intents.
- Partition names use a strict ASCII allowlist.
- Commands are executable-plus-argument arrays; no shell interpolation of UI input.
- Child output is bounded and streamed; timeouts and process-tree termination are bounded.
- `system.cancel` carries the target request ID. On stdin EOF or process shutdown, active operations are cancelled and child processes are reaped.
- Bugreports/logcat may contain personal information; the user must review exports before sharing.
