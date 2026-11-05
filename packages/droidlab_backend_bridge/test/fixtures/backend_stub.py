#!/usr/bin/env python3
"""Deterministic child process used by BackendClient lifecycle tests."""
import json
import os
import sys
import time


mode = os.environ.get("DROIDLAB_TEST_MODE", "normal")
if mode == "delayed_start":
    time.sleep(0.25)


def emit(message):
    sys.stdout.write(json.dumps({"version": 1, **message}) + "\n")
    sys.stdout.flush()


for raw in sys.stdin:
    try:
        request = json.loads(raw)
    except json.JSONDecodeError:
        continue

    operation = request.get("operation")
    request_id = request.get("id")
    if operation == "system.ping":
        emit({
            "id": request_id,
            "type": "completed",
            "result": {"status": "ok"},
        })
        continue

    if mode == "malformed_preflight" and operation == "protocol.malformed_preflight":
        emit({"id": request_id, "type": "preflight", "target": "DEVICE-1",
              "command": ["fastboot", 7], "destructive": True})
        continue

    if mode == "invalid_utf8" and operation == "protocol.invalid_utf8":
        sys.stdout.flush()
        sys.stdout.buffer.write(b"\xff\n")
        sys.stdout.buffer.flush()
        continue

    if mode == "exit_on_request":
        raise SystemExit(23)

    if operation == "system.cancel":
        emit({
            "id": request.get("args", {}).get("request_id", ""),
            "type": "cancelled",
        })
        continue

    if mode == "malformed_response" and operation == "protocol.broken":
        sys.stdout.write("{invalid-json}\n")
        sys.stdout.flush()
        continue

    if mode == "slow":
        time.sleep(0.2)

    emit({
        "id": request_id,
        "type": "completed",
        "result": {"operation": operation},
    })
