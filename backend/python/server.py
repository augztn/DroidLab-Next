#!/usr/bin/env python3
"""DroidLab versioned JSON Lines backend. stdout is protocol-only; diagnostics use stderr."""
from __future__ import annotations
import json, logging, math, os, shlex, shutil, signal, subprocess, sys, threading, time
from pathlib import Path
from typing import Any
from droidlab.core.command_guards import (
    is_adb_target_connected, is_fastboot_target_connected,
    is_destructive_adb, is_valid_partition_name,
)
from droidlab.core.process_runner import run_streaming, ProcessCancelledError
from droidlab.core import payload_dumper

PROTOCOL_VERSION = 1
MAX_LINE_BYTES = 1024 * 1024
MAX_RETAINED_OUTPUT = 2 * 1024 * 1024
_WRITE_LOCK = threading.Lock()
_ACTIVE: dict[str, threading.Event] = {}
_DEVICE_LOCKS: dict[str, threading.Lock] = {}
_DEVICE_LOCKS_LOCK = threading.Lock()
_MUTATING = {"adb.shell", "adb.reboot", "adb.sideload", "fastboot.flash", "fastboot.erase", "fastboot.reboot", "fastboot.wipe", "fastboot.command"}

def emit(message: dict[str, Any]) -> None:
    envelope = {"version": PROTOCOL_VERSION, "timestamp": time.time(), **message}
    encoded = json.dumps(envelope, separators=(",", ":"), ensure_ascii=False)
    with _WRITE_LOCK:
        sys.stdout.write(encoded + "\n")
        sys.stdout.flush()

def response(request_id: str, kind: str, **kwargs: Any) -> None:
    emit({"id": request_id, "type": kind, **kwargs})

def tool_path(name: str) -> str:
    env_key = "DROIDLAB_" + name.upper().replace("-", "_") + "_PATH"
    configured = os.environ.get(env_key, "").strip()
    if configured:
        path = Path(configured).expanduser()
        if path.is_file():
            return str(path.resolve())
        raise RuntimeError(f"Configured {name} path does not exist: {path}")
    found = shutil.which(name)
    if not found:
        raise RuntimeError(f"{name} was not found on PATH. Configure its path in DroidLab settings.")
    return found

def run_capture(command: list[str], timeout: float = 10,
                cancel_event: threading.Event | None = None) -> subprocess.CompletedProcess[str]:
    return run_streaming(
        command,
        timeout=timeout,
        cancel_event=cancel_event,
        max_output_chars=512 * 1024,
    )

def bounded_timeout(value: Any, default: float, maximum: float) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return default
    if not math.isfinite(result) or result <= 0:
        return default
    return min(result, maximum)

def adb_scan(cancel_event: threading.Event | None = None) -> list[dict[str, Any]]:
    result = run_capture([tool_path("adb"), "devices", "-l"], 10, cancel_event)
    if result.returncode:
        raise RuntimeError(f"ADB scan failed: {result.stderr.strip() or result.returncode}")
    devices = []
    for line in result.stdout.splitlines()[1:]:
        fields = line.split()
        if len(fields) >= 2 and fields[1] in {"device", "recovery", "sideload", "unauthorized", "offline"}:
            details = {}
            for item in fields[2:]:
                if ":" in item:
                    key, value = item.split(":", 1)
                    details[key] = value
            devices.append({"serial": fields[0], "transport": "adb", "state": fields[1], "details": details})
    return devices

def fastboot_scan(cancel_event: threading.Event | None = None) -> list[dict[str, Any]]:
    result = run_capture([tool_path("fastboot"), "devices", "-l"], 8, cancel_event)
    if result.returncode:
        raise RuntimeError(f"Fastboot scan failed: {result.stderr.strip() or result.returncode}")
    devices = []
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[1].lower() == "fastboot":
            details = {}
            for item in fields[2:]:
                if ":" in item:
                    key, value = item.split(":", 1)
                    details[key] = value
            devices.append({"serial": fields[0], "transport": "fastboot", "state": "fastboot", "details": details})
    return devices

