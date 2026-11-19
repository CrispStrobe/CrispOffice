"""Independently audit new local receipts without rerunning application tests."""

import argparse
import collections
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess


parser = argparse.ArgumentParser()
parser.add_argument("--repo", required=True, type=Path)
parser.add_argument("--head", required=True)
parser.add_argument("--publication-head")
parser.add_argument("--allow-store-readme-change", action="store_true")
parser.add_argument("--native", required=True, type=Path)
parser.add_argument("--store", type=Path)
parser.add_argument("--native-only", action="store_true")
parser.add_argument("--runtime", required=True, type=Path)
parser.add_argument("--store-before", type=Path)
parser.add_argument("--store-after", type=Path)
parser.add_argument("--store-wrapper", type=Path)
parser.add_argument("--store-driver-source", type=Path)
parser.add_argument("--output", required=True, type=Path)
args = parser.parse_args()
assert args.native_only or args.store, "Provide --store or request --native-only"
repo = args.repo.resolve()


def sha_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def load(path):
    return json.loads(Path(path).read_text())


def git(*command):
    return subprocess.check_output(["git", "-C", str(repo), *command])


head = git("rev-parse", args.head + "^{commit}").decode().strip()
entries = {}
for entry in git("ls-tree", "-rz", head).split(b"\0"):
    if not entry:
        continue
    meta, path = entry.split(b"\t", 1)
    mode, kind, oid = meta.decode().split()
    entries[path.decode()] = {"mode": mode, "git_blob": oid}
publication = None
publication_entries = None
documentation_changes = []
allowed_documentation_paths = {"packages/quds_mail_store/README.md"} if args.allow_store_readme_change else set()
assert not allowed_documentation_paths or args.publication_head, "A documentation exception requires an exact publication commit"
if args.publication_head:
    publication = git("rev-parse", args.publication_head + "^{commit}").decode().strip()
    publication_entries = {}
    for entry in git("ls-tree", "-rz", publication).split(b"\0"):
        if not entry:
            continue
        meta, path = entry.split(b"\t", 1)
        mode, kind, oid = meta.decode().split()
        publication_entries[path.decode()] = {"mode": mode, "git_blob": oid}
    product_prefixes = ("packages/", "apps/", "third_party/")
    assert {path: value for path, value in entries.items() if path.startswith(product_prefixes) and path not in allowed_documentation_paths} == {
        path: value for path, value in publication_entries.items() if path.startswith(product_prefixes) and path not in allowed_documentation_paths
    }, "Published product tree differs from the qualified product tree"
    for path in sorted(allowed_documentation_paths):
        assert path in entries and path in publication_entries
        assert entries[path]["mode"] == publication_entries[path]["mode"] == "100644"
        if entries[path] != publication_entries[path]:
            before = git("show", head + ":" + path)
            after = git("show", publication + ":" + path)
            before.decode("utf-8")
            after.decode("utf-8")
            documentation_changes.append({
                "path": path, "qualified_git_blob": entries[path]["git_blob"],
                "published_git_blob": publication_entries[path]["git_blob"],
                "qualified_sha256": sha_bytes(before), "published_sha256": sha_bytes(after),
                "full_diff": git("diff", "--no-ext-diff", "--no-color", head, publication, "--", path).decode(),
                "reason": "Explicitly reviewed package README reconciliation only; no executable, configuration, test-plan or runtime input exception is permitted.",
            })


