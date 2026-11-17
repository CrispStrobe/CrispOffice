"""Small source/recipe controls; no real checkpoint or network access."""
from __future__ import annotations

import importlib.util
import hashlib
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest

from quantize_int4 import SOURCE_REVISION, SOURCE_SHA256, find_head, quantize
from summarize_qualification import compare_references, dart_summary, verify_evidence_chain


def node(name, op, inputs, outputs):
    return SimpleNamespace(name=name, op_type=op, input=inputs, output=outputs, domain="")


class HeadContractTests(unittest.TestCase):
    def test_output_topology_selects_the_classifier_not_its_encoder(self):
        encoder = node("encoder", "MatMul", ["x", "encoder_weight"], ["hidden"])
        head = node("arbitrary_exported_name", "MatMul", ["hidden", "head_weight"], ["projected"])
        add = node("bias", "Add", ["projected", "head_bias"], ["logits_labels"])
        graph = SimpleNamespace(node=[encoder, head, add],
                                initializer=[SimpleNamespace(name=x) for x in
                                             ("encoder_weight", "head_weight", "head_bias")])
        self.assertIs(find_head(graph, "logits_labels"), head)

    def test_ambiguous_or_unknown_suffix_is_rejected(self):
        a = node("a", "MatMul", ["x", "w"], ["a_out"])
        b = node("b", "MatMul", ["x", "w"], ["b_out"])
        graph = SimpleNamespace(node=[a, b, node("sum", "Add", ["a_out", "b_out"], ["out"])],
                                initializer=[SimpleNamespace(name="w")])
        with self.assertRaisesRegex(ValueError, "exactly one"):
            find_head(graph, "out")
        graph.node[-1] = node("unknown", "Softmax", ["a_out"], ["out"])
        with self.assertRaisesRegex(ValueError, "Unsupported output suffix"):
            find_head(graph, "out")


class QualityGateTests(unittest.TestCase):
    def test_loss_and_new_clean_edits_are_both_reported(self):
        cases = [{"id": "bad", "kind": "error", "input": "bad", "expected": "fixed"},
                 {"id": "clean", "kind": "clean", "input": "valid"}]
        baseline = {"cases_sha256": "same", "cases": [
            {**cases[0], "corrected": "fixed", "suggestions_utf16": []},
            {**cases[1], "corrected": "valid", "suggestions_utf16": []}]}
        candidate = {"cases_sha256": "same", "cases": [
            {**cases[0], "corrected": "bad", "suggestions_utf16": []},
            {**cases[1], "corrected": "invalid", "suggestions_utf16": []}]}
        result = compare_references(baseline, candidate, cases)
        self.assertEqual(result["lost_baseline_fixes"], ["bad"])
        self.assertEqual(result["new_or_changed_false_edits_on_clean"], ["clean"])
        self.assertFalse(result["frozen_probe_nonregression_passed"])

    def test_incomplete_panel_cannot_pass(self):
        source = [{"id": "x", "kind": "clean", "input": "valid"}]
        with self.assertRaisesRegex(ValueError, "coverage"):
            compare_references({"cases": []}, {"cases": []}, source)


class ExperimentIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.manifest = {
            "schema_version": 1, "kind": "quds-gector-int4-candidate", "status": "passed",
            "source_model_sha256": SOURCE_SHA256,
            "output": {"sha256": "1" * 64, "size_bytes": 128},
        }
        manifest_path = self.root / "candidate" / "candidate.json"
        manifest_path.parent.mkdir()
        manifest_path.write_text(json.dumps(self.manifest))
        self.references, self.reports = {}, {}
        for variant in ("f32", "int4"):
            model_sha = SOURCE_SHA256 if variant == "f32" else self.manifest["output"]["sha256"]
            reference = {
                "revision": SOURCE_REVISION,
                "input_sha256": {"model.onnx": SOURCE_SHA256, "tokenizer.json": "2" * 64},
                "inference_model": {
                    "sha256": model_sha, "source_model_sha256": SOURCE_SHA256,
                    "variant": "float32" if variant == "f32" else "matmulnbits-int4",
                    "size_bytes": 128,
                    "candidate_manifest_sha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
                },
                "cases": [{"id": "synthetic", "passes": [{}]}],
            }
            path = self.root / f"reference-{variant}" / "reference.json"
            path.parent.mkdir()
            path.write_text(json.dumps(reference))
            self.references[variant] = reference
            self.reports[variant] = {
                "complete": True, "model_sha256": model_sha,
                "fixture_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "tokenizer_sha256": "2" * 64,
                "expected_cases": 1, "cases_timed": 1, "expected_passes": 1, "passes_validated": 1,
                "timings": [{}], "validation": [{}],
            }
        self.provenance = {"declared_dart_experiments": {
            "dart-f32": [], "dart-int4": ["narrowDirectGemm"],
        }}

    def verify(self, provenance=None):
        verify_evidence_chain(self.root, self.references["f32"], self.references["int4"],
                              self.manifest, self.reports["f32"], self.reports["int4"],
                              provenance=provenance)

    def test_historical_reports_without_experiment_declarations_remain_valid(self):
        self.verify()
        self.verify({"quds_commit": "historical"})
        self.assertIsNone(dart_summary(self.reports["int4"])["experiments"])

    def test_matching_declared_arms_pass_and_remain_visible_in_measurements(self):
        self.reports["f32"]["experiments"] = []
        self.reports["int4"]["experiments"] = ["narrowDirectGemm"]
        self.verify(self.provenance)
        self.assertEqual(dart_summary(self.reports["f32"])["experiments"], [])
        self.assertEqual(dart_summary(self.reports["int4"])["experiments"], ["narrowDirectGemm"])

    def test_declared_opt_in_rejects_missing_disabled_or_wrong_reported_experiment(self):
        self.reports["f32"]["experiments"] = []
        for reported in (None, [], ["cacheAttributes"]):
            with self.subTest(reported=reported):
                self.reports["int4"].pop("experiments", None)
                if reported is not None:
                    self.reports["int4"]["experiments"] = reported
                with self.assertRaisesRegex(ValueError, "Dart int4 experiment metadata"):
                    self.verify(self.provenance)

    def test_declared_disabled_arm_rejects_missing_or_enabled_metadata(self):
        self.reports["int4"]["experiments"] = ["narrowDirectGemm"]
        for reported in (None, ["narrowDirectGemm"]):
            with self.subTest(reported=reported):
                self.reports["f32"].pop("experiments", None)
                if reported is not None:
                    self.reports["f32"]["experiments"] = reported
                with self.assertRaisesRegex(ValueError, "Dart f32 experiment metadata"):
                    self.verify(self.provenance)

    def test_present_but_malformed_or_incomplete_declarations_fail_closed(self):
        self.reports["f32"]["experiments"] = []
        self.reports["int4"]["experiments"] = ["narrowDirectGemm"]
        for declarations in (None, [], {}, {"dart-f32": []},
                             {"dart-f32": [], "dart-int4": "narrowDirectGemm"}):
            with self.subTest(declarations=declarations):
                with self.assertRaisesRegex(ValueError, "[Dd]eclared.*experiments"):
                    self.verify({"declared_dart_experiments": declarations})


@unittest.skipUnless(importlib.util.find_spec("onnx") and importlib.util.find_spec("onnxruntime"),
                     "Install qualification requirements for the tiny converter control")
class TinyConverterTests(unittest.TestCase):
    def test_real_quantizer_preserves_both_head_matrices(self):
        import numpy as np
        import onnx

        rng = np.random.default_rng(9)
        tensors = [onnx.numpy_helper.from_array(rng.normal(0, 0.1, shape).astype(np.float32), name)
                   for name, shape in (("enc_w", (128, 128)), ("labels_w", (128, 5000)),
                                       ("detect_w", (128, 2)))]
        nodes = [onnx.helper.make_node("MatMul", ["x", "enc_w"], ["h"], name="encoder"),
                 onnx.helper.make_node("MatMul", ["h", "labels_w"], ["logits_labels"], name="labels"),
                 onnx.helper.make_node("MatMul", ["h", "detect_w"], ["logits_d"], name="detect")]
        graph = onnx.helper.make_graph(nodes, "tiny-dual-head", [
            onnx.helper.make_tensor_value_info("x", onnx.TensorProto.FLOAT, [1, 2, 128])], [
            onnx.helper.make_tensor_value_info("logits_labels", onnx.TensorProto.FLOAT, [1, 2, 5000]),
            onnx.helper.make_tensor_value_info("logits_d", onnx.TensorProto.FLOAT, [1, 2, 2])], tensors)
        model = onnx.helper.make_model(graph, opset_imports=[onnx.helper.make_opsetid("", 17)])
        report = {"recipe": {}}
        result = quantize(model, report)
        self.assertEqual(report["quantized_node_count"], 1)
        self.assertEqual({x["node"] for x in report["recipe"]["excluded_heads"]}, {"labels", "detect"})
        self.assertEqual(sum(n.op_type == "MatMulNBits" for n in result.graph.node), 1)


if __name__ == "__main__":
    unittest.main()