def require_adb(serial: Any, states: tuple[str, ...] = ("device",), cancel_event: threading.Event | None = None) -> None:
    if not isinstance(serial, str) or not serial.strip():
        raise ValueError("An explicit device serial is required.")
    result = run_capture([tool_path("adb"), "devices", "-l"], 10, cancel_event)
    if not is_adb_target_connected(serial, result.stdout, result.returncode, states):
        state = None
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                fields = line.split()
                if len(fields) >= 2 and fields[0] == serial:
                    state = fields[1]
                    break
        if state == "unauthorized":
            raise RuntimeError(
                f"ADB device {serial!r} is unauthorized. Unlock the Android device, accept the "
                "“Allow USB debugging?” RSA fingerprint prompt, then press Refresh devices. "
                "If no prompt appears, revoke USB debugging authorizations in Developer options, "
                "unplug/reconnect USB, and accept the prompt again. No command was dispatched."
            )
        if state == "offline":
            raise RuntimeError(
                f"ADB device {serial!r} is offline. Reconnect USB or restart the ADB server, "
                "then refresh devices. No command was dispatched."
            )
        if result.returncode:
            raise RuntimeError(f"ADB device scan failed: {result.stderr.strip() or result.returncode}")
        raise RuntimeError(
            f"ADB target {serial!r} is not present in an allowed state ({', '.join(states)}). "
            "Refresh devices and select an online, authorized device. No command was dispatched."
        )

def require_fastboot(serial: Any, cancel_event: threading.Event | None = None) -> None:
    if not isinstance(serial, str) or not serial.strip():
        raise ValueError("An explicit Fastboot serial is required.")
    result = run_capture([tool_path("fastboot"), "devices", "-l"], 8, cancel_event)
    if not is_fastboot_target_connected(serial, result.stdout, result.returncode):
        raise RuntimeError(f"Fastboot target {serial!r} is not present in a fresh scan. No command was dispatched.")

def string_list(value: Any, name: str, maximum: int = 128) -> list[str]:
    if not isinstance(value, list) or not value or len(value) > maximum:
        raise ValueError(f"{name} must be an array containing 1 to {maximum} strings.")
    if any(not isinstance(item, str) or not item or "\x00" in item for item in value):
        raise ValueError(f"{name} contains an invalid string.")
    return value

def require_confirmation(args: dict[str, Any], operation: str,
                         intent: dict[str, Any] | None = None) -> None:
    if args.get("confirmed") is not True:
        raise PermissionError(f"{operation} requires explicit confirmation in the desktop UI.")
    if intent is not None and args.get("confirmation") != intent:
        raise PermissionError(f"{operation} confirmation is missing, stale, or does not match the dispatched target and arguments.")