def check_reporter(path, cwd, requested, platform):
    lines = path.read_text().splitlines()
    suites, tests, dones = {}, {}, {}
    start_count = 0
    terminals, all_suites = [], []
    warning_messages = []
    diagnostics = []
    stripped_hook_prefixes = 0
    for line_number, line in enumerate(lines, 1):
        text = line.strip()
        prefixes = ("Running build hooks...", "Running link hooks...")
        while text.startswith(prefixes):
            prefix = next(item for item in prefixes if text.startswith(item))
            text = text[len(prefix):].lstrip()
            stripped_hook_prefixes += 1
        if not text:
            continue
        event = json.loads(text)
        assert isinstance(event, dict) and isinstance(event.get("type"), str), (path, line_number)
        assert not terminals, (path, "event after terminal", line_number)
        kind = event["type"]
        if kind == "start":
            start_count += 1
            assert start_count == 1
        else:
            assert start_count == 1
        if kind == "suite":
            suite = event["suite"]
            assert type(suite["id"]) is int and suite["id"] not in suites
            suite_path = (cwd / suite["path"]).resolve().relative_to(repo).as_posix()
            assert suite.get("platform") == platform, (path, suite)
            suites[suite["id"]] = suite_path
        elif kind == "testStart":
            test = event["test"]
            assert type(test["id"]) is int and test["id"] not in tests
            assert type(test["suiteID"]) is int and isinstance(test["name"], str)
            tests[test["id"]] = test
        elif kind == "testDone":
            ident = event["testID"]
            assert type(ident) is int and ident in tests and ident not in dones
            assert type(event["hidden"]) is bool and type(event["skipped"]) is bool
            assert event["result"] == "success" and not event["skipped"], (path, event)
            dones[ident] = event
        elif kind == "allSuites":
            all_suites.append(event["count"])
        elif kind == "done":
            terminals.append(event["success"])
        elif kind == "error":
            raise AssertionError((path, event))
        elif kind == "print":
            message = str(event.get("message", ""))
            if re.search(r"warning", message, re.I):
                warning_messages.append({"test_id": event.get("testID"), "message": message})
            if re.search(r"A RenderFlex overflowed|RenderBox was not laid out|would not hit test|missed tap|The following assertion was thrown", message, re.I):
                diagnostics.append(message)
    assert start_count == 1 and terminals == [True]
    assert tests.keys() == dones.keys()
    assert all_suites == [len(suites)]
    expected = {(cwd / name).resolve().relative_to(repo).as_posix() for name in requested}
    assert set(suites.values()) == expected and len(suites) == len(expected), (path, expected, suites)
    assert not diagnostics, (path, diagnostics)
    cases = []
    excluded = 0
    per_suite = collections.Counter()
    for ident, completion in dones.items():
        test = tests[ident]
        assert test["suiteID"] in suites
        if completion["hidden"] or test["name"].startswith("loading ") or re.search(r"\((?:setUpAll|tearDownAll)\)$", test["name"]):
            excluded += 1
            continue
        suite = suites[test["suiteID"]]
        cases.append((suite, test["name"]))
        per_suite[suite] += 1
    assert len(cases) == len(set(cases))
    assert set(per_suite) == expected
    return {
        "suites": len(suites), "executions": len(cases), "failures": 0, "skips": 0,
        "errors": 0, "complete_starts_and_completions": True, "exact_suite_coverage": True,
        "terminal_success": True, "excluded_lifecycle_events": excluded,
        "known_native_hook_prefixes": stripped_hook_prefixes,
        "layout_or_tap_diagnostics": diagnostics, "warnings": warning_messages,
        "per_suite": dict(per_suite),
    }, cases


native = load(args.native / "verification.json")
store = None if args.native_only else load(args.store / "receipt.json")
assert native["source_commit"] == head
assert native["success"] is True
if store is not None:
    assert store["starting_commit"] == head and store["status"] == "PASS"
for key in ("source_unchanged", "environment_unchanged", "source_head_unchanged", "source_index_unchanged", "tracked_worktree_clean_before", "tracked_worktree_clean_after"):
    assert native[key] is True, key
assert not native.get("source_mismatches") and not native.get("environment_mismatches")
assert not native.get("unexpected_native_mappings_after")
assert native["github_actions_queried_or_awaited"] is False
if store is not None:
    assert store["source_unchanged"] is True and store["source_before"] == store["source_after"]
    assert store["direct_launcher_inputs_before"] == store["direct_launcher_inputs_after"]

sources = load(args.native / "source-before.json")
assert sources == load(args.native / "source-after.json")
assert len(sources) == native["source_input_count"]
for path, record in sources.items():
    assert all(entries[path][key] == record[key] for key in ("mode", "git_blob")), path
    documented_change = path in {item["path"] for item in documentation_changes}
    if publication_entries is not None and not documented_change:
        assert publication_entries[path] == entries[path], path
    assert record["materialized"] is True and record["sparse_omission"] is False, path
    candidate = repo / path
    assert not candidate.is_symlink(), path
    raw = candidate.read_bytes()
    if documented_change:
        assert sha_bytes(git("show", head + ":" + path)) == record["sha256"], path
        assert raw == git("show", publication + ":" + path), path
    else:
        assert sha_bytes(raw) == record["sha256"], path
    expected_blob = publication_entries[path]["git_blob"] if documented_change else record["git_blob"]
    assert hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest() == expected_blob, path
    assert ("100755" if candidate.stat().st_mode & 0o111 else "100644") == record["mode"], path
for path, digest in (store["source_before"].items() if store is not None else []):
    assert sha(repo / path) == digest, path
    assert sha_bytes(git("show", head + ":" + path)) == digest, path
    if publication_entries is not None:
        assert publication_entries[path] == entries[path], path
for path, digest in (store["direct_launcher_inputs_before"].items() if store is not None else []):
    candidate = Path(path)
    assert (sha(candidate) if candidate.is_file() else None) == digest, path

