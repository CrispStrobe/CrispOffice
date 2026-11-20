"""Recount the archived Dart/Flutter JSON events without counting skips as passes.

Usage: python audit_results.py /path/to/extracted/local-validation
Only the Python standard library is required. This does not rerun tests.
"""

import argparse
import collections
import json
from pathlib import Path


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
            # Flutter prints its first-run telemetry notice before JSON output.
            # A malformed JSON event must still fail this audit.
            if line.lstrip().startswith("{"):
                raise
            non_json_lines += 1
    starts = {row["test"]["id"]: row["test"] for row in events
              if row["type"] == "testStart"}
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
        test = starts[test_id]
        name = test["name"]
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log_directory", type=Path)
    args = parser.parse_args()
    expected = {"final-main-engine": (495, 0),
                "final-main-editor": (378, 8),
                "final-main-incoming": (928, 0),
                "final-formatted-incoming": (405, 0)}
    results = {}
    for name, totals in expected.items():
        result = count(args.log_directory / (name + ".jsonl"))
        assert (result["passed"], result["skipped"]) == totals, (name, result)
        results[name] = result
    # The formatted rerun is a subset of incoming coverage, not extra cases.
    print(json.dumps({"final_passed": 1801, "final_skipped": 8,
                      "format_followup_already_counted": 405,
                      "runs": results}, indent=2))


if __name__ == "__main__":
    main()
