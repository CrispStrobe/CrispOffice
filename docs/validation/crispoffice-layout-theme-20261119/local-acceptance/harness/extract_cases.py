#!/usr/bin/env python3
"""Extract Dart test evidence without accepting source changes or rewriting logs.

Public API:
    extract_log(path, platform=None, repo_root=None, cwd=None, exit_code=None)
    combine_reports(reports)

`platform` is a caller-supplied fallback for expanded output, which usually does
not print the runner platform. A Flutter TargetPlatform variant remains part of
the exact test name; it is not the runner platform. `cwd` resolves relative suite
paths, and `repo_root` optionally makes absolute suite paths repository-relative.

Only a complete, consistent successful log with a supplied zero process exit
code contributes `confirmed_pass_*` counts. These are process/log evidence, not
acceptance of any source revision. Failed, partial, ambiguous and mixed logs
remain visible and never become accepted merely because another run passed.
"""

import argparse
from collections import Counter, defaultdict
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit


ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
PROGRESS = re.compile(
    r"^\s*\d+:\d{2}(?::\d{2})?\s+(?P<counts>(?:[+~-]\d+\s*)+):\s?(?P<body>.*)$"
)
DESCRIPTION = re.compile(r"^(?P<file>.*?\.dart): (?P<name>.*)$")
PLATFORM = re.compile(r"^\[(?P<runtime>[^\],]+)(?:,\s*(?P<compiler>[^\]]+))?\]\s+")
HOOK = re.compile(r"(?:^|\s)\((?:setUpAll|tearDownAll|setUp|tearDown)\)$")
FATAL = re.compile(
    r"^(?:Unhandled exception|Fatal error|Segmentation fault|Traceback \(most recent call last\)|"
    r"Error:|EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK)", re.IGNORECASE
)
EVENT_TYPES = {"start", "suite", "group", "testStart", "testDone", "error", "print", "allSuites", "done"}


def _note(collection, message, line=None):
    item = {"message": message}
    if line is not None:
        item["line"] = line
    if item not in collection:
        collection.append(item)


def _platform(value):
    if not isinstance(value, str) or not value.strip():
        return None
    value = value.strip().lower()
    return {"node.js": "node", "dart vm": "vm", "internet explorer": "ie"}.get(value, value)


def _file(value, context):
    if not isinstance(value, str) or not value:
        return None
    if value.startswith("file:"):
        value = unquote(urlsplit(value).path)
    if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://", value):
        return value
    value = os.path.normpath(value)
    if not os.path.isabs(value) and context.get("cwd"):
        value = os.path.normpath(os.path.join(context["cwd"], value))
    root = context.get("repo_root")
    if root and os.path.isabs(value):
        try:
            value = str(Path(value).relative_to(root))
        except ValueError:
            pass
    return value.replace(os.sep, "/")


def _hidden_reason(name):
    if name.startswith("loading "):
        return "loader"
    if HOOK.search(name):
        return "setup_or_teardown"
    return None


def _empty_report(fmt, context):
    return {
        "schema_version": 1,
        "format": fmt,
        "context": context,
        "cases": [],
        "excluded_events": [],
        "ambiguities": [],
        "warnings": [],
        "errors": [],
        "terminal_success": None,
        "terminal_count": 0,
    }