environment = load(args.native / "environment-before.json")
assert environment == load(args.native / "environment-after.json")
assert len(environment) == native["runtime_input_count"]
for name, digest in environment.items():
    if name.startswith("runtime/"):
        candidate = args.runtime / name[len("runtime/"):]
    elif name.startswith("additional/"):
        candidate = Path(name[len("additional/"):])
    elif name == "workspace/package_config.json":
        candidate = repo / ".dart_tool/package_config.json"
    elif name == "workspace/native_assets.yaml":
        candidate = repo / ".dart_tool/native_assets.yaml"
    elif name.startswith("workspace/"):
        candidate = repo / name[len("workspace/"):]
    elif name == "sdk/flutter_tools/package_config.json":
        candidate = args.runtime / "flutter/packages/flutter_tools/.dart_tool/package_config.json"
    else:
        raise AssertionError(("Unknown runtime mapping", name))
    assert (sha(candidate) if candidate.is_file() else None) == digest, name
for name, digest in native["manifest_sha256"].items():
    assert sha(args.native / name) == digest, name
assert sha(repo / native["plan"]) == native["plan_sha256"]
plan = load(repo / native["plan"])
assert plan["groups"] == native["planned_groups"]
for kind, field in (("analysis", "analysis_files"), ("format", "formatted_files")):
    if isinstance(plan.get(kind), list):
        assert native[field] == plan[kind]

store_interval = None
assert bool(args.store_before) == bool(args.store_after)
if args.store_before:
    assert store is not None
    store_before = load(args.store_before)
    store_after = load(args.store_after)
    assert store_before["source_commit"] == head == store_after["source_commit"]
    assert store_before["source_tree"] == store_after["source_tree"] == native["source_tree"]
    assert store_before["source_inputs"] == store_after["source_inputs"] == {
        path: record["sha256"] for path, record in sources.items()
    }
    assert store_before["runtime_inputs"] == store_after["runtime_inputs"] == environment
    assert store_before["runtime_paths"] == store_after["runtime_paths"]
    assert store_before["snapshot_script_sha256"] == store_after["snapshot_script_sha256"]
    assert datetime.fromisoformat(store_before["captured_at_utc"]) <= datetime.fromisoformat(store["started_utc"])
    assert datetime.fromisoformat(store["finished_utc"]) <= datetime.fromisoformat(store_after["captured_at_utc"])
    store_interval = {
        "source_inputs": len(store_before["source_inputs"]),
        "runtime_inputs": len(store_before["runtime_inputs"]),
        "before_after_equal_and_match_native": True,
        "timestamps_bound_store_execution": True,
        "before_sha256": sha(args.store_before),
        "after_sha256": sha(args.store_after),
    }
if args.store_wrapper:
    assert store is not None
    assert store_interval is None, "Select a single Store interval source"
    wrapper = args.store_wrapper
    driver = load(wrapper / "driver-receipt.json")
    assert driver["source_commit"] == head and driver["source_tree"] == native["source_tree"]
    assert driver["accepted"] is True and driver["exit_code"] == 0
    for key in ("source_unchanged", "runtime_unchanged", "head_unchanged", "tracked_worktree_clean"):
        assert driver[key] is True, key
    assert driver["github_actions_queried_or_awaited"] is False
    before_source = load(wrapper / "source-before.json")
    before_environment = load(wrapper / "environment-before.json")
    assert before_source == load(wrapper / "source-after.json") == {
        path: record["sha256"] for path, record in sources.items()
    }
    assert before_environment == load(wrapper / "environment-after.json") == environment
    assert driver["source_input_count"] == len(before_source)
    assert driver["runtime_input_count"] == len(before_environment)
    assert sha(wrapper / "store.log") == driver["log_sha256"]
    assert driver["command"][-2:] == ["--output", str(args.store.resolve())]
    assert datetime.fromisoformat(driver["started_at_utc"]) <= datetime.fromisoformat(store["started_utc"])
    assert datetime.fromisoformat(store["finished_utc"]) <= datetime.fromisoformat(driver["finished_at_utc"])
    driver_source = args.store_driver_source or repo.parent / "run_store_bound.py"
    assert sha(driver_source) == driver["driver_sha256"]
    store_interval = {
        "source_inputs": len(before_source),
        "runtime_inputs": len(before_environment),
        "before_after_equal_and_match_native": True,
        "timestamps_bound_store_execution": True,
        "driver_sha256": driver["driver_sha256"],
        "driver_receipt_sha256": sha(wrapper / "driver-receipt.json"),
        "snapshot_hashes": {
            name: sha(wrapper / name)
            for name in ("source-before.json", "source-after.json", "environment-before.json", "environment-after.json")
        },
    }

cohorts = []
identities = []
planned = {group["name"]: group for group in plan["groups"]}
expected_run_names = list(planned)
if native["analysis_files"]:
    expected_run_names.append("analysis")
if native["formatted_files"]:
    expected_run_names.append("format")
