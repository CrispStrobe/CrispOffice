#!/usr/bin/env python3
"""Locally qualify the prepared-input CrispEmbed GECToR CPU library.

Three explicit steps preserve independently inspectable provenance:
  seal-build: hash the portable build, compiled sources and actual dependencies;
  quantize: produce and inspect the declared mixed Q4_K recipe;
  qualify: replay authenticated inputs, both heads and the original edit loop.

This is development evidence. The Python/ONNX oracle is not an application
dependency; neither this probe nor its timings include Quds guards or its UI.
"""
from __future__ import annotations

import argparse
from collections import Counter
import ctypes as C
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import sys
import time
from types import SimpleNamespace
from typing import Any

import numpy as np

from export_reference import (digest, load_module, peak_rss_bytes, summary,
                              utf16_offset, verify_bundle)
from quantize_int4 import SOURCE_REVISION, SOURCE_SHA256
from summarize_qualification import compare_references, timing_summary


GGML_REVISION = "3a27b6c665b191cb230be367db5c52d81dd3e2ac"
STRICT_ABSOLUTE_DIAGNOSTIC = 0.002
HEAD_WIDTHS = {"logits_labels": 5000, "logits_d": 2}
PROTOCOL_VERSION = 2
LONG_PROBE_LENGTHS = (64, 128, 256)
POLICY_HELPERS = ("export_reference.py", "summarize_qualification.py", "quantize_int4.py", "evaluate.py")
RECIPE = {
    "name": "mixed-q4_k",
    "encoder_matrices": "Q4_K",
    "token_embeddings": "Q8_0",
    "position_embeddings": "F16",
    "heads": "F16",
    "type_embeddings_norms_biases": "F32",
    "overrides": ["*=f32", "enc.*.attn.*.weight=q4_k", "enc.*.ffn.*.weight=q4_k",
                  "token_embd.weight=q8_0", "position_embd.weight=f16", "gector.*.weight=f16"],
}


def read_json(path: Path) -> dict[str, Any]:
    result = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(result, dict):
        raise ValueError(f"Expected JSON object: {path.name}")
    return result


def write_new_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False)
        stream.write("\n")


def sha_array(array: np.ndarray) -> str:
    return hashlib.sha256(memoryview(np.ascontiguousarray(array)).cast("B")).hexdigest()


def policy_source_inventory() -> dict[str, str]:
    directory = Path(__file__).resolve().parent
    for name in POLICY_HELPERS[:3]:
        module = sys.modules.get(name.removesuffix(".py"))
        location = getattr(module, "__file__", None)
        if location is None or Path(location).resolve() != directory / name:
            raise ValueError(f"Imported policy helper is outside the declared source directory: {name}")
    return {name: digest(directory / name) for name in (Path(__file__).name, *POLICY_HELPERS)}


def source_inventory_digest(inventory: dict[str, str]) -> str:
    return hashlib.sha256(json.dumps(inventory, sort_keys=True).encode()).hexdigest()


def verify_baseline(baseline: dict[str, Any], reference_sha256: str, build: dict[str, Any],
                    policy_sources: dict[str, str], parent_gguf: dict[str, Any] | None = None) -> None:
    if (baseline.get("precision") != "f32" or baseline.get("protocol_version") != PROTOCOL_VERSION
            or baseline.get("complete") is not True or baseline.get("passed") is not True
            or baseline.get("reference_sha256") != reference_sha256
            or baseline.get("build", {}).get("library") != build["library"]
            or baseline.get("build", {}).get("source_inventory_sha256") != build["source_inventory_sha256"]
            or baseline.get("qualification_source_sha256") != policy_sources
            or baseline.get("policy_sources_unchanged_during_run") is not True):
        raise ValueError("Native F32 baseline is incomplete, failed, or from a different reference/source/binary/policy")
    if parent_gguf is not None and baseline.get("model") != parent_gguf:
        raise ValueError("Native F32 baseline is not this mixed model's exact declared parent GGUF")


def long_probe_gates(probes: list[dict[str, Any]], threshold: float) -> dict[str, Any]:
    """Frozen shape and precision admission for every required prepared length."""
    lengths = [probe.get("token_count") for probe in probes]
    complete = (len(lengths) == len(LONG_PROBE_LENGTHS) and all(type(length) is int for length in lengths)
                and set(lengths) == set(LONG_PROBE_LENGTHS))
    precision = complete
    raw_argmax_exact = complete
    for probe in probes:
        heads = probe.get("heads", {})
        if set(heads) != set(HEAD_WIDTHS):
            complete = precision = raw_argmax_exact = False
            continue
        for name, width in HEAD_WIDTHS.items():
            head = heads[name]
            if head.get("shape") != [1, probe.get("token_count"), width]:
                complete = precision = raw_argmax_exact = False
            cosine = head.get("minimum_token_cosine")
            if (type(cosine) not in (int, float) or not np.isfinite(cosine)
                    or not -1 <= cosine <= 1 or cosine <= threshold):
                precision = False
            if head.get("raw_argmax_mismatches") != 0:
                raw_argmax_exact = False
    return {"required_token_counts": list(LONG_PROBE_LENGTHS), "complete": complete,
            "precision_policy_passed": complete and precision, "raw_argmax_exact": complete and raw_argmax_exact,
            "minimum_token_cosine_exclusive": threshold,
            "scope": "Gating shapes/numerics for both heads at every required length; timing and raw argmax are retained diagnostics."}


