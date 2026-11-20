#!/usr/bin/env python3
"""Independently recount the host-followup gate and bind all saved inputs.

Runs no application tests. Historical milestone and first-continuation counts
are deliberately excluded from this fresh evidence population.
"""
from __future__ import annotations

import argparse
import ast
from datetime import datetime, timezone
from fnmatch import fnmatchcase
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys


HERE = Path(__file__).resolve().parent
HELPER = HERE.parent / "evidence-audit/recheck_saved_evidence.py"
PINNED_HELPER = "55418e615c35d0add37b14edc2370074a288a0be6b194c7ac11d63f8175924b5"
PINNED_RUNNER = "4d01ed59729abaa64e3ab643e8ebcb2f7136dd2d9f02cc4b07b81a06fbb919bf"
PINNED_ADAPTER = "6a2aeba352f43a8d3e1712b11c329eb35b4ba5a9495197b97de6df3b347a2b39"
EXPECTED_FILE_COUNTS = {
    "engine-zotero": 29,
    "editor-zotero": 43,
    "engine-rendering": 14,
    "editor-rendering": 10,
    "engine-word-layout": 22,
    "editor-word-layout": 14,
    "mail-host": 11,
    "studio-integration": 14,
}
CACHE = {}


def load_module(path: Path, name: str, expected_sha256: str):
    assert hashlib.sha256(path.read_bytes()).hexdigest() == expected_sha256, path
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


helper = load_module(HELPER, "host_audit_saved_helpers", PINNED_HELPER)
adapter = load_module(HERE / "run_host_followup.py", "host_audit_catalog", PINNED_ADAPTER)
assert set(adapter.HOST_COHORTS) == set(EXPECTED_FILE_COUNTS)


def current_record(path: Path) -> dict:
    path = path.resolve()
    stat = path.stat()
    key = (str(path), stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns)
    if key not in CACHE:
        sha = hashlib.sha256()
        blob = hashlib.sha1(f"blob {stat.st_size}\0".encode())
        with path.open("rb") as stream:
            for data in iter(lambda: stream.read(1024 * 1024), b""):
                sha.update(data)
                blob.update(data)
        CACHE[key] = {"bytes": stat.st_size, "sha256": sha.hexdigest(), "git_blob_sha1": blob.hexdigest()}
    return CACHE[key]


def selection_from_git(name: str, entries: dict) -> list[str]:
    spec = adapter.HOST_COHORTS[name]
    prefix = spec["package"] + "/test/"
    result = {prefix + path for path in spec["additional"]}
    for pattern in spec["patterns"]:
        assert "/" not in pattern, "Extend this explicit top-level selector before adding recursive patterns"
        result.update(path for path in entries if path.startswith(prefix)
                      and "/" not in path[len(prefix):]
                      and fnmatchcase(path[len(prefix):], pattern))
    assert result and all(path in entries for path in result), (name, "selection missing from source Git tree")
    assert len(result) == EXPECTED_FILE_COUNTS[name], (name, len(result))
    return sorted(result)


def verify_static(repo: Path, evidence: Path, candidate_tree: dict, objects: dict) -> dict:
    path = evidence / "static/receipt.json"
    receipt = helper.read(path)
    assert receipt["accepted"] and receipt["inputs_identical"]
    assert receipt["before"] == receipt["after"]
    assert set(receipt["paths"]) == set(receipt["before"])
    source_tree = helper.tree(repo, receipt["head"])
    expected = sorted(path.decode() for path in helper.git(
        repo, "diff", "--name-only", "--diff-filter=ACMRT", "-z", receipt["base"], receipt["head"]
    ).split(b"\0") if path and path.endswith(b".dart"))
    assert sorted(receipt["paths"]) == expected
    extra = helper.source_records(repo, {source_tree[path] for path in expected} - objects.keys())
    objects.update(extra)
    for path, sha in receipt["before"].items():
        assert objects[source_tree[path]]["sha256"] == sha, path
    for name, check in receipt["checks"].items():
        assert name in ("format", "analysis") and check["exit_code"] == 0
        command = check["command"]
        if name == "format":
            assert command[1:4] == ["format", "--output=none", "--set-exit-if-changed"]
            assert sorted(command[4:]) == expected, (name, "unexpected command targets")
        else:
            assert command[1:3] == ["analyze", "--fatal-infos"]
            assert sorted(command[3:]) == expected
    changed = [path for path in expected if candidate_tree.get(path) != source_tree[path]]
    return {"source_commit": receipt["head"], "baseline_commit": receipt["base"],
            "target_count": len(expected), "receipt_sha256": current_record(evidence / "static/receipt.json")["sha256"],
            "before_after_and_git_source_verified": True,
            "candidate_changed_targets": changed,
            "all_targets_preserved_at_candidate": not changed}


