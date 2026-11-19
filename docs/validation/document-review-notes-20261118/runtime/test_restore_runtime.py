#!/usr/bin/env python3
"""Offline controls for native smoke ownership and exact workspace resolution."""

import importlib.util
import json
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


class WorkspacePackageVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name)
        self.member = self.repo / "packages/member"
        self.member.mkdir(parents=True)
        self.manifest = self.repo / "pubspec.yaml"
        self.manifest.write_text("name: root\nworkspace:\n  - packages/member\n")
        (self.member / "pubspec.yaml").write_text("name: member\n")
        self.lock = self.repo / "pubspec.lock"
        self.lock.write_text("packages:\n  dependency: {}\n  sdk_package: {}\n")
        self.config = self.repo / ".dart_tool/package_config.json"
        self.config.parent.mkdir()
        self.names = ["root", "member", "dependency", "sdk_package"]
        self.write_config(self.names)

    def write_config(self, names):
        self.config.write_text(json.dumps({"packages": [{"name": name} for name in names]}))

    def test_matches_names_from_all_authoritative_inputs_without_mutating_them(self):
        paths = [self.manifest, self.member / "pubspec.yaml", self.lock, self.config]
        before = {path: path.read_bytes() for path in paths}
        result = restore.verified_workspace_packages(self.repo)
        self.assertEqual(result, {
            "locked": ["dependency", "sdk_package"],
            "workspace": ["member", "root"],
            "resolved": sorted(self.names),
        })
        self.assertEqual({path: path.read_bytes() for path in paths}, before)

    def test_new_workspace_member_needs_no_hardcoded_count_change(self):
        transport = self.repo / "packages/transport"
        transport.mkdir()
        (transport / "pubspec.yaml").write_text("name: transport\n")
        self.manifest.write_text(
            "name: root\nworkspace:\n  - packages/member\n  - packages/transport\n"
        )
        self.write_config(self.names + ["transport"])
        result = restore.verified_workspace_packages(self.repo)
        self.assertEqual(len(result["resolved"]), 5)
        self.assertEqual(result["workspace"], ["member", "root", "transport"])

    def test_missing_locked_or_workspace_package_is_rejected(self):
        for name in ["dependency", "member", "root"]:
            with self.subTest(name=name):
                self.write_config([item for item in self.names if item != name])
                with self.assertRaisesRegex(RuntimeError, "missing=.*" + name):
                    restore.verified_workspace_packages(self.repo)

    def test_unexpected_package_is_rejected(self):
        self.write_config(self.names + ["surprise"])
        with self.assertRaisesRegex(RuntimeError, "unexpected=.*surprise"):
            restore.verified_workspace_packages(self.repo)

    def test_same_count_substitution_does_not_pass(self):
        self.write_config(["surprise" if item == "dependency" else item for item in self.names])
        with self.assertRaisesRegex(RuntimeError, "missing=.*dependency.*unexpected=.*surprise"):
            restore.verified_workspace_packages(self.repo)

    def test_duplicate_resolved_name_is_rejected_even_with_exact_name_set(self):
        self.write_config(self.names + ["member"])
        with self.assertRaisesRegex(RuntimeError, "Duplicate resolved package name: member"):
            restore.verified_workspace_packages(self.repo)

    def test_duplicate_manifest_name_is_rejected(self):
        (self.member / "pubspec.yaml").write_text("name: root\n")
        with self.assertRaisesRegex(RuntimeError, "Duplicate workspace package name: root"):
            restore.verified_workspace_packages(self.repo)

    def test_duplicate_normalized_workspace_directory_is_rejected(self):
        self.manifest.write_text(
            "name: root\nworkspace:\n  - packages/member\n  - ./packages/member\n"
        )
        with self.assertRaisesRegex(RuntimeError, "Duplicate workspace member directory"):
            restore.verified_workspace_packages(self.repo)

    def test_member_outside_repository_is_rejected_before_reading(self):
        self.manifest.write_text("name: root\nworkspace:\n  - ../outside\n")
        with self.assertRaisesRegex(RuntimeError, "must remain inside the repository"):
            restore.verified_workspace_packages(self.repo)

    def test_locked_name_cannot_hide_a_workspace_name_collision(self):
        self.lock.write_text("packages:\n  dependency: {}\n  sdk_package: {}\n  member: {}\n")
        with self.assertRaisesRegex(RuntimeError, "both lock and workspace: member"):
            restore.verified_workspace_packages(self.repo)

    def test_missing_or_invalid_manifest_name_is_rejected(self):
        for value in ["dependencies: {}\n", "name: 123\n", "name: ''\n"]:
            with self.subTest(value=value):
                (self.member / "pubspec.yaml").write_text(value)
                with self.assertRaisesRegex(RuntimeError, "Expected a package name"):
                    restore.verified_workspace_packages(self.repo)

    def test_malformed_resolved_entries_are_rejected(self):
        for value in [None, [], {"packages": {}}, {"packages": [None]},
                      {"packages": [{}]}, {"packages": [{"name": 123}]}]:
            with self.subTest(value=value):
                self.config.write_text(json.dumps(value))
                with self.assertRaisesRegex(RuntimeError, "Resolved package"):
                    restore.verified_workspace_packages(self.repo)


if __name__ == "__main__":
    unittest.main(verbosity=2)
