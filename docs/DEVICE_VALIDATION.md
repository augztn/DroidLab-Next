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