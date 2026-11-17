#!/usr/bin/env python3
"""Verify archived bytes and existing negative-control logs; execute no tests."""
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    manifest = json.loads((HERE / "manifest.json").read_bytes())
    raw = {}
    paths = set()
    for artifact in manifest["artifacts"]:
        name = artifact["stored_path"]
        assert name not in paths, name
        paths.add(name)
        stored = (HERE / name).read_bytes()
        assert len(stored) == artifact["stored_bytes"], name
        assert sha(stored) == artifact["stored_sha256"], name
        if artifact["compression"] == "gzip":
            assert stored[:3] == b"\x1f\x8b\x08", name
            assert stored[3] == 0 and stored[4:8] == b"\0" * 4, name
            data = gzip.decompress(stored)
        else:
            assert artifact["compression"] == "none", name
            data = stored
        assert len(data) == artifact["original_bytes"], name
        assert sha(data) == artifact["original_sha256"], name
        raw[name] = data
    summaries = {}
    for run in manifest["runs"]:
        events = [json.loads(line) for line in raw[run["log"]].decode().splitlines()
                  if line.startswith("{")]
        completed = [event for event in events if event.get("type") == "testDone"
                     and not event.get("hidden")]
        counts = Counter(event["result"] for event in completed)
        errors = [event for event in events if event.get("type") == "error"]
        observed = {
            "real_tests": len(completed), "success": counts["success"],
            "failure": counts["failure"], "error": counts["error"],
            "skipped": sum(bool(event.get("skipped")) for event in completed),
            "assertion_failure_events": sum(bool(event.get("isFailure")) for event in errors),
            "non_assertion_error_events": sum(not event.get("isFailure") for event in errors),
            "hidden_test_results_excluded": sum(
                event.get("type") == "testDone" and bool(event.get("hidden")) for event in events),
            "terminal": events[-1],
        }
        for key, value in observed.items():
            assert value == run["summary"][key], (run["id"], key)
        assert observed["terminal"]["type"] == "done"
        assert observed["terminal"]["success"] is False
        assert observed["assertion_failure_events"] == observed["failure"]
        assert observed["non_assertion_error_events"] == observed["error"] == observed["skipped"] == 0
        summaries[run["id"]] = observed
    pdf = json.loads(raw["pdf/pdf-baseline-receipt.json"])
    assert sha(raw["pdf/pdf-baseline.jsonl.gz"]) == pdf["log_sha256"]
    assert sha(raw["pdf/pdf-baseline-inputs.json.gz"]) == pdf["inputs_sha256"]
    pdf_inputs = json.loads(raw["pdf/pdf-baseline-inputs.json.gz"])
    for name in ["pdf_actual_text_scope_test.dart", "pdf_logical_text_export_test.dart",
                 "support/pdf_alias_fixture.dart"]:
        assert sha(raw["pdf/test_sources/" + name]) == pdf_inputs["packages/quds_office_engine/test/" + name]
    assert sha(raw["pdf/baseline-package_config.json.gz"]) == pdf_inputs["packages/quds_office_engine/.dart_tool/package_config.json"]
    binding = json.loads(raw["pdf/pdf-baseline-source-binding.json.gz"])
    assert binding["all_production_blobs_match"]
    assert binding["production_file_count"] == len(binding["production_files"]) == 294
    assert all(entry["match"] and entry["expected_git_blob"] == entry["actual_git_blob"]
               for entry in binding["production_files"])
    cmap_map = dict(line.split(maxsplit=1)[::-1]
                    for line in raw["cmap/baseline-inputs.sha256.gz"].decode().splitlines())
    assert sha(raw["cmap/baseline-test.dart"]) == cmap_map["test/sfnt_cmap_validation_test.dart"]
    invocation = json.loads(raw["cmap/invocation.json"])
    assert cmap_map["lib/src/fonts/sfnt_parser.dart"] == invocation["baseline_parser_sha256"]
    sheet = json.loads(raw["sheet/baseline.receipt.json"])
    assert sha(raw["sheet/baseline-regression-used.dart"]) == sheet["inputs"]["test/sheet_conditional_fidelity_test.dart"]
    for key in ["success", "failure", "error"]:
        assert sheet["canonical_results"][key] == summaries["sheet"][key]
    english = json.loads(raw["english-generator/receipt.json"])
    assert english["exit_code"] == 0 and english["inputs_unchanged"]
    assert sha(raw["english-generator/check.stdout.json.gz"]) == english["stdout_sha256"]
    assert sha(raw["english-generator/check.stderr.log.gz"]) == english["stderr_sha256"]
    inputs = json.loads(raw["english-generator/inputs.json.gz"])
    assert inputs["before"] == inputs["after"]
    generator_key = "packages/quds_office_engine/tool/proofing/generate_english_hyphenation.py"
    assert sha(raw["english-generator/generate_english_hyphenation-used.py"]) == inputs["before"][generator_key]
    assert json.loads(raw["english-generator/check.stdout.json.gz"])["mode"] == "check"
    print(json.dumps({"status": "passed", "artifacts_verified": len(paths),
                      "negative_control_summaries": summaries,
                      "english_generator_check": "passed; inputs unchanged",
                      "tests_executed_by_verifier": 0}, indent=2))


if __name__ == "__main__":
    main()
