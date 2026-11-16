"""Regression controls for the distribution license gate."""
import json
from pathlib import Path
import tempfile
import unittest

from license_bundle import selection, validate_fallback_revision


class LicensePolicyTest(unittest.TestCase):
    def test_selects_permitted_alternative(self):
        for expression, expected in [
            ("MIT OR Apache-2.0", ["MIT"]),
            ("GPL-2.0-only OR MPL-2.0", ["MPL-2.0"]),
            ("(MIT OR GPL-3.0-only) AND BSD-3-Clause", ["BSD-3-Clause", "MIT"]),
            ("Apache-2.0/MIT", ["MIT"]),
            ("Unicode-3.0", ["Unicode-3.0"]),
        ]:
            with self.subTest(expression=expression):
                self.assertEqual(selection(expression), expected)

    def test_rejects_forbidden_unknown_and_malformed_terms(self):
        for expression in [
            "GPL-3.0-only", "LGPL-2.1-only", "AGPL-3.0-only",
            "MIT AND GPL-3.0-only", "Unknown-License", "",
            "MIT OR", "(MIT", "MIT WITH", "MIT WITH unknown-exception",
            "MIT) OR GPL-3.0-only", "MIT; Apache-2.0",
        ]:
            with self.subTest(expression=expression):
                with self.assertRaises(ValueError):
                    selection(expression)

    def test_rejects_stale_fallback_notice(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            (source / ".cargo_vcs_info.json").write_text(json.dumps({
                "git": {"sha1": "different-source-revision"},
            }))
            with self.assertRaisesRegex(ValueError, "changed source revision"):
                validate_fallback_revision("harper-core", source)


if __name__ == "__main__":
    unittest.main()
