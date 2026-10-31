# DroidLab Python backend

Headless execution service. It communicates with Flutter using UTF-8 JSON Lines on stdin/stdout; stdout is protocol-only and diagnostics go to stderr.

Run from the repository root with `python3 -u backend/python/server.py`. Requests carry protocol version 1, a unique ID, operation name and object-valued args. Operations emit accepted, output/preflight events and a terminal result.

Override tool locations with `DROIDLAB_ADB_PATH`, `DROIDLAB_FASTBOOT_PATH`, and `DROIDLAB_PAYLOAD_DUMPER_GO_PATH`; select Python with `DROIDLAB_PYTHON`. The backend validates target serials with fresh transport scans, validates partition names, requires explicit confirmation for mutations, and serializes mutating operations per device.

Cancelling a host process does not roll back changes already accepted by device firmware.