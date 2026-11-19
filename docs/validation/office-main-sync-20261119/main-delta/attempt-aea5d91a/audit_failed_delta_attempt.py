#!/usr/bin/env python3
"""Document the rejected aea5 attempt without treating visible successes as accepted."""
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
    check(source == "aea5d91af0083bc088d599ed767188f0bb071195" and receipt["status"] == "FAIL", "Exact rejected source and status")
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
    groups, malformed_all, case_inventory = [], [], []
    for run in native["runs"]:
        raw = (gate / run["log"]).read_bytes()
        check(sha(raw) == run["log_sha256"], "Native command log hash: " + run["name"])
        if not run["log"].endswith(".jsonl"):
            check(run["exit_code"] == 0 and run["accepted"] is True, "Passed strict command: " + run["name"])
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
        check(sum(e["type"] == "start" for e in events) == sum(e["type"] == "done" for e in events) == 1 and events[-1]["type"] == "done" and events[-1]["success"] is True, "Reporter runner success despite external diagnostic lines: " + run["name"])
        visible = []
        for test_id, end in ends.items():
            start = starts[test_id]
            check(end.get("result") == "success" and end.get("skipped") is False, "Raw lifecycle success/no skip: " + start["name"])
            if end.get("hidden") or start["name"].startswith("loading ") or re.search(r"(?:^| )\((?:setUpAll|tearDownAll)\)$", start["name"]):
                continue
            visible.append({"id": test_id, "name": start["name"], "suite_id": start["suiteID"]})
        check(len(visible) == run["passed"] and run["failed"] == run["skipped"] == 0, "Raw visible count matches recorded development result: " + run["name"])
        malformed_all.extend(malformed)
        case_inventory.extend({"group": run["name"], **row} for row in visible)
        groups.append({"name": run["name"], "visible_successes": len(visible), "failed": 0, "skipped": 0,
                       "strict_gate_accepted": run["accepted"], "malformed_reporter_lines": len(malformed), "raw_sha256": sha(raw)})
    check(len(case_inventory) == native["passed"] == 159, "Exactly 159 visible successes retained only as rejected-attempt evidence")
    check(len(malformed_all) == 3 and all(row["group"] == "hunspell-native" for row in malformed_all), "Exact three native diagnostic lines caused strict reporter rejection")
    check(groups[0]["strict_gate_accepted"] is False and all(row["strict_gate_accepted"] is True for row in groups[1:]), "Only malformed native reporter group rejected")
    controls = (outer / "bundle-controls.log").read_bytes()
    rows = re.findall(rb"^test\S+ \([^)]+\) \.\.\. ok$", controls, re.MULTILINE)
    check(len(rows) == 17 and re.search(rb"Ran 17 tests in [^\n]+\n\s*\nOK\s*$", controls), "Seventeen successful controls in this rejected attempt")
    result = {"audit_checks_passed": not issues, "issues": issues, "source_commit": source, "source_tree": receipt["source_tree"],
              "audited_at_utc": datetime.now(timezone.utc).isoformat(), "recorded_failure_confirmed": not issues,
              "accepted_qualification": False, "attempt_status": "FAIL", "failure": "Three native C++ missing-dictionary stderr diagnostics were merged into the JSON reporter stream; strict accounting correctly rejected the native group.",
              "visible_application_successes": 159, "failed_application_case_events": 0, "skipped_application_case_events": 0,
              "groups": groups, "malformed_reporter_lines": malformed_all, "case_inventory": case_inventory,
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
