#!/usr/bin/env python3
"""Summarize bounded runtime evidence and compare INT4 edits with frozen F32."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import statistics

from quantize_int4 import SOURCE_SHA256, SOURCE_REVISION


def read(path: Path):
    return json.loads(path.read_text()) if path.is_file() else None


def timing_summary(rows: list[dict]) -> dict:
    samples = [value for row in rows for value in row.get("samples_seconds", [])]
    ordered = sorted(samples)
    tokens = [row["token_count"] for row in rows if isinstance(row.get("token_count"), int)]
    worst = max(rows, key=lambda row: row.get("p95_seconds", 0), default=None)
    return {
        "cases": len(rows), "samples": len(samples),
        "token_count_min": min(tokens) if tokens else None,
        "token_count_max": max(tokens) if tokens else None,
        "aggregate_sample_median_seconds": statistics.median(samples) if samples else None,
        "aggregate_sample_p95_seconds": ordered[max(0, (95 * len(ordered) + 99) // 100 - 1)]
        if ordered else None,
        "maximum_sample_seconds": max(samples) if samples else None,
        "worst_case": {key: worst.get(key) for key in
                       ("id", "token_count", "median_seconds", "p95_seconds", "maximum_seconds")}
        if worst else None,
        "aggregation_note": "Sample statistics combine the recorded sentence lengths; inspect per-case rows too.",
    }


def native_summary(reference: dict | None) -> dict | None:
    if reference is None:
        return None
    first, complete = [], []
    for case in reference.get("cases", []):
        tokens = len(case["passes"][0]["input_ids"][0]) if case.get("passes") else None
        for key, destination in (("reference_first_pass_benchmark", first),
                                 ("reference_correction_benchmark", complete)):
            if key in case:
                destination.append({"id": case["id"], "token_count": tokens, **case[key]})
    return {
        "inference_model": {key: reference.get("inference_model", {}).get(key) for key in
                            ("variant", "sha256", "size_bytes", "source_model_sha256")},
        "setup_seconds": reference.get("setup_seconds"),
        "peak_process_rss_bytes": reference.get("peak_process_rss_bytes"),
        "setup_peak_process_rss_bytes": reference.get("setup_peak_process_rss_bytes"),
        "ort_session": reference.get("runtime", {}).get("ort_session"),
        "case_count": len(reference.get("cases", [])),
        "pass_count": sum(len(row.get("passes", [])) for row in reference.get("cases", [])),
        "first_pass_inference": timing_summary(first),
        "complete_reference_correction": timing_summary(complete),
    }


def dart_summary(report: dict | None) -> dict | None:
    if report is None:
        return None
    keys = ("passed", "complete", "runtime_passed", "tokenizer_passed", "stage", "error",
            "model_variant", "experiments", "graph_load_seconds", "pool_setup_seconds", "cold_first_inference_seconds",
            "inference_peak_rss_bytes", "checkpoint_peak_rss_bytes", "post_validation_peak_rss_bytes",
            "rss_before_load_bytes", "rss_after_load_bytes", "rss_after_pool_bytes",
            "expected_cases", "expected_passes", "cases_timed", "passes_validated", "thread_scope")
    return {
        **{key: report.get(key) for key in keys},
        "inference_timing": timing_summary(report.get("timings", [])),
        "top_profile_operators": sorted(report.get("diagnostic_profile", {}).get("operators", []),
                                        key=lambda row: row.get("seconds", 0), reverse=True)[:6],
        "first_tokenizer_failures": report.get("tokenizer_failures", [])[:3],
        "first_runtime_failures": [row for row in report.get("validation", [])
                                   if row.get("passed") is not True][:3],
    }


def compare_references(baseline: dict, candidate: dict, expected: list[dict]) -> dict:
    left = {row["id"]: row for row in baseline["cases"]}
    right = {row["id"]: row for row in candidate["cases"]}
    ids = {row["id"] for row in expected}
    if len(ids) != len(expected) or set(left) != ids or set(right) != ids:
        raise ValueError("Reference case coverage differs from the frozen complete panel")
    if baseline["cases_sha256"] != candidate["cases_sha256"]:
        raise ValueError("Baseline and candidate use different cases")
    lost_fixes, new_clean_edits, differences = [], [], []
    baseline_fixes = candidate_fixes = baseline_clean_edits = candidate_clean_edits = 0
    for source in expected:
        name = source["id"]
        a, b = left[name], right[name]
        for field in ("input", "kind", "expected", "locale"):
            if a.get(field) != source.get(field) or b.get(field) != source.get(field):
                raise ValueError(f"Frozen case metadata changed: {name}: {field}")
        if source["kind"] == "error":
            a_ok, b_ok = a["corrected"] == source["expected"], b["corrected"] == source["expected"]
            baseline_fixes += a_ok
            candidate_fixes += b_ok
            if a_ok and not b_ok:
                lost_fixes.append(name)
        elif source["kind"] == "clean":
            baseline_clean_edits += a["corrected"] != source["input"]
            candidate_clean_edits += b["corrected"] != source["input"]
            if b["corrected"] != source["input"] and b["corrected"] != a["corrected"]:
                new_clean_edits.append(name)
        else:
            raise ValueError(f"Unknown source case kind: {source['kind']}")
        if a["corrected"] != b["corrected"] or a["suggestions_utf16"] != b["suggestions_utf16"]:
            differences.append({"id": name, "kind": source["kind"], "input": source["input"],
                                "baseline": a["corrected"], "candidate": b["corrected"],
                                "baseline_suggestions_utf16": a["suggestions_utf16"],
                                "candidate_suggestions_utf16": b["suggestions_utf16"]})
    return {"complete": True, "case_count": len(expected),
            "baseline_error_fixes": baseline_fixes, "candidate_error_fixes": candidate_fixes,
            "baseline_changed_clean_controls": baseline_clean_edits,
            "candidate_changed_clean_controls": candidate_clean_edits,
            "lost_baseline_fixes": lost_fixes, "new_or_changed_false_edits_on_clean": new_clean_edits,
            "differences": differences,
            "frozen_probe_nonregression_passed": not lost_fixes and not new_clean_edits}


def verify_evidence_chain(root: Path, baseline: dict, candidate: dict, manifest: dict,
                          dart_f32: dict, dart_int4: dict, *, provenance: dict | None = None) -> None:
    # Historical runs did not declare experiment selection. Preserve their
    # evidence, while requiring explicit matching metadata for newer runs.
    declarations = None
    if provenance is not None:
        if not isinstance(provenance, dict):
            raise ValueError("Source provenance must be an object")
        if "declared_dart_experiments" in provenance:
            declarations = provenance["declared_dart_experiments"]
            if not isinstance(declarations, dict):
                raise ValueError("Declared Dart experiments must be an object")
    if not manifest or manifest.get("status") != "passed" or manifest.get("source_model_sha256") != SOURCE_SHA256:
        raise ValueError("No authenticated successful INT4 conversion manifest")
    if manifest.get("kind") != "quds-gector-int4-candidate" or manifest.get("schema_version") != 1:
        raise ValueError("Candidate manifest schema differs")
    if (baseline.get("revision") != SOURCE_REVISION or candidate.get("revision") != SOURCE_REVISION
            or baseline.get("input_sha256") != candidate.get("input_sha256")
            or baseline.get("input_sha256", {}).get("model.onnx") != SOURCE_SHA256):
        raise ValueError("Reference bundle/model identities differ")
    base_model, quant_model = baseline.get("inference_model", {}), candidate.get("inference_model", {})
    candidate_sha = manifest.get("output", {}).get("sha256")
    if (base_model.get("sha256") != SOURCE_SHA256 or base_model.get("variant") != "float32"
            or base_model.get("source_model_sha256") != SOURCE_SHA256):
        raise ValueError("Baseline is not the frozen floating-point model")
    if (not candidate_sha or candidate_sha == SOURCE_SHA256
            or quant_model.get("sha256") != candidate_sha
            or quant_model.get("variant") != "matmulnbits-int4"
            or quant_model.get("source_model_sha256") != SOURCE_SHA256
            or quant_model.get("size_bytes") != manifest["output"].get("size_bytes")
            or quant_model.get("candidate_manifest_sha256") !=
            hashlib.sha256((root / "candidate" / "candidate.json").read_bytes()).hexdigest()):
        raise ValueError("INT4 reference is not linked to this exact candidate manifest")
    for variant, oracle, actual, model_sha in (("f32", baseline, dart_f32, SOURCE_SHA256),
                                               ("int4", candidate, dart_int4, candidate_sha)):
        if not actual or actual.get("complete") is not True:
            raise ValueError(f"Dart {variant} is missing or incomplete")
        if declarations is not None:
            arm = f"dart-{variant}"
            declared = declarations.get(arm)
            if not isinstance(declared, list) or not all(isinstance(name, str) for name in declared):
                raise ValueError(f"Declared experiments for {arm} must be a list of names")
            if actual.get("experiments") != declared:
                raise ValueError(f"Dart {variant} experiment metadata is missing or differs from its declaration")
        cases = len(oracle["cases"])
        passes = sum(len(row["passes"]) for row in oracle["cases"])
        fixture_sha = hashlib.sha256((root / f"reference-{variant}" / "reference.json").read_bytes()).hexdigest()
        if (actual.get("model_sha256") != model_sha or actual.get("fixture_sha256") != fixture_sha
                or actual.get("tokenizer_sha256") != oracle["input_sha256"].get("tokenizer.json")
                or actual.get("expected_cases") != cases or actual.get("cases_timed") != cases
                or actual.get("expected_passes") != passes or actual.get("passes_validated") != passes
                or len(actual.get("timings", [])) != cases or len(actual.get("validation", [])) != passes):
            raise ValueError(f"Dart {variant} source linkage or complete-case coverage differs")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--cases", type=Path, required=True)
    args = parser.parse_args()
    reports = args.root / "reports"
    reports.mkdir(parents=True, exist_ok=True)
    stages = {path.name.removesuffix(".status.json"): read(path)
              for path in sorted(reports.glob("*.status.json"))}
    baseline = read(args.root / "reference-f32" / "reference.json")
    candidate = read(args.root / "reference-int4" / "reference.json")
    required = ("python-dependencies", "dart-dependencies", "python-tests", "dart-compile", "reference-f32", "quantize-int4",
                "reference-int4", "dart-f32", "dart-int4")
    result = {"schema_version": 1, "kind": "quds-gector-qualification-summary",
              "application_qualified": False,
              "stages": stages,
              "all_required_stages_passed": all(stages.get(name, {}).get("status") == "passed"
                                                for name in required),
              "source_provenance": read(reports / "provenance.json"),
              "dart_f32": read(reports / "dart-f32.json"),
              "dart_int4": read(reports / "dart-int4.json"),
              "limits": ["This frozen synthetic panel does not establish representative German accuracy.",
                         "The upstream runner omits application guards and spelling checks.",
                         "Dart timings cover forwards, not the complete iterative checker.",
                         "Hosted CPU measurements do not qualify mobile, browser or other devices.",
                         "No runtime, model publication, release or default provider is enabled."]}
    try:
        expected = json.loads(args.cases.read_text())
        cases_hash = hashlib.sha256(args.cases.read_bytes()).hexdigest()
        if not baseline or not candidate:
            raise ValueError("Both complete native ORT references are required for the quantization comparison")
        if baseline["cases_sha256"] != cases_hash:
            raise ValueError("Reference differs from the supplied frozen cases file")
        result["quantization_quality"] = compare_references(baseline, candidate, expected)
    except Exception as error:
        result["quantization_quality"] = {"complete": False, "error": str(error),
                                          "frozen_probe_nonregression_passed": False}
    candidate_manifest = read(args.root / "candidate" / "candidate.json")
    try:
        verify_evidence_chain(args.root, baseline, candidate, candidate_manifest,
                              result["dart_f32"], result["dart_int4"],
                              provenance=result["source_provenance"])
        result["evidence_chain_passed"] = True
        result["evidence_chain_error"] = None
    except Exception as error:
        result["evidence_chain_passed"] = False
        result["evidence_chain_error"] = str(error)
    result["probe_passed"] = (result["all_required_stages_passed"]
                              and result["evidence_chain_passed"]
                              and result["quantization_quality"]["frozen_probe_nonregression_passed"]
                              and bool(result["dart_f32"] and result["dart_f32"].get("passed"))
                              and bool(result["dart_int4"] and result["dart_int4"].get("passed")))
    result["measurements"] = {
        "native_ort_f32": native_summary(baseline),
        "native_ort_int4": native_summary(candidate),
        "dart_f32": dart_summary(result["dart_f32"]),
        "dart_int4": dart_summary(result["dart_int4"]),
        "candidate_artifact": {key: candidate_manifest.get(key) for key in
                               ("status", "output", "quantized_node_count", "elapsed_seconds",
                                "peak_process_rss_bytes", "error")} if candidate_manifest else None,
        "stage_resources": {name: {key: value.get(key) for key in
                                   ("status", "elapsed_seconds", "child_peak_rss_bytes", "error")}
                            for name, value in stages.items()},
    }
    (reports / "qualification-summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("probe_passed", "application_qualified",
                                                  "all_required_stages_passed", "evidence_chain_passed",
                                                  "evidence_chain_error",
                                                  "quantization_quality",
                                                  "measurements")},
                     ensure_ascii=False, indent=2))
    return 0 if result["probe_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
