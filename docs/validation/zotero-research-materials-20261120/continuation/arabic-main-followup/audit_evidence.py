#!/usr/bin/env python3
"""Recount only the frozen Arabic follow-up gates and rebind their exact inputs.

This is a read-only evidence audit, apart from writing its own three reports.
It runs no application/native/browser tests and does not relabel older results.
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
import sys
from urllib.parse import unquote, urljoin, urlparse

import yaml

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
SOURCE = "f69e774fbb32a103260541e4a28fb17600bfc17e"
PREVIOUS = "a45ee3bf40dbb7e64a04f879fd6d574db7cb60b1"
EVIDENCE_CHECKPOINT = "a3373021b6cbe6ae333217417bd1615e88019f7d"
PRIMARY_SHA = "4d01ed59729abaa64e3ab643e8ebcb2f7136dd2d9f02cc4b07b81a06fbb919bf"
ADAPTER_SHA = "c35ea5371e02ac0ccef93a5fccb9d500e3096a5718ed773574cad1fb6f608877"
HOST_HELPER_SHA = "4c0d0588c9d2d71b9c2110f2df191b39fd38562efe637b1c0a4d21fe992f96f8"
ARCHIVES = ["docs/validation/mail-attachments-20261120/" + suffix for suffix in [
    "arabic-composer/capture_mail_arabic_test.dart", "attachment-core/attachment_mime_probe.dart"]]


def load(path: Path, name: str, expected: str):
    assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, path
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


prior = load(HERE.parent / "host-main-followup/audit_host_followup.py", "arabic_audit_helpers", HOST_HELPER_SHA)
h = prior.helper
current = prior.current_record
adapter = load(HERE / "run_arabic_followup.py", "arabic_audit_catalog", ADAPTER_SHA)


def match(path: Path, expected: dict) -> None:
    assert set(expected) <= {"bytes", "sha256", "git_blob_sha1"}
    assert all(current(path)[key] == value for key, value in expected.items()), path


def write(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def audit_inputs(repo: Path, folder: Path, receipt: dict, inventory: dict, tree: dict, objects: dict) -> dict:
    assert receipt["source_head_at_start"] == receipt["source_head_at_finish"] == SOURCE
    assert receipt["head_unchanged"] and not receipt["application_timeouts_modified"] and not receipt["timed_out"]
    runner = receipt["validation_runner"]
    assert runner["sha256"] == PRIMARY_SHA
    match(Path(runner["path"]), {key: value for key, value in runner.items() if key != "path"})
    for name, expected in receipt["artifacts"].items():
        match(folder / name, expected)
    assert h.read(folder / "input-check.json") == receipt["fingerprints"]
    for area, values in inventory.items():
        assert h.digest(values) == receipt["fingerprints"]["before_sha256"][area]
        assert h.digest(values) == receipt["fingerprints"]["after_sha256"][area]
        assert receipt["fingerprints"]["changed_paths"][area] == []
    for path, expected in inventory["source"].items():
        assert objects[tree[path]] == expected
        match(repo / path, expected)
    counts = {"source": len(inventory["source"]), "dependency_files": 0}
    for area, root in [("runtime", Path(receipt["runtime"]["flutter_root"])), ("workspace", repo)]:
        for path, expected in inventory[area].items():
            match(root / path, expected)
        counts[area] = len(inventory[area])
    for info in inventory["dependencies"].values():
        assert len(info["files"]) == info["file_count"] and h.digest(info["files"]) == info["inventory_sha256"]
        for path, expected in info["files"].items():
            match(Path(info["root"]) / path, expected)
        counts["dependency_files"] += len(info["files"])
    assert inventory["host_fonts"] == {}
    assert receipt["source_file_count"] == counts["source"]
    assert receipt["external_dependency_file_count"] == counts["dependency_files"]
    return counts


def audit_static(repo: Path, tree: dict, objects: dict) -> dict:
    folder = HERE / "static"
    receipt = h.read(folder / "receipt.json")
    assert receipt["head"] == receipt["head_after"] == SOURCE
    assert receipt["accepted"] and all(value is True for value in receipt["guards"].values())
    assert receipt["before"] == receipt["after"]
    paths = sorted(path.decode() for path in h.git(repo, "diff", "--name-only", "--diff-filter=ACMRT", "-z", receipt["base"], SOURCE).split(b"\0")
                   if path.endswith(b".dart"))
    assert sorted(receipt["all_changed_dart_paths"]) == sorted(receipt["before"]) == paths
    assert len(paths) == 131 and set(receipt["excluded_historical_artifacts"]) == set(ARCHIVES)
    assert sorted(receipt["paths"]) == sorted(set(paths) - set(ARCHIVES)) and len(receipt["paths"]) == 129
    assert all(path.startswith(("packages/", "third_party/")) for path in receipt["paths"])
    for path, expected in receipt["before"].items():
        assert objects[tree[path]] == expected
        match(repo / path, expected)
    assert current(HERE / "run_product_static.py")["sha256"] == receipt["selector_script_sha256"]
    for name, check in receipt["checks"].items():
        assert check["exit_code"] == 0
        args = check["command"]
        if name == "format":
            assert args[1:4] == ["format", "--output=none", "--set-exit-if-changed"]
            assert sorted(args[4:]) == sorted(receipt["paths"])
        else:
            assert name == "analysis" and args[1:3] == ["analyze", "--fatal-infos"]
            assert sorted(args[3:]) == sorted(receipt["paths"])
    assert "No issues found!" in (folder / "analysis.log").read_text()
    assert re.search(r"Formatted 129 files \(0 changed\)", (folder / "format.log").read_text())
    for path, item in receipt["excluded_historical_artifacts"].items():
        assert h.tree(repo, item["incoming_mail_head"])[path] == tree[path] == item["git_blob_sha1"]
        assert item["artifact_index_entry"]["sha256"] == item["sha256"]
        assert current(repo / item["context_receipt"])["sha256"] == item["context_receipt_sha256"]
    assert current(repo / "docs/validation/mail-attachments-20261120/artifact-index.json")["sha256"] == receipt["author_artifact_index_sha256"]
    old = receipt["preserved_all_110_attempt"]
    assert current(repo / old["path"])["sha256"] == old["sha256"]
    old_receipt = h.read(repo / old["path"])
    assert old_receipt["accepted"] is False and old_receipt["head"] == PREVIOUS and len(old_receipt["paths"]) == 110
    return {"status": "passed", "active_changed_dart_targets": 129, "all_changed_dart_inputs_bound": 131,
            "excluded_historical_artifacts": receipt["excluded_historical_artifacts"],
            "all_131_static_passed_claimed": False, "old_110_failed_attempt_preserved": old,
            "archive_static_rerun_claimed": False, "active_guard_exceptions": [],
            "receipt": current(folder / "receipt.json"), "analysis_log": current(folder / "analysis.log"),
            "format_log": current(folder / "format.log")}


def audit_dependencies(repo: Path, runtime: dict) -> dict:
    receipt = h.read(HERE / "dependency-reuse.json")
    web = h.read(HERE / "web-dependency-reuse.json")
    assert receipt["status"] == web["status"] == "passed"
    assert receipt["head"] == web["source_head"] == web["incoming_commit"] == SOURCE
    assert receipt["prior_source"] == PREVIOUS and receipt["lockfile_unchanged"] and web["lockfile_unchanged"]
    assert receipt["resolution_sdk_package_cache_or_configuration_writes"] is False
    assert web["resolution_config_sdk_cache_or_head_writes"] is False
    assert current(HERE / "check_dependency_reuse.py")["sha256"] == receipt["checker_sha256"]
    assert current(HERE.parent / "publication-final/check_web_dependency_reuse.py")["sha256"] == receipt["web_checker_sha256"] == web["checker_sha256"]
    assert current(HERE / "web-dependency-reuse.json")["sha256"] == receipt["prior_studio_web_edge_proof"]["sha256"]
    for path, key in [("pubspec.lock", "lockfile_sha256"), (".dart_tool/package_config.json", "package_configuration_sha256"),
                      (".dart_tool/package_graph.json", "saved_package_graph_sha256")]:
        assert current(repo / path)["sha256"] == receipt[key] == web[key]
    manifest = receipt["manifest_path"]
    old = yaml.safe_load(h.git(repo, "show", PREVIOUS + ":" + manifest))
    new = yaml.safe_load((repo / manifest).read_text())
    assert old.pop("version") == "0.2.0" and new.pop("version") == "0.3.0" and old == new
    config_path = repo / ".dart_tool/package_config.json"
    config = h.read(config_path)
    roots = {row["name"]: Path(unquote(urlparse(urljoin(config_path.as_uri(), row["rootUri"])).path)) for row in config["packages"]}
    nodes = {row["name"]: row for row in h.read(repo / ".dart_tool/package_graph.json")["packages"]}
    morph = nodes["quds_arabic_morph"]
    assert morph["version"] == receipt["saved_graph_version"] == "0.2.0" and receipt["declared_version"] == "0.3.0"
    assert roots["quds_arabic_morph"] == repo / "packages/quds_arabic_morph"
    assert set(morph["dependencies"]) == set(new["dependencies"]) == set(receipt["unchanged_morph_dependency_edges"])
    assert set(morph["devDependencies"]) == set(new["dev_dependencies"]) == set(receipt["unchanged_morph_dev_dependency_edges"])
    consumers = {}
    for name, root in roots.items():
        if not root.is_relative_to(repo):
            continue
        spec = yaml.safe_load((root / "pubspec.yaml").read_text())
        for section in ["dependencies", "dev_dependencies", "dependency_overrides"]:
            if "quds_arabic_morph" in spec.get(section, {}):
                declaration = spec[section]["quds_arabic_morph"]
                assert isinstance(declaration, dict) and set(declaration) == {"path"}
                assert (root / declaration["path"]).resolve() == roots["quds_arabic_morph"]
                consumers[f"{name}:{section}"] = declaration
    assert consumers == receipt["all_morph_consumers_use_unversioned_local_path"]
    assert h.git(repo, "show", PREVIOUS + ":pubspec.lock") == (repo / "pubspec.lock").read_bytes()
    lock = yaml.safe_load((repo / "pubspec.lock").read_text())
    hosted = []
    for name, row in lock["packages"].items():
        if row["source"] != "hosted":
            continue
        assert str(yaml.safe_load((roots[name] / "pubspec.yaml").read_text())["version"]) == row["version"]
        checksum = Path(runtime["pub_cache"]) / "hosted-hashes/pub.dev" / f'{name}-{row["version"]}.sha256'
        assert checksum.read_text().strip() == row["description"]["sha256"]
        hosted.append(name)
    assert sorted(hosted) == receipt["hosted_package_names"] and len(hosted) == receipt["hosted_versions_and_archive_hashes_verified"] == 126
    before_studio = yaml.safe_load(h.git(repo, "show", web["before_commit"] + ":packages/quds_office_editor/example/pubspec.yaml"))
    before_studio["dependencies"]["web"] = "^1.1.2"
    assert before_studio == yaml.safe_load((repo / "packages/quds_office_editor/example/pubspec.yaml").read_text())
    assert lock["packages"]["web"] == web["locked_web"]
    edges = {name: set(row.get("dependencies", [])) for name, row in nodes.items()}
    assert "web" not in edges["quds_office_studio"] and "file_picker" in edges["quds_office_studio"] and "web" in edges["file_picker"]
    virtual = {key: set(value) for key, value in edges.items()}
    virtual["quds_office_studio"].add("web")

    def closure(graph, start):
        result, pending = set(), [start, *nodes[start].get("devDependencies", [])]
        while pending:
            name = pending.pop()
            if name not in result:
                result.add(name)
                pending.extend(graph[name])
        return sorted(result)

    closures = {name: closure(edges, name) for name in edges}
    assert closures == {name: closure(virtual, name) for name in virtual}
    assert len(closures) == web["compared_package_closures"] == 152 and h.digest(closures) == web["all_closures_sha256"]
    previous_path = repo / receipt["previous_input_inventory"]
    assert current(previous_path)["sha256"] == receipt["previous_input_inventory_sha256"] == web["previous_input_inventory_sha256"]
    saved = h.read(previous_path)["before"]
    counts = {"external_dependency_files": 0, "runtime_files": 0, "workspace_configuration_files": 0}
    for info in saved["dependencies"].values():
        for path, expected in info["files"].items():
            match(Path(info["root"]) / path, expected)
            counts["external_dependency_files"] += 1
    for area, root, key in [("runtime", Path(runtime["flutter_root"]), "runtime_files"), ("workspace", repo, "workspace_configuration_files")]:
        for path, expected in saved[area].items():
            match(root / path, expected)
            counts[key] += 1
    assert counts == receipt["rehashed_unchanged_inputs"]
    return {"status": "verified", "receipt": current(HERE / "dependency-reuse.json"),
            "web_receipt": current(HERE / "web-dependency-reuse.json"), "rehashed_unchanged_inputs": counts,
            "hosted_versions_and_archive_checksums": len(hosted), "unchanged_virtual_closures": len(closures),
            "morph_current_declared_version": "0.3.0", "morph_saved_graph_version": "0.2.0",
            "studio_direct_web_edge_present_in_saved_graph": False, "saved_metadata_regeneration_claimed": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    assert h.git(repo, "rev-parse", "HEAD").decode().strip() == SOURCE
    tree = h.tree(repo, SOURCE)
    catalog = adapter.ARABIC_COHORTS
    assert catalog == h.read(HERE / "recommended-selection.json")["cohorts"]
    receipts = {name: h.read(HERE / ("accepted-" + name) / "receipt.json") for name in catalog}
    assert all(row["status"] == "passed" for row in receipts.values()), "Every bounded cohort must finish successfully before audit"
    inputs = {name: h.read(HERE / ("accepted-" + name) / "inputs.json.gz")["before"] for name in catalog}
    source_paths = set(path for inventory in inputs.values() for path in inventory["source"])
    static_paths = h.read(HERE / "static/receipt.json")["all_changed_dart_paths"]
    objects = h.source_records(repo, {tree[path] for path in source_paths | set(static_paths)})
    rows, all_cases, all_files = [], [], []
    for name, spec in catalog.items():
        folder = HERE / ("accepted-" + name)
        receipt = receipts[name]
        assert receipt["exit_code"] == 0 and all(value is True for value in receipt["guards"].values())
        assert spec["patterns"] == []
        expected = sorted(spec["package"] + "/test/" + path for path in spec["additional"])
        assert all(path in tree for path in expected) and len(expected) == len(set(expected))
        counted, cases = h.recount(folder / "events.jsonl.gz", repo, receipt["cwd"])
        assert counted["suite_paths"] == sorted(receipt["selected_repository_paths"]) == expected
        assert counted["passed"] == receipt["tests"]["passed"] == receipt["tests"]["application_cases"]
        assert counted["files"] == receipt["tests"]["suite_count"]
        assert receipt["tests"]["failed"] == receipt["tests"]["skipped"] == 0
        for suite in receipt["tests"]["suites"]:
            path = str(Path(suite["path"]).relative_to(repo))
            assert counted["per_suite"][path] == suite["passed"] and suite["failed"] == suite["skipped"] == 0
        provenance = receipt["selection_adapter"]
        assert provenance == h.read(folder / "selection-adapter.json")
        assert provenance["selection_catalog"] == catalog and provenance["selection"] == spec
        assert provenance["code_before"] == provenance["code_after"] and provenance["code_unchanged"]
        assert provenance["primary_runner_exit_code"] == 0 and provenance["native_and_live_download_suites_excluded"]
        assert provenance["primary_test_audit_and_fingerprint_logic_unchanged"] and provenance["shared_sdk_validation_lock_unchanged"]
        assert provenance["catalog_disjointness_check_unchanged"]
        for saved in provenance["code_before"].values():
            match(Path(saved["path"]), {key: value for key, value in saved.items() if key != "path"})
        verified = audit_inputs(repo, folder, receipt, inputs[name], tree, objects)
        counted.update(name=name, source_commit=SOURCE, primary_runner_status="passed", primary_failed_guards=[],
                       receipt=current(folder / "receipt.json"), verified_inputs=verified)
        rows.append(counted)
        all_cases.extend(cases)
        all_files.extend(expected)
    assert len(all_cases) == len(set(all_cases)) and len(all_files) == len(set(all_files)) == 12
    static = audit_static(repo, tree, objects)
    dependencies = audit_dependencies(repo, receipts["studio-integration"]["runtime"])
    scope = h.read(HERE / "applicability.json")
    assert scope["status"] == "verified_bounded_arabic_main_applicability" and scope["source"] == SOURCE
    assert scope["exact_author_delta_paths_and_postimages"] and scope["changed_path_count"] == 38
    match(HERE / "audit_applicability.py", scope["auditor_record"])
    match(HERE / "source-delta.patch", scope["source_delta_patch"])
    for path, row in scope["changed_paths"].items():
        if row["after"] is not None:
            match(repo / path, row["record"])
    review = h.read(HERE / "incoming-review.json")
    limitation = h.read(HERE / "web-model-removal-limitation.json")
    assert review["source"]["candidate"] == limitation["source"]["candidate"] == SOURCE
    assert review["source_checks_all_passed"] and all(value is True for value in review["source_checks"].values())
    assert current(HERE / "review_incoming_arabic.py")["sha256"] == review["review_script_sha256"]
    assert len(review["source_findings"]) == 1 and limitation["finding"] == review["source_findings"][0]
    finding = limitation["finding"]
    for item in finding["evidence"]:
        assert item["revision"] == SOURCE and tree[item["path"]] == item["blob"]
        match(repo / item["path"], {key: item[key] for key in ["bytes", "sha256"]})
    sdk_doc = finding["local_sdk_documentation"]
    assert current(Path(sdk_doc["path"]))["sha256"] == sdk_doc["sha256"]
    assert finding["fresh_VM_tests_do_not_cover_this_browser_transfer_path"]
    previous_summary = HERE.parent / "publication-final/summary.json"
    previous_record = current(previous_summary)
    assert previous_record == h.record(h.git(repo, "show", EVIDENCE_CHECKPOINT + ":" + str(previous_summary.relative_to(repo))))
    previous = h.read(previous_summary)
    assert previous["status"] == "partial_browser_environment_blocked" and previous["qualified_source"] == PREVIOUS
    assert previous["focused_distinct_passed_cases"] == 356 and previous["focused_distinct_test_files"] == 27
    browser = previous["browser_attempt"]
    assert browser["application_cases_executed"] == 0 and browser["primary_receipt_status"] == "failed"
    assert browser["pinned_browser_launch_invocations"] == 4 and browser["loading_errors"] == 1
    browser_receipt = HERE.parent / "web-persistence-followup/accepted-web-chrome/receipt.json"
    match(browser_receipt, browser["receipt"])
    assert h.read(browser_receipt)["source_head_at_start"] == PREVIOUS
    cases_path = HERE / "accepted-case-identities.json.gz"
    cases_path.write_bytes(gzip.compress(json.dumps(sorted(all_cases), ensure_ascii=False, separators=(",", ":")).encode() + b"\n", mtime=0))
    assert h.git(repo, "rev-parse", "HEAD").decode().strip() == SOURCE
    result = {
        "status": "passed_selected_vm_gates_native_and_browser_unqualified",
        "audited_at_utc": datetime.now(timezone.utc).isoformat(), "qualified_source": SOURCE,
        "source_tree": h.git(repo, "rev-parse", SOURCE + "^{tree}").decode().strip(),
        "distinct_passed_cases": len(all_cases), "successful_application_executions": len(all_cases),
        "distinct_test_files": len(all_files), "failed_or_skipped_application_cases": 0,
        "primary_guard_exceptions": [], "cohorts": rows, "static": static, "dependency_reuse": dependencies,
        "source_applicability": {"path": "applicability.json", "record": current(HERE / "applicability.json")},
        "incoming_source_review": {"path": "incoming-review.json", "record": current(HERE / "incoming-review.json"),
                                   "author_qualification": review["author_qualification"],
                                   "metadata_record": current(HERE / "pr231-metadata.json")},
        "incoming_browser_limitation": {"path": "web-model-removal-limitation.json", "record": current(HERE / "web-model-removal-limitation.json"),
                                        "finding_id": finding["id"], "classification": limitation["classification"],
                                        "publication_disposition": limitation["publication_disposition"],
                                        "browser_runtime_reproduced": False, "covered_by_fresh_vm_tests": False},
        "case_identity_artifact": current(cases_path), "source_paths_rebound": len(source_paths),
        "source_blob_objects_rehashed": len(objects), "current_files_rehashed": len(prior.CACHE),
        "previous_phase": {"source": PREVIOUS, "summary": previous_record, "accepted_cases": 356, "accepted_files": 27,
                           "status": "partial_browser_environment_blocked", "browser_application_cases": 0,
                           "browser_loader_errors": 1, "browser_launch_invocations": 4,
                           "relabelled_to_arabic_source": False, "raw_receipts_modified": False},
        "fresh_browser_execution_performed": False, "fresh_browser_application_acceptance_claimed": False,
        "native_abi3_or_wasm_adapter2_execution_qualified": False, "real_disambiguation_model_execution_qualified": False,
        "combined_cross_source_total_claimed": False,
        "limits": [
            "These12 selected files are a separate f69 VM/unit/widget population. Earlier356/27,2386/157,3201/129 and2886 historical counts remain source-attributed and overlap; they are not added.",
            "VM tests use synthetic/fake transport and model behavior. They do not build or execute the native ABI3 or Wasm adapter2, rank a real context model, or qualify live downloads.",
            "The unchanged earlier Chrome attempt belongs only to a45: one loader error, zero application cases. No fresh browser execution or pass is claimed for the changed f69 Arabic web source.",
            "The incoming Arabic browser model-removal path retains a source-identified transferred-buffer reuse defect. It is disclosed separately, not runtime reproduced here, fixed, or covered by the selected VM tests.",
            "All129 active changed package/third-party Dart targets pass strict analysis and format. Two unchanged historical Mail harnesses are bound as preserved artifacts; their older110-target failure remains unchanged and is not rerun or reclassified.",
            "Saved dependency metadata is reused, with morph version0.2.0 versus current declaration0.3.0 and the absent Studio direct web edge disclosed. Effective dependency edges, reachable byte closures and external pins are verified unchanged; no resolver regeneration is claimed.",
            "The complete38-path source audit binds native/worker/license files outside the primary runner input inventory without claiming VM execution covers those platforms.",
        ],
        "verifier_record": current(Path(__file__)), "imported_host_helper_sha256": HOST_HELPER_SHA,
        "github_actions_queried": False, "product_files_modified": False,
    }
    write(HERE / "audit.json", result)
    summary = {key: value for key, value in result.items() if key not in ["cohorts", "verifier_record", "imported_host_helper_sha256"]}
    summary["cohorts"] = [{key: row[key] for key in ["name", "passed", "files", "source_commit", "primary_runner_status", "primary_failed_guards", "receipt"]} for row in rows]
    summary["independent_audit"] = {"path": "audit.json", "record": current(HERE / "audit.json")}
    write(HERE / "summary.json", summary)
    print(json.dumps({key: result[key] for key in ["status", "qualified_source", "distinct_passed_cases", "distinct_test_files", "source_paths_rebound", "source_blob_objects_rehashed", "current_files_rehashed"]}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
