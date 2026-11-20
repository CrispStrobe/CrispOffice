#!/usr/bin/env python3
"""Exercise the release script's actual version and universal-library guard.

The guard is extracted without running app builds, signing, or downloads.
Only vtool is replaced with fixture output, so this runs on Linux as well.
"""

from pathlib import Path
import re
import subprocess
import unittest


SCRIPT = Path(__file__).with_name("build_macos_app.sh")
SOURCE = SCRIPT.read_text(encoding="utf-8")
FUNCTION = re.search(r"^version_le\(\) \{.*?^\}", SOURCE, re.MULTILINE | re.DOTALL)
GUARD = re.search(
    r"^  library_minima=.*?(?=^  # Only system libraries)",
    SOURCE,
    re.MULTILINE | re.DOTALL,
)
if FUNCTION is None or GUARD is None:
    raise RuntimeError("Could not locate the release script's minimum-OS guard")


class MinimumMacOSVersionTest(unittest.TestCase):
    def compare(self, library, app):
        return subprocess.run(
            ["bash", "-c", FUNCTION[0] + '\nversion_le "$1" "$2"',
             "minimum-version-test", library, app],
            capture_output=True, text=True, timeout=5,
        )

    def guard(self, app, output, vtool_status=0):
        command = (
            "set -euo pipefail\n" + FUNCTION[0] + "\n"
            'APP_MINIMUM_OS="$1"\nVTOOL_OUTPUT="$2"\nVTOOL_STATUS="$3"\n'
            'library="fixture.dylib"\npath="/fixture.dylib"\n'
            'vtool() { printf "%s\\n" "$VTOOL_OUTPUT"; return "$VTOOL_STATUS"; }\n'
            + GUARD[0]
        )
        return subprocess.run(
            ["bash", "-c", command, "minimum-version-test", app, output,
             str(vtool_status)],
            capture_output=True, text=True, timeout=5,
        )

    def test_numeric_order_and_equivalent_zero_components(self):
        cases = [
            ("11.0", "13.0", 0), ("26.0", "13.0", 1),
            ("10.15", "13.0", 0), ("13.1", "13.0", 1),
            ("13.0", "13.0", 0), ("13", "13.0", 0),
            ("13.0", "13", 0), ("13.0.0", "13.0", 0),
            ("13.0", "13.0.0", 0), ("13.0.1", "13.0", 1),
            ("13.10", "13.2", 1), ("13.2", "13.10", 0),
            ("13.1.10", "13.1.9", 1), ("013.00", "13.0", 0),
        ]
        for library, app, expected in cases:
            with self.subTest(library=library, app=app):
                result = self.compare(library, app)
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_malformed_versions_fail_closed(self):
        for invalid in ("", "13..0", "13.", ".13", "13.0beta", "-1", "13 0",
                        "13\n0", r"\0613.0"):
            for library, app in ((invalid, "13.0"), ("13.0", invalid)):
                with self.subTest(library=library, app=app):
                    self.assertEqual(self.compare(library, app).returncode, 2)

    def test_each_universal_architecture_must_fit_the_app(self):
        for output in ("minos 13.1.9\nminos 13.1.10",
                       "minos 13.1.10\nminos 13.1.9"):
            with self.subTest(output=output):
                result = self.guard("13.1.9", output)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("needs macOS 13.1.10", result.stderr)
        self.assertEqual(
            self.guard("13.0", "    minos 11.0\n    minos 13.0.0").returncode, 0,
        )

    def test_missing_invalid_or_unreadable_minimum_is_rejected(self):
        for output in ("", "sdk 26.2", "minos 13.x", "minos",
                       "minos 11.0\nminos", "minos\nminos 11.0"):
            with self.subTest(output=output):
                self.assertNotEqual(self.guard("13.0", output).returncode, 0)
        self.assertNotEqual(self.guard("13.0", "minos 11.0", 1).returncode, 0)

    def test_complete_release_script_parses(self):
        result = subprocess.run(
            ["bash", "-n", str(SCRIPT)], capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
