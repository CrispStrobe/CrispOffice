#!/usr/bin/env python3
"""Recount the final accepted gates and preserve the blocked Chrome attempt.

Runs no application tests. Earlier source-attributed results remain immutable
and are not added to these fresh focused counts.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import re

import yaml


HERE = Path(__file__).resolve().parent
SOURCE = "a45ee3bf40dbb7e64a04f879fd6d574db7cb60b1"
CORE = "214c4ed80bef0cb871f74e90c506d508679d3d6e"
PINNED_HOST_AUDITOR = "4c0d0588c9d2d71b9c2110f2df191b39fd38562efe637b1c0a4d21fe992f96f8"
PINNED_PRIMARY = "4d01ed59729abaa64e3ab643e8ebcb2f7136dd2d9f02cc4b07b81a06fbb919bf"
ARCHIVES = ["docs/validation/mail-attachments-20261120/" + path for path in
            ["arabic-composer/capture_mail_arabic_test.dart", "attachment-core/attachment_mime_probe.dart"]]
WEB_VM = ["packages/quds_office_editor/example/test/" + path for path in
          ["studio_hunspell_web_host_test.dart", "studio_hunspell_web_cancellation_test.dart", "studio_downloads_manager_test.dart"]]
WEB_TEST = "packages/quds_office_editor/example/test/studio_web_persistence_test.dart"
WEB_NAMES = ["a verified dictionary survives a new session and is removable",
             "stored bytes that no longer match the pins are deleted",
             "the morphology database is restored only after verification"]


path = HERE.parent / "host-main-followup/audit_host_followup.py"
assert hashlib.sha256(path.read_bytes()).hexdigest() == PINNED_HOST_AUDITOR
spec = importlib.util.spec_from_file_location("prior_host_audit_helpers", path)
prior = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prior)
h = prior.helper
current = prior.current_record


def match(path: Path, expected: dict) -> None:
    assert set(expected) <= {"bytes", "sha256", "git_blob_sha1"}
    actual = current(path)
    assert all(actual[key] == value for key, value in expected.items()), path


def write(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def input_audit(repo: Path, folder: Path, receipt: dict, inventory: dict, source_tree: dict, objects: dict) -> dict:
    assert receipt["source_head_at_start"] == receipt["source_head_at_finish"] == SOURCE
    assert receipt["head_unchanged"] and not receipt["application_timeouts_modified"] and not receipt["timed_out"]
    runner = receipt.get("validation_runner", receipt.get("primary_runner"))
    assert runner["sha256"] == PINNED_PRIMARY
    match(Path(runner["path"]), {key: value for key, value in runner.items() if key != "path"})
    for name, expected in receipt["artifacts"].items():
        match(folder / name, expected)
    assert h.read(folder / "input-check.json") == receipt["fingerprints"]
    for area, values in inventory.items():
        assert h.digest(values) == receipt["fingerprints"]["before_sha256"][area]
        assert h.digest(values) == receipt["fingerprints"]["after_sha256"][area]
        assert receipt["fingerprints"]["changed_paths"][area] == []
    for path, expected in inventory["source"].items():
        assert objects[source_tree[path]] == expected
        match(repo / path, expected)
    counts = {"source": len(inventory["source"]), "dependency_files": 0}
    for area, root in [("runtime", Path(receipt["runtime"]["flutter_root"])), ("workspace", repo)]:
        for path, expected in inventory[area].items():
            match(root / path, expected)
        counts[area] = len(inventory[area])
    for name, info in inventory["dependencies"].items():
        assert len(info["files"]) == info["file_count"] and h.digest(info["files"]) == info["inventory_sha256"]
        for path, expected in info["files"].items():
            match(Path(info["root"]) / path, expected)
        counts["dependency_files"] += len(info["files"])
    for path, expected in inventory["host_fonts"].items():
        assert Path(path).is_file() is expected["present"]
        if expected["present"]:
            match(Path(path), {key: value for key, value in expected.items() if key != "present"})
    counts["host_fonts"] = len(inventory["host_fonts"])
    for area in ["web_sdk_cache", "chromium", "qualification_tools"]:
        if area in inventory:
            for path, expected in inventory[area].items():
                match(Path(path), expected)
            counts[area] = len(inventory[area])
    return counts


def static_audit(repo: Path, tree: dict, objects: dict) -> dict:
    full_dir, active_dir = HERE / "static", HERE / "static-product"
    full, active = h.read(full_dir / "receipt.json"), h.read(active_dir / "receipt.json")
    assert full["head"] == active["head"] == active["head_after"] == SOURCE
    expected = sorted(path.decode() for path in h.git(repo, "diff", "--name-only", "--diff-filter=ACMRT", "-z", full["base"], SOURCE).split(b"\0")
                      if path and path.endswith(b".dart"))
    assert sorted(full["paths"]) == sorted(active["all_changed_dart_paths"]) == expected and len(expected) == 110
    assert full["accepted"] is False and full["inputs_identical"] and full["before"] == full["after"]
    assert full["checks"]["format"]["exit_code"] == full["checks"]["analysis"]["exit_code"] == 1
    assert set(active["excluded_historical_artifacts"]) == set(ARCHIVES)
    assert sorted(active["paths"]) == sorted(set(expected) - set(ARCHIVES)) and len(active["paths"]) == 108
    assert active["accepted"] and all(active["guards"].values()) and active["before"] == active["after"]
    assert current(full_dir / "receipt.json")["sha256"] == active["preserved_all_110_attempt"]["sha256"]
    assert current(HERE / "run_product_static.py")["sha256"] == active["selector_script_sha256"]
    for receipt in [full, active]:
        for path, saved in receipt["before"].items():
            if tree[path] not in objects:
                objects.update(h.source_records(repo, [tree[path]]))
            expected_record = {"sha256": saved} if isinstance(saved, str) else saved
            assert all(objects[tree[path]][key] == value for key, value in expected_record.items())
            match(repo / path, expected_record)
        for name, check in receipt["checks"].items():
            command = check["command"]
            if name == "format":
                assert command[1:4] == ["format", "--output=none", "--set-exit-if-changed"]
                assert sorted(command[4:]) == sorted(receipt["paths"])
            else:
                assert name == "analysis" and command[1:3] == ["analyze", "--fatal-infos"]
                assert sorted(command[3:]) == sorted(receipt["paths"])
            if receipt is active:
                assert check["exit_code"] == 0
    for path, item in active["excluded_historical_artifacts"].items():
        match(repo / path, {key: item[key] for key in ["bytes", "sha256", "git_blob_sha1"]})
        assert h.tree(repo, item["incoming_mail_head"])[path] == tree[path] == item["git_blob_sha1"]
        assert current(repo / item["context_receipt"])["sha256"] == item["context_receipt_sha256"]
        assert item["artifact_index_entry"]["sha256"] == item["sha256"]
    index = repo / "docs/validation/mail-attachments-20261120/artifact-index.json"
    assert current(index)["sha256"] == active["author_artifact_index_sha256"]
    log = (full_dir / "analysis.log").read_text()
    diagnostics = re.findall(r"^\s*(info|warning|error) - (.*?\.dart):\d+:\d+ - (.*?) - (\w+)\s*$", log, re.M)
    assert len(diagnostics) == 14 and {row[0] for row in diagnostics} == {"info"}
    assert {row[1] for row in diagnostics} == set(ARCHIVES)
    format_changes = re.findall(r"^Changed (.+)$", (full_dir / "format.log").read_text(), re.M)
    assert format_changes == [ARCHIVES[1]]
    assert "No issues found!" in (active_dir / "analysis.log").read_text()
    assert re.search(r"Formatted 108 files \(0 changed\)", (active_dir / "format.log").read_text())
    return {"active_source": {"status": "passed", "targets": 108, "receipt": current(active_dir / "receipt.json"),
                               "analysis_log": current(active_dir / "analysis.log"), "format_log": current(active_dir / "format.log")},
            "full_changed_path_preflight": {"status": "failed", "targets": 110, "receipt": current(full_dir / "receipt.json"),
                                            "analysis_log": current(full_dir / "analysis.log"), "format_log": current(full_dir / "format.log"),
                                            "infos": 14, "diagnostic_paths": ARCHIVES, "would_format_paths": format_changes,
                                            "inputs_unchanged": True, "original_receipt_modified": False},
            "excluded_archive_inputs": active["excluded_historical_artifacts"],
            "all_110_passed": False, "active_product_guard_exceptions": []}


def dependency_audit(repo: Path) -> dict:
    receipt = h.read(HERE / "dependency-reuse.json")
    assert receipt["status"] == "passed" and receipt["source_head"] == SOURCE
    assert receipt["lockfile_unchanged"] and receipt["all_virtual_closures_identical"]
    assert receipt["saved_graph_contains_new_direct_edge"] is False
    assert receipt["resolution_config_sdk_cache_or_head_writes"] is False
    assert current(HERE / "check_web_dependency_reuse.py")["sha256"] == receipt["checker_sha256"]
    for path, key in [("pubspec.lock", "lockfile_sha256"), (".dart_tool/package_config.json", "package_configuration_sha256"),
                      (".dart_tool/package_graph.json", "saved_package_graph_sha256")]:
        assert current(repo / path)["sha256"] == receipt[key]
    before_manifest = yaml.safe_load(h.git(repo, "show", CORE + ":packages/quds_office_editor/example/pubspec.yaml"))
    after_manifest = yaml.safe_load((repo / "packages/quds_office_editor/example/pubspec.yaml").read_text())
    before_manifest["dependencies"]["web"] = "^1.1.2"
    assert before_manifest == after_manifest
    lock = yaml.safe_load((repo / "pubspec.lock").read_text())
    assert lock["packages"]["web"] == receipt["locked_web"]
    assert h.git(repo, "show", CORE + ":pubspec.lock") == (repo / "pubspec.lock").read_bytes()
    graph = h.read(repo / ".dart_tool/package_graph.json")
    nodes = {row["name"]: row for row in graph["packages"]}
    edges = {name: set(row.get("dependencies", [])) for name, row in nodes.items()}
    assert "web" not in edges["quds_office_studio"] and "file_picker" in edges["quds_office_studio"] and "web" in edges["file_picker"]
    virtual = {key: set(value) for key, value in edges.items()}
    virtual["quds_office_studio"].add("web")
    def closure(graph, start):
        result, pending = set(), [start, *nodes[start].get("devDependencies", [])]
        while pending:
            name = pending.pop()
            if name in result:
                continue
            result.add(name)
            pending.extend(graph[name])
        return sorted(result)
    closures = {name: closure(edges, name) for name in edges}
    assert closures == {name: closure(virtual, name) for name in virtual}
    assert len(closures) == receipt["compared_package_closures"] == 152
    assert h.digest(closures) == receipt["all_closures_sha256"]
    previous = Path(receipt["previous_input_inventory"])
    assert current(previous)["sha256"] == receipt["previous_input_inventory_sha256"]
    old_inputs = h.read(previous)["before"]
    package = old_inputs["dependencies"]["web"]
    assert len(package["files"]) == receipt["rehashed_web_files"] == 192
    for path, record in package["files"].items():
        match(Path(package["root"]) / path, record)
    return {"status": "verified", "receipt": current(HERE / "dependency-reuse.json"),
            "unchanged_reachable_package_closures": 152, "unchanged_web_package_files": 192,
            "new_direct_edge_recorded_in_saved_graph": False,
            "saved_graph_reused_without_regeneration": True,
            "explanation": "The unchanged saved graph already reaches web through Studio→file_picker→web; adding the new direct edge changes none of its152 dependency closures."}


def blocked_browser(folder: Path, receipt: dict) -> dict:
    assert receipt["status"] == "failed" and receipt["exit_code"] == 1 and not receipt["timed_out"]
    false_guards = sorted(key for key, value in receipt["guards"].items() if not value)
    expected = sorted(["exact_three_application_passes", "exact_three_expected_case_names", "final_event_success", "no_failures_skips_or_errors"])
    assert false_guards == expected
    assert receipt["selected_repository_paths"] == [WEB_TEST] and receipt["expected_case_names"] == WEB_NAMES
    events = [json.loads(line) for line in gzip.decompress((folder / "events.jsonl.gz").read_bytes()).decode().splitlines() if line.strip()]
    assert all(isinstance(row, dict) and "type" in row for row in events)
    suites = [row["suite"] for row in events if row["type"] == "suite"]
    starts = [row["test"] for row in events if row["type"] == "testStart"]
    ends = [row for row in events if row["type"] == "testDone"]
    errors = [row for row in events if row["type"] == "error"]
    done = [row for row in events if row["type"] == "done"]
    assert len(suites) == len(starts) == len(ends) == len(errors) == len(done) == 1
    assert starts[0]["name"].startswith("loading ") and starts[0]["url"] is None
    assert ends[0]["testID"] == starts[0]["id"] == errors[0]["testID"]
    assert ends[0]["result"] == "error" and not ends[0]["skipped"] and done[0]["success"] is False
    assert "Failed to launch browser" in errors[0]["error"]
    assert receipt["tests"]["application_cases"] == receipt["tests"]["passed"] == 0
    assert len(receipt["tests"]["excluded_failures"]) == len(receipt["tests"]["error_events"]) == 1
    stderr = gzip.decompress((folder / "stderr.log.gz").read_bytes()).decode()
    assert "socket() failed: Operation not permitted (1)" in stderr
    assert "Failed to launch browser after 3 tries" in stderr
    launches = [json.loads(line) for line in (folder / "chromium-launches.jsonl").read_text().splitlines()]
    assert launches == receipt["chromium_launches"] and len(launches) == 4
    for launch in launches:
        assert launch["binary_sha256"] == current(Path(launch["binary"]))["sha256"]
        assert launch["profile"] == str(folder / "browser-profile") and launch["disk_cache"] == str(folder / "browser-disk-cache")
    after = h.read(folder / "inputs-after.json.gz")
    assert after == h.read(folder / "inputs.json.gz")["before"]
    return {"status": "environment_blocked", "primary_receipt_status": "failed", "receipt": current(folder / "receipt.json"),
            "attempted_test_files": 1, "application_cases_executed": 0, "application_passes": 0,
            "loading_errors": 1, "pinned_browser_launch_invocations": 4, "sdk_max_retries": 3,
            "launch_count_interpretation": "Initial launch plus3 retries; SDK text says after3tries but the pinned loop starts retry=0.",
            "failed_guards": false_guards,
            "all_recorded_executable_inputs_unchanged": True, "native_or_browser_application_acceptance_claimed": False,
            "cause": "Chromium process-singleton socket creation was denied with Operation not permitted before any application test ran.",
            "original_failed_artifacts_preserved": True,
            "folder_name_is_not_acceptance_status": "The existing accepted-web-chrome directory name is retained; receipt.status remains failed."}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=HERE / "audit.json")
    args = parser.parse_args()
    repo = args.repo.resolve()
    assert h.git(repo, "rev-parse", "HEAD").decode().strip() == SOURCE
    tree = h.tree(repo, SOURCE)
    web_dir = HERE.parent / "web-persistence-followup"
    folders = {"engine-rendering": HERE / "accepted-engine-rendering", "editor-rendering": HERE / "accepted-editor-rendering",
               "web-persistence-vm": web_dir / "accepted-web-vm", "web-persistence-chrome": web_dir / "accepted-web-chrome"}
    receipts = {name: h.read(folder / "receipt.json") for name, folder in folders.items()}
    inputs = {name: h.read(folder / "inputs.json.gz")["before"] for name, folder in folders.items()}
    objects = h.source_records(repo, {tree[path] for inventory in inputs.values() for path in inventory["source"]})
    results, all_cases, all_files = [], [], []
    for name, folder in folders.items():
        receipt = receipts[name]
        verified_inputs = input_audit(repo, folder, receipt, inputs[name], tree, objects)
        if name == "web-persistence-chrome":
            browser = blocked_browser(folder, receipt)
            browser["verified_inputs"] = verified_inputs
            continue
        assert receipt["status"] == "passed" and receipt["exit_code"] == 0
        assert receipt["guards"] and all(value is True for value in receipt["guards"].values())
        counted, cases = h.recount(folder / "events.jsonl.gz", repo, receipt["cwd"])
        expected = sorted(WEB_VM) if name == "web-persistence-vm" else prior.selection_from_git(name, tree)
        assert counted["suite_paths"] == sorted(receipt["selected_repository_paths"]) == expected
        assert counted["passed"] == receipt["tests"]["passed"] and counted["files"] == receipt["tests"]["suite_count"]
        for suite in receipt["tests"]["suites"]:
            path = str(Path(suite["path"]).relative_to(repo))
            assert suite["passed"] == counted["per_suite"][path] and suite["failed"] == suite["skipped"] == 0
        provenance = receipt["selection_adapter"]
        assert provenance == h.read(folder / "selection-adapter.json") and provenance["code_before"] == provenance["code_after"]
        if name == "web-persistence-vm":
            assert counted["passed"] == 19 and counted["files"] == 3
            assert provenance["original_primary_guard_logic_unchanged"] and provenance["shared_validation_lock_unchanged"]
            for path, record in provenance["code_before"].items():
                match(Path(path), record)
        else:
            assert provenance["selection_catalog"] == prior.adapter.HOST_COHORTS
            assert provenance["code_unchanged"] and provenance["primary_runner_exit_code"] == 0
            for record in provenance["code_before"].values():
                match(Path(record["path"]), {key: value for key, value in record.items() if key != "path"})
        counted.update(name=name, source_commit=SOURCE, receipt=current(folder / "receipt.json"),
                       primary_runner_status="passed", primary_failed_guards=[], verified_inputs=verified_inputs)
        results.append(counted)
        all_cases.extend(cases)
        all_files.extend(expected)
    assert len(all_cases) == len(set(all_cases)) == 356 and len(all_files) == len(set(all_files)) == 27
    core_dir = HERE.parent / "host-main-followup"
    old_cases = set()
    core_summary = h.read(core_dir / "summary.json")
    for row in core_summary["cohorts"]:
        folder = core_dir / ("accepted-" + row["name"])
        receipt = h.read(folder / "receipt.json")
        assert current(folder / "receipt.json")["sha256"] == row["receipt_sha256"]
        if set(receipt["selected_repository_paths"]) & set(all_files):
            _, cases = h.recount(folder / "events.jsonl.gz", repo, receipt["cwd"])
            old_cases.update(cases)
    static = static_audit(repo, tree, objects)
    dependency = dependency_audit(repo)
    scope_path = HERE / "source-applicability.json"
    scope = h.read(scope_path)
    assert scope["status"] == "verified_bounded_source_delta_and_applicability_scope" and scope["publication_source"] == SOURCE
    match(HERE / "audit_source_applicability.py", scope["auditor_record"])
    match(HERE / "declaration-identities.json", scope["slide_declaration_scope"]["complete_identity_artifact"])
    match(HERE / "production-delta.patch", scope["production_delta_patch"])
    review = h.read(core_dir / "web-persistence-review.json")
    author_tree = h.tree(repo, review["author_source"])
    assert all(tree[row["path"]] == author_tree[row["path"]] == row["author_blob"] for row in review["complete_delta"]["paths"])
    case_path = HERE / "accepted-case-identities.json.gz"
    case_path.write_bytes(gzip.compress(json.dumps(sorted(all_cases), ensure_ascii=False, separators=(",", ":")).encode() + b"\n", mtime=0))
    assert h.git(repo, "rev-parse", "HEAD").decode().strip() == SOURCE
    result = {
        "status": "partial_browser_environment_blocked", "audited_at_utc": datetime.now(timezone.utc).isoformat(),
        "qualified_source": SOURCE, "source_tree": h.git(repo, "rev-parse", SOURCE + "^{tree}").decode().strip(),
        "focused_distinct_passed_cases": 356, "focused_successful_application_executions": 356,
        "focused_distinct_test_files": 27, "accepted_failed_or_skipped_application_cases": 0,
        "accepted_primary_guard_exceptions": [], "accepted_cohorts": results,
        "browser_attempt": browser, "browser_acceptance_met": False,
        "static": static, "dependency_reuse": dependency,
        "source_applicability": {"path": "source-applicability.json", "record": current(scope_path)},
        "case_identity_artifact": current(case_path),
        "overlap_with_prior_core": {"prior_source": CORE, "repeated_case_identities": len(set(all_cases) & old_cases),
                                    "new_case_identities_relative_to_core": len(set(all_cases) - old_cases),
                                    "combined_cross_source_total_claimed": False},
        "author_browser_evidence": {"author_source": review["author_source"], "reported_browser_cases": 3,
                                    "all_nine_incoming_web_paths_exact_author_blobs": True,
                                    "independently_passed_here": False, "source_review_record": current(core_dir / "web-persistence-review.json")},
        "source_blob_objects_rehashed": len(objects), "current_files_rehashed": len(prior.CACHE),
        "verifier_record": current(Path(__file__)), "imported_host_auditor_sha256": PINNED_HOST_AUDITOR,
        "limits": [
            "The356 accepted cases are a separate final-source population. Earlier2386/157,3201/129 and2886 historical totals retain their own sources and overlap; they are not summed.",
            "The unchanged Chrome attempt is failed: one loader error, zero application cases, no browser application acceptance. Source, dependency, SDK, Chromium and tool pins all remained unchanged.",
            "The110-target static preflight remains failed for14 infos and one formatting difference in two preserved historical evidence harnesses. All108 active changed package/third-party Dart targets pass their own strict gate.",
            "Earlier core input equality is not claimed for the final tree: the separate source audit identifies eight changed recorded inputs, four new inputs, native conditional boundaries and bounded slide declaration changes.",
            "Author-reported Chrome cases are attributed separately. No native Word/macOS, live Zotero/Mail account or successful real Wasm-model activation is established by this local evidence.",
        ],
        "github_actions_queried": False, "product_files_modified": False,
    }
    write(args.output.resolve(), result)
    summary = {key: result[key] for key in ["status", "qualified_source", "source_tree", "focused_distinct_passed_cases",
               "focused_successful_application_executions", "focused_distinct_test_files", "accepted_failed_or_skipped_application_cases",
               "accepted_primary_guard_exceptions", "browser_attempt", "browser_acceptance_met", "static", "dependency_reuse",
               "source_applicability", "overlap_with_prior_core", "author_browser_evidence", "limits"]}
    summary["accepted_cohorts"] = [{key: row[key] for key in ["name", "passed", "files", "source_commit", "primary_runner_status", "primary_failed_guards", "receipt"]}
                                   for row in results]
    summary["independent_audit"] = {"path": args.output.name, "record": current(args.output.resolve())}
    write(HERE / "summary.json", summary)
    print(json.dumps({key: result[key] for key in ["status", "focused_distinct_passed_cases", "focused_distinct_test_files", "browser_acceptance_met", "overlap_with_prior_core"]}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