def execute(request_id: str, operation: str, args: dict[str, Any], cancel: threading.Event) -> dict[str, Any]:
    if operation == "system.ping":
        return {"status": "ok", "backend": "droidlab-python", "protocol_version": PROTOCOL_VERSION, "python": sys.version.split()[0]}
    if operation == "system.tools":
        tools = {}
        for name in ("adb", "fastboot", "payload-dumper-go"):
            try:
                tools[name] = {"available": True, "path": tool_path(name)}
            except Exception as exc:
                tools[name] = {"available": False, "error": str(exc)}
        return {"tools": tools}
    if operation == "devices.list":
        devices, warnings = [], []
        for scanner, label in ((lambda: adb_scan(cancel), "adb"), (lambda: fastboot_scan(cancel), "fastboot")):
            try:
                devices.extend(scanner())
            except Exception as exc:
                warnings.append({"transport": label, "message": str(exc)})
        return {"devices": devices, "warnings": warnings}
    if operation == "adb.shell":
        serial = args.get("serial")
        command = string_list(args.get("command"), "command")
        require_adb(serial, cancel_event=cancel)
        guard_tokens = ["shell", *shlex.split(" ".join(command))]
        require_confirmation(args, "ADB shell command", {
            "operation": "adb.shell", "serial": serial, "command": command,
        })
        cmd = [tool_path("adb"), "-s", serial, "shell", *command]
        response(request_id, "preflight", target=serial, command=cmd, destructive=is_destructive_adb(guard_tokens))
        result = run_streaming(cmd, timeout=bounded_timeout(args.get("timeout_seconds"), 60, 900),
            cancel_event=cancel, on_line=lambda line: response(request_id, "output", stream="stdout", line=line))
        if result.returncode:
            raise RuntimeError(f"ADB shell exited with status {result.returncode}: {result.stdout[-MAX_RETAINED_OUTPUT:]}")
        return {"exit_code": result.returncode, "output": result.stdout}
    if operation == "adb.reboot":
        serial, mode = args.get("serial"), args.get("mode", "system")
        if mode not in {"system", "bootloader", "recovery"}:
            raise ValueError("Unsupported reboot mode.")
        require_confirmation(args, "ADB reboot", {
            "operation": "adb.reboot", "serial": serial, "mode": mode,
        })
        if not isinstance(serial, str) or not serial.strip():
            raise ValueError("An explicit device serial is required.")
        # The shared legacy selector supports both Android ADB and bootloader modes.
        adb_result = run_capture([tool_path("adb"), "devices", "-l"], 10, cancel)
        adb_state = None
        if adb_result.returncode == 0:
            for line in adb_result.stdout.splitlines()[1:]:
                fields = line.split()
                if len(fields) >= 2 and fields[0] == serial:
                    adb_state = fields[1]
                    break
        if adb_state in {"device", "recovery"}:
            transport = "adb"
            command = [tool_path("adb"), "-s", serial, "reboot"] + ([] if mode == "system" else [mode])
        elif adb_state in {"unauthorized", "offline", "sideload"}:
            require_adb(serial, cancel_event=cancel)
            raise RuntimeError("ADB device is not in a command-ready state.")
        else:
            require_fastboot(serial, cancel_event=cancel)
            if mode == "bootloader":
                return {"exit_code": 0, "transport": "fastboot", "message": "Device is already in Fastboot/bootloader mode."}
            transport = "fastboot"
            command = [tool_path("fastboot"), "-s", serial, "reboot"] + (["recovery"] if mode == "recovery" else [])
        response(request_id, "preflight", target=serial, command=command, destructive=False)
        result = run_streaming(command, timeout=35, cancel_event=cancel,
            on_line=lambda line: response(request_id, "output", stream=transport, line=line))
        if result.returncode:
            raise RuntimeError(f"{transport.upper()} reboot failed ({result.returncode}): {result.stdout}")
        return {"exit_code": 0, "transport": transport, "message": f"{transport.upper()} accepted reboot request to {mode}; USB mode transition is not verified."}
    if operation == "adb.sideload":
        serial, package = args.get("serial"), args.get("package_path")
        require_confirmation(args, "ADB recovery sideload", {
            "operation": "adb.sideload", "serial": serial, "package_path": package,
        })
        if not isinstance(package, str) or Path(package).suffix.lower() != ".zip" or not Path(package).expanduser().is_file():
            raise ValueError("Choose an existing OTA .zip package.")
        require_adb(serial, ("sideload", "recovery", "device"), cancel_event=cancel)
        command = [tool_path("adb"), "-s", serial, "sideload", str(Path(package).expanduser().resolve())]
        response(request_id, "preflight", target=serial, command=command, destructive=True)
        result = run_streaming(command, timeout=1800, cancel_event=cancel,
            on_line=lambda line: response(request_id, "output", stream="stdout", line=line))
        if result.returncode:
            raise RuntimeError(f"Sideload outcome uncertain (exit {result.returncode}). Check recovery state and output before retrying. {result.stdout[-MAX_RETAINED_OUTPUT:]}")
        return {"exit_code": 0, "message": "ADB reported sideload command completion; update acceptance and boot are not verified."}
    if operation == "adb.bugreport":
        serial, output = args.get("serial"), args.get("output_path")
        require_adb(serial, cancel_event=cancel)
        if not isinstance(output, str) or not output.strip():
            raise ValueError("output_path is required.")
        destination = Path(output).expanduser().resolve()
        if destination.exists() or destination.is_symlink():
            raise ValueError("Bugreport destination exists; refusing to overwrite.")
        destination.parent.mkdir(parents=True, exist_ok=True)
        result = run_streaming([tool_path("adb"), "-s", serial, "bugreport", str(destination)],
            timeout=900, cancel_event=cancel,
            on_line=lambda line: response(request_id, "output", stream="stdout", line=line))
        if result.returncode:
            raise RuntimeError(f"Bugreport failed ({result.returncode}): {result.stdout[-MAX_RETAINED_OUTPUT:]}")
        return {"path": str(destination), "exit_code": 0}
    if operation == "adb.device_info":
        serial = args.get("serial")
        require_adb(serial, cancel_event=cancel)
        keys = ["ro.product.manufacturer", "ro.product.model", "ro.product.device",
            "ro.build.version.release", "ro.build.version.sdk", "ro.boot.slot_suffix"]
        result = run_streaming([tool_path("adb"), "-s", serial, "shell", "getprop"],
            timeout=30, cancel_event=cancel)
        if result.returncode:
            raise RuntimeError(f"getprop failed: {result.stdout[-MAX_RETAINED_OUTPUT:]}")
        properties = {}
        for line in result.stdout.splitlines():
            if line.startswith("[") and "]: [" in line:
                key, value = line[1:].split("]: [", 1)
                properties[key] = value.rstrip("]")
        return {"serial": serial, "properties": {key: properties.get(key, "") for key in keys}}
    if operation == "adb.logcat.start":
        serial, filters = args.get("serial"), args.get("filters", [])
        require_adb(serial, cancel_event=cancel)
        if not isinstance(filters, list) or any(not isinstance(item, str) or "\x00" in item for item in filters):
            raise ValueError("filters must be strings.")
        command = [tool_path("adb"), "-s", serial, "logcat", *filters]
        result = run_streaming(command, timeout=24 * 3600, cancel_event=cancel,
            on_line=lambda line: response(request_id, "output", stream="logcat", line=line),
            max_output_chars=1024)
        return {"exit_code": result.returncode, "cancelled": cancel.is_set()}
    if operation == "fastboot.command":
        serial, raw_command = args.get("serial"), args.get("command")
        if not isinstance(raw_command, str) or not raw_command.strip() or "\\x00" in raw_command:
            raise ValueError("A non-empty Fastboot command is required.")
        tokens = shlex.split(raw_command)
        if not tokens or tokens[0].startswith("-") or any(
            token in {"-s", "--serial"} for token in tokens
        ):
            raise ValueError("Provide Fastboot subcommand arguments only; device selection is managed by DroidLab.")
        intent = {"operation": "fastboot.command", "serial": serial, "command": raw_command}
        require_confirmation(args, "Advanced Fastboot command", intent)
        require_fastboot(serial, cancel_event=cancel)
        command = [tool_path("fastboot"), "-s", serial, *tokens]
        response(request_id, "preflight", target=serial, command=command, destructive=True)
        result = run_streaming(command, timeout=bounded_timeout(args.get("timeout_seconds"), 900, 1800),
            cancel_event=cancel,
            on_line=lambda line: response(request_id, "output", stream="stdout", line=line))
        if result.returncode:
            raise RuntimeError(
                f"Advanced Fastboot command failed ({result.returncode}); inspect device state before retrying."
            )
        return {"exit_code": 0, "command": tokens, "output": result.stdout}
    if operation == "fastboot.flash":
        serial, partition, image = args.get("serial"), args.get("partition"), args.get("image_path")
        if not is_valid_partition_name(partition):
            raise ValueError("Invalid partition name.")
        if not isinstance(image, str) or not Path(image).expanduser().is_file():
            raise ValueError("Image file does not exist.")
        require_confirmation(args, "Fastboot flash", {
            "operation": "fastboot.flash", "serial": serial,
            "partition": partition, "image_path": image,
        })
        require_fastboot(serial, cancel_event=cancel)
        command = [tool_path("fastboot"), "-s", serial, "flash", partition, str(Path(image).expanduser().resolve())]
        response(request_id, "preflight", target=serial, command=command, destructive=True)
        result = run_streaming(command, timeout=bounded_timeout(args.get("timeout_seconds"), 900, 3600),
            cancel_event=cancel, on_line=lambda line: response(request_id, "output", stream="stdout", line=line))
        if result.returncode:
            raise RuntimeError(f"Fastboot flash failed ({result.returncode}); device state may be uncertain. Inspect before retrying.")
        return {"exit_code": 0, "message": "Fastboot reported flash completion; bootability is not verified."}
    if operation == "fastboot.erase":
        serial, partition = args.get("serial"), args.get("partition")
        if not is_valid_partition_name(partition):
            raise ValueError("Invalid partition name.")
        require_confirmation(args, "Fastboot erase", {
            "operation": "fastboot.erase", "serial": serial, "partition": partition,
        })
        require_fastboot(serial, cancel_event=cancel)
        command = [tool_path("fastboot"), "-s", serial, "erase", partition]
        response(request_id, "preflight", target=serial, command=command, destructive=True)
        result = run_streaming(command, timeout=180, cancel_event=cancel,
            on_line=lambda line: response(request_id, "output", stream="stdout", line=line))
        if result.returncode:
            raise RuntimeError(f"Fastboot erase failed ({result.returncode}); inspect device state before retrying.")
        return {"exit_code": 0, "message": "Fastboot reported erase completion."}
    if operation == "fastboot.reboot":
        serial, mode = args.get("serial"), args.get("mode", "system")
        if mode not in {"system", "recovery", "bootloader"}:
            raise ValueError("Unsupported Fastboot reboot mode.")
        require_confirmation(args, "Fastboot reboot", {
            "operation": "fastboot.reboot", "serial": serial, "mode": mode,
        })
        require_fastboot(serial, cancel_event=cancel)
        command = [tool_path("fastboot"), "-s", serial]
        command += (["reboot"] if mode == "system" else
                    ["reboot", "recovery"] if mode == "recovery" else
                    ["reboot-bootloader"])
        result = run_streaming(command, timeout=45, cancel_event=cancel)
        if result.returncode:
            raise RuntimeError(f"Fastboot reboot failed: {result.stdout}")
        return {"exit_code": 0, "message": f"Fastboot accepted reboot request to {mode}; transition is not verified."}
    if operation == "fastboot.wipe":
        serial = args.get("serial")
        require_confirmation(args, "Fastboot wipe userdata", {
            "operation": "fastboot.wipe", "serial": serial, "mode": "wipe-userdata",
        })
        require_fastboot(serial, cancel_event=cancel)
        command = [tool_path("fastboot"), "-s", serial, "-w"]
        response(request_id, "preflight", target=serial, command=command, destructive=True)
        result = run_streaming(command, timeout=600, cancel_event=cancel,
            on_line=lambda line: response(request_id, "output", stream="stdout", line=line))
        if result.returncode:
            raise RuntimeError(f"Fastboot wipe failed ({result.returncode}); device state may be uncertain.")
        return {"exit_code": 0, "message": "Fastboot reported userdata/cache wipe completion."}
    if operation == "payload.inspect":
        parts = payload_dumper.inspect_source(args.get("source_path"),
            progress=lambda line: response(request_id, "output", stream="payload", line=line), cancel_event=cancel)
        return {"partitions": parts}
    if operation == "payload.extract":
        selected = args.get("partitions") or None
        if selected is not None and (not isinstance(selected, list) or any(not is_valid_partition_name(p) for p in selected)):
            raise ValueError("Invalid partition list.")
        files = payload_dumper.extract(args.get("source_path"), args.get("output_dir"), selected,
            progress=lambda line: response(request_id, "output", stream="payload", line=line),
            cancel_event=cancel, fingerprint=bool(args.get("sha256", False)))
        return {"files": files}
    raise ValueError(f"Unknown operation: {operation}")

