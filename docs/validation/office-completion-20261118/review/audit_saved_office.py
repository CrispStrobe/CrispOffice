#!/usr/bin/env python3
"""Audit committed Office retry evidence without rerunning product gates.

All archive bytes are read from Git at --evidence-commit. No historical
environment is recreated, and no current runtime claim is made.
"""
import argparse
import collections
from datetime import datetime, timezone
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile
from urllib.parse import unquote, urlparse
import zipfile

SOURCE = "9d060658ee6be8ec97d73f56b9aec10d346b7952"
IMPLEMENTATION = "9a7c80be00258def2dcae3bb288c28558c83aa72"
BASE = "docs/validation/office-retry-20261118"
PRIVATE_CASES = {
    "TrueType subsets without cmap get ToUnicode cmap for the host",
    "JPEG with DCT SMask attaches softMaskJpeg for the host",
}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--evidence-commit", default="c9d86b3e543f8ffa7c8114d31c57922f134188ef")
    args = ap.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    findings = []
    checks = 0
    started = datetime.now(timezone.utc).isoformat()

    def check(value, name, detail=None):
        nonlocal checks
        checks += 1
        if not value:
            findings.append({"check": name, "detail": detail})
        return bool(value)

    def sha(data):
        return hashlib.sha256(data).hexdigest()

    def git(*argv):
        return subprocess.check_output(["git", "-C", str(args.repo), *argv])

    def blob(path, ref=None):
        return git("show", (ref or args.evidence_commit) + ":" + path)

    def j(data):
        return json.loads(data)

    source_tree = git("rev-parse", SOURCE + "^{tree}").decode().strip()
    difference = git("diff", "--name-only", IMPLEMENTATION, SOURCE).decode().splitlines()
    latest_difference = git("diff", "--name-only", SOURCE, args.evidence_commit).decode().splitlines()
    check(all(p.startswith("docs/") for p in difference), "execution-implementation-only-docs-diff", difference)
    check(all(p.startswith("docs/") for p in latest_difference), "evidence-source-only-docs-diff", latest_difference)
    entries = {}
    for record in git("ls-tree", "-rz", SOURCE).split(b"\0"):
        if not record:
            continue
        meta, name = record.split(b"\t", 1)
        mode, kind, oid = meta.decode().split()
        if kind == "blob":
            entries[name.decode()] = {"mode": mode, "blob": oid}
    pinned_data = {}

    def audit_source_map(mapping, label, complete=False):
        mismatches = []
        for path, row in mapping.items():
            actual = entries.get(path)
            if path not in pinned_data:
                pinned_data[path] = blob(path, SOURCE)
            data = pinned_data[path]
            expected_mode = row.get("git_mode", row.get("mode"))
            ok = actual and actual["mode"] == expected_mode and actual["blob"] == row["git_blob"] and sha(data) == row["sha256"]
            if "bytes" in row:
                ok = ok and len(data) == row["bytes"]
            if not ok:
                mismatches.append(path)
        check(not mismatches, "source-map-exact-git-blobs-modes-hashes", {"label": label, "mismatches": mismatches})
        if complete:
            check(set(mapping) == {p for p in entries if not p.startswith("docs/")}, "source-map-complete-nondocumentation", label)
        return len(mapping)

    archives = {}
    payloads = {}
    paths = git("ls-tree", "-r", "--name-only", args.evidence_commit, BASE + "/evidence").decode().splitlines()
    for path in paths:
        if not path.endswith(".tar.index.json"):
            continue
        index_bytes = blob(path)
        index = j(index_bytes)
        name = PurePosixPath(path).name.removesuffix(".tar.index.json")
        archive_bytes = blob(path.removesuffix(".index.json") + ".xz")
        check(len(archive_bytes) == index["bytes"] and sha(archive_bytes) == index["sha256"], "archive-whole-hash-size", name)
        indexed = {r["path"]: r for r in index["members"]}
        check(len(indexed) == len(index["members"]) == index["member_count"], "archive-index-unique-count", name)
        data_by_name = {}
        with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:xz") as tar:
            for member in tar:
                pp = PurePosixPath(member.name)
                safe = member.isfile() and not pp.is_absolute() and ".." not in pp.parts and member.name not in data_by_name
                check(safe, "archive-safe-unique-member", {"archive": name, "member": member.name})
                if not safe:
                    continue
                data = tar.extractfile(member).read()
                pin = indexed.get(member.name)
                check(pin and len(data) == pin["bytes"] and sha(data) == pin["sha256"], "archive-member-hash-size", {"archive": name, "member": member.name})
                data_by_name[member.name] = data
        check(set(data_by_name) == set(indexed), "archive-exact-member-set", name)
        archives[name] = {"sha256": sha(archive_bytes), "bytes": len(archive_bytes), "index_sha256": sha(index_bytes), "members_verified": len(data_by_name)}
        payloads[name] = data_by_name

    def audit_events(data, selection, cwd, summary, label):
        events = []
        for line in data.decode(errors="replace").splitlines():
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if isinstance(event, dict):
                events.append(event)
        starts = [e["test"] for e in events if e.get("type") == "testStart"]
        ends = [e for e in events if e.get("type") == "testDone"]
        suites = [e["suite"] for e in events if e.get("type") == "suite"]
        check(len({r["id"] for r in starts}) == len(starts), "event-unique-start", label)
        check(len({r["testID"] for r in ends}) == len(ends), "event-unique-end", label)
        check({r["id"] for r in starts} == {r["testID"] for r in ends}, "every-start-completed", label)
        check(len({r["id"] for r in suites}) == len(suites), "event-unique-suite", label)
        def resolved(path):
            if path.startswith("file:"):
                path = unquote(urlparse(path).path)
            p = PurePosixPath(path)
            return str(p if p.is_absolute() else PurePosixPath(cwd) / p)
        actual = [resolved(x["path"]) for x in suites]
        expected = [str(PurePosixPath(cwd) / p) for p in selection]
        check(len(actual) == len(set(actual)) == len(expected) and set(actual) == set(expected), "event-exact-selected-suites", label)
        by_id = {r["id"]: r for r in starts}
        suite_ids = {r["id"]: r for r in suites}
        visible = []
        hidden = 0
        excluded = []
        for row in ends:
            outcome = "skipped" if row.get("skipped") else row.get("result", "unknown")
            check(outcome == "success", "all-visible-hidden-events-success", {"gate": label, "id": row["testID"], "outcome": outcome})
            if row.get("hidden"):
                hidden += 1
                continue
            case = by_id.get(row["testID"], {})
            visible.append({"test_id": row["testID"], "suite_id": case.get("suiteID"), "name": case.get("name"), "outcome": outcome})
            if suite_ids.get(case.get("suiteID"), {}).get("path", "").endswith("/pdf_file_test.dart"):
                matched = next((s for s in PRIVATE_CASES if case.get("name", "") == s or case.get("name", "").endswith(" " + s)), None)
                if matched:
                    excluded.append({"test_id": row["testID"], "matched_case_name": matched})
        done = [r for r in events if r.get("type") == "done"]
        check(len(done) == 1 and done[0].get("success") is True, "event-successful-terminal-done", label)
        check(not [r for r in events if r.get("type") == "error"], "event-no-errors", label)
        outcomes = dict(collections.Counter(x["outcome"] for x in visible))
        check(summary["completed_tests"] == visible and summary["raw_runner_outcomes"] == outcomes, "raw-events-exact-summary", label)
        check(summary["raw_success_count"] == len(visible) and summary["substantive_success_count"] == len(visible) - len(excluded), "event-counts-match-summary", label)
        check(summary["passed"] and not summary["allowed_skipped_cases"] and not summary["unexpected_skipped_cases"], "test-summary-acceptance-no-skips", label)
        check({(r["test_id"], r["matched_case_name"]) for r in summary["excluded_success_cases"]} == {(r["test_id"], r["matched_case_name"]) for r in excluded}, "only-exact-private-exclusions", label)
        return {"selected_suites": len(selection), "raw_successes": len(visible), "substantive_successes": len(visible) - len(excluded), "excluded_private_cases": excluded, "hidden_loaders": hidden, "unexpected_skips": 0}

    canonical = payloads["canonical-complete"]
    receipt = j(canonical["receipt.json"])
    plan = j(canonical["plan.json"])
    frozen = j(blob("docs/validation/office-local-20261118/frozen-plan.json"))
    frozen["source_commit"] = SOURCE
    check(frozen == plan, "exact-frozen-plan")
    check(receipt["source_commit"] == receipt["working_head_after"] == SOURCE and receipt["source_tree"] == source_tree, "canonical-exact-source-tree-head")
    check(receipt["status"] == "passed" and receipt["all_passed"] and receipt["analysis_config_restored"] and receipt["source_matches_frozen_commit"], "canonical-acceptance")
    check(sha(canonical["plan.json"]) == receipt["plan_sha256"] and sha(canonical["run-used.py"]) == receipt["runner_sha256"], "canonical-plan-runner-bindings")
    check(not receipt["historical_qualifications_counted"] and not receipt["github_actions_queried_awaited_or_rerun"], "canonical-no-historical-or-ci")
    integrity = {}
    for group in ["source", "dependencies", "runtime", "workspace", "system", "harness"]:
        before, after = canonical[group + "-before.json"], canonical[group + "-after.json"]
        check(before == after and receipt["input_integrity"][group + "_unchanged"], "canonical-inputs-byte-identical", group)
        integrity[group] = {"count": len(j(before)), "sha256": sha(before), "byte_identical": before == after}
    source_map = j(canonical["source-before.json"])
    check(not source_map["commit_mismatches"] and not source_map["untracked_non_evidence_paths"], "canonical-clean-source-map")
    source_count = audit_source_map(source_map["files"], "canonical", complete=True)
    cohort_names = ["engine-zotero", "editor-zotero", "engine-integration", "editor-integration", "harper-contract", "gector-contract"]
    expected_names = [p + "-strict-analysis" for p in ["engine", "editor", "harper", "gector", "proofing-tools"]] + ["format", "python-controls"] + cohort_names
    check([r["name"] for r in receipt["commands"]] == expected_names, "canonical-exact-thirteen-commands")
    events_summary = {}
    for row in receipt["commands"]:
        name = row["name"]
        check(row["exit_code"] == 0 and not row["timed_out"] and row["status"] == "passed", "canonical-command-zero-exit", name)
        streams = {}
        for stream in ["stdout", "stderr"]:
            packed = canonical[row[stream]]
            data = gzip.decompress(packed)
            check(sha(packed) == row[stream + "_gzip_sha256"] and sha(data) == row[stream + "_sha256"], "canonical-stream-hash", {"command": name, "stream": stream})
            streams[stream] = data
        if name in cohort_names:
            selected = plan["cohorts"][name]["tests"]
            check(row["command"][-len(selected):] == selected, "canonical-command-exact-selection", name)
            events_summary[name] = audit_events(streams["stdout"], selected, row["cwd"], j(canonical[name + "/test-summary.json"]), name)
        elif name.endswith("-strict-analysis"):
            check(row["command"][1:3] == ["analyze", "--fatal-infos"] and b"No issues found!" in streams["stdout"], "strict-analysis-policy-and-output", name)
        elif name == "format":
            check(row["command"][1:5] == ["format", "--language-version=3.12", "--output=none", "--set-exit-if-changed"] and row["command"][5:] == plan["format_targets"], "format-exact-policy-targets")
            check(len(plan["format_targets"]) == 145 and b"(0 changed)" in streams["stdout"], "format-145-zero-changes")
    check(sum(v["selected_suites"] for v in events_summary.values()) == plan["unique_test_files"] == 224, "canonical-224-files")
    check(sum(v["raw_successes"] for v in events_summary.values()) == receipt["raw_runner_success_total"] == 4236, "canonical-4236-raw")
    check(sum(v["substantive_successes"] for v in events_summary.values()) == receipt["substantive_success_total"] == 4234, "canonical-4234-substantive")
    check(j(canonical["system-before.json"]).get("/home/mohammed/Desktop/al_tahreer_profile.pdf") is None, "private-fixture-absence-explicit")
    python = j(canonical["python-controls-summary.json"])
    check(python == receipt["python_controls_summary"] and python["passed"] and python["tests_run"] == 117, "python-117-controls")
    for key in ["errors", "expected_failures", "failures", "missing_selected_tests", "unexpected_skipped_cases", "unexpected_successes"]:
        check(not python[key], "python-no-failure-or-missing", key)

    supplemental = {}
    for name in ["portable", "editor-example", "calendar-timezones"]:
        content = payloads[name + "-9d060658"]
        r, outer = j(content["result/receipt.json"]), j(content["orchestration.json"])
        check(r["passed"] and outer["passed"] and outer["exit_code"] == 0 and r["head_unchanged"] and r["source_commit"] == outer["source_commit"] == SOURCE, "supplemental-source-outer-acceptance", name)
        before = gzip.decompress(content["result/inputs-before.json.gz"])
        after = gzip.decompress(content["result/inputs-after.json.gz"])
        check(before == after and all(r["input_integrity"].values()), "supplemental-inputs-identical", name)
        audit_source_map(j(before)["source"]["files"], name, complete=True)
        if name != "calendar-timezones":
            check(r["exit_code"] == 0, "supplemental-child-zero-exit", name)
            for stream, pin in r["outputs"].items():
                packed = content["result/" + stream + ".gz"]
                data = gzip.decompress(packed)
                check(sha(packed) == pin["compressed_sha256"] and sha(data) == pin["sha256"] and len(data) == pin["bytes"], "supplemental-stream-pins", name + "/" + stream)
            supplemental[name] = audit_events(gzip.decompress(content["result/stdout.gz"]), r["selected_files"], r["cwd"], r["test_summary"], name)
            check(supplemental[name]["substantive_successes"] == (225 if name == "portable" else 2), "supplemental-exact-count", name)
            if name == "portable":
                check("--platform=node" in r["command"] and len(r["selected_files"]) == 17, "portable-17-node-suites")
                check("test/odt_complex_field_fidelity_test.dart" in plan["cohorts"]["engine-integration"]["tests"], "node-exclusion-retained-in-vm")
        else:
            zones = {"UTC": [0, 0, 0], "Europe/Berlin": [60, 120, 60], "America/Los_Angeles": [-480, -420, -480]}
            check([v["timezone"] for v in r["runs"]] == list(zones), "calendar-exact-three-zones")
            results = []
            for run in r["runs"]:
                zone = run["timezone"]
                prefix = "result/" + zone.replace("/", "_") + "/"
                check(run["passed"] and run["exit_code"] == 0 and run["timezone_verified"], "calendar-zone-accepted", zone)
                probe = j(content[prefix + "timezone-probe.stdout"])
                check(probe == run["timezone_probe"] and [x["offsetMinutes"] for x in probe] == zones[zone], "calendar-actual-timezone-offsets", zone)
                results.append(audit_events(gzip.decompress(content[prefix + "stdout.gz"]), r["selected_files"], run["cwd"], run["test_summary"], zone))
            check(r["test_executions"] == sum(x["substantive_successes"] for x in results) == 24, "calendar-24-overlapping-executions")
            supplemental[name] = {"zones": list(zones), "test_executions": 24, "additional_unique_tests": 0}

    consumers = {}
    for name in ["retained33", "current7", "boundary5", "frame5", "native-prepare"]:
        content = payloads[name + "-9d060658"]
        guard = j(content["guard/receipt.json"])
        outer = j(content["orchestration.json"])
        check(guard["source_commit"] == outer["source_commit"] == SOURCE and guard["passed"] and outer["passed"] and guard["child_exit_code"] == outer["exit_code"] == 0, "guard-source-process-acceptance", name)
        for field in ["source_checkout_clean_before", "source_checkout_clean_after", "source_bytes_match_frozen_commit_before_and_after", "runtime_and_workspace_unchanged"]:
            check(guard[field] is True, "guard-stability-flag", name + "/" + field)
        before = j(gzip.decompress(content["guard/inputs-before.json.gz"]))
        after = j(gzip.decompress(content["guard/inputs-after.json.gz"]))
        check(before == after, "guard-all-input-maps-identical", name)
        audit_source_map(before["source"], name)
        check(len(before["source"]) == guard["source_file_count"] and len(before["runtime"]) == guard["runtime_and_workspace_file_count"], "guard-exact-map-counts", name)
        for path, pin in guard["output_hashes"].items():
            check(sha(content["guard/" + path]) == pin, "guard-output-pins", name + "/" + path)
        extracted = args.output / "extracted" / name
        extracted.mkdir(parents=True, exist_ok=True)
        for path, data in content.items():
            destination = extracted / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
        if name == "native-prepare":
            controls = j(content["result/audit-controls.json"])
            build = j(content["result/provider-build.json"])
            check(controls["passed"] and len(controls["controls"]) == 23 and all(x["passed"] for x in controls["controls"]), "native-23-audit-controls")
            check(all(build[x] for x in ["completed", "passed", "source_stable", "dependencies_stable", "sdk_stable"]) and build["compile"]["returncode"] == 0, "native-prepare-build-pass")
            check(build["source_files"] == build["source_files_after"] and build["sdk_inputs"] == build["sdk_inputs_after"] and build["dependency_inputs"] == build["dependency_inputs_after"], "native-build-inputs-identical")
            for path, pin in build["source_files"].items():
                if path not in ["pubspec.lock", "pubspec.yaml"]:
                    check(sha(blob(path, SOURCE)) == pin, "native-build-source-pin", path)
            consumers[name] = {"accepted": True, "audit_controls": 23, "aot_build_passed": True, "sweep_accepted": False, "guard_runtime_files": len(before["runtime"])}
            continue
        if name == "frame5":
            r = j(content["result/summary.json"])
            check(r["head_at_start"] == SOURCE and r["source_inputs_unchanged"] and r["fixture_count"] == r["fixture_passes"] == 5, "frame5-summary")
            fixtures = j(content["result/fixture-results.json"])
            schemas = j(content["result/schema-results.json"])
            check(len(fixtures) == 5 and all(x["pass"] for x in fixtures), "frame5-fixture-acceptance")
            check(len(schemas) == r["schema_parts"] == r["jing_valid"] == 20 and all(x["jing_valid"] for x in schemas), "frame5-official-oracle-all-parts")
            check(sum(x["lxml_valid"] for x in schemas) == r["lxml_valid"] == 19, "frame5-lxml-diagnostic-retained")
            check(content["result/source-inputs-before.json"] == content["result/source-inputs-after.json"], "frame5-inputs-byte-identical")
            commands = j(content["result/commands.json"])
            summary = {"fixtures": 5, "passed": 5, "schema_parts_passed": 20, "lxml_false_negatives": 1, "scope": r["scope"]}
        else:
            r = j(content["result/receipt.json"])
            check(r["passed"] and r.get("source_head", r.get("source_commit")) == SOURCE, "consumer-source-acceptance", name)
            commands = r["commands"]
            fixtures = r["fixtures"]
            check(len(fixtures) == {"retained33": 33, "current7": 7, "boundary5": 5}[name], "consumer-exact-fixture-count", name)
            for path, pin in r.get("output_hashes", r.get("output_sha256", {})).items():
                check("result/" + path in content and sha(content["result/" + path]) == pin, "consumer-output-receipt-pins", name + "/" + path)
            if name == "boundary5":
                check(r["inputs_unchanged"] and content["result/inputs-before.json"] == content["result/inputs-after.json"], "boundary-inputs-identical")
                check(all(set(x["variants"]) == {"direct", "imported", "source"} for x in fixtures), "boundary-three-variants-each")
                summary = {"fixtures": 5, "strict_layouts": 4, "bounded_controls": 1, "pdf_variants": 15, "docx_reopens": 10, "scope": r["scope"]}
            else:
                check(all(x["passed"] for x in fixtures), "consumer-all-fixtures-pass", name)
                check(all(r[x] for x in ["head_unchanged", "source_unchanged", "runtime_unchanged", "fixtures_unchanged"]), "consumer-stability-flags", name)
                check(j(gzip.decompress(content["result/inputs.json.gz"])) == j(gzip.decompress(content["result/inputs-after.json.gz"])), "consumer-input-maps-identical", name)
                key, failures = ("passed_parts", "failures") if name == "retained33" else ("jing_passed_parts", "jing_failures")
                parts = 0
                for fixture in fixtures:
                    check(len(fixture["schema"][key]) == 4 and not fixture["schema"][failures], "consumer-four-schema-parts-each", name + "/" + fixture["name"])
                    parts += len(fixture["schema"][key])
                summary = r["summary"]
                check(summary["fixtures"] == summary["passed"] == len(fixtures) and summary["failed"] == 0 and summary["schema_parts_passed"] == summary["schema_parts_total"] == parts, "consumer-derived-summary", name)
        check(all(x.get("exit_code") == 0 for x in commands), "consumer-all-commands-zero-exit", name)
        package_count = 0
        for path, data in content.items():
            if path.endswith((".docx", ".odt")):
                with zipfile.ZipFile(io.BytesIO(data)) as package:
                    check(package.testzip() is None, "document-package-crcs", name + "/" + path)
                package_count += 1
        consumers[name] = {"accepted": True, **summary, "command_count": len(commands), "packages_with_valid_crc": package_count, "guard_source_files": len(before["source"]), "guard_runtime_files": len(before["runtime"])}

    reviews = {}
    for name in ["canonical", "supplemental"]:
        data = blob(BASE + "/review/" + name + "-review.json")
        report = j(data)
        accepted = report.get("accepted", report.get("canonical_qualification_accepted"))
        check(accepted and not report["findings"] and report["source_commit"] == SOURCE, "saved-independent-review-accepted", name)
        reviews[name] = {"sha256": sha(data), "checks": report["independent_checks"], "accepted": accepted}
    result = {
        "schema": "quds.office.saved_evidence_audit.v1", "started_utc": started,
        "completed_utc": datetime.now(timezone.utc).isoformat(),
        "evidence_commit": args.evidence_commit, "execution_source": SOURCE, "implementation_source": IMPLEMENTATION,
        "source_tree": source_tree, "source_files_bound_to_git": source_count,
        "source_differences_are_documentation_only": True,
        "audit_script_sha256": sha(Path(__file__).read_bytes()),
        "checks": checks, "findings": findings, "accepted": not findings,
        "archives": archives, "total_verified_archive_members": sum(x["members_verified"] for x in archives.values()),
        "canonical": {"input_integrity": integrity, "cohorts": events_summary, "raw_successes": 4236, "substantive_successes": 4234, "python_controls": 117},
        "supplemental": supplemental, "document_consumers_and_native_prepare": consumers,
        "prior_independent_reviews": reviews,
        "remaining_product_gate": "native serial 1/2/4/8-thread sweep with independent semantic audit",
        "qualification_accepted": False, "release_accepted": False,
        "limitations": ["Archive audit validates the saved run; it does not assert that a newly restored runtime has the same bytes.", "Consumer assertions are inspected here; a separate offline replay can verify measured archived outputs against the preserved contracts.", "Native preparation is not native semantic qualification.", "Boundary5 includes one bounded control; document render results are LibreOffice, not Microsoft Word."],
        "github_actions_endpoints_queried": 0, "product_gates_rerun": False,
    }
    (args.output / "saved-evidence-audit.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"accepted": not findings, "checks": checks, "findings": findings, "archives": len(archives), "members": result["total_verified_archive_members"]}))
    return 0 if not findings else 1


if __name__ == "__main__":
    raise SystemExit(main())
