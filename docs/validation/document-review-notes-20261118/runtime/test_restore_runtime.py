#!/usr/bin/env python3
"""Offline controls for the native smoke entrypoint's package and cleanup."""

import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "notes_runtime_restore", Path(__file__).with_name("restore_runtime.py")
)
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)


class NativeSmokeEntrypointTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name)
        self.member = self.repo / "packages/quds_mail_store"
        self.member.mkdir(parents=True)
        self.manifest = self.member / "pubspec.yaml"
        self.manifest.write_text(
            "name: quds_mail_store\nresolution: workspace\n"
            "dependencies:\n  sqlite3: 3.9.1\n"
        )
        self.source = self.repo / (
            "docs/validation/document-review-notes-20261118/runtime/native_asset_smoke.dart"
        )
        self.source.parent.mkdir(parents=True)
        self.contents = b"// Preserve exact bytes.\r\nvoid main() {}\n"
        self.source.write_bytes(self.contents)

    def test_entrypoint_uses_sqlite_member_and_preserves_other_inputs(self):
        generated = self.member / ".dart_tool"
        generated.mkdir()
        sibling = generated / "existing-cache"
        sibling.write_bytes(b"keep")
        manifest_bytes = self.manifest.read_bytes()
        with restore.native_smoke_entrypoint(self.repo) as entrypoint:
            self.assertEqual(entrypoint.parent.parent, generated)
            self.assertEqual(entrypoint.name, self.source.name)
            self.assertEqual(entrypoint.read_bytes(), self.contents)
            self.assertEqual(self.manifest.read_bytes(), manifest_bytes)
        self.assertFalse(entrypoint.parent.exists())
        self.assertEqual(sibling.read_bytes(), b"keep")
        self.assertEqual(self.source.read_bytes(), self.contents)
        self.assertEqual(self.manifest.read_bytes(), manifest_bytes)

    def test_failed_probe_removes_only_its_temporary_directory(self):
        with self.assertRaisesRegex(RuntimeError, "smoke failed"):
            with restore.native_smoke_entrypoint(self.repo) as entrypoint:
                raise RuntimeError("smoke failed")
        self.assertFalse(entrypoint.parent.exists())
        self.assertTrue((self.member / ".dart_tool").is_dir())
        self.assertEqual(self.source.read_bytes(), self.contents)

    def test_wrong_sqlite_pin_refuses_to_stage(self):
        self.manifest.write_text("name: quds_mail_store\ndependencies:\n  sqlite3: 3.9.0\n")
        with self.assertRaisesRegex(RuntimeError, "pinned Mail store SQLite"):
            with restore.native_smoke_entrypoint(self.repo):
                self.fail("An unpinned member must not execute")
        self.assertFalse((self.member / ".dart_tool").exists())

    def test_missing_source_leaves_no_generated_probe(self):
        self.source.unlink()
        with self.assertRaises(FileNotFoundError):
            with restore.native_smoke_entrypoint(self.repo):
                self.fail("A missing source must not execute")
        self.assertFalse((self.member / ".dart_tool").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
