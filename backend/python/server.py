#!/usr/bin/env python3
"""DroidLab versioned JSON Lines backend. stdout is protocol-only; diagnostics use stderr."""
from __future__ import annotations
import json, logging, math, os, re, shlex, signal, subprocess, sys, threading, time
from pathlib import Path
from typing import Any
from droidlab.core.command_guards import (
    explicit_device_selector, is_adb_target_connected, is_fastboot_target_connected,
    is_destructive_adb, is_destructive_fastboot, is_valid_partition_name,
    validate_device_selector,
)
from droidlab.core.process_runner import run_streaming, ProcessCancelledError
from droidlab.core.device_metadata import (
    first_property, parse_battery_level, parse_fastboot_getvar, parse_getprop_output,
)
from droidlab.core import payload_dumper
from droidlab.core.tool_resolver import resolve_tool_path
from droidlab.core.windows_volumes import list_removable_drives

PROTOCOL_VERSION = 1
MAX_LINE_BYTES = 1024 * 1024
MAX_RETAINED_OUTPUT = 2 * 1024 * 1024
MAX_ACTIVE_REQUESTS = 8
_WRITE_LOCK = threading.Lock()
_ACTIVE_LOCK = threading.Lock()
_ACTIVE: dict[str, threading.Event] = {}
_WORKER_SLOTS = threading.BoundedSemaphore(MAX_ACTIVE_REQUESTS)
_DEVICE_LOCKS: dict[str, threading.Lock] = {}
_DEVICE_LOCKS_LOCK = threading.Lock()
_MUTATING = {"adb.shell", "adb.reboot", "adb.sideload", "fastboot.flash", "fastboot.erase", "fastboot.reboot", "fastboot.wipe", "fastboot.set_active"}

def emit(message: dict[str, Any]) -> None:
    envelope = {"version": PROTOCOL_VERSION, "timestamp": time.time(), **message}
    encoded = json.dumps(envelope, separators=(",", ":"), ensure_ascii=False)
    with _WRITE_LOCK:
        sys.stdout.write(encoded + "\n")
        sys.stdout.flush()

def response(request_id: str, kind: str, **kwargs: Any) -> None:
    emit({"id": request_id, "type": kind, **kwargs})