expected_run_names.append("whitespace")
assert [run["name"] for run in native["runs"]] == expected_run_names
for run in native["runs"]:
    assert run["exit_code"] == 0 and run["accepted"] is True
    raw = args.native / run["log"]
    assert sha(raw) == run["log_sha256"]
    compressed = args.native / run["compressed_log"]
    assert sha(compressed) == run["compressed_log_sha256"]
    assert gzip.decompress(compressed.read_bytes()) == raw.read_bytes()
    if run["name"] == "analysis":
        assert run["command"] == [str(args.runtime.resolve() / "bin/dart"), "analyze", "--fatal-infos", "--fatal-warnings", *native["analysis_files"]]
    elif run["name"] == "format":
        assert run["command"] == [str(args.runtime.resolve() / "bin/dart"), "format", "--output=none", "--set-exit-if-changed", *native["formatted_files"]]
    if run["name"] in planned:
        group = planned[run["name"]]
        assert run["cwd"] == group["cwd"]
        assert run["command"][-len(group["tests"]):] == group["tests"]
        checked, cases = check_reporter(raw, repo / group["cwd"], group["tests"], group.get("platform", "vm"))
        assert checked["executions"] == run["passed"]
        cohorts.append({"gate": "native", "name": run["name"], **checked})
        identities.extend(cases)
        for kind in ("cases", "errors"):
            assert sha(args.native / run[kind + "_file"]) == run[kind + "_sha256"]

store_order = ["runtime", "runner-regressions", "locked-resolution", "core-analysis", "store-analysis", "format", "core-vm", "core-node", "store-vm", "portable-node", "browser-entry", "browser-worker", "whitespace"]
if store is not None:
    assert [check["name"] for check in store["checks"]] == store_order
for check in (store["checks"] if store is not None else []):
    assert check["exit_code"] == 0 and check["status"] == "PASS"
    log = args.store / check["log"]
    assert sha(log) == check["log_sha256"]
    if not log.name.endswith(".jsonl"):
        continue
    cwd = Path(check["cwd"])
    requested = [part for part in check["command"] if part.endswith("_test.dart")]
    if not requested:
        root = cwd.relative_to(repo).as_posix() + "/"
        requested = sorted(path[len(root):] for path in entries if path.startswith(root + "test/") and path.endswith("_test.dart"))
    platform = check["command"][check["command"].index("--platform") + 1]
    checked, cases = check_reporter(log, cwd, requested, platform)
    assert checked["executions"] == check["tests"]["passed"]
    cohorts.append({"gate": "store", "name": check["name"], **checked})
    identities.extend(cases)

python_count = 0
if store is not None:
    python_log = (args.store / "runner-regressions.log").read_text()
    python_counts = re.findall(r"Ran (\d+) tests? in", python_log)
    assert len(python_counts) == 1 and re.search(r"\nOK\s*$", python_log)
    python_count = int(python_counts[0])
report = {
    "audited_at_utc": datetime.now(timezone.utc).isoformat(),
    "qualified_source": head,
    "qualified_tree": git("rev-parse", head + "^{tree}").decode().strip(),
    "publication_head": publication,
    "publication_product_and_bound_inputs_identical": publication is not None and not documentation_changes,
    "publication_continuity": {
        "checked": publication is not None,
        "accepted_with_reviewed_documentation_exception": bool(documentation_changes),
        "native_inputs_identical": len(sources) - len(documentation_changes) if publication else None,
        "native_inputs_changed": len(documentation_changes) if publication else None,
        "all_other_product_entries_and_bound_inputs_identical": publication is not None,
        "documentation_changes": documentation_changes,
    },
    "cohorts": cohorts,
    "application_executions": len(identities),
    "distinct_file_name_case_identities": len(set(identities)),
    "suite_platform_executions": sum(item["suites"] for item in cohorts),
    "distinct_test_files": len({path for path, _ in identities}),
    "fresh_store_python_controls": python_count,
    "native_source_inputs": len(sources),
    "native_runtime_records": len(environment),
    "native_strict_analysis_paths": len(native["analysis_files"]),
    "native_format_paths": len(native["formatted_files"]),
    "store_source_inputs": len(store["source_before"]) if store is not None else None,
    "store_direct_launcher_inputs": len(store["direct_launcher_inputs_before"]) if store is not None else None,
    "store_full_interval_binding": store_interval,
    "source_before_after_and_git_binding": True,
    "runtime_before_after_and_live_readback": True,
    "qualification_tests_rerun_by_auditor": False,
    "historical_results_added": False,
    "github_actions_queried": False,
    "receipt_hashes": {"native": sha(args.native / "verification.json"), "store": sha(args.store / "receipt.json") if store is not None else None},
    "audit_script_sha256": sha(Path(__file__)),
    "passed": True,
}
args.output.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({key: value for key, value in report.items() if key != "cohorts"}, indent=2))
