#!/usr/bin/env python3
"""Export pinned Proofbird inputs, raw logits and edit traces for backend parity.

This is an evaluation tool. It does not register an application provider or
claim the guards omitted by the upstream runner. Large tensors stay in the
output directory and should be published as CI artifacts, not source files.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import statistics
import sys
import tempfile
import time
from types import SimpleNamespace
import urllib.request


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            result.update(chunk)
    return result.hexdigest()


def utf16_offset(text: str, offset: int) -> int:
    return len(text[:offset].encode("utf-16-le")) // 2


def peak_rss_bytes() -> int | None:
    try:
        import resource
        value = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        return int(value if sys.platform == "darwin" else value * 1024)
    except (ImportError, AttributeError):
        return None


def summary(values: list[float]) -> dict:
    ordered = sorted(values)
    return {
        "samples_seconds": values,
        "median_seconds": statistics.median(values),
        "p95_seconds": ordered[max(0, (95 * len(ordered) + 99) // 100 - 1)],
        "maximum_seconds": ordered[-1],
    }


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValueError(f"Cannot import evaluation module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def verify_bundle(eval_dir: Path, model_dir: Path, download: bool = False) -> tuple[list[dict], str]:
    """Reuse the existing evaluator's digest and revision; never modify its golds.

    The evaluator currently exposes no download helper. Downloads here use the
    same pinned manifest, additionally checking size and hash before publishing
    a temporary file. Existing mismatched files are errors, never overwritten.
    """
    evaluator = load_module("pinned_evaluation", eval_dir / "evaluate.py")
    manifest = json.loads((eval_dir / "artifacts.json").read_text())
    revisions = set()
    names = set()
    for artifact in manifest:
        name = artifact["file"]
        if name in names or Path(name).name != name:
            raise ValueError(f"Invalid or duplicate artifact name: {name}")
        names.add(name)
        match = re.fullmatch(
            r"https://huggingface\.co/proofbird/gector-bert-de/resolve/([0-9a-f]{40})/([^/]+)",
            artifact["url"],
        )
        if not match or match[2] != name:
            raise ValueError(f"Artifact is not pinned to the expected repository: {name}")
        revisions.add(match[1])
        if match[1] != evaluator.REVISION:
            raise ValueError(f"Artifact revision differs from the pinned evaluator: {name}")
    if len(revisions) != 1 or not {"model.onnx", "quickstart.py"}.issubset(names):
        raise ValueError("The bundle must contain one immutable model revision and its runner")
    if download:
        model_dir.mkdir(parents=True, exist_ok=True)
    for artifact in manifest:
        name = artifact["file"]
        path = model_dir / name
        if not path.exists() and download:
            temporary = None
            try:
                with tempfile.NamedTemporaryFile(dir=model_dir, prefix=f".{name}.",
                                                 suffix=".download", delete=False) as output:
                    temporary = Path(output.name)
                    with urllib.request.urlopen(artifact["url"], timeout=120) as response:
                        while chunk := response.read(1024 * 1024):
                            output.write(chunk)
                if (temporary.stat().st_size != artifact["size"]
                        or evaluator.digest(temporary) != artifact["sha256"]):
                    raise ValueError(f"Downloaded artifact failed integrity validation: {name}")
                temporary.replace(path)
            finally:
                if temporary is not None:
                    temporary.unlink(missing_ok=True)
        if (not path.is_file() or path.stat().st_size != artifact["size"]
                or evaluator.digest(path) != artifact["sha256"]):
            raise ValueError(f"Missing or changed pinned input: {path}")
    runner_hash = next(x["sha256"] for x in manifest if x["file"] == "quickstart.py")
    if evaluator.digest(eval_dir / "vendor" / "quickstart.py") != runner_hash:
        raise ValueError("The vendored runner differs from the pinned reference")
    return manifest, revisions.pop()


class TraceTokenizer:
    def __init__(self, delegate, traces):
        self.delegate, self.traces = delegate, traces

    def encode(self, words, **kwargs):
        encoded = self.delegate.encode(words, **kwargs)
        seen, first = set(), []
        for token, word_id in enumerate(encoded.word_ids):
            word = 0 if token == 0 else None if word_id is None else word_id + 1
            if word is not None and word not in seen:
                seen.add(word)
                first.append(token)
        self.traces.append({
            "words": list(words), "tokens": encoded.tokens,
            "word_ids": encoded.word_ids,
            "first_subword_indices": first,
            "tokenizer_offsets": encoded.offsets,
        })
        return encoded


class TraceSession:
    def __init__(self, delegate, traces, output_dir, case_id, model, softmax):
        self.delegate, self.traces = delegate, traces
        self.output_dir, self.case_id = output_dir, case_id
        self.model, self.softmax = model, softmax

    def run(self, output_names, inputs):
        import numpy as np
        started = time.perf_counter()
        values = self.delegate.run(output_names, inputs)
        elapsed = time.perf_counter() - started
        trace = self.traces[-1]
        trace["input_ids"] = inputs["input_ids"].tolist()
        trace["attention_mask"] = inputs["attention_mask"].tolist()
        trace["reference_inference_seconds"] = elapsed
        trace["outputs"] = {}
        for name, value in zip(output_names, values):
            if name not in {"logits_labels", "logits_d"}:
                raise ValueError(f"Unexpected output {name}")
            filename = f"{self.case_id}.pass-{len(self.traces)}.{name}.f32le"
            path = self.output_dir / filename
            np.asarray(value, dtype="<f4", order="C").tofile(path)
            trace["outputs"][name] = {
                "dtype": "float32", "byte_order": "little", "layout": "row-major",
                "shape": list(value.shape), "file": filename,
                "size_bytes": path.stat().st_size, "sha256": digest(path),
            }
        by_name = dict(zip(output_names, values))
        probs = self.softmax(by_name["logits_labels"][0])
        probs[:, self.model.keep] += self.model.keep_confidence
        wrong = self.softmax(by_name["logits_d"][0])[:, self.model.incorrect]
        indices = trace["first_subword_indices"]
        label_ids = [int(probs[token].argmax()) for token in indices]
        probabilities = [float(probs[token, label]) for token, label in zip(indices, label_ids)]
        incorrect = [float(wrong[token]) for token in indices]
        thresholded_ids = [label if probability >= self.model.min_error_prob else self.model.keep
                           for label, probability in zip(label_ids, probabilities)]
        sentence_probability = max(incorrect)
        if sentence_probability < self.model.min_error_prob:
            thresholded_ids = [self.model.keep] * len(thresholded_ids)
        labels = [self.model.labels[label] for label in thresholded_ids]
        trace["selected"] = {
            "label_ids": label_ids, "thresholded_label_ids": thresholded_ids, "labels": labels,
            "label_probabilities": probabilities, "incorrect_probabilities": incorrect,
            "sentence_incorrect_probability": sentence_probability,
        }
        return values


def session_metadata(session) -> dict:
    options = session.get_session_options()
    return {
        "providers": session.get_providers(),
        "intra_op_num_threads": options.intra_op_num_threads,
        "inter_op_num_threads": options.inter_op_num_threads,
        "execution_mode": str(options.execution_mode),
        "graph_optimization_level": str(options.graph_optimization_level),
        "thread_count_note": "Zero requests ONNX Runtime's automatic thread selection.",
    }


def create_reference_model(module, model_dir: Path, inference_model: Path, threads: int):
    """Keep upstream algorithms intact, with an explicit inference resource budget."""
    original_ort = module.ort
    options = original_ort.SessionOptions()
    options.intra_op_num_threads = threads
    options.inter_op_num_threads = 1
    options.execution_mode = original_ort.ExecutionMode.ORT_SEQUENTIAL

    def create_session(_upstream_path, *, providers):
        return original_ort.InferenceSession(str(inference_model), sess_options=options, providers=providers)

    # The pinned constructor only uses ort.InferenceSession. Replace its module
    # reference, not the process-global onnxruntime module, and restore it even
    # if loading fails. Tokenizer/config/labels/decoder still come from the bundle.
    module.ort = SimpleNamespace(InferenceSession=create_session)
    try:
        return module.Gector(model=str(model_dir))
    finally:
        module.ort = original_ort


def verify_inference_model(model_dir: Path, manifest: list[dict], candidate: Path | None,
                           candidate_manifest: Path | None) -> tuple[Path, dict]:
    source = next(x for x in manifest if x["file"] == "model.onnx")
    if candidate is None and candidate_manifest is None:
        return model_dir / "model.onnx", {
            "file": "model.onnx", "variant": "float32", "sha256": source["sha256"],
            "size_bytes": source["size"], "source_model_sha256": source["sha256"],
        }
    if candidate is None or candidate_manifest is None:
        raise ValueError("inference-model and candidate-manifest must be supplied together")
    provenance = json.loads(candidate_manifest.read_text())
    if (provenance.get("schema_version") != 1
            or provenance.get("kind") != "quds-gector-int4-candidate"
            or provenance.get("status") != "passed"):
        raise ValueError("Candidate manifest must record successful version-1 verification")
    if provenance.get("source_model_sha256") != source["sha256"]:
        raise ValueError("Candidate was not derived from the pinned source model")
    output = provenance["output"]
    if (not candidate.is_file() or candidate.name != output["file"]
            or candidate.stat().st_size != output["size_bytes"]
            or digest(candidate) != output["sha256"]):
        raise ValueError("Candidate model does not match its verified manifest")
    return candidate, {
        "file": candidate.name, "variant": "matmulnbits-int4", "sha256": output["sha256"],
        "size_bytes": output["size_bytes"], "source_model_sha256": source["sha256"],
        "candidate_manifest_sha256": digest(candidate_manifest), "recipe": provenance["recipe"],
    }


def export_census(model_dir: Path, output_dir: Path) -> None:
    """Optional architecture metadata for backend planning; no tensor data."""
    from collections import Counter
    import onnx

    graph = onnx.load(str(model_dir / "model.onnx"), load_external_data=False)

    def value_info(value):
        tensor = value.type.tensor_type
        return {"name": value.name, "dtype": onnx.TensorProto.DataType.Name(tensor.elem_type),
                "shape": [d.dim_value if d.HasField("dim_value") else d.dim_param
                          for d in tensor.shape.dim]}

    def attribute_value(value):
        if isinstance(value, onnx.TensorProto):
            return {"dtype": onnx.TensorProto.DataType.Name(value.data_type), "shape": list(value.dims)}
        if isinstance(value, onnx.GraphProto):
            return {"name": value.name, "node_count": len(value.node)}
        if isinstance(value, bytes):
            return value.decode("utf-8", errors="replace")
        if isinstance(value, (list, tuple)):
            return [attribute_value(x) for x in value]
        return value

    cfg = json.loads((model_dir / "config.json").read_text())
    result = {
        "model_sha256": digest(model_dir / "model.onnx"),
        "onnx_version": onnx.__version__, "ir_version": graph.ir_version,
        "opset_imports": [{"domain": x.domain, "version": x.version} for x in graph.opset_import],
        "config": {k: v for k, v in cfg.items() if k not in {"id2label", "label2id"}},
        "inputs": [value_info(x) for x in graph.graph.input],
        "outputs": [value_info(x) for x in graph.graph.output],
        "operators": dict(sorted(Counter(f"{x.domain or 'ai.onnx'}::{x.op_type}"
                                          for x in graph.graph.node).items())),
        "initializers": [{"name": x.name, "dtype": onnx.TensorProto.DataType.Name(x.data_type),
                          "shape": list(x.dims), "data_location": int(x.data_location)}
                         for x in graph.graph.initializer],
        "nodes": [{"name": x.name, "domain": x.domain, "op_type": x.op_type,
                   "inputs": list(x.input), "outputs": list(x.output),
                   "attributes": {a.name: attribute_value(onnx.helper.get_attribute_value(a)) for a in x.attribute}}
                  for x in graph.graph.node],
    }
    (output_dir / "onnx-census.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--eval-dir", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--download", action="store_true", help="Fetch only missing pinned artifacts.")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--cases-file", type=Path)
    parser.add_argument("--case-id", action="append", default=[])
    parser.add_argument("--warmups", type=int, default=2)
    parser.add_argument("--repeats", type=int, default=10)
    parser.add_argument("--threads", type=int, default=2, help="ORT intra-op threads; inter-op is 1, execution sequential.")
    parser.add_argument("--inference-model", type=Path, help="Use a verified derived model with the pinned bundle's decoder/tokenizer.")
    parser.add_argument("--candidate-manifest", type=Path, help="Required provenance/verification sidecar for inference-model.")
    parser.add_argument("--source-revision", help="Git revision of the evaluation source, if known.")
    parser.add_argument("--onnx-census", action="store_true", help="Also export graph metadata; requires onnx.")
    args = parser.parse_args()
    if args.warmups < 0 or args.repeats < 1:
        parser.error("warmups must be nonnegative and repeats must be positive")
    if args.threads < 1:
        parser.error("threads must be positive")
    manifest, revision = verify_bundle(args.eval_dir, args.model_dir, args.download)
    inference_model_path, inference_model_info = verify_inference_model(
        args.model_dir, manifest, args.inference_model, args.candidate_manifest)
    cases_path = args.cases_file or args.eval_dir / "cases.json"
    cases = json.loads(cases_path.read_text())
    ids = [case["id"] for case in cases]
    if len(ids) != len(set(ids)) or any(not re.fullmatch(r"[a-zA-Z0-9_-]+", x) for x in ids):
        parser.error("case IDs must be unique and safe filename components")
    if set(args.case_id) - set(ids):
        parser.error("unknown case-id")
    if args.case_id:
        cases = [case for case in cases if case["id"] in args.case_id]
    if not cases:
        parser.error("no cases selected")
    if args.output_dir.exists() and any(args.output_dir.iterdir()):
        parser.error("output-dir must be new or empty; retain previous evidence separately")
    args.output_dir.mkdir(parents=True, exist_ok=True)

    import numpy as np
    runner_path = args.eval_dir / "vendor" / "quickstart.py"
    module = load_module("proofbird_reference", runner_path)
    started = time.perf_counter()
    model = create_reference_model(module, args.model_dir, inference_model_path, args.threads)
    setup_seconds = time.perf_counter() - started
    native_session, native_tokenizer = model.session, model.tokenizer
    decoder = {"keep_label_id": model.keep, "incorrect_label_id": model.incorrect,
               "keep_confidence": model.keep_confidence, "min_error_prob": model.min_error_prob}
    setup_peak_rss = peak_rss_bytes()
    rows = []
    for case in cases:
        traces = []
        model.tokenizer = TraceTokenizer(native_tokenizer, traces)
        model.session = TraceSession(native_session, traces, args.output_dir, case["id"], model, module.softmax)
        corrected, suggestions = model.correct(case["input"])
        if len(traces) != len(model.passes):
            raise RuntimeError("Reference pass trace is inconsistent")
        for trace, applied in zip(traces, model.passes):
            trace["reference_decoding"] = applied
            if [word["tag"] for word in applied["words"]] != trace["selected"]["labels"]:
                raise RuntimeError("Observed raw logits disagree with the upstream decoder")
        utf16_suggestions = [{
            "start": utf16_offset(case["input"], item["start"]),
            "end": utf16_offset(case["input"], item["start"] + item["length"]),
            "original": item["original"], "replacement": item["replacement"],
        } for item in suggestions]
        inputs = {
            "input_ids": np.array(traces[0]["input_ids"], dtype=np.int64),
            "attention_mask": np.array(traces[0]["attention_mask"], dtype=np.int64),
        }
        times = []
        for iteration in range(args.warmups + args.repeats):
            started = time.perf_counter()
            outputs = native_session.run(["logits_labels", "logits_d"], inputs)
            elapsed = time.perf_counter() - started
            if iteration >= args.warmups:
                times.append(elapsed)
            del outputs
        # Measure the original full iterative correction with observers removed.
        # Export I/O and extra probability calculations must not inflate latency.
        model.session, model.tokenizer = native_session, native_tokenizer
        correction_times = []
        for iteration in range(args.warmups + args.repeats):
            started = time.perf_counter()
            repeated_corrected, repeated_suggestions = model.correct(case["input"])
            elapsed = time.perf_counter() - started
            if repeated_corrected != corrected or repeated_suggestions != suggestions:
                raise RuntimeError(f"Reference correction changed across repeated runs: {case['id']}")
            if iteration >= args.warmups:
                correction_times.append(elapsed)
        rows.append({**case, "corrected": corrected, "suggestions_codepoints": suggestions,
                     "suggestions_utf16": utf16_suggestions, "passes": traces,
                     "reference_first_pass_benchmark": summary(times),
                     "reference_correction_benchmark": summary(correction_times)})
        print(json.dumps({"case": case["id"], "tokens": len(inputs["input_ids"][0]),
                          "passes": len(traces), "median_seconds": statistics.median(times)}), flush=True)
    model.session, model.tokenizer = native_session, native_tokenizer
    packages = {name: importlib.metadata.version(name) for name in
                ["onnxruntime", "tokenizers", "huggingface-hub", "numpy"]}
    result = {
        "schema_version": 1, "kind": "quds-gector-reference",
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "model": "proofbird/gector-bert-de", "revision": revision,
        "inference_model": inference_model_info,
        "decoder": decoder, "source_revision": args.source_revision,
        "input_sha256": {x["file"]: x["sha256"] for x in manifest},
        "manifest_sha256": digest(args.eval_dir / "artifacts.json"),
        "cases_sha256": digest(cases_path), "exporter_sha256": digest(Path(__file__)),
        "evaluator_sha256": digest(args.eval_dir / "evaluate.py"),
        "runtime": {"python": sys.version, "platform": platform.platform(),
                    "machine": platform.machine(), "cpu_count": os.cpu_count(),
                    "packages": packages, "ort_session": session_metadata(native_session)},
        "setup_seconds": setup_seconds, "setup_peak_process_rss_bytes": setup_peak_rss,
        "peak_process_rss_bytes": peak_rss_bytes(),
        "warmups": args.warmups, "repeats": args.repeats,
        "limits": [
            "Pinned upstream runner; application guards and spelling checks are omitted.",
            "Tokenizer offsets are relative to pretokenized words, not document offsets.",
            "Recorded inference timings exclude tensor file serialization and edit decoding.",
            "Correction timings execute the original complete iterative runner without export observers.",
            "Peak RSS covers the entire Python process and is not model-only allocation.",
            "Quantized backends need edit-quality evaluation as well as numerical parity.",
        ],
        "cases": rows,
    }
    output = args.output_dir / "reference.json"
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    if args.onnx_census:
        export_census(args.model_dir, args.output_dir)
    print(str(output), flush=True)


if __name__ == "__main__":
    main()
