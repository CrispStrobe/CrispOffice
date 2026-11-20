"""Offline controls for the shared iOS/Android packaging helper.

    python3 tools/proofing/test_mobile_native.py
"""
from __future__ import annotations

import argparse
from contextlib import redirect_stderr
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest

import mobile_native


def receipt(output: Path, files: dict[str, bytes], name: str = "build-receipt.json") -> None:
    for relative, data in files.items():
        path = output / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    (output / name).write_text(json.dumps(
        {"files": {k: hashlib.sha256(v).hexdigest() for k, v in files.items()}}))


def arguments(*argv: str):
    parser = argparse.ArgumentParser()
    mobile_native.add_arguments(parser)
    args = parser.parse_args(list(argv))
    mobile_native.check_arguments(parser, args)
    return args


class MobileNativeTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="mobile-native-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.output = self.root / "out"
        receipt(self.output, {
            "android/arm64-v8a/libx.so": b"arm64",
            "android/x86_64/libx.so": b"x86_64",
            "ios/x.xcframework/Info.plist": b"plist",
            "ios/x.xcframework/ios-arm64/x.framework/x": b"device",
        })

    def test_jnilibs_root_receives_every_abi(self) -> None:
        jni = self.root / "jniLibs"
        mobile_native.install_from_arguments(self.output, arguments("--android", "--install-android", str(jni)), "x")
        self.assertEqual((jni / "arm64-v8a/libx.so").read_bytes(), b"arm64")
        self.assertEqual((jni / "x86_64/libx.so").read_bytes(), b"x86_64")

    def test_abi_directory_receives_only_that_abi(self) -> None:
        target = self.root / "jniLibs" / "arm64-v8a"
        mobile_native.install_from_arguments(self.output, arguments("--android", "--install-android", str(target)), "x")
        self.assertEqual(target.joinpath("libx.so").read_bytes(), b"arm64")
        self.assertFalse((self.root / "jniLibs" / "x86_64").exists())

    def test_xcframework_tree_is_copied_exactly(self) -> None:
        target = self.root / "Frameworks"
        mobile_native.install_from_arguments(self.output, arguments("--ios", "--install-ios", str(target)), "x")
        self.assertEqual((target / "x.xcframework/ios-arm64/x.framework/x").read_bytes(), b"device")

    def test_changed_artifact_is_rejected_before_copying(self) -> None:
        (self.output / "android/x86_64/libx.so").write_bytes(b"changed")
        jni = self.root / "jniLibs"
        with self.assertRaisesRegex(SystemExit, "changed build artifact"):
            mobile_native.install_from_arguments(
                self.output, arguments("--android", "--install-android", str(jni)), "x")
        self.assertFalse(jni.exists())

    def test_install_flags_require_their_build(self) -> None:
        for argv, message in ((["--install-android", "x"], "--install-android requires --android"),
                              (["--install-ios", "x"], "--install-ios requires --ios"),
                              (["--android-abi", "x86_64"], "--android-abi requires --android")):
            errors = io.StringIO()
            with self.subTest(argv=argv), redirect_stderr(errors), self.assertRaises(SystemExit):
                arguments(*argv)
            self.assertIn(message, errors.getvalue())

    def test_plist_is_well_formed_and_escaped(self) -> None:
        text = mobile_native._plist({"A": "x&y", "B": ["iPhoneOS"]})
        self.assertIn("<string>x&amp;y</string>", text)
        self.assertIn("<array>", text)


if __name__ == "__main__":
    unittest.main()
