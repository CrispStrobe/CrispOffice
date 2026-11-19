#!/usr/bin/env python3
"""Document the rejected c0c v2 attempt without treating visible successes as accepted."""
import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ("repo", "outer", "output"):
        p.add_argument("--" + name, type=Path, required=True)
    a = p.parse_args()
    outer = a.outer.resolve()
    issues = []
    def check(value, message):
        if not value:
            issues.append(message)
    def read(path):
        return json.loads(path.read_bytes())
    receipt = read(outer / "execution.json")
    source = receipt["source_commit"]
    check(source == "c0c71a26e014cadda7a1f42244e710509dea5f6c" and receipt["status"] == "FAIL", "Exact rejected source and status")
    check([r["name"] for r in receipt["runs"]] == ["locked-workspace-resolution", "delta-continuity", "bundle-controls", "native"], "Exact stopped attempt command inventory")
    check(not (outer / "node").exists() and not list(outer.glob("hunspell-browser.js*")), "Node and browser outputs absent")
    for name, expected in receipt["manifest_sha256"].items():
        check(sha((outer / name).read_bytes()) == expected, "Outer manifest hash: " + name)
    before, after = (read(outer / ("source-" + phase + ".json")) for phase in ("before", "after"))
    runtime_before, runtime_after = (read(outer / ("runtime-" + phase + ".json")) for phase in ("before", "after"))
    check(before == after and runtime_before == runtime_after, "Recorded source/runtime before and after unchanged")
    check(all(receipt[k] is True for k in ("source_unchanged", "runtime_unchanged", "source_head_unchanged", "tracked_worktree_clean_after")), "Recorded frozen-source guards passed")
    names = sorted(before)
    proc = subprocess.run(["git", "--no-replace-objects", "cat-file", "--batch"], cwd=a.repo,
                          input="".join(source + ":" + name + "\n" for name in names).encode(), stdout=subprocess.PIPE, check=True)
    stream = io.BytesIO(proc.stdout)
    for name in names:
        _, kind, size = stream.readline().decode().split()
        raw = stream.read(int(size))
        check(stream.read(1) == b"\n" and kind == "blob" and sha(raw) == before[name], "Immutable frozen source binding: " + name)
    check(not stream.read(), "Complete immutable source object stream")
    gate = outer / "native"
    native = read(gate / "verification.json")
    check(native["success"] is False and native["source_commit"] == source, "Native gate rejected on exact source")
    for name, expected in native["manifest_sha256"].items():
        check(sha((gate / name).read_bytes()) == expected, "Native manifest hash: " + name)
    check(read(gate / "source-before.json") == read(gate / "source-after.json") and read(gate / "environment-before.json") == read(gate / "environment-after.json"), "Native source/runtime manifests identical")
    groups, malformed_all, case_inventory, strict_commands, reporter_errors = [], [], [], [], []
    for run in native["runs"]:
        raw = (gate / run["log"]).read_bytes()
        check(sha(raw) == run["log_sha256"], "Native command log hash: " + run["name"])
        if not run["log"].endswith(".jsonl"):
            strict_commands.append({"name": run["name"], "exit_code": run["exit_code"], "accepted": run["accepted"], "raw_sha256": sha(raw), "log": run["log"]})
            continue
        events, malformed = [], []
        for number, line in enumerate(raw.decode().splitlines(), 1):
            value = line.strip()
            for prefix in ("Running build hooks...", "Running link hooks..."):
                if value.startswith(prefix):
                    value = value[len(prefix):].lstrip()
            if not value:
                continue
            try:
                events.append(json.loads(value))
            except json.JSONDecodeError:
                malformed.append({"group": run["name"], "line": number, "text": value})
        starts_rows = [e["test"] for e in events if e["type"] == "testStart"]
        ends_rows = [e for e in events if e["type"] == "testDone"]
        starts = {row["id"]: row for row in starts_rows}
        ends = {row["testID"]: row for row in ends_rows}
        check(len(starts_rows) == len(starts) and len(ends_rows) == len(ends) and set(starts) == set(ends), "Complete distinct raw lifecycle IDs: " + run["name"])
        check(sum(e["type"] == "start" for e in events) == sum(e["type"] == "done" for e in events) == 1 and events[-1]["type"] == "done"
              and events[-1]["success"] == (run["failed"] == 0), "Reporter terminal result agrees with recorded failures: " + run["name"])
        reporter_errors.extend({"group": run["name"], **e} for e in events if e["type"] == "error")
        visible = []
        for test_id, end in ends.items():
            start = starts[test_id]
            check(end.get("skipped") is False, "No skipped raw lifecycle: " + start["name"])
            if end.get("hidden") or start["name"].startswith("loading ") or re.search(r"(?:^| )\((?:setUpAll|tearDownAll)\)$", start["name"]):
                continue
            visible.append({"id": test_id, "name": start["name"], "suite_id": start["suiteID"], "result": end.get("result")})
        passed = sum(row["result"] == "success" for row in visible)
        failed = sum(row["result"] != "success" for row in visible)
        check(passed == run["passed"] and failed == run["failed"] and run["skipped"] == 0, "Independent visible result counts agree: " + run["name"])
        malformed_all.extend(malformed)
        case_inventory.extend({"group": run["name"], **row} for row in visible)
        groups.append({"name": run["name"], "visible_successes": passed, "failed": failed, "skipped": 0,
                       "strict_gate_accepted": run["accepted"], "malformed_reporter_lines": len(malformed), "raw_sha256": sha(raw)})
    check(sum(row["visible_successes"] for row in groups) == native["passed"] == 469, "Exactly 469 visible successes retained only as rejected-attempt evidence")
    check(sum(row["failed"] for row in groups) == native["failed"] == 3 and len(case_inventory) == 472, "Exactly three failing cases among 472 visible cases")
    check(not malformed_all, "No malformed native reporter lines after missing-file repair")
    check({row["name"] for row in groups if not row["strict_gate_accepted"]} == {"studio-main-merge-vm"}, "Only Studio test group rejected")
    check(len(reporter_errors) == 3 and all(row["group"] == "studio-main-merge-vm" for row in reporter_errors), "Exact three raw Studio failure events")
    check({row["name"] for row in strict_commands if not row["accepted"]} == {"format"}, "Only strict formatting rejected among static checks")
    format_raw = (gate / "checks/format.log").read_text()
    changed_format_paths = re.findall(r"^Changed (.+)$", format_raw, re.MULTILINE)
    check(set(changed_format_paths) == {"packages/quds_office_editor/example/lib/suite_workspace.dart", "packages/quds_office_editor/example/test/pdf_gallery_smoke_test.dart", "packages/quds_office_editor/example/test/pdf_showcase_test.dart"}, "Exact three inherited formatting targets require correction")
    controls = (outer / "bundle-controls.log").read_bytes()
    rows = re.findall(rb"^test\S+ \([^)]+\) \.\.\. ok$", controls, re.MULTILINE)
    check(len(rows) == 17 and re.search(rb"Ran 17 tests in [^\n]+\n\s*\nOK\s*$", controls), "Seventeen successful controls in this rejected attempt")
    result = {"audit_checks_passed": not issues, "issues": issues, "source_commit": source, "source_tree": receipt["source_tree"],
              "audited_at_utc": datetime.now(timezone.utc).isoformat(), "recorded_failure_confirmed": not issues,
              "accepted_qualification": False, "attempt_status": "FAIL", "failure": "Three Studio selector assertions failed, and strict no-write formatting found three inherited files needing formatting. The gate correctly rejected the complete attempt.",
              "visible_application_successes": 469, "failed_application_case_events": 3, "skipped_application_case_events": 0,
              "groups": groups, "malformed_reporter_lines": malformed_all, "case_inventory": case_inventory,
              "failed_cases": [row for row in case_inventory if row["result"] != "success"], "raw_reporter_errors": reporter_errors,
              "strict_commands": strict_commands, "formatting_required_paths": changed_format_paths,
              "separate_python_successes_in_rejected_attempt": 17,
              "application_cases_added_to_final_totals": 0, "python_controls_added_to_final_totals": 0,
              "node_started": False, "browser_compile_started": False, "source_inputs_bound_to_immutable_commit": len(before),
              "source_snapshots_equal": before == after, "runtime_snapshots_equal": runtime_before == runtime_after,
              "runtime_inputs_in_stable_envelope": len(runtime_before), "outer_execution_sha256": sha((outer / "execution.json").read_bytes()),
              "native_receipt_sha256": sha((gate / "verification.json").read_bytes()), "audit_script_sha256": sha(Path(__file__).read_bytes()),
              "method": "Read-only raw valid-event recount with explicit malformed-line inventory, original receipt and snapshot hashes, immutable source object verification. The rejected attempt remains unchanged and contributes zero to accepted totals."}
    a.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("audit_checks_passed", "issues", "recorded_failure_confirmed", "accepted_qualification", "visible_application_successes", "application_cases_added_to_final_totals")}, indent=2))
    return int(bool(issues))


if __name__ == "__main__":
    raise SystemExit(main())
