"""Regression tests for the selectable UI palettes."""

import re
import unittest

from droidlab.config.constants import THEME_TOKENS


class ThemeTokenTests(unittest.TestCase):
    def test_every_theme_has_the_required_surface_and_semantic_tokens(self):
        required = {
            "label",
            "bg",
            "panel",
            "panel_alt",
            "border",
            "text",
            "muted",
            "input",
            "accent",
            "accent2",
            "button",
            "console",
            "success",
            "warning",
            "danger",
        }
        for name, tokens in THEME_TOKENS.items():
            with self.subTest(theme=name):
                self.assertTrue(required.issubset(tokens))
                for key in required - {"label"}:
                    self.assertRegex(tokens[key], re.compile(r"^#[0-9a-fA-F]{6}$"), key)

    def test_theme_picker_options_have_distinct_labels_and_palettes(self):
        labels = [tokens["label"] for tokens in THEME_TOKENS.values()]
        self.assertEqual(len(labels), len(set(labels)))

        palette_signatures = {
            tuple((key, value) for key, value in tokens.items() if key != "label")
            for tokens in THEME_TOKENS.values()
        }
        self.assertEqual(len(palette_signatures), len(THEME_TOKENS))

    def test_charcoal_blue_uses_a_cool_blue_accent(self):
        blue = THEME_TOKENS["cyberpunk_glass"]
        charcoal = THEME_TOKENS["standard_dark"]
        self.assertNotEqual(blue["accent"], charcoal["accent"])
        self.assertNotEqual(blue["panel"], charcoal["panel"])


if __name__ == "__main__":
    unittest.main()