def qualification_status(report: dict[str, Any]) -> tuple[bool, bool]:
    complete = (len(report["cases"]) == report["expected_cases"]
                and len(report["validation"]) == report["expected_passes"]
                and report["long_probe_gates"]["complete"])
    quality = report["quality_vs_original"]["frozen_probe_nonregression_passed"]
    if "quality_vs_native_f32" in report:
        quality = quality and report["quality_vs_native_f32"]["frozen_probe_nonregression_passed"]
    f32_exact = report["selected_tags_exact"] and not report["quality_vs_original"]["differences"]
    passed = (complete and report["precision_policy_passed"]
              and report["long_probe_gates"]["precision_policy_passed"]
              and report["policy_sources_unchanged_during_run"]
              and quality and (report["precision"] != "f32" or f32_exact))
    return complete, passed


def relative_source(path: Path, source: Path) -> str:
    try:
        return path.resolve().relative_to(source.resolve()).as_posix()
    except ValueError as error:
        raise ValueError("Compiled source is outside the declared native source tree") from error


def git_revision(source: Path) -> str:
    return subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()


def capture_build(source: Path, build: Path, library: Path, output: Path) -> dict[str, Any]:
    if output.exists():
        raise ValueError("Build receipt already exists; retain the earlier source separately")
    source, build = source.resolve(), build.resolve()
    commands_file = build / "compile_commands.json"
    commands = json.loads(commands_file.read_text())
    cache = {}
    for line in (build / "CMakeCache.txt").read_text().splitlines():
        match = re.match(r"([^/#][^:]*):[^=]*=(.*)", line)
        if match:
            cache[match[1]] = match[2]
    if any(cache.get(key) != "OFF" for key in ("GGML_NATIVE", "CRISPEMBED_NATIVE")):
        raise ValueError("Qualification requires GGML_NATIVE=OFF and CRISPEMBED_NATIVE=OFF")
    compiled, sources = [], set()
    for item in commands:
        path = Path(item["file"])
        name = relative_source(path, source)
        arguments = item.get("arguments") or shlex.split(item["command"])
        if any("march=native" in arg or "mcpu=native" in arg for arg in arguments):
            raise ValueError("Build contains machine-native compiler flags")
        sources.add(path.resolve())
        flags = [arg for arg in arguments if arg.startswith(("-D", "-O", "-m", "-f", "-std="))]
        compiled.append({"file": name, "compiler": Path(arguments[0]).name, "flags": flags})
    names = {row["file"] for row in compiled}
    if not {"src/gector.cpp", "src/core/gguf_loader.cpp"}.issubset(names):
        raise ValueError("The build is missing the actual prepared-input library sources")
    allowed_helpers = {"src/gector.cpp", "src/core/gguf_loader.cpp", "tools/quantize.cpp",
                       "tools/gector/main.cpp", "tests/test_gector.cpp"}
    if any(name not in allowed_helpers and not name.startswith("ggml/src/") for name in names):
        raise ValueError("Unexpected source in the closed grammar build")
    ninja = shutil.which("ninja") or str(Path(sys.executable).parent / "ninja")
    dependencies = subprocess.check_output([ninja, "-C", str(build), "-t", "deps"], text=True)
    for line in dependencies.splitlines():
        if not line.startswith("    "):
            continue
        path = Path(line.strip())
        if not path.is_absolute():
            path = build / path
        if path.is_file() and path.resolve().is_relative_to(source):
            sources.add(path.resolve())
    for path in [source / "tools/gector/CMakeLists.txt", source / "LICENSE", source / "ggml/LICENSE"]:
        sources.add(path)
    # CMake inputs are recorded in addition to compiler dependency files.
    sources.update((source / "ggml").rglob("CMakeLists.txt"))
    sources.update((source / "ggml/cmake").rglob("*.cmake"))
    inventory = {relative_source(path, source): digest(path) for path in sorted(sources)}
    ggml = git_revision(source / "ggml")
    if ggml != GGML_REVISION:
        raise ValueError("ggml source differs from the pinned grammar dependency")
    quantizer = build / "crispembed-gector-quantize"
    report = {
        "schema": "quds.gector.native-build.v1", "source_revision": git_revision(source),
        "ggml_revision": ggml, "portable": True,
        "cmake_flags": {key: value for key, value in cache.items()
                        if (key.startswith(("GGML_", "CRISPEMBED_")) and value in ("ON", "OFF"))
                        or key in ("CMAKE_BUILD_TYPE", "CMAKE_CXX_STANDARD")},
        "compiled_sources": sorted(compiled, key=lambda item: item["file"]),
        "source_sha256": inventory,
        "compile_commands_sha256": digest(commands_file),
        "cmake_cache_sha256": digest(build / "CMakeCache.txt"),
        "library": {"file": library.name, "sha256": digest(library), "size_bytes": library.stat().st_size},
        "quantizer": {"file": quantizer.name, "sha256": digest(quantizer), "size_bytes": quantizer.stat().st_size},
        "build_provenance_limit": "Source/dependency and binary hashes seal this observed local build; not a signed release attestation.",
    }
    report["source_inventory_sha256"] = hashlib.sha256(json.dumps(inventory, sort_keys=True).encode()).hexdigest()
    write_new_json(output, report)
    return report


