"""Independently recount Dart/Flutter JSON events, including explicit skips.

Usage: python audit_results.py /path/to/extracted/acceptance
Only the Python standard library is required; this does not rerun tests.
"""

import argparse
import collections
import hashlib
import json
from pathlib import Path


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def count(path):
    events = []
    non_json_lines = 0
    for line in path.read_text().splitlines():
        if not line.strip():
            non_json_lines += 1
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            if line.lstrip().startswith("{"):
                raise
            non_json_lines += 1
    starts = {row["test"]["id"]: row["test"] for row in events
              if row["type"] == "testStart"}
    assert starts, (path, "no test starts")
    completed = set()
    counts = collections.Counter()
    suites = {}
    skips = []
    reasons = {row["testID"]: row["message"] for row in events
               if row["type"] == "print" and row.get("messageType") == "skip"}
    for row in events:
        if row["type"] != "testDone":
            continue
        test_id = row["testID"]
        assert test_id not in completed, (path, "duplicate completion", test_id)
        completed.add(test_id)
        name = starts[test_id]["name"]
        if (row.get("hidden") or name.startswith("loading ")
                or name.endswith("(setUpAll)") or name.endswith("(tearDownAll)")):
            continue
        suite = name.split(".dart", 1)[0] + ".dart" if ".dart" in name else name.split(" ", 1)[0]
        outcome = "skipped" if row.get("skipped") else row["result"]
        counts[outcome] += 1
        suites.setdefault(suite, collections.Counter())[outcome] += 1
        if outcome == "skipped":
            skips.append({"name": name, "reason": reasons.get(test_id)})
    done = [row for row in events if row["type"] == "done"]
    errors = [row for row in events if row["type"] == "error"]
    assert len(done) == 1 and done[0]["success"] is True, (path, done)
    assert not errors, (path, errors)
    assert completed == set(starts), (path, "unfinished test events")
    assert counts.get("failure", 0) == counts.get("error", 0) == 0
    assert path.with_suffix(".stderr").stat().st_size == 0
    return {"passed": counts["success"], "skipped": counts["skipped"],
            "failed": 0, "errors": 0, "done_success": True,
            "terminal_elapsed_ms": done[0]["time"], "suites": suites,
            "skipped_cases": skips, "non_json_lines": non_json_lines}


def audit(directory):
    results = {}
    for name in ("engine", "editor", "incoming"):
        receipt = json.loads((directory / (name + "-receipt.json")).read_text())
        log = directory / (name + ".jsonl")
        result = count(log)
        assert receipt["exit_code"] == 0, name
        assert receipt["source_stable"] is True, name
        assert receipt["acceptance"] == result, name
        assert receipt["log_sha256"] == sha256(log), name
        assert receipt["stderr_sha256"] == sha256(log.with_suffix(".stderr")), name
        before_path = directory / (name + "-sources-before.json")
        after_path = directory / (name + "-sources-after.json")
        assert receipt["source_manifest_sha256"] == sha256(before_path), name
        assert before_path.read_bytes() == after_path.read_bytes(), name
        results[name] = result
    return {"passed": sum(r["passed"] for r in results.values()),
            "skipped": sum(r["skipped"] for r in results.values()),
            "failed": 0, "runs": results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log_directory", type=Path)
    args = parser.parse_args()
    print(json.dumps(audit(args.log_directory), indent=2))


if __name__ == "__main__":
    main()