def _finish(report):
    cases = report["cases"]
    pending = [row for row in cases if row["result"] in {"unknown", "incomplete"}]
    for row in cases:
        if not row.get("file"):
            _note(report["ambiguities"], "A visible test has no unambiguous suite file.", row.get("start_line"))
        if not row.get("platform"):
            _note(report["ambiguities"], "Runner platform was not reported; supply an explicit platform fallback.", row.get("start_line"))
    if not cases:
        _note(report["ambiguities"], "No visible test cases were recovered.")
    if report["terminal_count"] > 1:
        _note(report["ambiguities"], "Multiple terminal events: split concatenated runs before qualification.")
    failed = bool(report["errors"]) or any(row["result"] in {"failed", "error"} for row in cases)
    failed |= report["terminal_success"] is False
    exit_code = report["context"].get("exit_code")
    if exit_code not in (None, 0):
        failed = True
        _note(report["errors"], f"Caller supplied nonzero process exit code {exit_code}.")
    complete = report["terminal_count"] == 1 and not pending and not report.get("unfinished_hidden_events")
    if failed:
        status = "failed"
    elif report["terminal_count"] == 0 or report.get("unfinished_hidden_events"):
        status = "incomplete"
    elif report["ambiguities"] or pending:
        status = "ambiguous"
    else:
        status = "passed"
    if exit_code is None:
        _note(report["warnings"], "Process exit code is unconfirmed; confirmed pass counts remain zero.")
    report["complete"] = complete
    report["status"] = status
    report["process_success_confirmed"] = exit_code == 0
    report["usable_pass_evidence"] = status == "passed" and complete and exit_code == 0
    report["scope"] = "Log/process evidence only; source-revision acceptance must be supplied separately."
    report["counts"] = {
        "visible_case_occurrences": len(cases),
        "results": dict(sorted(Counter(row["result"] for row in cases).items())),
        "excluded_event_occurrences": len(report["excluded_events"]),
        "confirmed_pass_occurrences": sum(row["result"] == "passed" for row in cases) if report["usable_pass_evidence"] else 0,
        "distinct_file_name_platform": len({(row.get("file"), row["name"], row.get("platform")) for row in cases}),
        "distinct_file_name": len({(row.get("file"), row["name"]) for row in cases}),
    }
    by_file = defaultdict(Counter)
    for row in cases:
        by_file[(row.get("file"), row.get("platform"))][row["result"]] += 1
    report["per_file"] = [
        {"file": file, "platform": platform, "results": dict(sorted(results.items())), "total": sum(results.values())}
        for (file, platform), results in sorted(by_file.items(), key=lambda item: str(item[0]))
    ]
    return report


