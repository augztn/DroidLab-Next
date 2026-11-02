import unittest

from droidlab.core.device_metadata import (
    first_property,
    parse_battery_level,
    parse_fastboot_getvar,
    parse_getprop_output,
)


class DeviceMetadataTests(unittest.TestCase):
    def test_parse_getprop_output_ignores_non_property_lines(self):
        self.assertEqual(
            parse_getprop_output(
                "[ro.product.model]: [Pixel Test]\n"
                "noise\n"
                "[ro.build.version.sdk]: [35]\n"
            ),
            {"ro.product.model": "Pixel Test", "ro.build.version.sdk": "35"},
        )

    def test_parse_getprop_output_preserves_embedded_closing_brackets(self):
        self.assertEqual(
            parse_getprop_output("[ro.test.value]: [value]]\n"),
            {"ro.test.value": "value]"},
        )

    def test_first_property_uses_priority_and_skips_empty_values(self):
        self.assertEqual(
            first_property({"brand": "", "manufacturer": "Example"}, "brand", "manufacturer"),
            "Example",
        )

    def test_battery_level_accepts_valid_percentage(self):
        self.assertEqual(parse_battery_level("  level: 87\n"), 87)

    def test_battery_level_rejects_out_of_range_and_missing_values(self):
        self.assertIsNone(parse_battery_level("level: 101\n"))
        self.assertIsNone(parse_battery_level("status: 2\n"))

    def test_fastboot_getvar_parses_bootloader_prefix_and_stderr_text(self):
        self.assertEqual(
            parse_fastboot_getvar("(bootloader) current-slot: b\n", "current-slot"),
            "b",
        )

    def test_fastboot_getvar_parses_plain_userspace_output(self):
        self.assertEqual(
            parse_fastboot_getvar("is-userspace: yes\n", "is-userspace"),
            "yes",
        )

    def test_fastboot_getvar_parses_info_prefix(self):
        self.assertEqual(
            parse_fastboot_getvar("INFO: is-userspace: yes\n", "is-userspace"),
            "yes",
        )

    def test_fastboot_getvar_parses_timestamp_prefix(self):
        self.assertEqual(
            parse_fastboot_getvar("[  0.001s] is-userspace: yes\n", "is-userspace"),
            "yes",
        )

    def test_fastboot_getvar_escapes_requested_key(self):
        self.assertEqual(
            parse_fastboot_getvar("(bootloader) product.name: unit\n", "product.name"),
            "unit",
        )


if __name__ == "__main__":
    unittest.main()
