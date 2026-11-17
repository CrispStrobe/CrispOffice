"""Small integrity/alignment tests; no network, model download, or inference."""
from __future__ import annotations

import hashlib
import importlib.util
import io
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import numpy as np

SPEC = importlib.util.spec_from_file_location("export_reference", Path(__file__).with_name("export_reference.py"))
export = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(export)
REVISION = "8e3b50beef7d775cedb7b876009e88bcf2e8d6af"


def softmax(value):
    exp = np.exp(value - value.max(axis=-1, keepdims=True))
    return exp / exp.sum(axis=-1, keepdims=True)


class ExportReferenceTests(unittest.TestCase):
    def make_bundle(self, root):
        evaluation, model = root / "eval", root / "model"
        (evaluation / "vendor").mkdir(parents=True)
        model.mkdir()
        (evaluation / "evaluate.py").write_text(
            "import hashlib\n"
            f"REVISION = {REVISION!r}\n"
            "def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()\n"
        )
        payloads = {"model.onnx": b"test-only-model", "quickstart.py": b"# test-only runner\n"}
        manifest = []
        for filename, data in payloads.items():
            (model / filename).write_bytes(data)
            manifest.append({"file": filename,
                             "url": f"https://huggingface.co/proofbird/gector-bert-de/resolve/{REVISION}/{filename}",
                             "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)})
        (evaluation / "vendor" / "quickstart.py").write_bytes(payloads["quickstart.py"])
        (evaluation / "artifacts.json").write_text(json.dumps(manifest))
        return evaluation, model, manifest, payloads

    def test_utf16_offsets_preserve_supplementary_and_combining_characters(self):
        text = "😀a\u0308b"
        self.assertEqual([export.utf16_offset(text, x) for x in range(5)], [0, 2, 3, 4, 5])

    def test_first_subword_alignment_keeps_cls_and_skips_sep(self):
        encoding = SimpleNamespace(
            word_ids=[None, 0, 0, 1, None], tokens=["[CLS]", "Ha", "##us", "ist", "[SEP]"],
            offsets=[(0, 0), (0, 2), (2, 4), (0, 3), (0, 0)],
        )
        calls, traces = [], []

        def encode(words, **kwargs):
            calls.append((words, kwargs))
            return encoding

        wrapped = export.TraceTokenizer(SimpleNamespace(encode=encode), traces)
        self.assertIs(wrapped.encode(["Haus", "ist"], is_pretokenized=True), encoding)
        self.assertEqual(calls, [(["Haus", "ist"], {"is_pretokenized": True})])
        self.assertEqual(traces[0]["first_subword_indices"], [0, 1, 3])
        self.assertEqual(traces[0]["words"], ["Haus", "ist"])

    def test_bundle_fails_closed_for_changed_or_unpinned_input(self):
        with TemporaryDirectory() as temporary:
            evaluation, model, manifest, _ = self.make_bundle(Path(temporary))
            self.assertEqual(export.verify_bundle(evaluation, model)[1], REVISION)
            (model / "model.onnx").write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "Missing or changed"):
                export.verify_bundle(evaluation, model)
            manifest[0]["url"] = manifest[0]["url"].replace(REVISION, "main")
            (evaluation / "artifacts.json").write_text(json.dumps(manifest))
            with patch.object(export.urllib.request, "urlopen") as fetch:
                with self.assertRaisesRegex(ValueError, "not pinned"):
                    export.verify_bundle(evaluation, model, download=True)
                fetch.assert_not_called()

    def test_changed_vendor_is_not_silently_accepted(self):
        with TemporaryDirectory() as temporary:
            evaluation, model, _, _ = self.make_bundle(Path(temporary))
            (evaluation / "vendor" / "quickstart.py").write_text("# altered\n")
            with self.assertRaisesRegex(ValueError, "vendored runner differs"):
                export.verify_bundle(evaluation, model)

    def test_download_publishes_only_verified_bytes_and_cleans_partial_files(self):
        with TemporaryDirectory() as temporary:
            evaluation, model, _, payloads = self.make_bundle(Path(temporary))
            target = model / "model.onnx"
            target.unlink()
            with patch.object(export.urllib.request, "urlopen", return_value=io.BytesIO(b"wrong")):
                with self.assertRaisesRegex(ValueError, "failed integrity"):
                    export.verify_bundle(evaluation, model, download=True)
            self.assertFalse(target.exists())
            self.assertFalse(list(model.glob("*.download")))
            with patch.object(export.urllib.request, "urlopen", return_value=io.BytesIO(payloads["model.onnx"])):
                export.verify_bundle(evaluation, model, download=True)
            self.assertEqual(target.read_bytes(), payloads["model.onnx"])

    def test_capture_is_little_endian_unmodified_and_obeys_decoder_thresholds(self):
        labels = np.array([[[2.0, 1.0, 0.0], [0.0, 1.0, 2.0], [9.0, 0.0, 0.0]]], dtype=np.float32)
        detection = np.array([[[0.0, 1.0], [0.0, 2.0], [0.0, 0.0]]], dtype=np.float32)
        original_labels = labels.copy()
        inputs = {"input_ids": np.array([[101, 1024, 102]], dtype=np.int64),
                  "attention_mask": np.ones((1, 3), dtype=np.int64)}
        returned = [labels, detection]

        def run(names, passed_inputs):
            self.assertEqual(names, ["logits_labels", "logits_d"])
            self.assertIs(passed_inputs, inputs)
            return returned

        model = SimpleNamespace(keep=0, incorrect=1, labels=["$KEEP", "$DELETE", "$REPLACE_ist"],
                                keep_confidence=0.0, min_error_prob=0.8)
        traces = [{"first_subword_indices": [0, 1]}]
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            wrapped = export.TraceSession(SimpleNamespace(run=run), traces, directory, "test-case", model, softmax)
            self.assertIs(wrapped.run(["logits_labels", "logits_d"], inputs), returned)
            np.testing.assert_array_equal(labels, original_labels)
            trace = traces[0]
            self.assertEqual(trace["selected"]["label_ids"], [0, 2])
            # Each label probability is below 0.8, while sentence detection is above it.
            self.assertEqual(trace["selected"]["labels"], ["$KEEP", "$KEEP"])
            self.assertEqual(trace["selected"]["thresholded_label_ids"], [0, 0])
            self.assertGreater(trace["selected"]["sentence_incorrect_probability"], 0.8)
            self.assertEqual(trace["input_ids"], [[101, 1024, 102]])
            for name, expected in zip(["logits_labels", "logits_d"], returned):
                metadata = trace["outputs"][name]
                saved = (directory / metadata["file"]).read_bytes()
                self.assertEqual(metadata["shape"], list(expected.shape))
                self.assertEqual(metadata["sha256"], hashlib.sha256(saved).hexdigest())
                self.assertEqual(saved, expected.astype("<f4").tobytes(order="C"))

    def test_percentile_uses_nearest_rank(self):
        result = export.summary([float(x) for x in range(1, 21)])
        self.assertEqual(result["median_seconds"], 10.5)
        self.assertEqual(result["p95_seconds"], 19.0)

    def test_session_budget_and_model_override_leave_runtime_module_unchanged(self):
        calls = []

        def create_session(path, **kwargs):
            calls.append((path, kwargs))
            return "captured-session"

        runtime = SimpleNamespace(SessionOptions=SimpleNamespace,
                                  ExecutionMode=SimpleNamespace(ORT_SEQUENTIAL="sequential"),
                                  InferenceSession=create_session)
        module = SimpleNamespace(ort=runtime)

        def gector(model):
            self.assertEqual(model, "/bundle")
            return module.ort.InferenceSession("/bundle/model.onnx", providers=["CPUExecutionProvider"])

        module.Gector = gector
        result = export.create_reference_model(module, Path("/bundle"), Path("/candidate/model.onnx"), 2)
        self.assertEqual(result, "captured-session")
        self.assertIs(module.ort, runtime)
        self.assertIs(runtime.InferenceSession, create_session)
        self.assertEqual(calls[0][0], "/candidate/model.onnx")
        options = calls[0][1]["sess_options"]
        self.assertEqual((options.intra_op_num_threads, options.inter_op_num_threads, options.execution_mode),
                         (2, 1, "sequential"))

        def fail(**kwargs):
            raise RuntimeError("simulated load failure")

        module.Gector = fail
        with self.assertRaisesRegex(RuntimeError, "simulated"):
            export.create_reference_model(module, Path("/bundle"), Path("/candidate/model.onnx"), 2)
        self.assertIs(module.ort, runtime)

    def test_candidate_requires_verified_source_and_exact_output_bytes(self):
        with TemporaryDirectory() as temporary:
            _, model, manifest, _ = self.make_bundle(Path(temporary))
            candidate = model / "model.int4.onnx"
            candidate.write_bytes(b"test-only-candidate")
            provenance = {
                "schema_version": 1, "kind": "quds-gector-int4-candidate", "status": "passed",
                "source_model_sha256": manifest[0]["sha256"],
                "output": {"file": candidate.name, "sha256": export.digest(candidate),
                           "size_bytes": candidate.stat().st_size},
                "recipe": {"format": "ONNX MatMulNBits", "bits": 4},
            }
            sidecar = model / "candidate.json"
            sidecar.write_text(json.dumps(provenance))
            path, result = export.verify_inference_model(model, manifest, candidate, sidecar)
            self.assertEqual(path, candidate)
            self.assertEqual(result["variant"], "matmulnbits-int4")
            self.assertEqual(result["sha256"], provenance["output"]["sha256"])
            candidate.write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "does not match"):
                export.verify_inference_model(model, manifest, candidate, sidecar)
            provenance["source_model_sha256"] = "0" * 64
            sidecar.write_text(json.dumps(provenance))
            with self.assertRaisesRegex(ValueError, "not derived"):
                export.verify_inference_model(model, manifest, candidate, sidecar)


if __name__ == "__main__":
    unittest.main()