def _parse_json(lines, context):
    report = _empty_report("dart-json", context)
    suites, active, rows = {}, {}, []
    start_count, expected_suites = 0, None
    for number, line in lines:
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            if line.lstrip().startswith("{") or PROGRESS.match(line):
                _note(report["ambiguities"], "Malformed JSON or mixed reporter output.", number)
            elif FATAL.search(line.strip()):
                _note(report["errors"], line.strip(), number)
            else:
                _note(report["warnings"], "Non-reporter output was ignored.", number)
            continue
        if not isinstance(event, dict) or event.get("type") not in EVENT_TYPES:
            _note(report["ambiguities"], "Unknown JSON record; its effect on the test stream is unverified.", number)
            continue
        kind = event["type"]
        if report["terminal_count"] and kind != "print":
            _note(report["ambiguities"], "Reporter events occurred after the terminal event.", number)
        if kind == "start":
            start_count += 1
        elif kind == "suite":
            suite = event.get("suite", {})
            if not isinstance(suite, dict) or "id" not in suite:
                _note(report["ambiguities"], "Malformed suite event.", number)
                continue
            if suite["id"] in suites:
                _note(report["ambiguities"], "Duplicate suite ID.", number)
            suites[suite["id"]] = suite
        elif kind == "allSuites":
            expected_suites = event.get("count")
        elif kind == "testStart":
            test = event.get("test", {})
            if not isinstance(test, dict) or not isinstance(test.get("name"), str) or "id" not in test:
                _note(report["ambiguities"], "Malformed testStart event.", number)
                continue
            if test["id"] in active:
                _note(report["ambiguities"], "Duplicate test ID, possibly concatenated runs.", number)
            row = {
                "test_id": test["id"], "suite_id": test.get("suiteID"),
                "name": test["name"], "result": "incomplete", "start_line": number,
                "result_source": "json-events", "done_seen": False,
            }
            rows.append(row)
            active[test["id"]] = row
        elif kind == "testDone":
            row = active.get(event.get("testID"))
            if row is None:
                _note(report["ambiguities"], "testDone has no matching testStart.", number)
                continue
            if row["done_seen"]:
                _note(report["ambiguities"], "Repeated testDone for one test ID.", number)
            row["done_seen"] = True
            row["end_line"] = number
            row["hidden"] = event.get("hidden") is True
            result = event.get("result")
            if result in {"failure", "error"}:
                row["result"] = "failed" if result == "failure" else "error"
            elif event.get("skipped") is True:
                row["result"] = "skipped"
            elif result == "success":
                row["result"] = "passed"
            else:
                row["result"] = "unknown"
                _note(report["ambiguities"], "Unknown testDone result.", number)
        elif kind == "error":
            _note(report["errors"], str(event.get("error", "Runner reported an error.")), number)
            row = active.get(event.get("testID"))
            if row is not None:
                row["reported_error"] = True
        elif kind == "done":
            report["terminal_count"] += 1
            report["terminal_success"] = event.get("success")
            if event.get("success") not in (True, False):
                _note(report["ambiguities"], "Terminal event has no Boolean success result.", number)
    if start_count != 1:
        _note(report["ambiguities"], f"Expected one runner start, found {start_count}.")
    if expected_suites is not None and expected_suites != len(suites):
        _note(report["ambiguities"], "allSuites count does not match observed suite events.")
    report["suite_count"] = len(suites)
    report["unfinished_hidden_events"] = 0
    for row in rows:
        suite = suites.get(row.pop("suite_id"), {})
        row["file"] = _file(suite.get("path"), context)
        row["platform"] = _platform(suite.get("platform")) or context.get("platform")
        row["platform_source"] = "reporter" if _platform(suite.get("platform")) else "caller" if context.get("platform") else "unreported"
        if row.pop("reported_error", False):
            row["result"] = "error"
        reason = _hidden_reason(row["name"])
        if row.pop("hidden", False):
            reason = reason or "reporter_hidden"
        done = row.pop("done_seen")
        if reason:
            row["excluded_reason"] = reason
            report["excluded_events"].append(row)
            if not done:
                report["unfinished_hidden_events"] += 1
            if row["result"] in {"failed", "error"}:
                _note(report["errors"], "A hidden loader/setup/teardown event failed.", row["start_line"])
        else:
            report["cases"].append(row)
    return _finish(report)