def verify_build(receipt: Path, source: Path, library: Path, *, quantizer: Path | None = None) -> dict[str, Any]:
    record = read_json(receipt)
    if (record.get("schema") != "quds.gector.native-build.v1" or record.get("portable") is not True
            or record.get("ggml_revision") != GGML_REVISION):
        raise ValueError("No authenticated portable native build receipt")
    inventory = record.get("source_sha256", {})
    if not {"src/gector.cpp", "src/gector.h", "src/core/gguf_loader.cpp"}.issubset(inventory):
        raise ValueError("Incomplete native source inventory")
    for name, expected in inventory.items():
        path = source / name
        if not path.resolve().is_relative_to(source.resolve()) or digest(path) != expected:
            raise ValueError(f"Native source changed after build sealing: {name}")
    if hashlib.sha256(json.dumps(inventory, sort_keys=True).encode()).hexdigest() != record.get("source_inventory_sha256"):
        raise ValueError("Native source inventory digest changed")
    for key, path in (("library", library), ("quantizer", quantizer)):
        if path is None:
            continue
        expected = record[key]
        if path.stat().st_size != expected["size_bytes"] or digest(path) != expected["sha256"]:
            raise ValueError(f"Native {key} differs from its sealed build")
    return record


def expected_tensor_type(name: str, precision: str) -> str:
    if precision == "f32":
        return "F32"
    if precision != "mixed-q4_k":
        raise ValueError("Unknown qualification precision")
    if re.fullmatch(r"enc\.(?:[0-9]|1[01])\.(?:attn\.[qkvo]|ffn\.fc[12])\.weight", name):
        return "Q4_K"
    if name == "token_embd.weight":
        return "Q8_0"
    if name in ("position_embd.weight", "gector.labels.weight", "gector.detect.weight"):
        return "F16"
    return "F32"


def expected_tensor_shapes() -> dict[str, list[int]]:
    result = {"token_embd.weight": [768, 31102], "position_embd.weight": [768, 512],
              "token_type_embd.weight": [768, 2], "embd_ln.weight": [768], "embd_ln.bias": [768],
              "gector.labels.weight": [768, 5000], "gector.labels.bias": [5000],
              "gector.detect.weight": [768, 2], "gector.detect.bias": [2]}
    for layer in range(12):
        for suffix, shape in (("attn.q", [768, 768]), ("attn.k", [768, 768]),
                              ("attn.v", [768, 768]), ("attn.o", [768, 768]),
                              ("ffn.fc1", [768, 3072]), ("ffn.fc2", [3072, 768])):
            result[f"enc.{layer}.{suffix}.weight"] = shape
            result[f"enc.{layer}.{suffix}.bias"] = [shape[1]]
        for norm in ("ln1", "ln2"):
            for kind in ("weight", "bias"):
                result[f"enc.{layer}.{norm}.{kind}"] = [768]
    return result


def inspect_gguf(model: Path, precision: str) -> list[dict[str, Any]]:
    import gguf
    reader = gguf.GGUFReader(str(model))
    for key, expected in (("general.architecture", "gector"), ("gector.format_version", 1),
                          ("gector.source.revision", SOURCE_REVISION), ("gector.source.sha256", SOURCE_SHA256),
                          ("gector.precision", precision)):
        field = reader.get_field(key)
        if field is None or field.contents() != expected:
            raise ValueError(f"GGUF metadata differs from declared model profile: {key}")
    shapes = expected_tensor_shapes()
    if len(reader.tensors) != len(shapes) or {tensor.name for tensor in reader.tensors} != set(shapes):
        raise ValueError("GGUF does not contain the exact 201 trained tensors")
    result = []
    for tensor in reader.tensors:
        if list(tensor.shape) != shapes[tensor.name] or tensor.tensor_type.name != expected_tensor_type(tensor.name, precision):
            raise ValueError(f"GGUF tensor shape/type differs from the declared recipe: {tensor.name}")
        result.append({"name": tensor.name, "ggml_shape": list(map(int, tensor.shape)),
                       "type": tensor.tensor_type.name, "size_bytes": int(tensor.n_bytes),
                       "sha256": sha_array(tensor.data)})
    return result


def verify_model(model: Path, manifest: Path, precision: str) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    record = read_json(manifest)
    schema = "crispembed.gector.conversion.v1" if precision == "f32" else "quds.gector.mixed-q4_k.v1"
    if (record.get("schema") != schema or record.get("precision") != precision
            or record.get("gguf_readback_verified") is not True
            or record.get("source", {}).get("model_sha256") != SOURCE_SHA256
            or record.get("source", {}).get("revision") != SOURCE_REVISION):
        raise ValueError("Model manifest does not authenticate the declared pinned conversion")
    output = record["output"]
    if model.name != output["file"] or model.stat().st_size != output["size_bytes"] or digest(model) != output["sha256"]:
        raise ValueError("GGUF bytes differ from the authenticated manifest")
    census = inspect_gguf(model, precision)
    expected = {item["name"]: item for item in record["tensors"]}
    if len(expected) != 201 or len(record["tensors"]) != 201:
        raise ValueError("Model manifest has incomplete or duplicate tensors")
    for item in census:
        if any(expected[item["name"]].get(key) != item[key] for key in ("type", "ggml_shape", "size_bytes", "sha256")):
            raise ValueError(f"GGUF tensor census differs from manifest: {item['name']}")
    return record, census


