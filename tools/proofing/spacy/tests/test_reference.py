"""Model-free controls: checked-in oracle fixtures are required, never skipped."""

import copy
import hashlib
import json
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
from export_reference import coordinate_maps, extract_verified_model, json_bytes, load_cases
from verify_reference import read_json, safe_path, verify

CASES = TOOLS / "fixtures/cases.json"
REFERENCE = TOOLS / "fixtures/development"


class InputContractTests(unittest.TestCase):
    def mutate_cases(self, mutate):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "cases.json"
            data = json.loads(CASES.read_text(encoding="utf-8"))
            mutate(data)
            path.write_bytes(json_bytes(data))
            with self.assertRaises(ValueError):
                load_cases(path, "development")

    def test_original_scalar_boundaries(self):
        byte, utf16 = coordinate_maps("A😀e\u0301\x00")
        self.assertEqual(byte, [0, 1, 5, 6, 8, 9])
        self.assertEqual(utf16, [0, 1, 3, 4, 5, 6])

    def test_lone_surrogate_rejected(self):
        with self.assertRaises(UnicodeEncodeError):
            coordinate_maps("bad\ud800text")

    def test_duplicate_id_rejected(self):
        self.mutate_cases(lambda data: data["acceptance"][0].update(id=data["development"][0]["id"]))

    def test_cross_split_reuse_rejected(self):
        self.mutate_cases(lambda data: data["acceptance"][0].update(text=data["development"][1]["text"]))

    def test_empty_fixture_set_rejected(self):
        self.mutate_cases(lambda data: data.update(development=[]))

    def test_case_path_escape_rejected(self):
        self.mutate_cases(lambda data: data["development"][0].update(id="../../payload"))

    def test_missing_and_wrong_model_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaisesRegex(ValueError, "missing"):
                extract_verified_model(root / "missing.whl", root / "model")
            bad = root / "bad.whl"
            bad.write_bytes(b"untrusted")
            with self.assertRaisesRegex(ValueError, "size or SHA"):
                extract_verified_model(bad, root / "model")

    def test_duplicate_json_key_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "duplicate.json"
            path.write_text('{"complete": false, "complete": true}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Duplicate"):
                read_json(path)

    def test_symlink_escape_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "escape").symlink_to(root.parent, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "symlink"):
                safe_path(root, "escape/payload")


class FrozenReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Deliberately fail if fixtures were not committed/downloaded correctly.
        cls.validated = verify(REFERENCE, CASES)

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "reference"
        shutil.copytree(REFERENCE, self.root)

    def tearDown(self):
        self.temporary.cleanup()

    def update_case(self, mutate, *, ident="single"):
        path = self.root / ident / "case.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        mutate(data)
        path.write_bytes(json_bytes(data))
        self.rehash_member(f"{ident}/case.json")

    def rehash_member(self, path):
        manifest_path = self.root / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        payload = (self.root / path).read_bytes()
        for case in manifest["cases"]:
            for member in case["files"]:
                if member["path"] == path:
                    member.update(size_bytes=len(payload), sha256=hashlib.sha256(payload).hexdigest())
        manifest_path.write_bytes(json_bytes(manifest))

    def test_real_reference_denominators(self):
        self.assertEqual(self.validated["cases"], 16)
        self.assertEqual(self.validated["tokens"], 113)
        self.assertEqual(self.validated["parser_steps"], 244)
        self.assertEqual(self.validated["trace_stages"], 1201)

    def test_missing_numeric_payload_is_failure(self):
        (self.root / "single/traces.f32").unlink()
        with self.assertRaisesRegex(ValueError, "missing"):
            verify(self.root, CASES)

    def test_same_size_corruption_is_failure(self):
        path = self.root / "single/traces.f32"
        payload = bytearray(path.read_bytes())
        payload[0] ^= 1
        path.write_bytes(payload)
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            verify(self.root, CASES)

    def test_missing_stage_cannot_be_rehashed_into_success(self):
        self.update_case(lambda case: case["traces"].pop("tok2vec.encoder.layer.2.residual"))
        with self.assertRaisesRegex(ValueError, "stage inventory"):
            verify(self.root, CASES)

    def test_wrong_utf16_span_is_failure(self):
        self.update_case(lambda case: case["annotations"]["tokens"][0].update(end_utf16=4))
        with self.assertRaisesRegex(ValueError, "UTF-16"):
            verify(self.root, CASES)

    def test_nonfinite_rehashed_trace_is_failure(self):
        path = self.root / "single/traces.f32"
        payload = bytearray(path.read_bytes())
        payload[0:4] = struct.pack("<f", float("nan"))
        path.write_bytes(payload)
        self.rehash_member("single/traces.f32")
        def mutate(case):
            for descriptor in case["traces"].values():
                if descriptor["offset_bytes"] == 0 and descriptor["size_bytes"]:
                    descriptor["sha256"] = hashlib.sha256(payload[:descriptor["size_bytes"]]).hexdigest()
        self.update_case(mutate)
        with self.assertRaisesRegex(ValueError, "Nonfinite"):
            verify(self.root, CASES)

    def test_missing_notices_is_failure(self):
        (self.root / "LICENSES_SOURCES").unlink()
        with self.assertRaisesRegex(ValueError, "missing"):
            verify(self.root, CASES)

    def test_unexpected_payload_is_failure(self):
        (self.root / "extra.bin").write_bytes(b"not in inventory")
        with self.assertRaisesRegex(ValueError, "unexpected"):
            verify(self.root, CASES)


if __name__ == "__main__":
    unittest.main()