def _parse_expanded(lines, context):
    report = _empty_report("dart-expanded", context)
    observations, loaded = [], set()
    previous = None
    for number, line in lines:
        match = PROGRESS.match(line)
        if not match:
            if FATAL.search(line.strip()):
                _note(report["errors"], line.strip(), number)
            continue
        counts = {"+": 0, "~": 0, "-": 0}
        counts.update({kind: int(value) for kind, value in re.findall(r"([+~-])(\d+)", match["counts"])})
        if previous is None and any(counts.values()):
            _note(report["ambiguities"], "The log starts after tests have completed; earlier identities may be missing.", number)
        if previous and any(counts[key] < previous[key] for key in counts):
            _note(report["ambiguities"], "Progress counters decreased, possibly concatenated runs.", number)
        previous = counts
        body = match["body"]
        if body.strip() in {"All tests passed!", "All tests skipped.", "Some tests failed."}:
            report["terminal_count"] += 1
            report["terminal_success"] = body.strip() != "Some tests failed."
            report["terminal_counters"] = {"passed": counts["+"], "skipped": counts["~"], "failed": counts["-"]}
            continue
        if report["terminal_count"]:
            _note(report["ambiguities"], "Progress appeared after a terminal summary.", number)
        platform_match = PLATFORM.match(body)
        runtime = None
        if platform_match:
            runtime = _platform(platform_match["runtime"])
            body = body[platform_match.end():]
        result = "unknown"
        if body.endswith(" - did not complete [E]"):
            body = body[:-len(" - did not complete [E]")]
            result = "incomplete"
        elif body.endswith(" [E]"):
            body = body[:-4]
            result = "failed"
        if body.startswith("loading "):
            name, file = body, body[len("loading "):]
            loaded.add(file)
            reason = "loader"
        else:
            description = DESCRIPTION.match(body)
            name = description["name"] if description else body
            file = description["file"] if description else None
            reason = _hidden_reason(name)
        observations.append({
            "name": name, "raw_file": file, "platform": runtime or context.get("platform"),
            "platform_source": "reporter" if runtime else "caller" if context.get("platform") else "unreported",
            "start_line": number, "result": result, "excluded_reason": reason,
        })
    unique = {}
    for row in observations:
        raw_file = row.pop("raw_file")
        if raw_file is None and len(loaded) == 1:
            raw_file = next(iter(loaded))
            row["file_source"] = "single_loader_path"
        else:
            row["file_source"] = "description" if raw_file else "unreported"
        row["file"] = _file(raw_file, context)
        if row["excluded_reason"]:
            report["excluded_events"].append(row)
            if row["result"] == "failed":
                _note(report["errors"], "A synthetic loader/setup/teardown event failed.", row["start_line"])
            continue
        row.pop("excluded_reason")
        key = (row["file"], row["name"], row["platform"])
        if key not in unique:
            row["observed_lines"] = [row["start_line"]]
            unique[key] = row
        else:
            saved = unique[key]
            saved["observed_lines"].append(row["start_line"])
            if row["result"] in {"failed", "incomplete"}:
                saved["result"] = row["result"]
    report["cases"] = list(unique.values())
    counts = report.get("terminal_counters")
    if counts:
        cases = report["cases"]
        known_failed = sum(row["result"] == "failed" for row in cases)
        hidden_failed = {
            (row.get("file"), row["name"], row.get("platform"))
            for row in report["excluded_events"] if row["result"] == "failed"
        }
        expected_visible = sum(counts.values()) - len(hidden_failed)
        if len(cases) != expected_visible:
            _note(report["ambiguities"], f"Final counters cover {expected_visible} visible cases but {len(cases)} distinct identities were recovered; concurrent omissions or duplicate names cannot be resolved.")
        elif known_failed + len(hidden_failed) != counts["failed"]:
            _note(report["ambiguities"], "Failure counters do not match explicit failing test identities.")
        elif counts["passed"] and counts["skipped"]:
            _note(report["ambiguities"], "Mixed passing/skipped expanded output does not reliably identify skipped cases; use JSON reporter evidence.")
        else:
            for row in cases:
                if row["result"] == "unknown":
                    row["result"] = "skipped" if counts["skipped"] else "passed"
                    row["result_source"] = "terminal_summary_and_exact_counter_reconciliation"
        if report["terminal_success"] and counts["failed"]:
            _note(report["errors"], "Success summary contradicts nonzero failure counter.")
    else:
        for row in report["cases"]:
            if row["result"] == "unknown":
                row["result"] = "incomplete"
    return _finish(report)


