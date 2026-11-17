"""Small source/recipe controls; no real checkpoint or network access."""
from __future__ import annotations

import importlib.util
from types import SimpleNamespace
import unittest

from quantize_int4 import find_head, quantize
from summarize_qualification import compare_references


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
