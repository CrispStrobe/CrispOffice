#!/usr/bin/env python3
"""Package existing negative controls; run only the English generator --check.

This is the collection script, not a reconstructed historical test runner.
It never runs Dart tests or Git and writes only beside this script.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys


HERE = Path(__file__).resolve().parent
BASELINE = "becfa07c1be62429a8bcf78910aa1ffb46248b1a"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode()


def summarize(data: bytes) -> dict:
    events = [json.loads(line) for line in data.decode().splitlines()
              if line.startswith("{")]
    tests = {event["test"]["id"]: event["test"] for event in events
             if event.get("type") == "testStart"}
    suites = {event["suite"]["id"]: event["suite"]["path"] for event in events
              if event.get("type") == "suite"}
    completed = [event for event in events if event.get("type") == "testDone"
                 and not event.get("hidden")]
    errors = [event for event in events if event.get("type") == "error"]
    result = Counter(event["result"] for event in completed)
    by_suite = {}
    for event in completed:
        test = tests[event["testID"]]
        suite = suites[test["suiteID"]]
        entry = by_suite.setdefault(suite, {"success": 0, "failure": 0,
                                           "error": 0, "skipped": 0})
        entry[event["result"]] += 1
        entry["skipped"] += int(bool(event.get("skipped")))
    return {
        "real_tests": len(completed),
        "success": result["success"], "failure": result["failure"],
        "error": result["error"],
        "skipped": sum(bool(event.get("skipped")) for event in completed),
        "assertion_failure_events": sum(bool(e.get("isFailure")) for e in errors),
        "non_assertion_error_events": sum(not e.get("isFailure") for e in errors),
        "hidden_test_results_excluded": sum(
            e.get("type") == "testDone" and bool(e.get("hidden")) for e in events),
        "per_suite": by_suite,
        "terminal": events[-1],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch-root", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args()
    scratch = args.scratch_root.resolve()
    repo = args.repo_root.resolve()
    engine = repo / "packages/quds_office_engine"
    baseline = scratch / "sheet-work/baseline-source"
    original_engine = baseline / "packages/quds_office_engine"
    entries = []

    def store(relative: str, data: bytes, *, original_path: str,
              origin: str, compress: bool = False) -> None:
        destination = HERE / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if compress:
            buffer = io.BytesIO()
            with gzip.GzipFile(filename="", mode="wb", fileobj=buffer,
                               compresslevel=9, mtime=0) as stream:
                stream.write(data)
            stored = buffer.getvalue()
        else:
            stored = data
        destination.write_bytes(stored)
        entries.append({
            "stored_path": relative, "original_path": original_path,
            "origin": origin, "compression": "gzip" if compress else "none",
            "gzip_mtime": 0 if compress else None,
            "original_bytes": len(data), "original_sha256": digest(data),
            "stored_bytes": len(stored), "stored_sha256": digest(stored),
        })

    def copy(source: Path, relative: str, *, compress: bool = False) -> None:
        store(relative, source.read_bytes(), original_path=str(source),
              origin="byte-for-byte existing evidence", compress=compress)

    for filename in ["pdf-baseline-receipt.json", "run_pdf_baseline.py"]:
        copy(scratch / "negative-controls" / filename, "pdf/" + filename)
    for filename in ["pdf-baseline.jsonl", "pdf-baseline-inputs.json",
                     "pdf-baseline-source-binding.json"]:
        copy(scratch / "negative-controls" / filename, "pdf/" + filename + ".gz",
             compress=True)
    copy(original_engine / ".dart_tool/package_config.json",
         "pdf/baseline-package_config.json.gz", compress=True)
    for filename in ["pdf_actual_text_scope_test.dart",
                     "pdf_logical_text_export_test.dart",
                     "support/pdf_alias_fixture.dart"]:
        copy(original_engine / "test" / filename, "pdf/test_sources/" + filename)

    for filename in ["baseline.jsonl", "baseline-inputs.sha256"]:
        copy(scratch / "cmap-validation" / filename, "cmap/" + filename + ".gz",
             compress=True)
    copy(scratch / "cmap-validation/baseline-test.dart", "cmap/baseline-test.dart")
    for filename in ["baseline.receipt.json", "baseline-regression-used.dart"]:
        copy(scratch / "sheet-work" / filename, "sheet/" + filename)
    for filename in ["baseline.stdout.jsonl", "baseline.stderr.log"]:
        copy(scratch / "sheet-work" / filename, "sheet/" + filename + ".gz",
             compress=True)

    pdf_inputs_bytes = (scratch / "negative-controls/pdf-baseline-inputs.json").read_bytes()
    pdf_inputs = json.loads(pdf_inputs_bytes)
    pdf_binding = json.loads((scratch / "negative-controls/pdf-baseline-source-binding.json").read_bytes())
    assert all(digest((baseline / path).read_bytes()) == expected
               for path, expected in pdf_inputs.items())
    pdf_matches = {}
    pdf_test_versions = {}
    for name in ["pdf_actual_text_scope_test.dart", "pdf_logical_text_export_test.dart"]:
        pdf_matches[name] = (original_engine / "test" / name).read_bytes() == (engine / "test" / name).read_bytes()
        pdf_test_versions[name] = {
            "historical_snapshot_sha256": digest((original_engine / "test" / name).read_bytes()),
            "current_at_collection_sha256": digest((engine / "test" / name).read_bytes()),
            "equal_at_collection": pdf_matches[name],
        }
    sheet_receipt = json.loads((scratch / "sheet-work/baseline.receipt.json").read_bytes())
    for path, expected in sheet_receipt["inputs"].items():
        actual = (scratch / "sheet-work/baseline-regression-used.dart" if path.startswith("test/")
                  else original_engine / path)
        assert digest(actual.read_bytes()) == expected
    cmap_map = {}
    for line in (scratch / "cmap-validation/baseline-inputs.sha256").read_text().splitlines():
        expected, path = line.split(maxsplit=1)
        cmap_map[path] = expected
        actual = (scratch / "cmap-validation/baseline-test.dart" if path.startswith("test/")
                  else original_engine / path)
        assert digest(actual.read_bytes()) == expected

    # This checks the incoming generator without writing its generated assets.
    generator = engine / "tool/proofing/generate_english_hyphenation.py"
    manifest_path = engine / "third_party/hyphenation/english-manifest.json"
    english_manifest = json.loads(manifest_path.read_bytes())
    english_paths = {generator, manifest_path}
    for item in english_manifest["inputs"]:
        english_paths.add(engine / "third_party/hyphenation" / item["source"])
        english_paths.add(engine / item["generated"])
        english_paths.add(engine / "third_party/hyphenation" /
                          ("ENGLISH_US_LICENSE" if item["language"] == "en-US" else "ENGLISH_GB_LICENSE"))
    before = {str(path.relative_to(repo)): digest(path.read_bytes())
              for path in sorted(english_paths)}
    command = [sys.executable, "tool/proofing/generate_english_hyphenation.py", "--check"]
    started = datetime.now(timezone.utc).isoformat()
    checked = subprocess.run(command, cwd=engine, capture_output=True, timeout=30)
    finished = datetime.now(timezone.utc).isoformat()
    after = {str(path.relative_to(repo)): digest(path.read_bytes())
             for path in sorted(english_paths)}
    receipt = {
        "kind": "read-only generator verification; not a negative-control test run",
        "command": command, "cwd": str(engine),
        "started_at_utc": started, "finished_at_utc": finished,
        "exit_code": checked.returncode, "inputs_unchanged": before == after,
        "stdout_sha256": digest(checked.stdout), "stderr_sha256": digest(checked.stderr),
        "input_count": len(before), "github_actions_used": False,
    }
    store("english-generator/check.stdout.json.gz", checked.stdout,
          original_path="captured stdout from command in receipt.json",
          origin="fresh read-only generator check", compress=True)
    store("english-generator/check.stderr.log.gz", checked.stderr,
          original_path="captured stderr from command in receipt.json",
          origin="fresh read-only generator check", compress=True)
    store("english-generator/inputs.json.gz", json_bytes({"before": before, "after": after}),
          original_path="collected input hashes before and after --check",
          origin="fresh read-only input binding", compress=True)
    store("english-generator/receipt.json", json_bytes(receipt),
          original_path="generated read-only command receipt",
          origin="fresh read-only generator check")
    copy(generator, "english-generator/generate_english_hyphenation-used.py")
    assert checked.returncode == 0 and before == after

    runs = [
        {"id": "pdf", "log": "pdf/pdf-baseline.jsonl.gz",
         "baseline_commit": BASELINE,
         "test_variant": "Exact historical ac295d4b-era snapshots; final logical-export control helper subsequently changed",
         "production_binding_scope": "294 production and manifest blobs checked against baseline, plus 298 before/after input hashes",
         "expected": (33, 3, 30),
         "source": scratch / "negative-controls/pdf-baseline.jsonl"},
        {"id": "cmap", "log": "cmap/baseline.jsonl.gz",
         "baseline_commit": BASELINE,
         "test_variant": "Earlier 45-probe snapshot; not the final expanded 55-test file",
         "production_binding_scope": "Recorded sfnt_parser.dart hash matches baseline; no full-workspace baseline map was retained",
         "expected": (45, 4, 41),
         "source": scratch / "cmap-validation/baseline.jsonl"},
        {"id": "sheet", "log": "sheet/baseline.stdout.jsonl.gz",
         "baseline_commit": BASELINE,
         "test_variant": "Original 28-test snapshot; not the subsequently expanded test file",
         "production_binding_scope": "Three recorded production source hashes and the exact original test snapshot",
         "expected": (28, 11, 17),
         "source": scratch / "sheet-work/baseline.stdout.jsonl"},
    ]
    for run in runs:
        run["summary"] = summarize(run.pop("source").read_bytes())
        expected = run.pop("expected")
        assert tuple(run["summary"][key] for key in ["real_tests", "success", "failure"]) == expected
        assert run["summary"]["error"] == run["summary"]["skipped"] == 0
        assert run["summary"]["non_assertion_error_events"] == 0

    for name in ["README.md", "verify.py", "package_evidence.py", "cmap/invocation.json"]:
        path = HERE / name
        if not path.is_file():
            raise FileNotFoundError(path)
        data = path.read_bytes()
        entries.append({"stored_path": name, "original_path": "created in evidence bundle: " + name,
                        "origin": "collection documentation or verification script",
                        "compression": "none", "gzip_mtime": None,
                        "original_bytes": len(data), "original_sha256": digest(data),
                        "stored_bytes": len(data), "stored_sha256": digest(data)})
    manifest = {
        "schema_version": 1, "collected_at_utc": datetime.now(timezone.utc).isoformat(),
        "baseline_commit": BASELINE,
        "purpose": "Preserve existing failing regression evidence without rerunning tests",
        "negative_control_tests_rerun_during_collection": False,
        "github_actions_used": False,
        "counts_policy": "Each run is reported separately; do not add these overlapping historical results to final passing cohorts.",
        "gzip": {"mtime": 0, "filename": "", "compression_level": 9},
        "runs": runs,
        "collection_checks": {
            "pdf_recorded_inputs_rechecked": len(pdf_inputs),
            "pdf_recorded_inputs_still_match": True,
            "pdf_recorded_production_blob_count": pdf_binding["production_file_count"],
            "pdf_recorded_production_blobs_match_baseline": pdf_binding["all_production_blobs_match"],
            "pdf_test_copies_equal_current": pdf_matches,
            "pdf_test_versions": pdf_test_versions,
            "cmap_parser_hash_matches_isolated_baseline": True,
            "sheet_recorded_source_and_exact_test_hashes_match": True,
            "english_generator_exit_code": checked.returncode,
            "english_generator_inputs_unchanged": before == after,
        },
        "artifacts": sorted(entries, key=lambda item: item["stored_path"]),
    }
    (HERE / "manifest.json").write_bytes(json_bytes(manifest))
    print(json.dumps({"artifact_count": len(entries),
                      "summaries": {run["id"]: run["summary"] for run in runs},
                      "english_generator": receipt}, indent=2))


if __name__ == "__main__":
    main()
