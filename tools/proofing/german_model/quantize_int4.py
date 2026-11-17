#!/usr/bin/env python3
"""Create one authenticated ONNX MatMulNBits candidate, retaining both heads.

This is a hosted qualification tool, not a model publication command. Q4_K is
a different ggml format. Only the frozen v2.1 bundle is admitted here.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
from pathlib import Path
import platform
import sys
import time

from export_reference import digest, peak_rss_bytes, verify_bundle


SOURCE_SHA256 = "6d7b43b4bd95c7a00c02c8babc7569d28558df894afe4874d96c202e6ab9a464"
SOURCE_REVISION = "8e3b50beef7d775cedb7b876009e88bcf2e8d6af"
OUTPUTS = {"logits_labels": 5000, "logits_d": 2}


def write_json(path: Path, value: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


def find_head(graph, output: str):
    """Locate the last linear operation through a deliberately narrow suffix.

    Do not infer classifier names from a generic BERT checkpoint. Unknown
    output transformations or ambiguous linear ancestry require a new review.
    """
    producers = {}
    for node in graph.node:
        for value in node.output:
            if value in producers:
                raise ValueError(f"Multiple producers for {value}")
            producers[value] = node
    initializers = {value.name for value in graph.initializer}
    found = {}
    visited = set()

    def visit(value, depth):
        if value in initializers or value in visited:
            return
        if depth > 16:
            raise ValueError(f"Output suffix too deep for {output}")
        visited.add(value)
        node = producers.get(value)
        if node is None:
            raise ValueError(f"Unresolved output ancestry: {output}: {value}")
        if node.domain not in ("", "ai.onnx"):
            raise ValueError(f"Unsupported output-domain ancestry for {output}")
        if node.op_type in ("MatMul", "Gemm"):
            found[node.name] = node
        elif node.op_type == "Constant":
            return
        elif node.op_type == "Add":
            for child in node.input:
                visit(child, depth + 1)
        elif node.op_type in ("Identity", "Cast", "Reshape", "Squeeze", "Unsqueeze", "Flatten"):
            visit(node.input[0], depth + 1)
        else:
            raise ValueError(f"Unsupported output suffix {node.op_type} for {output}")

    visit(output, 0)
    if len(found) != 1:
        raise ValueError(f"Expected exactly one output head for {output}, found {len(found)}")
    return next(iter(found.values()))


def census(model) -> dict:
    import onnx

    def info(value):
        tensor = value.type.tensor_type
        return {"name": value.name, "dtype": onnx.TensorProto.DataType.Name(tensor.elem_type),
                "shape": [d.dim_value if d.HasField("dim_value") else d.dim_param
                          for d in tensor.shape.dim]}

    return {
        "ir_version": model.ir_version,
        "opset_imports": [{"domain": x.domain, "version": x.version} for x in model.opset_import],
        "inputs": [info(x) for x in model.graph.input],
        "outputs": [info(x) for x in model.graph.output],
        "operators": dict(sorted(Counter(f"{n.domain or 'ai.onnx'}::{n.op_type}"
                                         for n in model.graph.node).items())),
        "initializers": [{"name": x.name, "dtype": onnx.TensorProto.DataType.Name(x.data_type),
                          "shape": list(x.dims), "raw_data_bytes": len(x.raw_data),
                          "external_data": bool(x.external_data)} for x in model.graph.initializer],
        "quantized_nodes": [{"name": n.name, "inputs": list(n.input), "outputs": list(n.output),
                             "attributes": {a.name: onnx.helper.get_attribute_value(a)
                                            for a in n.attribute}}
                            for n in model.graph.node if n.op_type == "MatMulNBits"],
    }


def quantize(model, report: dict):
    import onnx
    from onnxruntime.quantization import QuantFormat
    from onnxruntime.quantization.matmul_nbits_quantizer import (
        DefaultWeightOnlyQuantConfig, MatMulNBitsQuantizer,
    )

    if any(t.external_data for t in model.graph.initializer):
        raise ValueError("External tensors are outside this frozen single-file contract")
    if any(a.type in (onnx.AttributeProto.GRAPH, onnx.AttributeProto.GRAPHS)
           for n in model.graph.node for a in n.attribute):
        raise ValueError("Subgraphs require a separate head-protection review")
    if {x.name for x in model.graph.output} != set(OUTPUTS):
        raise ValueError("Expected exactly logits_labels and logits_d")
    if any(n.op_type == "MatMulNBits" for n in model.graph.node):
        raise ValueError("Source must be the original floating-point graph")

    # Node names are not tensor identifiers. Give unnamed/duplicate nodes stable
    # unique names so the upstream exclusion API cannot select an ambiguous set.
    counts = Counter(n.name for n in model.graph.node)
    used = {n.name for n in model.graph.node if n.name and counts[n.name] == 1}
    renamed = []
    for index, node in enumerate(model.graph.node):
        if not node.name or counts[node.name] > 1:
            name = f"gector_quant_node_{index}"
            if name in used:
                raise ValueError("Generated node name conflicts with source")
            renamed.append({"index": index, "original": node.name, "candidate": name})
            node.name = name
            used.add(name)
    report["renamed_nodes"] = renamed
    initializers = {x.name: x for x in model.graph.initializer}
    protected_nodes, protected_weights, head_records = {}, {}, []
    for output, width in OUTPUTS.items():
        head = find_head(model.graph, output)
        weight = initializers.get(head.input[1])
        if weight is None or len(weight.dims) != 2 or weight.data_type != onnx.TensorProto.FLOAT:
            raise ValueError(f"{output} must have a directly stored FP32 linear weight")
        attrs = {x.name: onnx.helper.get_attribute_value(x) for x in head.attribute}
        transposed = head.op_type == "Gemm" and attrs.get("transB", 0) != 0
        if weight.dims[0 if transposed else 1] != width:
            raise ValueError(f"Classifier width differs for {output}")
        protected_nodes[head.name] = head.SerializeToString()
        protected_weights[weight.name] = hashlib.sha256(weight.SerializeToString()).hexdigest()
        head_records.append({"output": output, "node": head.name, "op_type": head.op_type,
                             "weight": weight.name, "shape": list(weight.dims),
                             "dtype": "FLOAT", "tensor_proto_sha256": protected_weights[weight.name]})
    if len(protected_nodes) != 2:
        raise ValueError("The two output heads must be distinct")

    eligible = [n.name for n in model.graph.node
                if n.op_type == "MatMul" and n.domain in ("", "ai.onnx")
                and len(n.input) == 2 and n.input[1] in initializers
                and len(initializers[n.input[1]].dims) == 2 and n.name not in protected_nodes]
    if not eligible:
        raise ValueError("No eligible encoder MatMul weights; do not emit a mislabeled INT4 model")
    io_before = ([x.SerializeToString() for x in model.graph.input],
                 [x.SerializeToString() for x in model.graph.output])
    report["recipe"]["excluded_heads"] = head_records
    report["recipe"]["eligible_node_names"] = eligible
    report["source_census"] = census(model)
    config = DefaultWeightOnlyQuantConfig(
        block_size=128, is_symmetric=True, accuracy_level=0,
        quant_format=QuantFormat.QOperator, op_types_to_quantize=("MatMul",), bits=4,
    )
    converter = MatMulNBitsQuantizer(model, nodes_to_exclude=list(protected_nodes), algo_config=config)
    converter.process()
    candidate = converter.model.model
    nodes = {n.name: n for n in candidate.graph.node}
    tensors = {t.name: t for t in candidate.graph.initializer}
    for name, serialized in protected_nodes.items():
        if name not in nodes or nodes[name].SerializeToString() != serialized:
            raise ValueError(f"Classifier operation changed: {name}")
    for name, checksum in protected_weights.items():
        if name not in tensors or hashlib.sha256(tensors[name].SerializeToString()).hexdigest() != checksum:
            raise ValueError(f"Classifier weight changed: {name}")
    if io_before != ([x.SerializeToString() for x in candidate.graph.input],
                     [x.SerializeToString() for x in candidate.graph.output]):
        raise ValueError("Graph input/output contract changed")
    quantized = [n for n in candidate.graph.node if n.op_type == "MatMulNBits"]
    if len(quantized) != len(eligible):
        raise ValueError(f"Quantized coverage differs: {len(quantized)} versus {len(eligible)}")
    for node in quantized:
        attrs = {a.name: onnx.helper.get_attribute_value(a) for a in node.attribute}
        if (node.domain != "com.microsoft" or len(node.input) != 3
                or attrs.get("bits") != 4 or attrs.get("block_size") != 128
                or attrs.get("accuracy_level", 0) != 0):
            raise ValueError(f"Unexpected packed-weight contract: {node.name}")
    onnx.checker.check_model(candidate)
    report["candidate_census"] = census(candidate)
    report["quantized_node_count"] = len(quantized)
    return candidate


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--eval-dir", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--source-revision", required=True)
    args = parser.parse_args()
    if args.output_dir.exists() and any(args.output_dir.iterdir()):
        parser.error("output-dir must be new or empty; preserve prior attempts")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    report_path = args.output_dir / "candidate.json"
    report = {
        "schema_version": 1, "kind": "quds-gector-int4-candidate", "status": "running",
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "source_revision": args.source_revision, "source_model_sha256": SOURCE_SHA256,
        "model_revision": SOURCE_REVISION, "converter_sha256": digest(Path(__file__)),
        "recipe": {"format": "ONNX MatMulNBits", "algorithm": "ORT DEFAULT round-to-nearest",
                   "bits": 4, "block_size": 128, "symmetric": True, "accuracy_level": 0,
                   "quantized_ops": ["MatMul"], "excluded_heads": [],
                   "non_matmul_policy": "Original precision; embeddings, bias and norms unchanged"},
        "limits": ["This is ONNX INT4, not GGUF Q4_K.",
                   "Conversion integrity does not establish runtime or correction quality.",
                   "Both output-head matrices remain FP32; only encoder MatMul weights are selected."],
    }
    write_json(report_path, report)
    started = time.perf_counter()
    try:
        import onnx
        manifest, revision = verify_bundle(args.eval_dir, args.model_dir)
        source = next(x for x in manifest if x["file"] == "model.onnx")
        if revision != SOURCE_REVISION or source["sha256"] != SOURCE_SHA256:
            raise ValueError("The frozen model contract differs")
        report["versions"] = {name: importlib.metadata.version(name)
                              for name in ("onnx", "onnxruntime", "numpy")}
        if report["versions"]["onnxruntime"] != "1.23.2" or report["versions"]["onnx"] != "1.19.1":
            raise ValueError("Converter package versions differ from the declared recipe")
        report["runtime"] = {"python": sys.version, "platform": platform.platform()}
        report["source_size_bytes"] = source["size"]
        candidate = quantize(onnx.load(str(args.model_dir / "model.onnx")), report)
        output = args.output_dir / "model.int4.onnx"
        temporary = args.output_dir / "model.int4.onnx.tmp"
        onnx.save_model(candidate, str(temporary), save_as_external_data=False)
        temporary.replace(output)
        report["output"] = {"file": output.name, "sha256": digest(output),
                            "size_bytes": output.stat().st_size}
        report["status"] = "passed"
    except Exception as error:
        report["status"] = "failed"
        report["error"] = {"type": type(error).__name__, "message": str(error)}
        raise
    finally:
        report["elapsed_seconds"] = time.perf_counter() - started
        report["peak_process_rss_bytes"] = peak_rss_bytes()
        write_json(report_path, report)


if __name__ == "__main__":
    main()
