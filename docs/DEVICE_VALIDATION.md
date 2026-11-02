# Device transition validation

This is the manual hardware acceptance checklist for ADB, bootloader Fastboot, and Fastbootd. CI uses mocked subprocesses and does not replace this test on supported physical devices.

## Preconditions

- Use a device with an unlockable/recoverable boot chain and a known-good stock or custom firmware image.
- Back up user data. Keep the exact factory firmware and recovery instructions available.
- Record device model, product/codename, bootloader version, Android version, active slot, and host platform.
- Use a direct USB connection and a known-good cable. Do not run destructive tests on a primary device.

## Transition matrix

| Start state | Action | Expected state |
| --- | --- | --- |
| Android, authorized ADB | `adb reboot bootloader` | Bootloader Fastboot; device appears in `fastboot devices` |
| Android, authorized ADB | `adb reboot fastboot` | Fastbootd; `fastboot getvar is-userspace` reports `yes` |
| Bootloader Fastboot | `fastboot reboot fastboot` | Fastbootd; `is-userspace` reports `yes` |
| Fastbootd | `fastboot reboot bootloader` | Bootloader Fastboot; `is-userspace` reports `no` |
| Either Fastboot mode | `fastboot reboot` | Android; device returns to authorized ADB after boot |

Run one transition at a time. Refresh DroidLab's device list after each transition and verify the reported transport/mode before continuing. USB disconnect/re-enumeration can take several seconds.

## Slot switching

1. Record `fastboot getvar current-slot`.
2. Run `fastboot set_active other` through DroidLab's confirmation flow.
3. Verify `fastboot getvar current-slot` reports the opposite slot.
4. Do not reboot unless the target slot contains a bootable, compatible image set.

## Partition discovery and firmware compatibility

1. Run **Discover partitions** in Fastboot Toolkit in both bootloader Fastboot and Fastbootd where supported.
2. Compare discovered names, sizes, types, `has-slot`, and logical partition metadata with the manufacturer's firmware package and device documentation.
3. Test a non-destructive read-only query first. Never infer flash compatibility from a matching partition name alone.
4. Before flashing, confirm product/codename, hardware revision, Android release, slot layout, dynamic-partition status, image format, and AVB/vbmeta requirements.
5. Flash only a known-good image for the exact device variant. Verify command output and boot state; a successful fastboot exit code is not proof of bootability.

## Recovery and failure handling

- Confirm a device can enter recovery and return to Android without DroidLab losing its selected serial.
- Test unauthorized/offline ADB, unplug during a read-only query, and reconnect/re-scan.
- For interrupted writes, assume device state is uncertain. Do not automatically retry; inspect the device and use the documented vendor recovery path.
- Record host OS, platform-tools version, device build, exact steps, and sanitized logs for each failure.

## Evidence

Attach the completed matrix, `fastboot getvar all` output after removing serials, and DroidLab diagnostic report after reviewing redactions. Do not publish IMEI, serial, account identifiers, tokens, or private firmware.

## Host storage and ADB transfer validation

- On Windows, verify that USB flash drives reported by Windows as `DRIVE_REMOVABLE` appear in the mounted-storage selector.
- Verify that fixed internal disks, USB-attached disks reported as `DRIVE_FIXED`, optical drives and unavailable drive letters do not appear.
- Drag a regular file onto the ADB Toolkit push source field, select an authorized device, confirm the exact source and destination, and verify the file contents on-device.
- Pull a known file into a clean local directory and verify its contents on a filesystem with hard-link support and on FAT/exFAT where the exclusive-create fallback is used. Repeat with an existing same-name local file and confirm DroidLab refuses to overwrite it.
- Disconnect the device during a transfer and verify the operation reports an uncertain/failed outcome without automatically retrying.


## Platform-Tools installation validation

- On Windows and macOS, start with no configured ADB/Fastboot overrides and no existing DroidLab-managed Platform-Tools directory.
- Open Settings and start the Platform-Tools installer. Verify that the download cannot begin until the user explicitly accepts Google's Android SDK License Agreement.
- Cancel the dialog and verify no download or filesystem changes occur.
- Accept the license, install version 37.0.1 from Google's official HTTPS download endpoint, and verify both `adb version` and `fastboot --version` report the expected version.
- Verify the installation is stored in the per-user application-data directory, not the app bundle or a system-wide directory.
- Verify custom ADB/Fastboot executable paths still take precedence over the managed installation; clearing the override should select the managed tools before PATH.
- Interrupt a download and verify no partial installation becomes active. Retry and verify the installer can complete cleanly.
- Verify the app bundle does not contain copied Google Platform-Tools binaries.