def quantize_candidate(source_model: Path, source_manifest: Path, quantizer: Path,
                       build_receipt: Path, source_dir: Path, library: Path,
                       output: Path, manifest: Path) -> dict[str, Any]:
    if output.exists() or manifest.exists() or output.resolve() == manifest.resolve():
        raise ValueError("Use new distinct candidate and manifest paths; retain earlier artifacts")
    parent, _ = verify_model(source_model, source_manifest, "f32")
    build = verify_build(build_receipt, source_dir, library, quantizer=quantizer)
    command = [str(quantizer.resolve()), str(source_model.resolve()), str(output.resolve()), "q4_k", "--standard-file-type"]
    for override in RECIPE["overrides"]:
        command += ["--tensor-type", override]
    command += ["--metadata-string", "gector.precision=mixed-q4_k"]
    output.parent.mkdir(parents=True, exist_ok=True)
    log = output.with_suffix(output.suffix + ".quantizer.log")
    with log.open("x", encoding="utf-8") as stream:
        subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=True)
    census = inspect_gguf(output, "mixed-q4_k")
    counts = dict(sorted(Counter(item["type"] for item in census).items()))
    if counts != {"F16": 3, "F32": 125, "Q4_K": 72, "Q8_0": 1}:
        raise ValueError("Quantizer did not produce the exact declared mixed recipe")
    report = {
        "schema": "quds.gector.mixed-q4_k.v1", "precision": "mixed-q4_k", "recipe": RECIPE,
        "source": parent["source"], "parent_gguf": parent["output"],
        "parent_manifest_sha256": digest(source_manifest), "build_manifest_sha256": digest(build_receipt),
        "quantizer": build["quantizer"],
        "output": {"file": output.name, "size_bytes": output.stat().st_size, "sha256": digest(output)},
        "tensor_types": counts, "tensors": census, "gguf_readback_verified": True,
        "native_parity_qualified": False, "decoded_quality_qualified": False,
    }
    write_new_json(manifest, report)
    return report


def numeric_comparison(candidate: np.ndarray, baseline: np.ndarray) -> dict[str, Any]:
    if candidate.shape != baseline.shape or candidate.ndim != 3 or candidate.shape[0] != 1:
        raise ValueError("Comparison requires identical [1,tokens,classes] shapes")
    if not np.isfinite(candidate).all() or not np.isfinite(baseline).all():
        raise ValueError("Comparison received non-finite output")
    a, b = candidate.astype(np.float64), baseline.astype(np.float64)
    error = np.abs(a - b)
    flat_a, flat_b = a.reshape(-1), b.reshape(-1)
    denominator = np.linalg.norm(flat_a) * np.linalg.norm(flat_b)
    cosine = float(flat_a @ flat_b / denominator) if denominator else float(np.array_equal(a, b))
    norm = np.linalg.norm(a, axis=-1) * np.linalg.norm(b, axis=-1)
    row_cosines = np.divide(np.sum(a * b, axis=-1), norm, out=np.zeros_like(norm), where=norm != 0)
    row_cosines[(norm == 0) & np.all(a == b, axis=-1)] = 1
    return {"shape": list(candidate.shape), "maximum_absolute_error": float(error.max()),
            "mean_absolute_error": float(error.mean()), "rms_error": float(np.sqrt(np.mean(error * error))),
            "cosine": min(1.0, max(-1.0, cosine)),
            "minimum_token_cosine": min(1.0, max(-1.0, float(row_cosines.min()))),
            "strict_absolute_diagnostic_passed": bool(error.max() <= STRICT_ABSOLUTE_DIAGNOSTIC),
            "raw_argmax_mismatches": int(np.sum(a.argmax(axis=-1) != b.argmax(axis=-1)))}


def selection(outputs: dict[str, np.ndarray], indices: list[int], decoder: dict[str, Any]) -> dict[str, Any]:
    for name, width in HEAD_WIDTHS.items():
        value = outputs[name]
        if value.ndim != 3 or value.shape[0] != 1 or value.shape[2] != width or not np.isfinite(value).all():
            raise ValueError(f"Invalid native output head: {name}")
    if outputs["logits_labels"].shape[1] != outputs["logits_d"].shape[1]:
        raise ValueError("Output heads have different token counts")
    if not indices or indices != sorted(set(indices)) or indices[0] != 0 or indices[-1] >= outputs["logits_labels"].shape[1]:
        raise ValueError("Invalid first-subword selection indices")
    def softmax(value):
        value = np.exp(value - np.max(value, axis=-1, keepdims=True))
        return value / np.sum(value, axis=-1, keepdims=True)
    probabilities = softmax(outputs["logits_labels"][0])
    probabilities[:, decoder["keep_label_id"]] += decoder["keep_confidence"]
    incorrect = softmax(outputs["logits_d"][0])[:, decoder["incorrect_label_id"]]
    labels = [int(probabilities[index].argmax()) for index in indices]
    confidence = [float(probabilities[index, label]) for index, label in zip(indices, labels)]
    wrong = [float(incorrect[index]) for index in indices]
    thresholded = [label if probability >= decoder["min_error_prob"] else decoder["keep_label_id"]
                   for label, probability in zip(labels, confidence)]
    if max(wrong) < decoder["min_error_prob"]:
        thresholded = [decoder["keep_label_id"]] * len(indices)
    return {"label_ids": labels, "thresholded_label_ids": thresholded,
            "label_probabilities": confidence, "incorrect_probabilities": wrong,
            "sentence_incorrect_probability": max(wrong)}