def extract_log(path, *, platform=None, repo_root=None, cwd=None, exit_code=None):
    """Return one immutable-log extraction; no files are written by this API."""
    path = Path(path)
    raw = path.read_bytes()
    context = {
        "platform": _platform(platform), "exit_code": exit_code,
        "repo_root": str(Path(repo_root).resolve()) if repo_root else None,
        "cwd": str(Path(cwd).resolve()) if cwd else None,
    }
    decoded = raw.decode("utf-8", errors="replace")
    lines = [(index, ANSI.sub("", line)) for index, line in enumerate(decoded.splitlines(), 1)]
    json_reporter = False
    for _, line in lines:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(event, dict) and event.get("type") in EVENT_TYPES:
            json_reporter = True
            break
    report = _parse_json(lines, context) if json_reporter else _parse_expanded(lines, context)
    if b"\r" in raw.replace(b"\r\n", b""):
        _note(report["ambiguities"], "Carriage-return updates may be compact reporter output; exact names are not guaranteed.")
        report = _finish(report)
    if "\ufffd" in decoded:
        _note(report["ambiguities"], "Invalid UTF-8 was replaced; exact test names may be damaged.")
        report = _finish(report)
    report["log"] = {"path": str(path.resolve()), "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw)}
    return report


def combine_reports(reports):
    """Deduplicate observations without replacing earlier failures with passes."""
    by_platform, logical = defaultdict(list), defaultdict(list)
    confirmed_platform, confirmed_logical = set(), set()
    for report_index, report in enumerate(reports):
        for case_index, row in enumerate(report["cases"]):
            key = (row.get("file"), row["name"], row.get("platform"))
            occurrence = {
                "report_index": report_index, "case_index": case_index,
                "result": row["result"], "run_status": report["status"],
                "usable_pass_evidence": report["usable_pass_evidence"] and row["result"] == "passed",
            }
            by_platform[key].append(occurrence)
            logical[key[:2]].append(occurrence)
            if occurrence["usable_pass_evidence"]:
                confirmed_platform.add(key)
                confirmed_logical.add(key[:2])

    def grouped(groups, include_platform):
        result = []
        for key, occurrences in sorted(groups.items(), key=lambda item: str(item[0])):
            outcomes = sorted({item["result"] for item in occurrences})
            row = {
                "file": key[0], "name": key[1], "occurrences": occurrences,
                "results": outcomes,
                "result": outcomes[0] if len(outcomes) == 1 else "mixed",
                "all_observations_confirmed_passes": all(item["usable_pass_evidence"] for item in occurrences),
            }
            if include_platform:
                row["platform"] = key[2]
            result.append(row)
        return result

    result = {
        "schema_version": 1,
        "scope": "Evidence extraction only; overlapping source revisions and final acceptance remain the caller's decision.",
        "all_runs_usable_pass_evidence": bool(reports) and all(report["usable_pass_evidence"] for report in reports),
        "counts": {
            "logs": len(reports),
            "run_statuses": dict(sorted(Counter(report["status"] for report in reports).items())),
            "case_occurrences": sum(len(report["cases"]) for report in reports),
            "distinct_file_name_platform": len(by_platform),
            "distinct_file_name": len(logical),
            "confirmed_pass_file_name_platform": len(confirmed_platform),
            "confirmed_pass_file_name": len(confirmed_logical),
        },
        "reports": reports,
        "deduplicated_by_platform": grouped(by_platform, True),
        "deduplicated_logical": grouped(logical, False),
    }
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("logs", nargs="+", type=Path)
    parser.add_argument("--platform", help="Fallback runner platform for logs that omit it; does not override JSON suite platform.")
    parser.add_argument("--repo-root", type=Path)
    parser.add_argument("--cwd", type=Path, help="Test process cwd, used only to resolve relative suite paths.")
    parser.add_argument("--exit-code", type=int, help="Explicit process exit code for every selected log; omit when unknown.")
    parser.add_argument("--output", type=Path, help="Write extracted JSON here; never choose an original log/receipt path.")
    parser.add_argument("--require-success", action="store_true", help="Return exit 2 unless all logs provide confirmed complete pass evidence.")
    args = parser.parse_args(argv)
    if args.output and args.output.resolve() in {path.resolve() for path in args.logs}:
        parser.error("Output must not overwrite an input log.")
    reports = [extract_log(path, platform=args.platform, repo_root=args.repo_root, cwd=args.cwd, exit_code=args.exit_code) for path in args.logs]
    result = combine_reports(reports)
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        if args.output.exists():
            parser.error("Output already exists; choose a new path to preserve existing evidence.")
        args.output.write_text(encoded)
        print(json.dumps({"output": str(args.output.resolve()), "counts": result["counts"], "all_runs_usable_pass_evidence": result["all_runs_usable_pass_evidence"]}, indent=2))
    else:
        sys.stdout.write(encoded)
    return 2 if args.require_success and not result["all_runs_usable_pass_evidence"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