def verify_comparator(repo: Path, evidence: Path, candidate_tree: dict, objects: dict) -> dict:
    folder = evidence / "comparator-controls"
    receipt = helper.read(folder / "receipt.json")
    assert receipt["status"] == "passed" and receipt["tests_run"] == 8
    assert receipt["failures"] == receipt["errors"] == receipt["skipped"] == 0
    assert receipt["source"] == "214c4ed80bef0cb871f74e90c506d508679d3d6e"
    assert receipt["source_before"] == receipt["source_after"] and receipt["source_matches_git"]
    assert receipt["runtime_before"] == receipt["runtime_after"]
    source_tree = helper.tree(repo, receipt["source"])
    source_paths = {"packages/quds_office_engine/tool/fidelity/" + name for name in
                    ["word_native_layout.py", "test_word_native_layout.py"]}
    assert set(receipt["source_before"]) == source_paths
    objects.update(helper.source_records(repo, {source_tree[path] for path in source_paths} - objects.keys()))
    for path, expected in receipt["source_before"].items():
        assert objects[source_tree[path]] == expected
        assert candidate_tree[path] == source_tree[path] and current_record(repo / path) == expected
    for path, expected in receipt["runtime_before"].items():
        assert current_record(Path(path)) == expected
    assert current_record(evidence / "run_comparator_checks.py") == receipt["runner"]
    assert receipt["runner"]["sha256"] == "c5275345cb0607c917295fc8d7a757482dec6a50d5a505852234265df1eed89d"
    assert current_record(folder / "unittest.log") == receipt["log"]
    log = (folder / "unittest.log").read_text()
    names = re.findall(r"^test_\w+ \(([^)]+)\) \.\.\. ok$", log, re.M)
    assert names == receipt["case_ids"] and len(names) == len(set(names)) == 8
    assert re.search(r"\nRan 8 tests in [\d.]+s\n\nOK\n\Z", log)
    source = helper.git(repo, "show", receipt["source"] + ":packages/quds_office_engine/tool/fidelity/test_word_native_layout.py")
    module = ast.parse(source)
    expected_names = sorted("captured_word_comparator_tests." + node.name + "." + method.name
                            for node in module.body if isinstance(node, ast.ClassDef)
                            for method in node.body if isinstance(method, ast.FunctionDef) and method.name.startswith("test_"))
    assert sorted(names) == expected_names
    return {"status": "verified", "source_commit": receipt["source"], "synthetic_controls_passed": 8,
            "source_files_verified": len(source_paths), "named_python_pillow_runtime_files_verified": len(receipt["runtime_before"]),
            "receipt_sha256": current_record(folder / "receipt.json")["sha256"],
            "log_sha256": receipt["log"]["sha256"], "case_ids": names,
            "included_in_dart_test_total": False, "native_word_or_real_corpus_execution": False,
            "scope": receipt["scope"]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, default=HERE)
    parser.add_argument("--source", action="append", required=True,
                        help="Explicitly allowed source commit; repeat if cohorts were qualified at several commits")
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo, evidence = args.repo.resolve(), args.evidence.resolve()
    resolve = lambda ref: helper.git(repo, "rev-parse", "--verify", ref).decode().strip()
    sources = {resolve(ref) for ref in args.source}
    candidate = resolve(args.candidate)
    assert resolve("HEAD") == candidate, "Audit the named checkout candidate after all tests have finished"
    trees = {source: helper.tree(repo, source) for source in sources}
    candidate_tree = helper.tree(repo, candidate)
    receipts, inventories, oids = {}, {}, set()
    for name in EXPECTED_FILE_COUNTS:
        folder = evidence / ("accepted-" + name)
        receipt = helper.read(folder / "receipt.json")
        assert receipt["source_head_at_start"] in sources, (name, "unexpected qualification source")
        receipts[name] = receipt
        inventory = helper.read(folder / "inputs.json.gz")["before"]
        inventories[name] = inventory
        source_tree = trees[receipt["source_head_at_start"]]
        oids.update(source_tree[path] for path in inventory["source"])
        oids.update(candidate_tree[path] for path in inventory["source"] if path in candidate_tree)
    objects = helper.source_records(repo, oids)
    all_cases, all_paths, results, drift = [], [], [], {}
    source_union = set()
    for name in EXPECTED_FILE_COUNTS:
        folder = evidence / ("accepted-" + name)
        receipt, inventory = receipts[name], inventories[name]
        source = receipt["source_head_at_start"]
        source_tree = trees[source]
        assert receipt["status"] == "passed" and receipt["exit_code"] == 0 and not receipt["timed_out"], name
        assert receipt["guards"] and all(value is True for value in receipt["guards"].values()), name
        assert receipt["source_head_at_finish"] == source and receipt["head_unchanged"]
        assert not receipt["application_timeouts_modified"]
        assert receipt["validation_runner"]["sha256"] == PINNED_RUNNER
        actual_runner = current_record(Path(receipt["validation_runner"]["path"]))
        assert all(receipt["validation_runner"][key] == value for key, value in actual_runner.items())
        for filename, expected in receipt["artifacts"].items():
            assert current_record(folder / filename) == expected, (name, filename)
        assert helper.read(folder / "input-check.json") == receipt["fingerprints"]
        counted, cases = helper.recount(folder / "events.jsonl.gz", repo, receipt["cwd"])
        selected = selection_from_git(name, source_tree)
        assert selected == counted["suite_paths"] == sorted(receipt["selected_repository_paths"])
        assert counted["passed"] == receipt["tests"]["passed"]
        assert counted["files"] == receipt["tests"]["suite_count"] == EXPECTED_FILE_COUNTS[name]
        for suite in receipt["tests"]["suites"]:
            path = str(Path(suite["path"]).relative_to(repo))
            assert counted["per_suite"][path] == suite["passed"] and suite["failed"] == suite["skipped"] == 0
        for area, value in inventory.items():
            assert helper.digest(value) == receipt["fingerprints"]["before_sha256"][area]
            assert helper.digest(value) == receipt["fingerprints"]["after_sha256"][area]
            assert receipt["fingerprints"]["changed_paths"][area] == []
        for path, expected in inventory["source"].items():
            oid = source_tree[path]
            assert objects[oid] == expected, (name, path)
            source_union.add(path)
            if candidate_tree.get(path) != oid:
                entry = drift.setdefault(path, {"candidate_blob": candidate_tree.get(path), "qualified_versions": {}})
                entry["qualified_versions"][source] = oid
            assert path in candidate_tree, ("candidate removed a recorded input", path)
            assert current_record(repo / path) == objects[candidate_tree[path]], ("uncommitted candidate input", path)
        live_counts = {"source_git_inputs": len(inventory["source"]), "dependency_files": 0}
        for area, root in [("runtime", Path(receipt["runtime"]["flutter_root"])), ("workspace", repo)]:
            for path, expected in inventory[area].items():
                assert current_record(root / path) == expected, (name, area, path)
            live_counts[area] = len(inventory[area])
        for package, info in inventory["dependencies"].items():
            assert len(info["files"]) == info["file_count"]
            assert helper.digest(info["files"]) == info["inventory_sha256"]
            for path, expected in info["files"].items():
                assert current_record(Path(info["root"]) / path) == expected, (name, package, path)
            live_counts["dependency_files"] += len(info["files"])
        for path, expected in inventory["host_fonts"].items():
            assert Path(path).is_file() is expected["present"], (name, "host-font presence", path)
            if expected["present"]:
                assert current_record(Path(path)) == {key: value for key, value in expected.items() if key != "present"}
        live_counts["host_fonts"] = len(inventory["host_fonts"])
        provenance = receipt.get("selection_adapter")
        if provenance is None:
            # This cohort started before the additive adapter was available.
            # Its unchanged primary selector is exactly the reviewed 43-file set.
            assert name == "editor-zotero"
            assert source == "214c4ed80bef0cb871f74e90c506d508679d3d6e"
            assert not (folder / "selection-adapter.json").exists()
            selection_provenance = "pinned_primary_runner_direct"
        else:
            assert provenance == helper.read(folder / "selection-adapter.json")
            assert provenance["selection_catalog"] == adapter.HOST_COHORTS
            assert provenance["selection"] == adapter.HOST_COHORTS[name]
            assert provenance["code_before"] == provenance["code_after"] and provenance["code_unchanged"]
            assert provenance["primary_runner_exit_code"] == 0
            for flag in ["primary_test_audit_and_fingerprint_logic_unchanged", "shared_sdk_validation_lock_unchanged",
                         "catalog_disjointness_check_unchanged", "host_font_inputs_captured_by_original_engine_rendering_guard"]:
                assert provenance[flag] is True
            assert provenance["code_before"]["adapter"]["sha256"] == PINNED_ADAPTER
            assert provenance["code_before"]["primary_runner"]["sha256"] == PINNED_RUNNER
            for info in provenance["code_before"].values():
                actual = current_record(Path(info["path"]))
                assert info["bytes"] == actual["bytes"] and info["sha256"] == actual["sha256"]
            selection_provenance = "pinned_primary_runner_with_reviewed_catalog_adapter"
        counted.update(name=name, source_commit=source,
                       distinct_passed_cases=len(set(cases)), primary_runner_status=receipt["status"],
                       selection_provenance=selection_provenance, exact_reviewed_selection_verified=True,
                       primary_failed_guards=[], source_inventory_sha256=helper.digest(inventory["source"]),
                       receipt_sha256=current_record(folder / "receipt.json")["sha256"], verified_inputs=live_counts,
                       started_at_utc=receipt["started_at_utc"], finished_at_utc=receipt["finished_at_utc"])
        results.append(counted)
        all_cases.extend(cases)
        all_paths.extend(selected)
    assert len(all_paths) == len(set(all_paths)) == 157
    assert len(all_cases) == len(set(all_cases)), "No duplicate-case accounting exception applies to this gate"
    static = verify_static(repo, evidence, candidate_tree, objects)
    comparator = verify_comparator(repo, evidence, candidate_tree, objects)
    result = {
        "status": "fresh_host_evidence_verified" if not drift else "fresh_host_evidence_verified_candidate_delta_requires_review",
        "audited_at_utc": datetime.now(timezone.utc).isoformat(),
        "qualified_sources": sorted({row["source_commit"] for row in results}),
        "candidate_commit": candidate,
        "candidate_tree": resolve(candidate + "^{tree}"),
        "fresh_successful_application_executions": len(all_cases),
        "fresh_distinct_passed_cases": len(set(all_cases)),
        "fresh_distinct_test_files": len(set(all_paths)),
        "failed_or_skipped_application_executions": 0,
        "repeated_successful_executions_excluded_from_distinct_count": 0,
        "primary_receipts_rejected": [],
        "primary_guard_exceptions": [],
        "cohorts": results,
        "static": static,
        "comparator_controls": comparator,
        "source_blob_objects_rehashed": len(objects),
        "distinct_recorded_source_paths": len(source_union),
        "source_runtime_workspace_dependency_and_font_files_rehashed": len(CACHE),
        "candidate_preserves_all_recorded_source_inputs": not drift,
        "candidate_recorded_source_differences": drift,
        "current_candidate_inputs_match_git": True,
        "verifier_sha256": current_record(Path(__file__))["sha256"],
        "imported_helpers_sha256": PINNED_HELPER,
        "catalog_adapter_sha256": PINNED_ADAPTER,
        "primary_runner_sha256": PINNED_RUNNER,
        "limits": [
            "This audit runs no application tests; it independently recounts the eight fresh raw streams and rehashes their saved Git inputs and available current external inputs.",
            "The earlier 2,886-case milestone and 3,201-distinct-case continuation remain separate source-attributed populations. Their overlapping cases are not added to this count.",
            "editor-zotero ran the pinned primary runner directly before the adapter was available. Its unchanged 43-file selector is independently verified equal to this reviewed catalog; no adapter receipt is fabricated.",
            "The incoming author native Word corpus achieved 20 of 24 pages above its 95% threshold; its strict acceptance gate is not met. Local Dart/Flutter qualification does not replace that native corpus result.",
            "No native macOS bundle, physical display, live Zotero account or live Mail service acceptance is established by these local tests.",
            "Runtime inventory covers the named SDK files recorded by the runner, not every operating-system library or binary.",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    keys = ["status", "qualified_sources", "candidate_commit", "candidate_tree", "fresh_successful_application_executions",
            "fresh_distinct_passed_cases", "fresh_distinct_test_files", "failed_or_skipped_application_executions",
            "repeated_successful_executions_excluded_from_distinct_count", "primary_receipts_rejected", "primary_guard_exceptions",
            "candidate_preserves_all_recorded_source_inputs", "candidate_recorded_source_differences", "static", "comparator_controls", "limits"]
    summary = {key: result[key] for key in keys}
    summary["cohorts"] = [{key: row[key] for key in ["name", "passed", "distinct_passed_cases", "files", "source_commit", "selection_provenance",
                                                       "primary_runner_status", "primary_failed_guards", "receipt_sha256"]}
                          for row in results]
    summary["independent_audit"] = {"path": str(args.output.relative_to(evidence)),
                                     "sha256": current_record(args.output)["sha256"]}
    (evidence / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(json.dumps({key: result[key] for key in ["status", "fresh_distinct_passed_cases", "fresh_distinct_test_files",
                                                  "candidate_preserves_all_recorded_source_inputs"]}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
