#!/usr/bin/env python3
"""Integrity controls for the additive hosted-cache extension."""

import hashlib
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

import yaml


SPEC = importlib.util.spec_from_file_location(
    "extend_runtime", Path(__file__).with_name("extend_runtime.py")
)
EXT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXT)


def lock(packages):
    return yaml.safe_dump({"packages": {
        name: {"source": "hosted", "version": version,
               "description": {"name": name, "url": "https://pub.dev", "sha256": sha}}
        for name, version, sha in packages
    }}).encode()


class LockProfileControls(unittest.TestCase):
    def setUp(self):
        self.base = lock([("original", "1.0.0", "a" * 64)])
        self.sdk = lock([("sdk_tool", "2.0.0", "b" * 64)])
        self.target = lock([("original", "1.0.0", "a" * 64), ("addition", "3.0.0", "c" * 64)])
        self.profile = {
            "base_lock_sha256": hashlib.sha256(self.base).hexdigest(),
            "target_lock_sha256": hashlib.sha256(self.target).hexdigest(),
            "sdk_tools_lock_sha256": hashlib.sha256(self.sdk).hexdigest(),
            "base_archive_count": 2, "target_archive_count": 3,
            "additions": [{"name": "addition", "version": "3.0.0", "sha256": "c" * 64}],
        }

    def test_exact_additive_profile(self):
        old, new, added = EXT.extension_archives(self.base, self.target, self.sdk, self.profile)
        self.assertEqual(set(old), {"original-1.0.0", "sdk_tool-2.0.0"})
        self.assertEqual(set(new), set(old) | {"addition-3.0.0"})
        self.assertEqual(list(added), ["addition-3.0.0"])

    def test_raw_lock_change_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "exact extension profile"):
            EXT.extension_archives(self.base, self.target + b"\n", self.sdk, self.profile)

    def test_replaced_original_archive_is_rejected_even_with_updated_target_hash(self):
        target = self.target.replace(("a" * 64).encode(), ("d" * 64).encode())
        profile = {**self.profile, "target_lock_sha256": hashlib.sha256(target).hexdigest()}
        with self.assertRaisesRegex(RuntimeError, "remove or replace"):
            EXT.extension_archives(self.base, target, self.sdk, profile)

    def test_removed_original_archive_is_rejected(self):
        target = lock([("addition", "3.0.0", "c" * 64)])
        profile = {**self.profile, "target_lock_sha256": hashlib.sha256(target).hexdigest(),
                   "target_archive_count": 2}
        with self.assertRaisesRegex(RuntimeError, "remove or replace"):
            EXT.extension_archives(self.base, target, self.sdk, profile)

    def test_unlisted_addition_is_rejected(self):
        profile = {**self.profile, "additions": []}
        with self.assertRaisesRegex(RuntimeError, "explicitly pinned additions"):
            EXT.extension_archives(self.base, self.target, self.sdk, profile)

    def test_unapproved_host_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "unapproved hosted archive"):
            EXT.archive_union(self.target.replace(b"https://pub.dev", b"https://example.org"))

    def test_conflicting_sdk_archive_hash_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "Conflicting archive identity"):
            EXT.archive_union(self.base, self.base.replace(("a" * 64).encode(), ("b" * 64).encode()))


class InputBindingControls(unittest.TestCase):
    def test_preserves_native_bindings_and_allows_only_generated_mapping_refresh(self):
        original = {"/native/language.so": "a", "/native/morph.so": "b", "/repo/assets.yaml": "old"}
        refreshed = {"/repo/assets.yaml": "new", "/native/sqlite.so": "c"}
        result = EXT.merge_bindings(original, refreshed, Path("/repo/assets.yaml"))
        self.assertEqual(result, {**original, **refreshed})
        self.assertEqual(original["/repo/assets.yaml"], "old")
        with self.assertRaisesRegex(RuntimeError, "previously bound native input changed"):
            EXT.merge_bindings(original, {"/native/language.so": "changed"}, Path("/repo/assets.yaml"))

    def test_retained_and_external_input_corruption_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            retained_file, external_file = root / "runtime.bin", root / "native.so"
            retained_file.write_bytes(b"runtime")
            external_file.write_bytes(b"native")
            retained = {"runtime.bin": {"bytes": 7, "sha256": EXT.digest(retained_file)}}
            additional = {str(external_file): EXT.digest(external_file)}
            EXT.verify_inputs(root, retained, additional)
            retained_file.write_bytes(b"changed")
            with self.assertRaisesRegex(RuntimeError, "retained runtime input changed"):
                EXT.verify_inputs(root, retained, additional)
            retained_file.write_bytes(b"runtime")
            external_file.unlink()
            with self.assertRaisesRegex(RuntimeError, "additional runtime input changed"):
                EXT.verify_inputs(root, retained, additional)

    def test_retained_traversal_is_rejected_before_access(self):
        with self.assertRaisesRegex(RuntimeError, "Unsafe retained runtime path"):
            EXT.verify_inputs(Path("/unused"), {"../outside": {"bytes": 0, "sha256": ""}}, {})


class ArchiveControls(unittest.TestCase):
    def archive(self, root, extra=None):
        archive = root / "package.tar.gz"
        contents = {"pubspec.yaml": b"name: package\nversion: 1.0.0\n", "lib/main.dart": b"library;\n"}
        if extra:
            contents.update(extra)
        with tarfile.open(archive, "w:gz") as stream:
            for name, data in contents.items():
                member = tarfile.TarInfo(name)
                member.size = len(data)
                stream.addfile(member, io.BytesIO(data))
        return archive, {"name": "package", "version": "1.0.0", "sha256": EXT.digest(archive)}

    def test_exact_archive_retains_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive, expected = self.archive(root)
            EXT.extract_verified(archive, root / "unpacked", expected)
            self.assertEqual((root / "unpacked/lib/main.dart").read_bytes(), b"library;\n")

    def test_wrong_archive_hash_is_rejected_before_extraction(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive, expected = self.archive(root)
            with self.assertRaisesRegex(RuntimeError, "locked SHA-256"):
                EXT.extract_verified(archive, root / "unpacked", {**expected, "sha256": "0" * 64})
            self.assertFalse((root / "unpacked").exists())

    def test_wrong_package_identity_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive, expected = self.archive(root)
            with self.assertRaisesRegex(RuntimeError, "package identity differs"):
                EXT.extract_verified(archive, root / "unpacked", {**expected, "name": "different"})

    def test_tar_traversal_cannot_write_outside_staging(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive, expected = self.archive(root, {"../escaped": b"no"})
            with self.assertRaises(tarfile.FilterError):
                EXT.extract_verified(archive, root / "unpacked", expected)
            self.assertFalse((root / "escaped").exists())


if __name__ == "__main__":
    unittest.main()
