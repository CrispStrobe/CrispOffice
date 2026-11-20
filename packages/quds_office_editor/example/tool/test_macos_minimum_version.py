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


def function(name):
    match = re.search(
        rf"^{re.escape(name)}\(\) \{{.*?^\}}",
        SOURCE, re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise RuntimeError(f"Could not locate the release script's {name}")
    return match[0]


VERSION_FUNCTION = function("version_le")
GUARD_FUNCTION = function("verify_library_minimum_os")


def modern(minimum="13.0", architecture="arm64", platform="MACOS", command=0):
    return (
        f"/fixture.dylib (architecture {architecture}):\n"
        f"Load command {command}\n"
        "      cmd LC_BUILD_VERSION\n"
        "  cmdsize 32\n"
        f" platform {platform}\n"
        f"    minos {minimum}\n"
        "      sdk 26.2\n"
        "   ntools 1\n"
        "     tool LD\n"
        "  version 1115.7.3\n"
    )


def legacy(minimum="10.15", architecture="x86_64", command=0):
    return (
        f"/fixture.dylib (architecture {architecture}):\n"
        f"Load command {command}\n"
        "      cmd LC_VERSION_MIN_MACOSX\n"
        "  cmdsize 16\n"
        f"  version {minimum}\n"
        "      sdk 13.0\n"
    )


class MinimumMacOSVersionTest(unittest.TestCase):
    def compare(self, library, app):
        return subprocess.run(
            ["bash", "-c", VERSION_FUNCTION + '\nversion_le "$1" "$2"',
             "minimum-version-test", library, app],
            capture_output=True, text=True, timeout=5,
        )

    def guard(self, app, output, vtool_status=0):
        command = (
            "set -euo pipefail\n" + VERSION_FUNCTION + "\n"
            + GUARD_FUNCTION + "\n"
            'VTOOL_OUTPUT="$2"\nVTOOL_STATUS="$3"\n'
            'vtool() {\n'
            '  [[ "$#" == 2 && "$1" == -show-build && "$2" == /fixture.dylib ]]'
            ' || return 64\n'
            '  printf "%s\\n" "$VTOOL_OUTPUT"\n'
            '  return "$VTOOL_STATUS"\n'
            '}\n'
            'verify_library_minimum_os "/fixture.dylib" "$1"\n'
        )
        return subprocess.run(
            ["bash", "-c", command, "minimum-version-test", app, output,
             str(vtool_status)],
            capture_output=True, text=True, timeout=5,
        )

    def test_numeric_order_and_equivalent_zero_components(self):
        huge = "9" * 80
        larger = "1" + "0" * 80
        cases = [
            ("11.0", "13.0", 0), ("26.0", "13.0", 1),
            ("10.15", "13.0", 0), ("13.1", "13.0", 1),
            ("13.0", "13.0", 0), ("13", "13.0", 0),
            ("13.0", "13", 0), ("13.0.0", "13.0", 0),
            ("13.0", "13.0.0", 0), ("13.0.1", "13.0", 1),
            ("13.10", "13.2", 1), ("13.2", "13.10", 0),
            ("13.1.10", "13.1.9", 1), ("013.00", "13.0", 0),
            ("0", "000.00.000", 0), ("000.00.000", "0", 0),
            ("00013.0008.0", "13.8", 0), ("13.0009", "13.8", 1),
            ("0" * 80 + "13.0008.0", "13.8", 0),
            (huge, larger, 0), (larger, huge, 1),
            ("13." + huge, "13." + larger, 0),
            ("13." + larger, "13." + huge, 1),
            ("13.0.9007199254740992", "13.0.9007199254740993", 0),
            ("13.0.9007199254740993", "13.0.9007199254740992", 1),
            ("13.18446744073709551616", "13.18446744073709551615", 1),
            ("13.18446744073709551615", "13.18446744073709551616", 0),
        ]
        for library, app, expected in cases:
            with self.subTest(library=library, app=app):
                result = self.compare(library, app)
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_malformed_versions_fail_closed(self):
        for invalid in ("", "13..0", "13.", ".13", "13.0beta", "-1", "+13",
                        "13 0", "13\n0", r"\0613.0", "13.0.0.1",
                        " 13.0", "13.0 ", "١٣.٠"):
            for library, app in ((invalid, "13.0"), ("13.0", invalid)):
                with self.subTest(library=library, app=app):
                    self.assertEqual(self.compare(library, app).returncode, 2)
            with self.subTest(app=invalid):
                result = self.guard(invalid, modern(), vtool_status=79)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn("app declares malformed minimum macOS", result.stderr)

    def test_each_universal_architecture_must_fit_the_app(self):
        # The modern record's nested linker version is deliberately much
        # newer than the app. It must never be read as a deployment target.
        accepted = [
            modern(), legacy(), modern() + legacy(), legacy() + modern(),
            modern("13.0.0") + legacy("11.0"),
            modern().replace(" (architecture arm64)", ""),
            modern() + legacy(command=1).split("\n", 1)[1],
        ]
        for output in accepted:
            with self.subTest(accepted=output):
                result = self.guard("13.0", output)
                self.assertEqual(result.returncode, 0, result.stderr)
        for app, output in [
            ("00013.00", modern("0013.000.0")),
            ("9" * 80, modern("9" * 80)),
        ]:
            with self.subTest(app=app):
                result = self.guard(app, output)
                self.assertEqual(result.returncode, 0, result.stderr)

        oversized = [
            modern("13.1.9") + legacy("13.1.10"),
            legacy("13.1.10") + modern("13.1.9"),
            legacy("13.1.9") + modern("13.1.10"),
            modern("13.1.10") + legacy("13.1.9"),
            modern("13.1.9")
            + legacy("13.1.10", command=1).split("\n", 1)[1],
        ]
        for output in oversized:
            with self.subTest(output=output):
                result = self.guard("13.1.9", output)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn("needs macOS 13.1.10", result.stderr)
        self.assertEqual(self.guard("13.0", modern("9" * 80)).returncode, 1)

    def test_missing_invalid_or_unreadable_minimum_is_rejected(self):
        missing_slice = "/fixture.dylib (architecture x86_64):\n"
        cases = {
            "empty": "",
            "header only": missing_slice,
            "unrelated fields only": missing_slice + "sdk 26.2\n",
            "missing header": modern().split("\n", 1)[1],
            "malformed load index": modern().replace("Load command 0", "Load command x"),
            "missing command kind": modern().replace("      cmd LC_BUILD_VERSION\n", ""),
            "duplicate command kind": modern().replace(
                "cmd LC_BUILD_VERSION", "cmd LC_BUILD_VERSION\n      cmd LC_BUILD_VERSION"),
            "unsupported command": legacy().replace("LC_VERSION_MIN_MACOSX", "LC_VERSION_MIN_IPHONEOS"),
            "missing platform": modern().replace(" platform MACOS\n", ""),
            "duplicate platform": modern().replace(" platform MACOS", " platform MACOS\n platform MACOS"),
            "non-macOS platform": modern(platform="IOS"),
            "simulator platform": modern(platform="IOSSIMULATOR"),
            "Catalyst platform": modern(platform="MACCATALYST"),
            "extra platform fields": modern(platform="MACOS extra"),
            "missing minos": modern().replace("    minos 13.0\n", ""),
            "empty minos": modern(""),
            "invalid minos": modern("13.x"),
            "too many version components": modern("13.0.0.1"),
            "extra minimum fields": modern("13.0 extra"),
            "duplicate minos": modern().replace("minos 13.0", "minos 13.0\n    minos 13.0"),
            "minimum outside a command": missing_slice + "minos 13.0\n",
            "legacy missing version": legacy().replace("  version 10.15\n", ""),
            "legacy malformed version": legacy("10.x"),
            "legacy duplicate version": legacy().replace("version 10.15", "version 10.15\n  version 10.15"),
            "legacy modern-only minimum": legacy().replace("version 10.15", "minos 10.15"),
            "earlier empty slice": missing_slice + modern(),
            "later empty slice": modern() + missing_slice,
            "later malformed slice": modern() + legacy("10.x"),
        }
        for name, output in cases.items():
            with self.subTest(case=name):
                result = self.guard("13.0", output)
                self.assertEqual(result.returncode, 1, result.stderr)
        result = self.guard("13.0", modern(), vtool_status=1)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("could not read macOS deployment commands", result.stderr)

    def test_complete_release_script_parses(self):
        self.assertRegex(
            SOURCE,
            r'(?m)^  verify_library_minimum_os "\$path" "\$APP_MINIMUM_OS" \|\| exit 1$',
        )
        result = subprocess.run(
            ["bash", "-n", str(SCRIPT)], capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
