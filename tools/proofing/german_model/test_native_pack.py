"""Offline pack controls with tiny explicitly trusted synthetic payloads."""

from dataclasses import replace
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import build_native_pack as pack


class Fixture:
    """Test-only trust injection; production has no pin or evidence override."""

    def __init__(self, root):
        self.root = root
        self.bundle = root / "bundle"
        self.native = root / "install"
        self.evidence = root / "evidence"
        for path in (self.bundle, self.native, self.evidence):
            path.mkdir()
        self.model = root / "candidate.gguf"
        model_pin = self.write(self.model, b"tiny synthetic model")
        library_pin = self.write(self.native / "lib/library.so", b"tiny synthetic library")
        model_directory = f"model/{model_pin.sha256}"
        library_path = f"native/{library_pin.sha256}/library.so"
        entries = [
            pack.Entry(f"{model_directory}/model.gguf", model_pin, "model", ""),
            pack.Entry(library_path, library_pin, "native", "lib/library.so"),
        ]
        for name in ("LICENSE", "NOTICE", "README.md", "quickstart.py", "gector-meta.json",
                     "config.json", "gector-guards.json", "language-rules.json",
                     "tokenizer_config.json", "tokenizer.json", "vocab.txt", "verb-form-vocab.txt"):
            pin = self.write(self.bundle / name, f"synthetic {name}".encode())
            entries.append(pack.Entry(f"{model_directory}/{name}", pin, "bundle", name))
        for name in ("include/gector.h", "share/licenses/LICENSE", "share/licenses/THIRD_PARTY_NOTICES"):
            pin = self.write(self.native / name, f"synthetic {name}".encode())
            entries.append(pack.Entry(f"native/{name}", pin, "native", name))
        pin = self.write(self.evidence / "receipt.json", b'{"synthetic": true}\n')
        entries.append(pack.Entry("evidence/receipt.json", pin, "evidence", "receipt.json"))
        self.policy = pack.Policy(tuple(entries), {
            "schema": "synthetic-test-only", "scope": "local-development-only",
            "model": {"directory": model_directory, "sha256": model_pin.sha256},
            "native": {"path": library_path, "sha256": library_pin.sha256},
        }, self.evidence)
        self.output = root / "pack"

    @staticmethod
    def write(path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return pack.Pin(len(data), hashlib.sha256(data).hexdigest())

    def build(self, *, output=None, policy=None):
        return pack._build_pack(self.model, self.bundle, self.native, output or self.output, policy or self.policy)


class NativePackTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.fixture = Fixture(self.root)

    def tearDown(self):
        for current, directories, files in os.walk(self.root):
            os.chmod(current, 0o700)
        self.temporary.cleanup()

    def test_production_policy_binds_archived_qualification_and_twelve_sidecars(self):
        policy = pack._policy()
        self.assertEqual(len([entry for entry in policy.entries if entry.source_kind == "bundle"]), 12)
        self.assertEqual(policy.metadata["model"]["sha256"], pack._MODEL_PIN.sha256)
        self.assertEqual(policy.metadata["native"]["sha256"], pack._LIBRARY_PIN.sha256)
        self.assertEqual(policy.metadata["scope"], "local-development-only")
        self.assertIn("native/include/gector.h", {entry.path for entry in policy.entries})

    def test_reproducible_pack_verifies_actual_total_and_content_addressed_paths(self):
        first = self.fixture.build()
        second = self.fixture.build(output=self.root / "second")
        self.assertEqual(first["manifest_sha256"], second["manifest_sha256"])
        actual_size = sum(path.stat().st_size for path in self.fixture.output.rglob("*") if path.is_file())
        self.assertEqual(first["sizes"]["total_bytes"], actual_size)
        self.assertEqual(Path(first["library"]).parent.name, first["library_sha256"])
        self.assertEqual(Path(first["model_directory"]).name, first["model"]["sha256"])
        self.assertTrue(pack._verify_pack(self.fixture.output, self.fixture.policy)["verified"])

    def test_wrong_model_sidecar_library_license_or_receipt_never_publishes(self):
        for path in (self.fixture.model, self.fixture.bundle / "vocab.txt",
                     self.fixture.native / "lib/library.so", self.fixture.native / "share/licenses/LICENSE",
                     self.fixture.evidence / "receipt.json"):
            with self.subTest(source=path.name):
                original = path.read_bytes()
                path.write_bytes(original + b"changed")
                with self.assertRaisesRegex(pack.PackError, "mismatch"):
                    self.fixture.build()
                self.assertFalse(self.fixture.output.exists())
                path.write_bytes(original)

    def test_existing_output_and_overlapping_directories_are_not_modified(self):
        self.fixture.output.mkdir()
        sentinel = self.fixture.output / "owned.txt"
        sentinel.write_text("keep")
        with self.assertRaises(pack.PackError):
            self.fixture.build()
        self.assertEqual(sentinel.read_text(), "keep")
        for root in (self.fixture.bundle, self.fixture.native, self.fixture.evidence):
            with self.subTest(root=root.name), self.assertRaises(pack.PackError):
                self.fixture.build(output=root / "new-pack")
            self.assertFalse((root / "new-pack").exists())

    def test_symlinked_input_file_or_ancestor_is_rejected(self):
        link = self.root / "linked.gguf"
        link.symlink_to(self.fixture.model)
        with self.assertRaisesRegex(pack.PackError, "Symlink"):
            pack._build_pack(link, self.fixture.bundle, self.fixture.native, self.fixture.output, self.fixture.policy)
        directory_link = self.root / "linked-bundle"
        directory_link.symlink_to(self.fixture.bundle, target_is_directory=True)
        with self.assertRaisesRegex(pack.PackError, "Symlink"):
            pack._build_pack(self.fixture.model, directory_link, self.fixture.native, self.fixture.output, self.fixture.policy)

    def test_traversal_duplicate_and_source_traversal_destinations_are_rejected(self):
        first = self.fixture.policy.entries[0]
        invalid_entries = [
            (*self.fixture.policy.entries, first),
            (replace(first, path="../escaped"),),
            (replace(first, path="/absolute"),),
            (replace(first, path="safe\\escape"),),
            (replace(first, source_name="../model.gguf"),),
        ]
        for entries in invalid_entries:
            with self.subTest(entries=entries), self.assertRaises(pack.PackError):
                self.fixture.build(policy=replace(self.fixture.policy, entries=entries))
        self.assertFalse(self.fixture.output.exists())

    def test_copy_corruption_cleans_only_private_staging(self):
        with patch.object(pack.shutil, "copyfileobj", side_effect=lambda source, target, count: target.write(b"wrong copy")):
            with self.assertRaisesRegex(pack.PackError, "mismatch"):
                self.fixture.build()
        self.assertFalse(self.fixture.output.exists())
        self.assertEqual(list(self.root.glob(".pack.stage-*")), [])
        self.assertEqual(self.fixture.model.read_bytes(), b"tiny synthetic model")

    def test_atomic_publish_cannot_replace_a_racing_empty_directory(self):
        original_publish = pack._publish_new

        def occupied(stage, output):
            output.mkdir()
            original_publish(stage, output)

        with patch.object(pack, "_publish_new", side_effect=occupied):
            with self.assertRaises(FileExistsError):
                self.fixture.build()
        self.assertTrue(self.fixture.output.is_dir())
        self.assertEqual(list(self.fixture.output.iterdir()), [])
        self.assertEqual(list(self.root.glob(".pack.stage-*")), [])

    def test_tampered_pack_payload_is_rejected_even_when_manifest_is_unchanged(self):
        receipt = self.fixture.build()
        library = Path(receipt["library"])
        library.chmod(0o644)
        library.write_bytes(b"not the pinned native library")
        library.chmod(0o444)
        with self.assertRaisesRegex(pack.PackError, "mismatch"):
            pack._verify_pack(self.fixture.output, self.fixture.policy)

    def test_self_declared_model_pins_and_duplicate_json_keys_are_not_trusted(self):
        self.fixture.build()
        manifest = self.fixture.output / "pack.json"
        original = manifest.read_bytes()
        changed = json.loads(original)
        changed["model"]["sha256"] = "0" * 64
        variants = [pack._encode(changed), original[:-2] + b',"scope":"local-development-only"}\n']
        changed = json.loads(original)
        changed["files"][0]["path"] = "../outside"
        variants.append(pack._encode(changed))
        for data in variants:
            with self.subTest(manifest=data[:30]):
                manifest.chmod(0o644)
                manifest.write_bytes(data)
                manifest.chmod(0o444)
                with self.assertRaises(pack.PackError):
                    pack._verify_pack(self.fixture.output, self.fixture.policy)

    def test_extra_files_symlinks_and_writable_outputs_are_rejected(self):
        self.fixture.build()
        output = self.fixture.output
        output.chmod(0o755)
        extra = output / "extra"
        extra.write_bytes(b"unrecorded")
        extra.chmod(0o444)
        output.chmod(0o555)
        with self.assertRaisesRegex(pack.PackError, "unexpected files"):
            pack._verify_pack(output, self.fixture.policy)
        output.chmod(0o755)
        extra.unlink()
        extra.symlink_to(self.fixture.model)
        output.chmod(0o555)
        with self.assertRaises(pack.PackError):
            pack._verify_pack(output, self.fixture.policy)
        output.chmod(0o755)
        extra.unlink()
        with self.assertRaisesRegex(pack.PackError, "writable"):
            pack._verify_pack(output, self.fixture.policy)


if __name__ == "__main__":
    unittest.main()
