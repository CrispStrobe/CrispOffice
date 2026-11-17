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


class LongProbeGateTests(unittest.TestCase):
    @staticmethod
    def probes():
        return [{"token_count": length,
                 "heads": {name: {"shape": [1, length, width], "minimum_token_cosine": .999,
                                  "raw_argmax_mismatches": 0}
                           for name, width in native.HEAD_WIDTHS.items()}}
                for length in (64, 128, 256)]

    @staticmethod
    def status(gates, unchanged=True):
        return native.qualification_status({
            "cases": [{}], "validation": [{}], "expected_cases": 1, "expected_passes": 1,
            "long_probe_gates": gates, "quality_vs_original": {
                "frozen_probe_nonregression_passed": True, "differences": []},
            "selected_tags_exact": True, "precision_policy_passed": True,
            "precision": "f32", "policy_sources_unchanged_during_run": unchanged})

    def test_all_three_lengths_and_both_heads_are_required_for_final_pass(self):
        gates = native.long_probe_gates(self.probes(), .99)
        self.assertEqual(gates["required_token_counts"], [64, 128, 256])
        self.assertTrue(gates["raw_argmax_exact"])
        self.assertEqual(self.status(gates), (True, True))

    def test_missing_duplicate_extra_and_noninteger_lengths_cannot_complete(self):
        for lengths in ([64, 128], [64, 128, 128], [64, 128, 256, 512],
                        [64, 128, "256"], [64, 128, [256]]):
            probes = self.probes()
            for row, length in zip(probes, lengths):
                row["token_count"] = length
            if len(lengths) < 3:
                probes = probes[:len(lengths)]
            elif len(lengths) > 3:
                probes.append({"token_count": lengths[-1], "heads": {}})
            with self.subTest(lengths=lengths):
                self.assertEqual(self.status(native.long_probe_gates(probes, .99)), (False, False))

    def test_missing_extra_or_wrong_shape_head_cannot_complete(self):
        for change in ("missing", "extra", "wrong_width", "wrong_length"):
            probes = self.probes()
            heads = probes[1]["heads"]
            if change == "missing":
                del heads["logits_d"]
            elif change == "extra":
                heads["hidden"] = heads["logits_d"]
            elif change == "wrong_width":
                heads["logits_labels"]["shape"][-1] -= 1
            else:
                heads["logits_d"]["shape"][1] -= 1
            with self.subTest(change=change):
                self.assertEqual(self.status(native.long_probe_gates(probes, .99)), (False, False))

    def test_one_long_head_failure_blocks_otherwise_passing_short_panel(self):
        for precision_threshold in (.99, .94):
            for index in range(3):
                for head in native.HEAD_WIDTHS:
                    for cosine in (precision_threshold, .5, float("nan"), float("inf"), 1.01, True, None):
                        probes = self.probes()
                        probes[index]["heads"][head]["minimum_token_cosine"] = cosine
                        with self.subTest(threshold=precision_threshold, length=index, head=head, cosine=cosine):
                            gates = native.long_probe_gates(probes, precision_threshold)
                            self.assertEqual(self.status(gates), (True, False))

    def test_raw_argmax_remains_visible_as_a_nongating_long_diagnostic(self):
        probes = self.probes()
        probes[2]["heads"]["logits_labels"]["raw_argmax_mismatches"] = 1
        gates = native.long_probe_gates(probes, .99)
        self.assertFalse(gates["raw_argmax_exact"])
        self.assertEqual(self.status(gates), (True, True))

    def test_changed_policy_cannot_receive_a_final_pass(self):
        self.assertEqual(self.status(native.long_probe_gates(self.probes(), .99), unchanged=False), (True, False))


class BaselineLinkageTests(unittest.TestCase):
    def setUp(self):
        self.sources = {name: "0" * 64 for name in ("qualify_native.py", *native.POLICY_HELPERS)}
        self.build = {"library": {"sha256": "1" * 64, "size_bytes": 50},
                      "source_inventory_sha256": "2" * 64}
        self.parent = {"file": "source-f32.gguf", "sha256": "3" * 64, "size_bytes": 100}
        self.reference = "4" * 64
        self.baseline = {"precision": "f32", "protocol_version": native.PROTOCOL_VERSION,
                         "complete": True, "passed": True, "reference_sha256": self.reference,
                         "build": self.build, "qualification_source_sha256": self.sources,
                         "policy_sources_unchanged_during_run": True, "model": self.parent}

    def test_exact_declared_parent_and_policy_are_admitted(self):
        native.verify_baseline(self.baseline, self.reference, self.build, self.sources, self.parent)

    def test_different_f32_hash_size_or_name_is_not_this_mixed_parent(self):
        for change in ({"sha256": "5" * 64}, {"size_bytes": 101}, {"file": "another-f32.gguf"}):
            baseline = {**self.baseline, "model": {**self.parent, **change}}
            with self.subTest(change=change):
                with self.assertRaisesRegex(ValueError, "exact declared parent GGUF"):
                    native.verify_baseline(baseline, self.reference, self.build, self.sources, self.parent)

    def test_old_incomplete_changed_or_unsealed_policy_is_not_a_baseline(self):
        changes = [{"protocol_version": 1}, {"complete": False}, {"passed": False},
                   {"policy_sources_unchanged_during_run": False}, {"qualification_source_sha256": {}},
                   {"reference_sha256": "5" * 64}, {"precision": "mixed-q4_k"}]
        for name in native.POLICY_HELPERS:
            changes.append({"qualification_source_sha256": {**self.sources, name: "f" * 64}})
        for change in changes:
            with self.subTest(change=change):
                with self.assertRaisesRegex(ValueError, "reference/source/binary/policy"):
                    native.verify_baseline({**self.baseline, **change}, self.reference,
                                           self.build, self.sources, self.parent)

    def test_another_binary_or_source_cannot_serve_as_control(self):
        for change in ({"library": {"sha256": "f" * 64, "size_bytes": 50}},
                       {"source_inventory_sha256": "f" * 64}):
            baseline = {**self.baseline, "build": {**self.build, **change}}
            with self.subTest(change=change):
                with self.assertRaises(ValueError):
                    native.verify_baseline(baseline, self.reference, self.build, self.sources, self.parent)


class PolicySourceTests(unittest.TestCase):
    def test_qualifier_and_every_local_policy_helper_are_hashed(self):
        inventory = native.policy_source_inventory()
        self.assertEqual(set(inventory), {"qualify_native.py", "export_reference.py", "evaluate.py",
                                          "quantize_int4.py", "summarize_qualification.py"})
        original = native.source_inventory_digest(inventory)
        self.assertEqual(original, native.source_inventory_digest(dict(reversed(list(inventory.items())))))
        for name in inventory:
            changed = {**inventory, name: "f" * 64}
            self.assertNotEqual(original, native.source_inventory_digest(changed))

    def test_imported_helper_from_another_directory_is_refused(self):
        for name in native.POLICY_HELPERS[:3]:
            with self.subTest(name=name), patch.dict(native.sys.modules, {
                    name.removesuffix(".py"): SimpleNamespace(__file__="/another-source/" + name)}):
                with self.assertRaisesRegex(ValueError, "outside the declared source directory"):
                    native.policy_source_inventory()

    def test_missing_helper_is_refused(self):
        with patch.dict(native.sys.modules, {"export_reference": SimpleNamespace()}):
            with self.assertRaises(ValueError):
                native.policy_source_inventory()


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