tool_path = resolve_tool_path

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
            except ProcessCancelledError:
                raise
            except Exception as exc:
                warnings.append({"transport": label, "message": str(exc)})
        return {"devices": devices, "warnings": warnings}
    if operation == "adb.shell":
        serial = args.get("serial")
        command_text = args.get("command_text")
        if command_text is not None:
            if not isinstance(command_text, str) or not command_text.strip() or "\x00" in command_text:
                raise ValueError("A non-empty Android shell command is required.")
            command = shlex.split(command_text, posix=(os.name != "nt"))
            confirmation = {"operation": "adb.shell", "serial": serial, "command_text": command_text}
        else:
            command = string_list(args.get("command"), "command")
            confirmation = {"operation": "adb.shell", "serial": serial, "command": command}
        if not command:
            raise ValueError("A non-empty Android shell command is required.")
        require_adb(serial, cancel_event=cancel)
        require_confirmation(args, "ADB shell command", confirmation)
        cmd = [tool_path("adb"), "-s", serial, "shell", *command]
        response(request_id, "preflight", target=serial, command=cmd,
            destructive=is_destructive_adb(["shell", *command]))
        result = run_streaming(cmd, timeout=bounded_timeout(args.get("timeout_seconds"), 60, 900),
            cancel_event=cancel, on_line=lambda line: response(request_id, "output", stream="stdout", line=line))
        if result.returncode:
            raise RuntimeError(f"ADB shell exited with status {result.returncode}: {result.stdout[-MAX_RETAINED_OUTPUT:]}")
        return {"exit_code": result.returncode, "output": result.stdout}

    if operation == "adb.command":
        serial = args.get("serial")
        command_text = args.get("command_text")
        if not isinstance(command_text, str) or not command_text.strip() or "\x00" in command_text:
            raise ValueError("A non-empty host ADB command is required.")
        command_args = shlex.split(command_text, posix=(os.name != "nt"))
        if not command_args:
            raise ValueError("A non-empty host ADB command is required.")
        command_args = string_list(command_args, "arguments")
        explicit_serial = explicit_device_selector(command_args, "adb")
        validate_device_selector(command_args, "adb", serial)
        values = list(command_args)
        index = 0
        takes_value = {"-s", "-t", "-H", "-P", "-L"}
        no_value = {"-d", "-e"}
        while index < len(values):
            token = values[index]
            if token in takes_value:
                index += 2
            elif token in no_value:
                index += 1
            elif token.startswith("-s="):
                index += 1
            elif token.startswith("-"):
                index += 1
            else:
                break
        verb = values[index].lower() if index < len(values) else ""
        discovery = verb in {"devices", "version", "help", "start-server", "kill-server", "connect", "disconnect"}
        if not discovery:
            if not serial:
                raise ValueError("Select an authorized ADB device for this host command.")
            require_adb(serial, cancel_event=cancel)
            if explicit_serial is None:
                command_args = ["-s", serial, *command_args]
        if verb in {"reboot", "sideload"}:
            raise ValueError(f"Use the dedicated DroidLab {verb} workflow so transport state and confirmation are validated.")
        intent = {
            "operation": "adb.command",
            "serial": serial,
            "command_text": command_text,
        }
        require_confirmation(args, "Advanced host ADB command", intent)
        command = [tool_path("adb"), *command_args]
        response(request_id, "preflight", target=serial or "host",
            command=command, destructive=is_destructive_adb(["adb", *command_args]))
        result = run_streaming(command,
            timeout=bounded_timeout(args.get("timeout_seconds"), 180, 1800),
            cancel_event=cancel,
            on_line=lambda line: response(request_id, "output", stream="stdout", line=line))
        if result.returncode:
            raise RuntimeError(
                f"ADB host command exited with status {result.returncode}: "
                f"{result.stdout[-MAX_RETAINED_OUTPUT:]}"
            )
        return {"exit_code": result.returncode, "output": result.stdout, "serial": serial}
    if operation == "adb.reboot":
        serial, mode = args.get("serial"), args.get("mode", "system")
        if mode not in {"system", "bootloader", "recovery", "fastboot"}:
            raise ValueError("Unsupported reboot mode.")
        require_confirmation(args, "Device reboot", {
            "operation": "adb.reboot", "serial": serial, "mode": mode,
        })
        if not isinstance(serial, str) or not serial.strip():
            raise ValueError("An explicit device serial is required.")

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
        elif adb_state == "sideload":
            transport = "adb"
            command = [tool_path("adb"), "-s", serial, "reboot"] + ([] if mode == "system" else [mode])
        elif adb_state in {"unauthorized", "offline"}:
            require_adb(serial, cancel_event=cancel)
            raise RuntimeError("ADB device is not in a command-ready state.")
        else:
            # USB may already have transitioned to bootloader after a previous request.
            require_fastboot(serial, cancel_event=cancel)
            if mode == "bootloader":
                return {
                    "exit_code": 0,
                    "transport": "fastboot",
                    "message": "Device is already in Fastboot/bootloader mode.",
                }
            transport = "fastboot"
            command = [tool_path("fastboot"), "-s", serial, "reboot"]
            if mode == "recovery":
                command.append("recovery")

        response(request_id, "preflight", target=serial, command=command, destructive=False)
        result = run_streaming(
            command,
            timeout=35,
            cancel_event=cancel,
            on_line=lambda line: response(request_id, "output", stream=transport, line=line),
        )
        if result.returncode:
            raise RuntimeError(f"{transport.upper()} reboot failed ({result.returncode}): {result.stdout}")
        return {
            "exit_code": 0,
            "transport": transport,
            "message": f"{transport.upper()} accepted reboot request to {mode}; USB mode transition is not verified.",
        }
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
    if operation == "device.info":
        serial = args.get("serial")
        if not isinstance(serial, str) or not serial.strip():
            raise ValueError("An explicit device serial is required.")
        scan = execute(request_id, "devices.list", {}, cancel)
        device = next((item for item in scan["devices"] if item.get("serial") == serial), None)
        if device is None:
            raise RuntimeError(f"Device {serial!r} is no longer connected. Refresh devices and retry.")
        values = {
            "Brand / Manufacturer": "",
            "Device name / Model": serial,
            "Model code": "",
            "Codename": "",
            "Active slot": "",
            "Bootloader": "",
            "Android Version": "",
            "Android SDK": "",
            "Battery": "",
            "Mode": device.get("transport", "unknown"),
        }
        if device.get("transport") == "adb":
            if device.get("state") != "device":
                raise RuntimeError(f"ADB device is {device.get('state')}; authorize and reconnect before reading metadata.")
            result = run_streaming([tool_path("adb"), "-s", serial, "shell", "getprop"],
                timeout=30, cancel_event=cancel)
            if result.returncode:
                raise RuntimeError(f"ADB getprop failed: {result.stdout[-MAX_RETAINED_OUTPUT:]}")
            properties = parse_getprop_output(result.stdout)
            values.update({
                "Brand / Manufacturer": first_property(properties, "ro.product.manufacturer", "ro.product.brand"),
                "Device name / Model": first_property(properties, "ro.product.marketname", "ro.product.model") or serial,
                "Model code": first_property(properties, "ro.product.name", "ro.product.model"),
                "Codename": first_property(properties, "ro.product.device", "ro.build.product"),
                "Active slot": first_property(properties, "ro.boot.slot_suffix", "ro.boot.slot"),
                "Android Version": first_property(properties, "ro.build.version.release"),
                "Android SDK": first_property(properties, "ro.build.version.sdk"),
            })
            battery = run_streaming([tool_path("adb"), "-s", serial, "shell", "dumpsys", "battery"],
                timeout=15, cancel_event=cancel)
            battery_level = parse_battery_level(battery.stdout)
            if battery_level is not None:
                values["Battery"] = f"{battery_level}%"
        elif device.get("transport") == "fastboot":
            binary = tool_path("fastboot")
            def getvar(key: str) -> str:
                result = run_streaming([binary, "-s", serial, "getvar", key],
                    timeout=10, cancel_event=cancel)
                output = (result.stdout or "") + "\n" + (result.stderr or "")
                return parse_fastboot_getvar(output, key)
            userspace = getvar("is-userspace").lower()
            if userspace == "yes":
                fastboot_mode = "Fastbootd (userspace Fastboot)"
            elif userspace == "no":
                fastboot_mode = "Bootloader Fastboot"
            else:
                fastboot_mode = "Fastboot (submode unknown)"
            values.update({
                "Model code": getvar("product"),
                "Codename": getvar("product"),
                "Brand / Manufacturer": getvar("manufacturer"),
                "Active slot": getvar("current-slot"),
                "Bootloader": {"yes": "Unlocked", "no": "Locked"}.get(getvar("unlocked").lower(), "Unknown"),
                "Mode": fastboot_mode,
            })
        else:
            raise RuntimeError("Unsupported device transport.")
        return {"serial": serial, "transport": device.get("transport"), "state": device.get("state"), "metadata": values}
    if operation == "adb.device_info":
        serial = args.get("serial")
        require_adb(serial, cancel_event=cancel)
        keys = ["ro.product.manufacturer", "ro.product.model", "ro.product.device",
            "ro.build.version.release", "ro.build.version.sdk", "ro.boot.slot_suffix"]
        result = run_streaming([tool_path("adb"), "-s", serial, "shell", "getprop"],
            timeout=30, cancel_event=cancel)
        if result.returncode:
            raise RuntimeError(f"getprop failed: {result.stdout[-MAX_RETAINED_OUTPUT:]}")
        properties = parse_getprop_output(result.stdout)
        return {"serial": serial, "properties": {key: properties.get(key, "") for key in keys}}
    if operation == "adb.logcat.start":
        serial, filters = args.get("serial"), args.get("filters", [])
        require_adb(serial, cancel_event=cancel)
        if not isinstance(filters, list) or any(not isinstance(item, str) or "\x00" in item for item in filters):
            raise ValueError("filters must be strings.")
        command = [tool_path("adb"), "-s", serial, "logcat", *filters]
        duration = bounded_timeout(args.get("timeout_seconds"), 24 * 3600, 24 * 3600)
        try:
            result = run_streaming(command, timeout=duration, cancel_event=cancel,
                on_line=lambda line: response(request_id, "output", stream="logcat", line=line),
                max_output_chars=1024)
            return {"exit_code": result.returncode, "cancelled": cancel.is_set()}
        except subprocess.TimeoutExpired:
            # A configured capture window ending is a successful stop, not an error.
            return {
                "exit_code": 0,
                "cancelled": False,
                "duration_limit_reached": True,
                "duration_seconds": int(duration),
            }
    if operation == "fastboot.command":
        serial, raw_command = args.get("serial"), args.get("command")
        if not isinstance(raw_command, str) or not raw_command.strip() or "\\x00" in raw_command:
            raise ValueError("A non-empty Fastboot command is required.")
        tokens = shlex.split(raw_command, posix=(os.name != "nt"))
        if not tokens:
            raise ValueError("A non-empty Fastboot command is required.")
        explicit_serial = explicit_device_selector(tokens, "fastboot")
        validate_device_selector(tokens, "fastboot", serial)
        # Discovery/help/version commands are useful without a connected device.
        discovery_verbs = {"devices", "help", "--help", "--version", "version"}
        verb_index = 0
        while verb_index < len(tokens) and tokens[verb_index].startswith("-"):
            token = tokens[verb_index]
            if token in {"-i", "-p", "-c", "--slot"} and verb_index + 1 < len(tokens):
                verb_index += 2
            else:
                verb_index += 1
        verb = tokens[verb_index].lower() if verb_index < len(tokens) else ""
        discovery = verb in discovery_verbs
        if not discovery and not serial:
            raise ValueError("Select a Fastboot device for this command.")
        if discovery and serial and explicit_serial is None:
            serial = None
        intent = {"operation": "fastboot.command", "serial": serial, "command": raw_command}
        require_confirmation(args, "Advanced Fastboot command", intent)
        if not discovery:
            require_fastboot(serial, cancel_event=cancel)
            if explicit_serial is None:
                tokens = ["-s", serial, *tokens]
        command = [tool_path("fastboot"), *tokens]
        response(request_id, "preflight", target=serial or "host", command=command,
            destructive=False if discovery else is_destructive_fastboot(["fastboot", *tokens]))
        result = run_streaming(command, timeout=bounded_timeout(args.get("timeout_seconds"), 900, 1800),
            cancel_event=cancel,
            on_line=lambda line: response(request_id, "output", stream="stdout", line=line))
        if result.returncode:
            raise RuntimeError(
                f"Advanced Fastboot command failed ({result.returncode}); inspect device state before retrying."
            )
        return {"exit_code": 0, "command": tokens, "output": result.stdout, "serial": serial}
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
    if operation == "fastboot.partitions":
        serial = args.get("serial")
        require_fastboot(serial, cancel_event=cancel)
        binary = tool_path("fastboot")
        result = run_streaming([binary, "-s", serial, "getvar", "all"], timeout=30, cancel_event=cancel)
        output = (result.stdout or "") + "\n" + (result.stderr or "")
        if result.returncode and not output.strip():
            raise RuntimeError("Fastboot partition discovery failed.")
        partitions: dict[str, dict[str, str]] = {}
        pattern = re.compile(r"(?im)^\s*(?:\(bootloader\)\s*)?(partition-size|partition-type|has-slot|is-logical):([A-Za-z0-9_.-]+)\s*:\s*(.*?)\s*$")
        for match in pattern.finditer(output):
            field, name, value = match.groups()
            entry = partitions.setdefault(name, {"name": name})
            entry[{"partition-size": "size", "partition-type": "type", "has-slot": "has_slot", "is-logical": "is_logical"}[field.lower()]] = value
        if not partitions:
            raise RuntimeError("The bootloader did not expose partition metadata. Some devices restrict getvar all; use partition names from the firmware package.")
        return {"serial": serial, "partitions": [partitions[name] for name in sorted(partitions, key=str.casefold)], "source": "fastboot getvar all"}

    if operation == "fastboot.set_active":
        serial, slot = args.get("serial"), str(args.get("slot", "")).lower()
        if slot not in {"a", "b", "other"}:
            raise ValueError("Active slot must be a, b, or other.")
        require_confirmation(args, "Fastboot active-slot change", {
            "operation": "fastboot.set_active", "serial": serial, "slot": slot,
        })
        require_fastboot(serial, cancel_event=cancel)
        binary = tool_path("fastboot")
        attempts = (
            [[binary, "-s", serial, "set_active", "other"]]
            if slot == "other" else
            [[binary, "-s", serial, "--set-active=" + slot],
             [binary, "-s", serial, "set_active", slot]]
        )
        output = ""
        for index, command in enumerate(attempts):
            response(request_id, "preflight", target=serial, command=command, destructive=True)
            result = run_streaming(command, timeout=20, cancel_event=cancel,
                on_line=lambda line: response(request_id, "output", stream="stdout", line=line))
            output = result.stdout
            if result.returncode == 0:
                return {"exit_code": 0, "serial": serial, "slot": slot, "output": output}
            if index == 0:
                continue
        raise RuntimeError("Fastboot could not change active slot. Device state was not verified; inspect current-slot before retrying. " + output[-MAX_RETAINED_OUTPUT:])
    if operation == "fastboot.reboot":
        serial, mode = args.get("serial"), args.get("mode", "system")
        if mode not in {"system", "recovery", "bootloader", "fastbootd"}:
            raise ValueError("Unsupported Fastboot reboot mode.")
        require_confirmation(args, "Fastboot reboot", {
            "operation": "fastboot.reboot", "serial": serial, "mode": mode,
        })
        require_fastboot(serial, cancel_event=cancel)
        command = [tool_path("fastboot"), "-s", serial]
        command += (["reboot"] if mode == "system" else
                    ["reboot", "recovery"] if mode == "recovery" else
                    ["reboot", "fastboot"] if mode == "fastbootd" else
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
    if operation == "storage.removable_drives":
        return {"drives": list_removable_drives()}
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

def _device_command_requires_lock(operation: str, args: dict[str, Any]) -> bool:
    """Return whether an advanced command may mutate the selected device.

    Read-only allowlists are intentionally narrow. Unknown commands are treated
    as mutations so new ADB/Fastboot verbs do not bypass per-device serialization.
    """
    if operation == "adb.command":
        raw = args.get("command_text", "")
        try:
            tokens = shlex.split(raw, posix=(os.name != "nt"))
        except (TypeError, ValueError):
            return True
        index = 0
        takes_value = {"-s", "-t", "-H", "-P", "-L"}
        flags = {"-d", "-e"}
        while index < len(tokens):
            token = tokens[index]
            if token in takes_value:
                index += 2
            elif token in flags:
                index += 1
            elif token.startswith("-s="):
                index += 1
            elif token.startswith("-"):
                # Do not guess whether an unknown option consumes a value.
                index += 1
            else:
                break
        verb = tokens[index].lower() if index < len(tokens) else ""
        host_only = {
            "devices", "version", "help", "start-server", "kill-server",
            "connect", "disconnect",
        }
        read_only = {
            "pull", "logcat", "get-state", "get-serialno", "get-devpath",
            "wait-for-device", "features", "jdwp",
        }
        return verb not in host_only and verb not in read_only

    if operation == "fastboot.command":
        raw = args.get("command", "")
        try:
            tokens = shlex.split(raw, posix=(os.name != "nt"))
        except (TypeError, ValueError):
            return True
        index = 0
        takes_value = {"-i", "-p", "-c", "--slot"}
        while index < len(tokens):
            token = tokens[index]
            if token in takes_value and index + 1 < len(tokens):
                index += 2
            elif token.startswith("-"):
                index += 1
            else:
                break
        verb = tokens[index].lower() if index < len(tokens) else ""
        if verb in {"devices", "help", "--help", "--version", "version", "getvar"}:
            return False
        # Fastboot's flashing get_unlock_ability is a read-only capability query.
        if tokens[index:index + 2] and [part.lower() for part in tokens[index:index + 2]] == [
            "flashing", "get_unlock_ability"
        ]:
            return False
        return True

    return operation in _MUTATING


def handle(
    message: dict[str, Any],
    cancel: threading.Event,
    release_worker_slot: bool = False,
) -> None:
    request_id, operation, args = message["id"], message["operation"], message["args"]
    lock = None
    lock_acquired = False
    try:
        response(request_id, "accepted", operation=operation)
        if _device_command_requires_lock(operation, args):
            serial = args.get("serial")
            if not isinstance(serial, str) or not serial:
                raise ValueError("An explicit target serial is required.")
            with _DEVICE_LOCKS_LOCK:
                lock = _DEVICE_LOCKS.setdefault(serial, threading.Lock())
            if not lock.acquire(timeout=0.1):
                lock = None
                raise RuntimeError(
                    f"Another mutating operation is already active for device {serial}."
                )
            lock_acquired = True

        result = execute(request_id, operation, args, cancel)
        response(request_id, "completed", result=result, cancelled=cancel.is_set())
    except ProcessCancelledError:
        response(
            request_id,
            "cancelled",
            message=(
                "Host process cancelled. This does not roll back changes "
                "already accepted by device firmware."
            ),
        )
    except Exception as exc:
        logging.exception("Operation %s failed", operation)
        response(
            request_id,
            "failed",
            error={"code": type(exc).__name__, "message": str(exc)},
        )
    finally:
        if lock is not None and lock_acquired:
            lock.release()
        with _ACTIVE_LOCK:
            _ACTIVE.pop(request_id, None)
        if release_worker_slot:
            _WORKER_SLOTS.release()

def main() -> None:
    logging.basicConfig(stream=sys.stderr, level=os.environ.get("DROIDLAB_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(message)s")
    workers: list[threading.Thread] = []

    def request_shutdown(signum: int, _frame: Any) -> None:
        logging.info("Received shutdown signal %s; cancelling active child operations.", signum)
        with _ACTIVE_LOCK:
            active_events = list(_ACTIVE.values())
        for event in active_events:
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
            request_id, operation, args = message.get("id"), message.get("operation"), message.get("args", {})
            if (
                not isinstance(request_id, str)
                or not request_id.strip()
                or not isinstance(operation, str)
                or not operation.strip()
                or not isinstance(args, dict)
            ):
                raise ValueError("Invalid request envelope.")
            if operation == "system.cancel":
                target = args.get("request_id")
                if not isinstance(target, str) or not target.strip():
                    emit({
                        "id": request_id,
                        "type": "failed",
                        "error": {
                            "code": "InvalidRequest",
                            "message": "system.cancel requires a non-empty request_id.",
                        },
                    })
                    continue
                with _ACTIVE_LOCK:
                    event = _ACTIVE.get(target)
                if event is not None:
                    event.set()
                emit({"id": request_id, "type": "completed",
                    "result": {"cancel_requested": event is not None, "target": target}})
                continue
            if len(json.dumps(message).encode("utf-8")) > MAX_LINE_BYTES:
                raise ValueError("Request exceeds maximum size.")
            cancel = threading.Event()
            with _ACTIVE_LOCK:
                if request_id in _ACTIVE:
                    emit({
                        "id": request_id,
                        "type": "failed",
                        "error": {"code": "DuplicateRequestId", "message": "Request ID is already active."},
                    })
                    continue
                if not _WORKER_SLOTS.acquire(blocking=False):
                    emit({
                        "id": request_id,
                        "type": "failed",
                        "error": {"code": "BackendBusy", "message": "Backend is at its active request limit. Retry after an operation finishes."},
                    })
                    continue
                _ACTIVE[request_id] = cancel
            worker = threading.Thread(target=handle, args=(message, cancel, True), daemon=False)
            try:
                worker.start()
            except BaseException:
                with _ACTIVE_LOCK:
                    _ACTIVE.pop(request_id, None)
                _WORKER_SLOTS.release()
                raise
            workers.append(worker)
            workers = [thread for thread in workers if thread.is_alive()]
        except Exception as exc:
            logging.warning("Rejected protocol input: %s", exc)
    finally:
        # EOF and process signals both cancel children and wait for process-tree cleanup.
        with _ACTIVE_LOCK:
            active_events = list(_ACTIVE.values())
        for event in active_events:
            event.set()
        for worker in workers:
            worker.join()

if __name__ == "__main__":
    main()