def handle(message: dict[str, Any], cancel: threading.Event) -> None:
    request_id, operation, args = message["id"], message["operation"], message["args"]
    lock = None
    lock_acquired = False
    try:
        response(request_id, "accepted", operation=operation)
        if operation in _MUTATING:
            serial = args.get("serial")
            if not isinstance(serial, str) or not serial:
                raise ValueError("An explicit target serial is required.")
            with _DEVICE_LOCKS_LOCK:
                lock = _DEVICE_LOCKS.setdefault(serial, threading.Lock())
            if not lock.acquire(timeout=0.1):
                lock = None
                raise RuntimeError(f"Another mutating operation is already active for device {serial}.")
            lock_acquired = True
        result = execute(request_id, operation, args, cancel)
        response(request_id, "completed", result=result, cancelled=cancel.is_set())
    except ProcessCancelledError:
        response(request_id, "cancelled", message="Host process cancelled. This does not roll back changes already accepted by device firmware.")
    except Exception as exc:
        logging.exception("Operation %s failed", operation)
        response(request_id, "failed", error={"code": type(exc).__name__, "message": str(exc)})
    finally:
        if lock is not None and lock_acquired:
            lock.release()
        _ACTIVE.pop(request_id, None)

def main() -> None:
    logging.basicConfig(stream=sys.stderr, level=os.environ.get("DROIDLAB_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(message)s")
    workers: list[threading.Thread] = []

    def request_shutdown(signum: int, _frame: Any) -> None:
        logging.info("Received shutdown signal %s; cancelling active child operations.", signum)
        for event in list(_ACTIVE.values()):
            event.set()
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, request_shutdown)
    signal.signal(signal.SIGINT, request_shutdown)
    try:
      while True:
        raw = sys.stdin.buffer.readline(MAX_LINE_BYTES + 1)
        if not raw:
            break
        if len(raw) > MAX_LINE_BYTES:
            logging.error("Rejected oversized protocol line.")
            while raw and not raw.endswith(b"\n"):
                raw = sys.stdin.buffer.readline(MAX_LINE_BYTES + 1)
            continue
        try:
            message = json.loads(raw.decode("utf-8"))
            if not isinstance(message, dict) or message.get("version") != PROTOCOL_VERSION:
                raise ValueError("Unsupported protocol version.")
            if message.get("operation") == "system.cancel":
                args = message.get("args", {})
                target = args.get("request_id") if isinstance(args, dict) else None
                event = _ACTIVE.get(target)
                if event is not None:
                    event.set()
                emit({"id": message.get("id", ""), "type": "completed",
                    "result": {"cancel_requested": event is not None, "target": target}})
                continue
            request_id, operation, args = message.get("id"), message.get("operation"), message.get("args", {})
            if not isinstance(request_id, str) or not request_id or not isinstance(operation, str) or not isinstance(args, dict):
                raise ValueError("Invalid request envelope.")
            if len(json.dumps(message).encode("utf-8")) > MAX_LINE_BYTES:
                raise ValueError("Request exceeds maximum size.")
            cancel = threading.Event()
            _ACTIVE[request_id] = cancel
            worker = threading.Thread(target=handle, args=(message, cancel), daemon=False)
            workers.append(worker)
            worker.start()
            workers = [thread for thread in workers if thread.is_alive()]
        except Exception as exc:
            logging.warning("Rejected protocol input: %s", exc)
    finally:
        # EOF and process signals both cancel children and wait for process-tree cleanup.
        for event in list(_ACTIVE.values()):
            event.set()
        for worker in workers:
            worker.join()

if __name__ == "__main__":
    main()