def checked_payload(directory: Path, record: dict[str, Any]) -> np.ndarray:
    name = record["file"]
    path = directory / name
    shape = record["shape"]
    if (Path(name).name != name or record.get("dtype") != "float32" or record.get("byte_order") != "little"
            or record.get("layout") != "row-major" or not isinstance(shape, list)
            or len(shape) != 3 or any(type(size) is not int or size <= 0 for size in shape)):
        raise ValueError("Invalid raw tensor payload record")
    expected = int(np.prod(shape, dtype=np.int64)) * 4
    if record["size_bytes"] != expected or path.stat().st_size != expected or digest(path) != record["sha256"]:
        raise ValueError(f"Changed or truncated tensor payload: {name}")
    result = np.fromfile(path, dtype="<f4").reshape(shape)
    if not np.isfinite(result).all():
        raise ValueError(f"Non-finite reference payload: {name}")
    return result


def save_payload(directory: Path, name: str, array: np.ndarray) -> dict[str, Any]:
    path = directory / name
    value = np.asarray(array, dtype="<f4", order="C")
    if path.exists() or not np.isfinite(value).all():
        raise ValueError("Refusing duplicate or non-finite native payload")
    value.tofile(path)
    return {"file": name, "dtype": "float32", "byte_order": "little", "layout": "row-major",
            "shape": list(value.shape), "size_bytes": path.stat().st_size, "sha256": digest(path)}


class NativeSession:
    """A session-shaped adapter for the unchanged authenticated upstream decoder."""
    I64P = C.POINTER(C.c_int64)
    FLOATP = C.POINTER(C.c_float)
    TRACE = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_char_p, FLOATP, C.c_size_t, C.c_size_t)

    def __init__(self, library: Path, model: Path, threads: int):
        if not 1 <= threads <= 64:
            raise ValueError("Native threads must be 1..64")
        self.library = C.CDLL(str(library.resolve()))
        lib = self.library
        lib.crispembed_gector_create.argtypes = [C.c_char_p, C.c_int, C.c_void_p, C.c_size_t]
        lib.crispembed_gector_create.restype = C.c_void_p
        lib.crispembed_gector_free.argtypes = [C.c_void_p]
        lib.crispembed_gector_free.restype = None
        signature = [C.c_void_p, self.I64P, C.c_size_t, self.I64P, C.c_size_t, C.c_size_t,
                     self.FLOATP, C.c_size_t, self.FLOATP, C.c_size_t, self.FLOATP, C.c_size_t]
        lib.crispembed_gector_forward.argtypes = signature + [C.c_void_p, C.c_size_t]
        lib.crispembed_gector_forward.restype = C.c_int
        lib.crispembed_gector_forward_trace.argtypes = signature + [self.TRACE, C.c_void_p, C.c_void_p, C.c_size_t]
        lib.crispembed_gector_forward_trace.restype = C.c_int
        error = C.create_string_buffer(2048)
        self.previous_gate = os.environ.get("CRISPEMBED_GECTOR")
        os.environ["CRISPEMBED_GECTOR"] = "1"
        try:
            self.context = lib.crispembed_gector_create(os.fsencode(model.resolve()), threads, error, len(error))
        except BaseException:
            self.restore_gate()
            raise
        if not self.context:
            self.restore_gate()
            raise RuntimeError("Native model load failed: " + error.value.decode("utf-8", "replace"))

    def restore_gate(self):
        if self.previous_gate is None:
            os.environ.pop("CRISPEMBED_GECTOR", None)
        else:
            os.environ["CRISPEMBED_GECTOR"] = self.previous_gate

    def close(self):
        if self.context:
            self.library.crispembed_gector_free(self.context)
            self.context = None
            self.restore_gate()

    def forward(self, inputs: dict[str, np.ndarray], trace: bool = False):
        ids, mask = inputs["input_ids"], inputs["attention_mask"]
        if (ids.dtype != np.int64 or mask.dtype != np.int64 or ids.ndim != 2 or ids.shape[0] != 1
                or mask.shape != ids.shape or not 1 <= ids.shape[1] <= 512
                or np.any(mask != 1) or np.any(ids < 0) or np.any(ids >= 31102)):
            raise ValueError("Native input must be unpadded rank-2 batch-one int64 IDs and all-ones masks")
        ids, mask = np.ascontiguousarray(ids), np.ascontiguousarray(mask)
        outputs = {name: np.empty((1, ids.size, width), dtype=np.float32) for name, width in HEAD_WIDTHS.items()}
        error = C.create_string_buffer(2048)
        arguments = [self.context, ids.ctypes.data_as(self.I64P), ids.size,
                     mask.ctypes.data_as(self.I64P), mask.size, 1,
                     outputs["logits_labels"].ctypes.data_as(self.FLOATP), outputs["logits_labels"].size,
                     outputs["logits_d"].ctypes.data_as(self.FLOATP), outputs["logits_d"].size, None, 0]
        stages = {}
        if trace:
            @self.TRACE
            def callback(_user, stage, values, rows, columns):
                try:
                    name = stage.decode("ascii")
                    width = {"labels": 5000, "detect": 2}.get(name, 768)
                    if name in stages or rows != ids.size or columns != width:
                        return 1
                    stages[name] = np.ctypeslib.as_array(values, shape=(rows * columns,)).copy().reshape(1, rows, columns)
                    return 0
                except Exception:
                    return 1
            status = self.library.crispembed_gector_forward_trace(*arguments, callback, None, error, len(error))
        else:
            status = self.library.crispembed_gector_forward(*arguments, error, len(error))
        if status:
            raise RuntimeError(f"Native forward failed ({status}): " + error.value.decode("utf-8", "replace"))
        if any(not np.isfinite(value).all() for value in outputs.values()):
            raise RuntimeError("Native forward produced non-finite logits")
        if trace:
            expected_stages = {"embedding", "labels", "detect", *(f"layer.{i}" for i in range(12))}
            if set(stages) != expected_stages or any(not np.isfinite(value).all() for value in stages.values()):
                raise RuntimeError("Native trace did not return all 15 finite expected stages")
            if not np.array_equal(stages["labels"], outputs["logits_labels"]) or not np.array_equal(stages["detect"], outputs["logits_d"]):
                raise RuntimeError("Native traced logits differ from returned logits")
        return outputs, stages

    def run(self, output_names, inputs):
        if output_names != ["logits_labels", "logits_d"]:
            raise ValueError("The authenticated reference must request both named trained heads")
        outputs, _ = self.forward(inputs)
        return [outputs[name] for name in output_names]


