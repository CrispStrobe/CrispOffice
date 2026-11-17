"""Bounded native evidence controls; no real checkpoint or network required."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import numpy as np

import qualify_native as native


class NumericalEvidenceTests(unittest.TestCase):
    def test_identical_vectors_and_zero_vectors_are_defined(self):
        for array in (np.zeros((1, 2, 3), dtype=np.float32), np.arange(6, dtype=np.float32).reshape(1, 2, 3)):
            result = native.numeric_comparison(array, array.copy())
            self.assertAlmostEqual(result["cosine"], 1)
            self.assertAlmostEqual(result["minimum_token_cosine"], 1)
            self.assertEqual(result["maximum_absolute_error"], 0)
            self.assertEqual(result["raw_argmax_mismatches"], 0)

    def test_one_bad_token_cannot_hide_in_flat_cosine(self):
        baseline = np.array([[[1000, 0], [0, 1]]], dtype=np.float32)
        candidate = np.array([[[1000, 0], [0, -1]]], dtype=np.float32)
        result = native.numeric_comparison(candidate, baseline)
        self.assertGreater(result["cosine"], .99)
        self.assertEqual(result["minimum_token_cosine"], -1)
        self.assertEqual(result["raw_argmax_mismatches"], 1)
        self.assertFalse(result["strict_absolute_diagnostic_passed"])

    def test_zero_against_nonzero_does_not_pass(self):
        result = native.numeric_comparison(np.zeros((1, 1, 2)), np.ones((1, 1, 2)))
        self.assertEqual(result["cosine"], 0)
        self.assertEqual(result["minimum_token_cosine"], 0)

    def test_shape_and_nonfinite_failures_do_not_become_numeric_passes(self):
        baseline = np.ones((1, 2, 3), dtype=np.float32)
        for candidate in (np.ones((2, 3)), np.ones((1, 2, 2)), np.full((1, 2, 3), np.nan)):
            with self.subTest(shape=candidate.shape):
                with self.assertRaises(ValueError):
                    native.numeric_comparison(candidate, baseline)

    def test_absolute_diagnostic_is_retained_even_when_cosine_is_high(self):
        baseline = np.array([[[1, 2, 3]]], dtype=np.float32)
        result = native.numeric_comparison(baseline + .01, baseline)
        self.assertGreater(result["cosine"], .99)
        self.assertFalse(result["strict_absolute_diagnostic_passed"])
        self.assertEqual(native.STRICT_ABSOLUTE_DIAGNOSTIC, .002)


class DecisionEvidenceTests(unittest.TestCase):
    def setUp(self):
        labels = np.zeros((1, 3, 5000), dtype=np.float32)
        labels[:, :, 1] = 12
        self.outputs = {"logits_labels": labels,
                        "logits_d": np.array([[[0, 12], [0, 12], [0, 12]]], dtype=np.float32)}
        self.decoder = {"keep_label_id": 0, "incorrect_label_id": 1,
                        "keep_confidence": 0.0, "min_error_prob": 0.0}

    def test_selects_only_first_subwords_including_cls(self):
        self.assertEqual(native.first_subwords([None, 0, 0, 1, None]), [0, 1, 3])
        selected = native.selection(self.outputs, [0, 2], self.decoder)
        self.assertEqual(selected["label_ids"], [1, 1])
        self.assertEqual(selected["thresholded_label_ids"], [1, 1])

    def test_keep_bonus_matches_upstream_policy(self):
        self.decoder["keep_confidence"] = 1
        self.assertEqual(native.selection(self.outputs, [0, 1], self.decoder)["label_ids"], [0, 0])

    def test_label_threshold_is_applied_before_sentence_detection(self):
        self.decoder["min_error_prob"] = .999999
        selected = native.selection(self.outputs, [0, 1], self.decoder)
        self.assertEqual(selected["label_ids"], [1, 1])
        self.assertEqual(selected["thresholded_label_ids"], [0, 0])

    def test_low_sentence_detection_suppresses_edits(self):
        self.decoder["min_error_prob"] = .5
        self.outputs["logits_d"] *= -1
        self.assertEqual(native.selection(self.outputs, [0, 1], self.decoder)["thresholded_label_ids"], [0, 0])

    def test_invalid_indices_and_heads_fail_closed(self):
        for indices in ([], [1], [0, 0], [0, 3], [0, 2, 1]):
            with self.subTest(indices=indices):
                with self.assertRaises(ValueError):
                    native.selection(self.outputs, indices, self.decoder)
        self.outputs["logits_d"][0, 0, 0] = np.nan
        with self.assertRaises(ValueError):
            native.selection(self.outputs, [0, 1], self.decoder)


class RecipeTests(unittest.TestCase):
    def test_complete_tensor_census_and_precise_mixed_recipe(self):
        shapes = native.expected_tensor_shapes()
        self.assertEqual(len(shapes), 201)
        counts = native.Counter(native.expected_tensor_type(name, "mixed-q4_k") for name in shapes)
        self.assertEqual(counts, {"Q4_K": 72, "Q8_0": 1, "F16": 3, "F32": 125})
        self.assertEqual(shapes["enc.3.ffn.fc1.weight"], [768, 3072])
        self.assertEqual(shapes["enc.3.ffn.fc2.weight"], [3072, 768])
        for name in shapes:
            self.assertEqual(native.expected_tensor_type(name, "f32"), "F32")

    def test_norm_bias_type_tables_remain_source_precision(self):
        for name in ("enc.0.attn.q.bias", "enc.0.ln1.weight", "gector.labels.bias", "token_type_embd.weight"):
            self.assertEqual(native.expected_tensor_type(name, "mixed-q4_k"), "F32")

    def test_recipe_has_explicit_protection_and_no_q4_0_fallback(self):
        self.assertEqual(native.RECIPE["overrides"][0], "*=f32")
        self.assertIn("gector.*.weight=f16", native.RECIPE["overrides"])
        self.assertNotIn("q4_0", json.dumps(native.RECIPE).lower())


class PayloadTests(unittest.TestCase):
    def setUp(self):
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.array = np.arange(6, dtype=np.float32).reshape(1, 2, 3)
        self.record = native.save_payload(self.root, "head.f32le", self.array)

    def test_actual_byte_roundtrip_is_verified(self):
        np.testing.assert_array_equal(native.checked_payload(self.root, self.record), self.array)

    def test_changed_or_truncated_bytes_cannot_be_used(self):
        path = self.root / self.record["file"]
        path.write_bytes(path.read_bytes()[:-1])
        with self.assertRaisesRegex(ValueError, "Changed or truncated"):
            native.checked_payload(self.root, self.record)

    def test_tensor_metadata_is_checked(self):
        for changed in ({"file": "../head.f32le"}, {"shape": [1, 2, 4]}, {"byte_order": "big"},
                        {"dtype": "float16"}, {"layout": "column-major"}, {"sha256": "0" * 64}):
            with self.subTest(changed=changed):
                with self.assertRaises(ValueError):
                    native.checked_payload(self.root, {**self.record, **changed})

    def test_duplicate_or_nonfinite_payloads_are_never_written(self):
        with self.assertRaises(ValueError):
            native.save_payload(self.root, "head.f32le", self.array)
        with self.assertRaises(ValueError):
            native.save_payload(self.root, "bad.f32le", np.full((1, 1, 2), np.inf))
        self.assertFalse((self.root / "bad.f32le").exists())


class BuildAuthenticationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        names = ["src/gector.cpp", "src/gector.h", "src/core/gguf_loader.cpp"]
        for name in names:
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("test source " + name)
        self.library = self.root / "native.so"
        self.library.write_bytes(b"test-only library bytes")
        inventory = {name: native.digest(self.source / name) for name in names}
        self.receipt = self.root / "build.json"
        self.record = {"schema": "quds.gector.native-build.v1", "portable": True,
                       "ggml_revision": native.GGML_REVISION, "source_sha256": inventory,
                       "source_inventory_sha256": hashlib.sha256(json.dumps(inventory, sort_keys=True).encode()).hexdigest(),
                       "library": {"size_bytes": self.library.stat().st_size, "sha256": native.digest(self.library)}}
        self.write_record()

    def write_record(self):
        self.receipt.write_text(json.dumps(self.record))

    def test_source_and_binary_receipt_is_verified(self):
        self.assertEqual(native.verify_build(self.receipt, self.source, self.library), self.record)

    def test_native_source_change_invalidates_build_receipt(self):
        (self.source / "src/gector.cpp").write_text("modified")
        with self.assertRaisesRegex(ValueError, "source changed"):
            native.verify_build(self.receipt, self.source, self.library)

    def test_binary_change_invalidates_build_receipt(self):
        self.library.write_bytes(b"different")
        with self.assertRaisesRegex(ValueError, "library differs"):
            native.verify_build(self.receipt, self.source, self.library)

    def test_nonportable_unpinned_or_incomplete_build_is_refused(self):
        for change in ({"portable": False}, {"ggml_revision": "changed"}, {"source_sha256": {}},
                       {"source_inventory_sha256": "0" * 64}):
            self.receipt.write_text(json.dumps({**self.record, **change}))
            with self.subTest(change=change):
                with self.assertRaises(ValueError):
                    native.verify_build(self.receipt, self.source, self.library)


class NativeInputAdapterTests(unittest.TestCase):
    @staticmethod
    def fake_library(context=123):
        def create(*_args):
            return context
        def free(*_args):
            return None
        def forward(*_args):
            return 0
        def forward_trace(*_args):
            return 0
        return SimpleNamespace(crispembed_gector_create=create, crispembed_gector_free=free,
                               crispembed_gector_forward=forward, crispembed_gector_forward_trace=forward_trace)

    def test_gate_stays_enabled_for_entire_session_then_restores(self):
        with patch.dict(os.environ, {"CRISPEMBED_GECTOR": "0"}), patch.object(native.C, "CDLL", return_value=self.fake_library()):
            session = native.NativeSession(Path("unused.so"), Path("unused.gguf"), 2)
            self.assertEqual(os.environ["CRISPEMBED_GECTOR"], "1")
            session.close()
            self.assertEqual(os.environ["CRISPEMBED_GECTOR"], "0")

    def test_failed_create_restores_gate(self):
        with patch.dict(os.environ, {"CRISPEMBED_GECTOR": "false"}), patch.object(native.C, "CDLL", return_value=self.fake_library(None)):
            with self.assertRaises(RuntimeError):
                native.NativeSession(Path("unused.so"), Path("unused.gguf"), 2)
            self.assertEqual(os.environ["CRISPEMBED_GECTOR"], "false")

    def test_wrong_dtype_shape_padding_and_range_fail_before_ffi(self):
        session = native.NativeSession.__new__(native.NativeSession)
        valid = np.array([[3, 7]], dtype=np.int64)
        inputs = [
            {"input_ids": valid.astype(np.int32), "attention_mask": np.ones_like(valid)},
            {"input_ids": valid[0], "attention_mask": np.ones_like(valid[0])},
            {"input_ids": valid, "attention_mask": np.array([[1, 0]], dtype=np.int64)},
            {"input_ids": np.array([[31102]], dtype=np.int64), "attention_mask": np.ones((1, 1), dtype=np.int64)},
            {"input_ids": np.array([[-1]], dtype=np.int64), "attention_mask": np.ones((1, 1), dtype=np.int64)},
            {"input_ids": np.ones((1, 513), dtype=np.int64), "attention_mask": np.ones((1, 513), dtype=np.int64)},
        ]
        for values in inputs:
            with self.subTest(shape=values["input_ids"].shape):
                with self.assertRaises(ValueError):
                    session.forward(values)

    def test_incomplete_or_reordered_heads_are_refused(self):
        session = native.NativeSession.__new__(native.NativeSession)
        for names in (["logits_labels"], ["logits_d", "logits_labels"], None):
            with self.assertRaises(ValueError):
                session.run(names, {})


if __name__ == "__main__":
    unittest.main()