def first_subwords(word_ids: list[int | None]) -> list[int]:
    seen, result = set(), []
    for token, word_id in enumerate(word_ids):
        word = 0 if token == 0 else None if word_id is None else word_id + 1
        if word is not None and word not in seen:
            seen.add(word)
            result.append(token)
    return result


def make_decoder(module, model_dir: Path, session: NativeSession):
    original_ort = module.ort
    module.ort = SimpleNamespace(InferenceSession=lambda _path, **_kwargs: session)
    try:
        return module.Gector(model=str(model_dir))
    finally:
        module.ort = original_ort


def qualify(args) -> dict[str, Any]:
    if args.output_dir.exists() and any(args.output_dir.iterdir()):
        raise ValueError("Output directory must be new or empty; retain previous evidence")
    if args.warmups < 0 or args.repeats < 1 or not 1 <= args.threads <= 64:
        raise ValueError("Invalid warmup/repeat/thread budget")
    if args.eval_dir.resolve() != Path(__file__).resolve().parent:
        raise ValueError("Qualification requires the local source-bound evaluation helpers")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    report = {"schema": "quds.gector.native-qualification.v1", "protocol_version": PROTOCOL_VERSION,
              "complete": False, "passed": False,
              "precision": args.precision, "timestamp_utc": datetime.now(timezone.utc).isoformat(),
              "warmups": args.warmups, "repeats": args.repeats, "threads": args.threads,
              "cases": [], "validation": [], "long_probes": []}
    session = None
    try:
        policy_sources = policy_source_inventory()
        assets, revision = verify_bundle(args.eval_dir, args.model_dir)
        build = verify_build(args.build_manifest, args.source_dir, args.library)
        model, census = verify_model(args.model, args.model_manifest, args.precision)
        reference = read_json(args.reference)
        cases_path = args.eval_dir / "cases.json"
        expected = json.loads(cases_path.read_text())
        ids = [case["id"] for case in expected]
        if (reference.get("kind") != "quds-gector-reference" or reference.get("revision") != revision
                or reference.get("cases_sha256") != digest(cases_path)
                or reference.get("input_sha256") != {item["file"]: item["sha256"] for item in assets}
                or reference.get("inference_model", {}).get("sha256") != SOURCE_SHA256
                or reference.get("inference_model", {}).get("variant") != "float32"
                or [case["id"] for case in reference.get("cases", [])] != ids):
            raise ValueError("Saved reference does not match the complete authenticated original panel")
        if reference.get("manifest_sha256") != digest(args.eval_dir / "artifacts.json"):
            raise ValueError("Reference artifact manifest differs from current pinned source")
        baseline = read_json(args.baseline) if args.baseline else None
        if args.precision == "mixed-q4_k" and baseline is None:
            raise ValueError("Mixed qualification requires a completed native F32 control")
        if baseline is not None:
            if args.precision == "mixed-q4_k" and not isinstance(model.get("parent_gguf"), dict):
                raise ValueError("Mixed model manifest is missing its exact parent GGUF")
            verify_baseline(baseline, digest(args.reference), build, policy_sources,
                            model["parent_gguf"] if args.precision == "mixed-q4_k" else None)
        baseline_passes = {(row["id"], row["pass"]): row for row in baseline["validation"]} if baseline else {}
        report.update({
            "model": model["output"], "model_manifest_sha256": digest(args.model_manifest),
            "source_model_sha256": SOURCE_SHA256, "reference_sha256": digest(args.reference),
            "cases_sha256": digest(cases_path), "source_revision": revision,
            "build_manifest_sha256": digest(args.build_manifest), "build": build,
            "qualifier_sha256": digest(Path(__file__)), "tensor_types": dict(Counter(item["type"] for item in census)),
            "qualification_source_sha256": policy_sources,
            "qualification_source_inventory_sha256": source_inventory_digest(policy_sources),
            "policy_sources_unchanged_during_run": False,
            "expected_cases": len(expected), "expected_passes": sum(len(case["passes"]) for case in reference["cases"]),
            "runtime": {"python": sys.version, "platform": platform.platform(), "machine": platform.machine(),
                        "cpu_count": os.cpu_count(), "gate": "CRISPEMBED_GECTOR=1",
                        "packages": {name: importlib.metadata.version(name)
                                     for name in ("numpy", "gguf", "onnxruntime", "tokenizers", "huggingface-hub")}},
            "limits": ["Native CPU qualification on one local host; no target-device or shipping approval.",
                       "Original iterative decoder is unchanged; application guards/editor costs are omitted.",
                       "Forward timings do not satisfy the complete-checker latency target.",
                       "64/128/256-token probes repeat prepared IDs and test shape/numerics/timing, not linguistic quality.",
                       "Peak RSS covers Python, model validation and the later development ONNX oracle.",
                       "Intermediate comparisons use the same-source native F32 control, not original ONNX hidden dumps."],
        })
        if args.baseline:
            report["baseline_sha256"] = digest(args.baseline)
        started = time.perf_counter()
        session = NativeSession(args.library, args.model, args.threads)
        report["setup_seconds"] = time.perf_counter() - started
        report["setup_peak_process_rss_bytes"] = peak_rss_bytes()
        module = load_module("proofbird_native_qualification", args.eval_dir / "vendor/quickstart.py")
        decoder = make_decoder(module, args.model_dir, session)
        config = {"keep_label_id": decoder.keep, "incorrect_label_id": decoder.incorrect,
                  "keep_confidence": decoder.keep_confidence, "min_error_prob": decoder.min_error_prob}
        if config != reference["decoder"]:
            raise ValueError("Decoder policy differs from the frozen original")
        threshold = 0.99 if args.precision == "f32" else 0.94
        for case in reference["cases"]:
            for index, trace in enumerate(case["passes"], 1):
                encoding = decoder.tokenizer.encode(trace["words"], is_pretokenized=True)
                if (encoding.ids != trace["input_ids"][0] or encoding.tokens != trace["tokens"]
                        or encoding.word_ids != trace["word_ids"]
                        or first_subwords(encoding.word_ids) != trace["first_subword_indices"]):
                    raise ValueError(f"Reference tokenization/alignment changed: {case['id']} pass {index}")
                inputs = {name: np.array(trace[name], dtype=np.int64) for name in ("input_ids", "attention_mask")}
                values, stages = session.forward(inputs, trace=True)
                heads, raw = {}, {}
                for name in HEAD_WIDTHS:
                    original = checked_payload(args.reference.parent, trace["outputs"][name])
                    heads[name] = {"original": numeric_comparison(values[name], original)}
                    if baseline:
                        control = checked_payload(args.baseline.parent, baseline_passes[(case["id"], index)]["outputs"][name])
                        heads[name]["native_f32"] = numeric_comparison(values[name], control)
                    raw[name] = save_payload(args.output_dir, f"{case['id']}.pass-{index}.{name}.f32le", values[name])
                hidden, intermediate = {}, {}
                for name, value in stages.items():
                    if name in ("labels", "detect"):
                        continue
                    hidden[name] = save_payload(args.output_dir, f"{case['id']}.pass-{index}.{name}.f32le", value)
                    if baseline:
                        control = checked_payload(args.baseline.parent, baseline_passes[(case["id"], index)]["stages"][name])
                        intermediate[name] = numeric_comparison(value, control)
                selected = selection(values, trace["first_subword_indices"], config)
                exact = all(selected[key] == trace["selected"][key] for key in ("label_ids", "thresholded_label_ids"))
                policy = all(comparison["minimum_token_cosine"] > threshold
                             for head in heads.values() for comparison in head.values())
                report["validation"].append({"id": case["id"], "pass": index, "token_count": inputs["input_ids"].size,
                                              "heads": heads, "selected": selected, "selected_tags_exact": exact,
                                              "precision_policy_passed": policy, "outputs": raw,
                                              "stages": hidden, "intermediate_vs_native_f32": intermediate})
            corrected, suggestions = decoder.correct(case["input"])
            utf16 = [{"start": utf16_offset(case["input"], item["start"]),
                      "end": utf16_offset(case["input"], item["start"] + item["length"]),
                      "original": item["original"], "replacement": item["replacement"]} for item in suggestions]
            applied = list(decoder.passes)
            inputs = {name: np.array(case["passes"][0][name], dtype=np.int64)
                      for name in ("input_ids", "attention_mask")}
            forward_times, complete_times = [], []
            for repeat in range(args.warmups + args.repeats):
                started = time.perf_counter()
                session.run(list(HEAD_WIDTHS), inputs)
                forward_elapsed = time.perf_counter() - started
                started = time.perf_counter()
                repeated_text, repeated_suggestions = decoder.correct(case["input"])
                complete_elapsed = time.perf_counter() - started
                if repeated_text != corrected or repeated_suggestions != suggestions:
                    raise RuntimeError(f"Native correction is not deterministic: {case['id']}")
                if repeat >= args.warmups:
                    forward_times.append(forward_elapsed)
                    complete_times.append(complete_elapsed)
            report["cases"].append({**{key: case[key] for key in ("id", "kind", "input", "expected", "locale") if key in case},
                                     "corrected": corrected, "suggestions_codepoints": suggestions,
                                     "suggestions_utf16": utf16, "passes": applied,
                                     "token_count": inputs["input_ids"].size,
                                     "first_pass_benchmark": summary(forward_times),
                                     "correction_benchmark": summary(complete_times)})
            print(json.dumps({"case": case["id"], "corrected": corrected, "passes": len(applied)}), flush=True)
        report["pre_oracle_peak_process_rss_bytes"] = peak_rss_bytes()
        # Long synthetic probes use exactly the same prepared IDs for both engines.
        import onnxruntime as ort
        options = ort.SessionOptions()
        options.intra_op_num_threads, options.inter_op_num_threads = args.threads, 1
        options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        oracle = ort.InferenceSession(str(args.model_dir / "model.onnx"), options, providers=["CPUExecutionProvider"])
        seed = reference["cases"][0]["passes"][0]["input_ids"][0]
        for length in LONG_PROBE_LENGTHS:
            body = (seed[1:-1] * ((length - 2 + len(seed[1:-1]) - 1) // len(seed[1:-1])))[:length - 2]
            ids_array = np.array([[seed[0], *body, seed[-1]]], dtype=np.int64)
            inputs = {"input_ids": ids_array, "attention_mask": np.ones_like(ids_array)}
            expected_outputs = dict(zip(HEAD_WIDTHS, oracle.run(list(HEAD_WIDTHS), inputs)))
            actual, _ = session.forward(inputs)
            times = []
            for repeat in range(args.warmups + args.repeats):
                started = time.perf_counter()
                session.forward(inputs)
                elapsed = time.perf_counter() - started
                if repeat >= args.warmups:
                    times.append(elapsed)
            report["long_probes"].append({"token_count": length, "input_ids": ids_array.tolist(),
                                         "input_sha256": sha_array(ids_array), "forward_benchmark": summary(times),
                                         "heads": {name: numeric_comparison(actual[name], expected_outputs[name]) for name in HEAD_WIDTHS}})
        report["quality_vs_original"] = compare_references(reference, report, expected)
        if baseline:
            report["quality_vs_native_f32"] = compare_references(baseline, report, expected)
        report["selected_tags_exact"] = all(row["selected_tags_exact"] for row in report["validation"])
        report["precision_policy_passed"] = all(row["precision_policy_passed"] for row in report["validation"])
        report["long_probe_gates"] = long_probe_gates(report["long_probes"], threshold)
        report["precision_policy"] = {"minimum_token_cosine_exclusive": threshold,
                                      "applies_to": "Both trained heads at every saved token/pass against original and native F32 when supplied; also every token of required 64/128/256 probes against original ONNX.",
                                      "strict_absolute_diagnostic": STRICT_ABSOLUTE_DIAGNOSTIC}
        report["timings"] = {
            "first_forward": timing_summary([{**case["first_pass_benchmark"], "id": case["id"], "token_count": case["token_count"]} for case in report["cases"]]),
            "complete_unguarded_correction": timing_summary([{**case["correction_benchmark"], "id": case["id"], "token_count": case["token_count"]} for case in report["cases"]]),
        }
        if policy_sources != policy_source_inventory():
            raise ValueError("Qualification policy source changed during execution")
        report["policy_sources_unchanged_during_run"] = True
        report["complete"], report["passed"] = qualification_status(report)
        report["peak_process_rss_bytes"] = peak_rss_bytes()
        return report
    except Exception as error:
        report["error"] = f"{type(error).__name__}: {error}"
        report["peak_process_rss_bytes"] = peak_rss_bytes()
        raise
    finally:
        if session is not None:
            session.close()
        write_new_json(args.output_dir / "qualification.json", report)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    seal = commands.add_parser("seal-build")
    for flag in ("source-dir", "build-dir", "library", "output"):
        seal.add_argument("--" + flag, type=Path, required=True)
    quant = commands.add_parser("quantize")
    for flag in ("source-model", "source-manifest", "quantizer", "build-manifest", "source-dir", "library", "output", "manifest"):
        quant.add_argument("--" + flag, type=Path, required=True)
    check = commands.add_parser("qualify")
    for flag in ("model", "model-manifest", "model-dir", "reference", "library", "build-manifest", "source-dir", "output-dir"):
        check.add_argument("--" + flag, type=Path, required=True)
    check.add_argument("--eval-dir", type=Path, default=Path(__file__).resolve().parent)
    check.add_argument("--baseline", type=Path)
    check.add_argument("--precision", choices=("f32", "mixed-q4_k"), required=True)
    check.add_argument("--threads", type=int, default=2)
    check.add_argument("--warmups", type=int, default=1)
    check.add_argument("--repeats", type=int, default=3)
    args = parser.parse_args()
    try:
        if args.command == "seal-build":
            result = capture_build(args.source_dir, args.build_dir, args.library, args.output)
            print(json.dumps({"sources": len(result["source_sha256"]), "library": result["library"]}, indent=2))
        elif args.command == "quantize":
            result = quantize_candidate(args.source_model, args.source_manifest, args.quantizer,
                                        args.build_manifest, args.source_dir, args.library, args.output, args.manifest)
            print(json.dumps({"output": result["output"], "tensor_types": result["tensor_types"]}, indent=2))
        else:
            result = qualify(args)
            print(json.dumps({"passed": result["passed"], "complete": result["complete"],
                              "quality": result["quality_vs_original"], "timings": result["timings"]}, indent=2))
            return 0 if result["passed"] else 1
        return 0
    except Exception as error:
        print(f"Native qualification failed: {type(error).__name__}: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
