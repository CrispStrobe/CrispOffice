#!/usr/bin/env python3
"""Independently audit the current native/Node qualification without rerunning it.

Derived from the committed host-final independent auditor. This standalone
version removes its historical one-fixture/Mail/web assumptions, verifies both
stdout and separately preserved stderr, and checks the fresh fixture addendum.
Plans and the auditor must be committed in --head. Only new audit outputs are
written, outside the source checkout; no remote service or GitHub Actions calls.
"""

import argparse
import collections
import gzip
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from urllib.parse import unquote, urlparse


RUNNER = "docs/validation/document-review-notes-20261118/run_checks.py"
AUDITOR = "docs/validation/office-finish-20261119/audit_qualification.py"
MANIFESTS = {
    "source-before.json", "source-after.json",
    "environment-before.json", "environment-after.json",
}
HOOK_PREFIXES = ("Running build hooks...", "Running link hooks...")
DIAGNOSTICS = re.compile(
    r"A Render\w+ overflowed|RenderBox was not laid out|"
    r"would not hit test on the specified widget|does not receive pointer events|"
    r"EXCEPTION CAUGHT BY (?:RENDERING|WIDGETS|FLUTTER TEST) LIBRARY|"
    r"setState\(\) called after dispose\(\)",
    re.I,
)
STATIC_DIAGNOSTICS = re.compile(r"^\s*(?:error|warning|info)\s*[•-]", re.I | re.M)
LIFECYCLE_NAME = re.compile(r"(?:^| )\((?:setUpAll|tearDownAll)\)$")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def read_json(path):
    return json.loads(path.read_text())


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_hash(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def local_file(path, expected=None, size=None):
    require(path.is_file() and not path.is_symlink(), f"Missing/redirected file: {path}")
    if size is not None:
        require(path.stat().st_size == size, f"File size changed: {path}")
    actual = file_hash(path)
    if expected is not None:
        require(actual == expected, f"File digest changed: {path}")
    return actual


def safe_relative(name):
    require(isinstance(name, str) and bool(name), f"Invalid relative path: {name!r}")
    path = PurePosixPath(name)
    require(not path.is_absolute() and ".." not in path.parts and path.as_posix() == name,
            f"Noncanonical relative path: {name!r}")
    return name


def reporter_path(name, repo, cwd):
    require(isinstance(name, str), "Reporter path must be text")
    path = Path(name)
    if not path.is_absolute():
        path = repo / cwd / path
    return path.resolve().relative_to(repo).as_posix()


def audit_events(raw, repo, cwd, requested, label, platform="vm"):
    """Independent strict reconstruction, including hidden/lifecycle failures."""
    text = raw.decode("utf-8")
    events, hook_prefixes = [], 0
    for line_number, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        while line.startswith(HOOK_PREFIXES):
            prefix = next(p for p in HOOK_PREFIXES if line.startswith(p))
            line = line[len(prefix):].lstrip()
            hook_prefixes += 1
        if not line:
            continue
        try:
            event = json.loads(line)
        except (ValueError, TypeError) as error:
            raise AssertionError(f"Malformed reporter record: {label}:{line_number}") from error
        require(isinstance(event, dict) and isinstance(event.get("type"), str),
                f"Malformed reporter event: {label}:{line_number}")
        events.append(event)
    require(bool(events), f"Empty reporter: {label}")
    require(events[0]["type"] == "start" and events[-1]["type"] == "done",
            f"Missing start/terminal boundary: {label}")
    kinds = collections.Counter(event["type"] for event in events)
    require(kinds["start"] == kinds["done"] == 1,
            f"Duplicate/missing reporter boundary: {label}")
    require(events[-1].get("success") is True, f"Unsuccessful terminal event: {label}")
    require(kinds["allSuites"] == 1, f"Missing/duplicate suite-count event: {label}")
    allowed = {"start", "done", "allSuites", "suite", "group", "testStart", "testDone", "print"}
    require(set(kinds) <= allowed, f"Error or unknown reporter event: {label}: {set(kinds) - allowed}")
    suites, starts, completions, groups = {}, {}, {}, {}
    warnings, excluded, case_rows = [], 0, []
    for event in events:
        kind = event["type"]
        if kind == "allSuites":
            require(type(event.get("count")) is int and event["count"] == len(requested),
                    f"Reporter suite count differs from committed plan: {label}")
        elif kind == "suite":
            item = event["suite"]
            ident = item["id"]
            require(type(ident) is int and ident not in suites, f"Duplicate/invalid suite id: {label}")
            require(item.get("platform") == platform, f"Wrong reporter platform: {label}")
            suites[ident] = reporter_path(item["path"], repo, cwd)
        elif kind == "group":
            item = event["group"]
            ident = item["id"]
            require(type(ident) is int and ident not in groups, f"Duplicate/invalid group id: {label}")
            require(type(item["suiteID"]) is int and item["suiteID"] in suites,
                    f"Unknown group suite: {label}")
            require(item.get("metadata", {}).get("skip", False) is False, f"Skipped group: {label}")
            if item.get("parentID") is not None:
                require(item["parentID"] in groups, f"Unknown parent group: {label}")
            groups[ident] = item
        elif kind == "testStart":
            item = event["test"]
            ident = item["id"]
            require(type(ident) is int and ident not in starts, f"Duplicate/invalid test start: {label}")
            require(type(item["suiteID"]) is int and item["suiteID"] in suites,
                    f"Unknown test suite: {label}")
            require(isinstance(item["name"], str), f"Invalid test name: {label}")
            require(item.get("metadata", {}).get("skip", False) is False, f"Skipped test metadata: {label}")
            require(all(group in groups for group in item.get("groupIDs", [])),
                    f"Unknown test group: {label}")
            starts[ident] = item
        elif kind == "testDone":
            ident = event["testID"]
            require(type(ident) is int and ident in starts and ident not in completions,
                    f"Missing/duplicate completion: {label}")
            require(type(event.get("hidden")) is bool, f"Invalid hidden flag: {label}")
            require(event.get("skipped") is False and event.get("result") == "success",
                    f"Failed/skipped reporter case, including lifecycle: {label}: {starts[ident]['name']}")
            completions[ident] = event
        elif kind == "print":
            require(isinstance(event.get("message"), str), f"Invalid print event: {label}")
            require(type(event.get("testID")) is int and event["testID"] in starts,
                    f"Print event without a started test: {label}")
            require(not DIAGNOSTICS.search(event["message"]),
                    f"Widget/layout/tap/disposal diagnostic: {label}")
            if re.search(r"\bwarning\b|\bdeprecated\b", event["message"], re.I):
                warnings.append({"test_name": starts[event["testID"]]["name"], "message": event["message"]})
    require(set(starts) == set(completions), f"Unfinished test starts: {label}")
    require(len(set(suites.values())) == len(suites) and set(suites.values()) == set(requested),
            f"Exact suite coverage differs from committed plan: {label}")
    identities, per_suite = set(), collections.Counter()
    for ident, completion in completions.items():
        item = starts[ident]
        if completion["hidden"] or item["name"].startswith("loading ") or LIFECYCLE_NAME.search(item["name"]):
            excluded += 1
            continue
        identity = (suites[item["suiteID"]], item["name"])
        require(identity not in identities, f"Duplicate case identity: {label}: {identity}")
        identities.add(identity)
        per_suite[identity[0]] += 1
        case_rows.append({"suite": identity[0], "name": identity[1], "result": "success", "skipped": False})
    require(all(per_suite[path] for path in requested), f"Requested empty suite: {label}")
    return {
        "passed_executions": len(identities), "suites": len(suites),
        "failed": 0, "skipped": 0, "errors": 0, "incomplete": 0,
        "exact_suite_coverage": True, "terminal_success": True,
        "complete_starts_and_completions": True, "duplicate_case_identities": 0,
        "layout_tap_and_disposal_diagnostics": 0,
        "excluded_successful_lifecycle_events": excluded,
        "known_native_hook_prefixes": hook_prefixes,
        "per_suite": dict(sorted(per_suite.items())), "warnings": warnings,
    }, identities, case_rows


class Audit:
    def __init__(self, args):
        self.args = args
        self.repo = args.repo.resolve()
        if args.runtime is None:
            first = read_json(args.native.resolve() / "verification.json")["runs"][0]["command"][0]
            executable = Path(first)
            require(executable.is_absolute() and executable.parent.name == "bin", "Cannot infer runtime root")
            args.runtime = executable.parent.parent
        self.runtime = args.runtime.resolve()
        self.source = self.git("rev-parse", "--verify", args.head + "^{commit}").decode().strip()
        self.tree_id = self.git("rev-parse", self.source + "^{tree}").decode().strip()
        self.tracked = self.tree(self.source)
        self.runtime_receipt = read_json(self.runtime / "runtime.json")
        self.retained = read_json(self.runtime / "retained-inputs.json")
        self.records = collections.defaultdict(list)
        self.cohorts = []
        self.diagnostics = []
        self.runtime_symlinks = []

    def git(self, *argv, data=None):
        env = {**os.environ, "GIT_OPTIONAL_LOCKS": "0"}
        return subprocess.check_output(["git", "-C", str(self.repo), *argv], input=data, env=env)

    def tree(self, source):
        rows = {}
        for entry in self.git("ls-tree", "-rz", "--full-tree", source).split(b"\0"):
            if not entry:
                continue
            metadata, name = entry.split(b"\t", 1)
            mode, kind, blob = metadata.decode().split()
            rows[name.decode()] = {"mode": mode, "kind": kind, "git_blob": blob}
        return rows

    def state(self):
        return {
            "head": self.git("rev-parse", "HEAD").decode().strip(),
            "index_sha256": digest(self.git("ls-files", "--stage", "-z")),
            "tracked_status": self.git("status", "--porcelain=v1", "--untracked-files=no").decode(),
        }

    def verify_sources(self, values):
        paths = sorted(values)
        for offset in range(0, len(paths), 96):
            selected = paths[offset:offset + 96]
            for path in selected:
                safe_relative(path)
                require(path in self.tracked and self.tracked[path]["kind"] == "blob",
                        f"Untracked/nonblob input: {path}")
            blobs = [self.tracked[path]["git_blob"] for path in selected]
            raw = self.git("cat-file", "--batch", data=("\n".join(blobs) + "\n").encode())
            cursor = 0
            for path, blob in zip(selected, blobs):
                end = raw.index(b"\n", cursor)
                actual, kind, length = raw[cursor:end].decode().split()
                length = int(length)
                cursor = end + 1
                content = raw[cursor:cursor + length]
                cursor += length + 1
                row = values[path]
                require(kind == "blob" and actual == blob, f"Git object mismatch: {path}")
                require(row["materialized"] is True and row["sparse_omission"] is False,
                        f"Omitted source input: {path}")
                require(row["mode"] == self.tracked[path]["mode"] and row["git_blob"] == blob,
                        f"Source metadata differs from frozen tree: {path}")
                require(digest(content) == row["sha256"], f"Frozen Git digest differs: {path}")
                local_file(self.repo / path, row["sha256"], length)
                mode = "100755" if (self.repo / path).stat().st_mode & 0o111 else "100644"
                require(mode == row["mode"], f"Materialized executable mode differs: {path}")
        return len(paths)

    def selected_paths(self, receipt, plan):
        base = receipt["source_base"]
        changed = [path for path in self.git(
            "diff", "--name-only", "--diff-filter=ACMRT", "-z", base, self.source
        ).decode().split("\0") if path.endswith(".dart") and path.startswith(("packages/", "apps/"))]
        static = {}
        for key in ("analysis", "format"):
            value = plan.get(key, "changed")
            value = changed if value == "changed" else value
            require(isinstance(value, list) and len(value) == len(set(value)), f"Invalid {key} paths")
            require(all(isinstance(path, str) and path in self.tracked for path in value),
                    f"Unknown {key} inputs")
            static[key] = value
        requested, group_names = [], set()
        require(isinstance(plan["groups"], list) and bool(plan["groups"]), "Empty/invalid plan")
        for group in plan["groups"]:
            require(re.fullmatch(r"[a-z0-9_-]+", group["name"]) and group["name"] not in group_names,
                    "Duplicate/unsafe group name")
            group_names.add(group["name"])
            safe_relative(group["cwd"])
            require(group["runner"] in {"dart", "flutter"}, "Unknown runner")
            require(group.get("platform", "vm") in {"vm", "node"}, "Unknown platform")
            require(group["runner"] != "flutter" or group.get("platform", "vm") == "vm", "Flutter non-VM plan")
            require(bool(group["tests"]), "Empty suite list")
            for suite in group["tests"]:
                safe_relative(suite)
                path = str(PurePosixPath(group["cwd"]) / suite)
                require(path in self.tracked and path.endswith("_test.dart"), f"Unknown test suite: {path}")
                requested.append(path)
        require(len(requested) == len(set(requested)), "Duplicate suite selection inside one plan")
        selected = {path for path in self.tracked if path.startswith(("packages/", "apps/", "third_party/"))}
        selected.update(path for path in self.tracked if "/" not in path and Path(path).suffix in {".yaml", ".lock"})
        selected.update([receipt["plan"], RUNNER, "tools/mail/check_store.py", "tools/mail/check_reader.py"])
        selected.update(requested)
        selected.update(static["analysis"])
        selected.update(static["format"])
        extra = plan.get("extra_inputs", [])
        require(isinstance(extra, list) and len(extra) == len(set(extra)), "Invalid duplicate extra inputs")
        require(AUDITOR in extra, "This independent auditor must be bound in both frozen plans")
        selected.update(extra)
        preserved = plan.get("whitespace_preserved_inputs", [])
        require(receipt["whitespace_preserved_inputs"] == preserved, "Whitespace exceptions differ")
        preserved_names = set()
        for entry in preserved:
            path = safe_relative(entry["path"])
            require(path.startswith("docs/validation/") and path not in preserved_names,
                    "Unsafe/duplicate whitespace exception")
            require(entry["git_blob"] == self.tracked[path]["git_blob"] and bool(entry["reason"].strip()),
                    "Unbound whitespace exception")
            preserved_names.add(path)
        selected.update(preserved_names)
        return selected, static, requested

    def expected_environment(self, groups):
        paths = {"runtime/" + name: self.runtime / safe_relative(name) for name in self.retained}
        paths.update({
            "workspace/pubspec.lock": self.repo / "pubspec.lock",
            "workspace/package_config.json": self.repo / ".dart_tool/package_config.json",
            "sdk/flutter_tools/package_config.json": self.runtime / "flutter/packages/flutter_tools/.dart_tool/package_config.json",
        })
        for name in ("runtime.json", "retained-inputs.json", "pub-cache-receipt.json", "cache-omissions.json",
                     "archive-members.json", "env.sh", "bin/dart", "bin/flutter"):
            paths["runtime/" + name] = self.runtime / name
        for name in self.runtime_receipt.get("additional_inputs", {}):
            require(Path(name).is_absolute(), f"Additional runtime input is not absolute: {name}")
            paths["additional/" + name] = Path(name)
        optional = {"workspace/native_assets.yaml": self.repo / ".dart_tool/native_assets.yaml"}
        for group in groups:
            directory = self.repo / group["cwd"]
            while directory != self.repo:
                require(self.repo in directory.parents, f"Runtime mapping path escaped repo: {directory}")
                candidate = directory / ".dart_tool/native_assets.yaml"
                optional["workspace/" + candidate.relative_to(self.repo).as_posix()] = candidate
                directory = directory.parent
        paths.update(optional)
        return paths, optional

    def phase(self, name, directory):
        receipt_path = directory / "verification.json"
        receipt = read_json(receipt_path)
        require(receipt["success"] is True and not receipt.get("runner_error"), f"Unaccepted {name} receipt")
        require(receipt["source_commit"] == self.source and receipt["source_tree"] == self.tree_id,
                f"Wrong frozen source: {name}")
        for key in ("source_unchanged", "environment_unchanged", "source_head_unchanged", "source_index_unchanged",
                    "tracked_worktree_clean_before", "tracked_worktree_clean_after"):
            require(receipt[key] is True, f"Unstable {name} boundary: {key}")
        for key in ("source_mismatches", "environment_mismatches", "unexpected_native_mappings_after", "sparse_source_omissions"):
            require(receipt[key] == [], f"Unexpected {name} input changes: {key}")
        require(receipt["github_actions_queried_or_awaited"] is False, f"Unexpected CI evidence: {name}")
        require(set(receipt["manifest_sha256"]) == MANIFESTS, f"Missing/extra manifests: {name}")
        for filename, expected in receipt["manifest_sha256"].items():
            local_file(directory / filename, expected)
        sources = read_json(directory / "source-before.json")
        environment = read_json(directory / "environment-before.json")
        require(sources == read_json(directory / "source-after.json"), f"Source changed during {name}")
        require(environment == read_json(directory / "environment-after.json"), f"Runtime changed during {name}")
        require(len(sources) == receipt["source_input_count"] == receipt["materialized_source_inputs"],
                f"Wrong source inventory count: {name}")
        require(len(environment) == receipt["runtime_input_count"], f"Wrong runtime count: {name}")
        plan_raw = self.git("show", self.source + ":" + safe_relative(receipt["plan"]))
        require(digest(plan_raw) == receipt["plan_sha256"], f"Plan not bound to frozen commit: {name}")
        plan = json.loads(plan_raw)
        require(plan["groups"] == receipt["planned_groups"], f"Planned groups changed: {name}")
        selected, static, requested = self.selected_paths(receipt, plan)
        require(set(sources) == selected, f"Incomplete full source selection: {name}: missing={selected-set(sources)}, extra={set(sources)-selected}")
        require(receipt["analysis_files"] == static["analysis"] and receipt["formatted_files"] == static["format"],
                f"Static lists changed: {name}")
        env_paths, optional = self.expected_environment(plan["groups"])
        require(set(environment) == set(env_paths), f"Incomplete runtime selection: {name}: missing={set(env_paths)-set(environment)}, extra={set(environment)-set(env_paths)}")
        for key, value in environment.items():
            if value is None:
                require(key in optional and not env_paths[key].exists() and not env_paths[key].is_symlink(),
                        f"Missing required/shadowed runtime input: {name}: {key}")
            else:
                require(re.fullmatch(r"[a-f0-9]{64}", value), f"Malformed runtime hash: {key}")
            if key in optional and key != "workspace/native_assets.yaml":
                require(value is None, f"Shadowing native-assets mapping: {name}: {key}")
        for path, record in self.retained.items():
            require(environment["runtime/" + path] == record["sha256"], f"Retained runtime mismatch: {name}: {path}")
        require(receipt["additional_runtime_inputs"] == self.runtime_receipt["additional_inputs"],
                f"Additional runtime receipt changed: {name}")
        for path, expected in receipt["additional_runtime_inputs"].items():
            require(environment["additional/" + path] == expected, f"Unbound additional runtime input: {path}")
        require(receipt["runtime_receipt_sha256"] == file_hash(self.runtime / "runtime.json"),
                f"Runtime receipt changed since {name}")
        require(receipt["workspace_lock_sha256"] == self.runtime_receipt["workspace_lock_sha256"] == file_hash(self.repo / "pubspec.lock"),
                f"Dependency lock changed: {name}")
        require(receipt["runtime"] == self.runtime_receipt["runtime"], f"Runtime version data changed: {name}")
        require(receipt["package_config"] == str(self.repo / ".dart_tool/package_config.json"), f"Unexpected package config: {name}")
        expected_runs = [group["name"] for group in plan["groups"]]
        expected_runs += [key for key in ("analysis", "format") if static[key]] + ["whitespace"]
        require([run["name"] for run in receipt["runs"]] == expected_runs, f"Incomplete/extra runs: {name}")
        groups = {group["name"]: group for group in plan["groups"]}
        phase_cases = set()
        observed = 0
        for run in receipt["runs"]:
            label = name + "/" + run["name"]
            require(run["accepted"] is True and run["exit_code"] == 0 and not run.get("runner_error") and not run.get("timed_out"),
                    f"Unaccepted run: {label}")
            log = directory / safe_relative(run["log"])
            local_file(log, run["log_sha256"])
            compressed = directory / safe_relative(run["compressed_log"])
            local_file(compressed, run["compressed_log_sha256"])
            raw = log.read_bytes()
            require(gzip.decompress(compressed.read_bytes()) == raw, f"Compressed log differs: {label}")
            if run["name"] in groups:
                group = groups[run["name"]]
                suites = [str(PurePosixPath(group["cwd"]) / path) for path in group["tests"]]
                if group["runner"] == "flutter":
                    command = [str(self.runtime / "bin/flutter"), "test", "--no-pub"]
                else:
                    command = [str(self.runtime / "bin/dart"), "--disable-dart-dev", "--packages=" + receipt["package_config"],
                               receipt["test_launcher"], "--platform=node" if group.get("platform", "vm") == "node" else "--compiler=kernel"]
                command += ["--concurrency=1", "--reporter=json", *group["tests"]]
                require(run["command"] == command and run["cwd"] == group["cwd"], f"Test command differs: {label}")
                stderr = directory / safe_relative(run["stderr_log"])
                stderr_gzip = directory / safe_relative(run["stderr_compressed_log"])
                local_file(stderr, run["stderr_log_sha256"])
                local_file(stderr_gzip, run["stderr_compressed_log_sha256"])
                stderr_raw = stderr.read_bytes()
                require(gzip.decompress(stderr_gzip.read_bytes()) == stderr_raw,
                        f"Compressed stderr differs: {label}")
                diagnostic = {
                    "label": label, "file": str(stderr), "bytes": len(stderr_raw),
                    "sha256": digest(stderr_raw), "text": stderr_raw.decode("utf-8"),
                    "policy": "Test stderr must be empty; no broad diagnostic allowlist.",
                }
                self.diagnostics.append(diagnostic)
                require(not stderr_raw, f"Unreviewed test stderr: {label}: {diagnostic['text'][:1500]}")
                result, identities, case_rows = audit_events(
                    raw, self.repo, group["cwd"], suites, label, group.get("platform", "vm"))
                require(result["passed_executions"] == run["passed"] and run["failed"] == run["skipped"] == 0,
                        f"Raw counts disagree with receipt: {label}")
                require(run["reporter_success"] is True and run["runner_start_events"] == run["terminal_events"] == 1,
                        f"Receipt reporter boundary rejected: {label}")
                for key in ("missing_requested_suites", "unexpected_suites", "empty_requested_suites", "unfinished_reporter_events", "protocol_anomalies"):
                    require(run[key] == [], f"Receipt anomalies: {label}: {key}")
                require(run["reporter_error_count"] == 0 and run["strict_event_accounting"]["valid"] is True,
                        f"Receipt strict accounting rejected: {label}")
                cases_path = directory / safe_relative(run["cases_file"])
                errors_path = directory / safe_relative(run["errors_file"])
                local_file(cases_path, run["cases_sha256"])
                local_file(errors_path, run["errors_sha256"])
                saved_cases = read_json(cases_path)
                require(read_json(errors_path) == [], f"Saved reporter errors: {label}")
                saved_rows = [{"suite": reporter_path(row["suite"], self.repo, group["cwd"]), "name": row["name"],
                               "result": row["result"], "skipped": row["skipped"]} for row in saved_cases]
                order = lambda row: (row["suite"], row["name"])
                require(sorted(saved_rows, key=order) == sorted(case_rows, key=order), f"Saved case inventory differs: {label}")
                require(not phase_cases.intersection(identities), f"Duplicate case identities across groups: {name}")
                phase_cases.update(identities)
                observed += len(identities)
                platform = group.get("platform", "vm")
                for identity in identities:
                    self.records[identity].append({"phase": name, "group": group["name"], "platform": platform, "runner": group["runner"]})
                self.cohorts.append({"phase": name, "name": group["name"], "runner": group["runner"], "platform": platform, **result})
            else:
                require(run["cwd"] == ".", f"Wrong static cwd: {label}")
                if run["name"] == "analysis":
                    command = [str(self.runtime / "bin/dart"), "analyze", "--fatal-infos", "--fatal-warnings", *static["analysis"]]
                    require(not STATIC_DIAGNOSTICS.search(raw.decode()), f"Strict analysis diagnostic: {label}")
                    require("No issues found!" in raw.decode(), f"Missing successful analyzer result: {label}")
                elif run["name"] == "format":
                    command = [str(self.runtime / "bin/dart"), "format", "--output=none", "--set-exit-if-changed", *static["format"]]
                    formatted = re.findall(r"Formatted (\d+) files? \((\d+) changed\)", raw.decode())
                    require(formatted == [(str(len(static["format"])), "0")], f"Unexpected formatter result: {label}")
                else:
                    require(raw == b"", f"Whitespace diagnostic: {label}")
                    command = ["git", "diff", "--check", receipt["source_base"], self.source, "--", ".",
                               *[":(exclude)" + item["path"] for item in plan.get("whitespace_preserved_inputs", [])]]
                require(run["command"] == command, f"Static command differs from committed plan: {label}")
        require(observed == receipt["passed"] and receipt["failed"] == receipt["skipped"] == 0,
                f"Phase total differs from raw events: {name}")
        return {"name": name, "directory": str(directory), "receipt": receipt, "receipt_sha256": file_hash(receipt_path),
                "plan": plan, "sources": sources, "environment": environment, "environment_paths": env_paths,
                "cases": phase_cases, "executions": observed, "suites": requested, "static": static}

    def runtime_file(self, path, expected, size=None):
        if path.is_symlink():
            target = path.resolve(strict=True)
            extra = self.runtime_receipt.get("additional_inputs", {})
            try:
                relative = target.relative_to(self.runtime).as_posix()
            except ValueError:
                relative = None
            declared = extra.get(str(target))
            if declared is None and relative in self.retained:
                declared = self.retained[relative]["sha256"]
            require(declared == expected, f"Unbound runtime symlink destination: {path}")
            local_file(target, expected, size)
            row = {"path": str(path), "target": str(target), "sha256": expected}
            if row not in self.runtime_symlinks:
                self.runtime_symlinks.append(row)
            return expected
        return local_file(path, expected, size)

    def fixture_binding(self, phases):
        binding = self.runtime_receipt["fixture_input_binding"]
        extra = self.runtime_receipt["additional_inputs"]
        original_path = Path(binding["original_restore_receipt"])
        local_file(original_path, binding["original_restore_sha256"])
        require(extra[str(original_path)] == binding["original_restore_sha256"], "Original restore receipt unbound")
        original = read_json(original_path)
        require(set(self.runtime_receipt) == set(original) | {"fixture_input_binding"}, "Unexpected runtime receipt shape change")
        for key, value in original.items():
            if key == "additional_inputs":
                require(all(extra.get(path) == expected for path, expected in value.items()),
                        "Original native/Node bindings changed")
            else:
                require(self.runtime_receipt[key] == value, f"Original restore provenance changed: {key}")
        addendum_path = Path(binding["addendum"])
        local_file(addendum_path, binding["addendum_sha256"])
        require(extra[str(addendum_path)] == binding["addendum_sha256"], "Fixture addendum not bound")
        addendum = read_json(addendum_path)
        require(addendum["original_restore_sha256"] == binding["original_restore_sha256"], "Original receipt identity differs")
        for name, expected in addendum["fixture_inputs"].items():
            require(extra.get(name) == expected, f"Fixture source/build/provenance omitted: {name}")
            self.runtime_file(Path(name), expected)
        require(set(extra) - set(original["additional_inputs"])
                == set(addendum["fixture_inputs"]) | {str(addendum_path)}, "Extra fixture runtime membership differs")
        require(binding["added_inputs"] == len(addendum["fixture_inputs"]) + 1, "Fixture binding count differs")
        environment_path = Path(addendum["environment_receipt"])
        local_file(environment_path, extra[str(environment_path)])
        environment = read_json(environment_path)
        script = Path(environment["script"])
        local_file(script, environment["script_sha256"])
        require(extra[str(script)] == environment["script_sha256"], "Fixture environment script not bound")
        declared = {}
        for line in script.read_text().splitlines():
            require(line.startswith("export "), "Unexpected fixture environment script command")
            key, value = line[7:].split("=", 1)
            require(re.fullmatch(r"QUDS_[A-Z0-9_]+", key), "Unexpected environment variable")
            require(key not in declared, "Duplicate environment variable")
            words = shlex.split(value)
            require(len(words) == 1, "Ambiguous environment value")
            declared[key] = words[0]
        require(declared == environment["environment"] == binding["environment"], "Literal fixture environment differs")
        for key, value in declared.items():
            if key.endswith("LIVE_DOWNLOAD"):
                require(value == "1", f"Live download qualification flag not enabled: {key}")
            else:
                path = Path(value)
                require(path.is_absolute() and path.exists(), f"Missing declared fixture: {key}")
                if path.is_file():
                    require(str(path) in extra, f"Fixture library outside runtime binding: {key}")
                else:
                    contents = {str(item) for item in path.rglob("*") if item.is_file()}
                    require(contents and contents <= set(extra), f"Fixture directory not fully bound: {key}")
        for phase in phases:
            require(phase["receipt"]["additional_runtime_inputs"] == extra, "Fixture phase inputs differ")
        return {"original_restore_receipt": str(original_path), "original_restore_sha256": binding["original_restore_sha256"],
                "addendum": str(addendum_path), "addendum_sha256": binding["addendum_sha256"],
                "additional_inputs": len(extra), "new_fixture_bindings": binding["added_inputs"],
                "declared_environment": declared, "environment_script_sha256": environment["script_sha256"],
                "scope": "Original restore provenance is unchanged. All declared fixture files, build sources, receipts, tools and environment declaration match both phase boundaries and current bytes. Per-process environment forwarding is recorded separately by the outer launcher."}

    def run(self):
        initial_state = self.state()
        require(self.source in self.git("rev-list", initial_state["head"]).decode().splitlines(),
                "Live HEAD does not retain the frozen source by ancestry")
        require(not initial_state["tracked_status"], "Audit requires a clean tracked checkout")
        live_tree = self.tree(initial_state["head"])
        product_prefixes = ("packages/", "apps/", "third_party/")
        require({name for name in live_tree if name.startswith(product_prefixes)}
                == {name for name in self.tracked if name.startswith(product_prefixes)},
                "Live checkout adds/removes product paths outside the frozen source inventory")
        untracked = self.git("ls-files", "--others", "--exclude-standard", "-z").decode().split("\0")
        require(not any(name.startswith(product_prefixes) for name in untracked),
                "Untracked product inputs are present during live readback")
        native = self.phase("NATIVE", self.args.native.resolve())
        node = self.phase("NODE", self.args.node.resolve())
        phases = (native, node)
        require(native["receipt"]["source_base"] == node["receipt"]["source_base"], "Phase base commits differ")
        source_union, environment_union, env_paths = {}, {}, {}
        for phase in phases:
            for name, value in phase["sources"].items():
                require(name not in source_union or source_union[name] == value, f"Phase source mismatch: {name}")
                source_union[name] = value
            for name, value in phase["environment"].items():
                require(name not in environment_union or environment_union[name] == value, f"Phase runtime mismatch: {name}")
                environment_union[name] = value
            env_paths.update(phase["environment_paths"])
        source_count = self.verify_sources(source_union)
        for name, expected in environment_union.items():
            target = env_paths[name]
            if expected is None:
                require(not target.exists() and not target.is_symlink(), f"Unexpected optional runtime input: {name}")
            else:
                self.runtime_file(target, expected)
        require(len(self.retained) == self.runtime_receipt["retained_runtime_input_count"],
                "Retained runtime inventory count changed")
        for name, record in self.retained.items():
            self.runtime_file(self.runtime / name, record["sha256"], record["bytes"])
        require(self.runtime_receipt["status"] == "ready" and self.runtime_receipt["archive"]["verified"] is True, "Restore provenance not ready/verified")
        for recorded, expected in self.runtime_receipt["executables_sha256"].items():
            target = self.runtime / "flutter" / Path(recorded).relative_to(Path(self.runtime_receipt["sdk"]))
            local_file(target, expected)
        archives = read_json(self.runtime / "pub-cache-receipt.json")
        require(bool(archives) and all(row["verified"] is True for row in archives), "Unverified hosted archive in restore receipt")
        require(len(archives) == self.runtime_receipt["hosted_archives_verified"], "Hosted archive receipt count differs")
        package_config = self.repo / ".dart_tool/package_config.json"
        packages = read_json(package_config)["packages"]
        tests = [package for package in packages if package["name"] == "test"]
        require(len(tests) == 1, "Ambiguous package:test mapping")
        parsed = urlparse(tests[0]["rootUri"])
        require(parsed.scheme in {"", "file"} and not parsed.netloc and not parsed.query and not parsed.fragment, "Nonlocal test launcher mapping")
        package_root = (Path(unquote(parsed.path)) if parsed.scheme else package_config.parent / unquote(parsed.path)).resolve()
        launcher = package_root / "bin/test.dart"
        require(all(phase["receipt"]["test_launcher"] == str(launcher) for phase in phases), "Launcher mapping differs from receipts")
        versions = {row["version"] for row in archives if row["name"] == "test" and row["verified"] is True}
        require(package_root.parent == self.runtime / "pub-cache/hosted/pub.dev" and package_root.name in {"test-" + value for value in versions}, "Launcher outside verified hosted package")
        require(self.retained[launcher.relative_to(self.runtime).as_posix()]["sha256"] == file_hash(launcher), "Launcher not retained/bound")
        fixtures = self.fixture_binding(phases)
        source_identities = {key for key in self.records}
        total_executions = sum(len(value) for value in self.records.values())
        require(total_executions == native["executions"] + node["executions"], "Current execution aggregation mismatch")
        suite_counts = {suite: {"distinct_cases": sum(1 for path, _ in self.records if path == suite),
                                "executions": sum(len(value) for (path, _), value in self.records.items() if path == suite)}
                        for suite in sorted({path for path, _ in self.records})}
        repeats = []
        for suite in sorted(set(native["suites"]) & set(node["suites"])):
            vm_cases = {key for key in native["cases"] if key[0] == suite}
            node_cases = {key for key in node["cases"] if key[0] == suite}
            require(vm_cases == node_cases, f"Shared NATIVE/NODE suite case identities differ: {suite}")
            repeats.append({"suite": suite, "native_cases": len(vm_cases), "node_cases": len(node_cases), "same_case_identities": True})
        final_state = self.state()
        require(initial_state == final_state, "Checkout HEAD/index/status changed during audit")
        casefile = self.args.output.with_name(self.args.output.stem + "-cases.json")
        require(not casefile.exists(), f"Refusing to overwrite case evidence: {casefile}")
        rows = [{"suite": suite, "name": name, "executions": executions} for (suite, name), executions in sorted(self.records.items())]
        casefile.write_text(json.dumps(rows, indent=2) + "\n")
        return {
            "accepted": True, "audited_at_utc": datetime.now(timezone.utc).isoformat(),
            "qualified_source": self.source, "qualified_tree": self.tree_id,
            "audit_method": "Read-only Git/blob/live-file verification and independent raw reporter reconstruction; no test or build re-execution, remote refresh, or GitHub Actions access.",
            "counts": {
                "native_executions": native["executions"], "native_distinct_scenarios": len(native["cases"]),
                "node_executions": node["executions"], "node_distinct_scenarios": len(node["cases"]),
                "total_current_executions": total_executions, "total_current_distinct_scenarios": len(source_identities),
                "repeated_current_executions": total_executions - len(source_identities),
                "distinct_current_suites": len(suite_counts),
                "suite_platform_executions": len(native["suites"]) + len(node["suites"]),
                "failed": 0, "skipped": 0, "errors": 0, "incomplete": 0,
                "historical_test_counts_added": False, "forecast_used": False,
            },
            "phases": [{"name": phase["name"], "directory": phase["directory"], "receipt_sha256": phase["receipt_sha256"],
                        "plan": phase["receipt"]["plan"], "plan_sha256": phase["receipt"]["plan_sha256"],
                        "suites": phase["suites"], "executions": phase["executions"],
                        "analysis_paths": phase["static"]["analysis"], "format_paths": phase["static"]["format"],
                        "source_input_records": len(phase["sources"]), "runtime_input_records": len(phase["environment"])} for phase in phases],
            "cohorts": self.cohorts, "suite_counts": suite_counts, "platform_repeats": repeats,
            "source_binding": {"all_phase_before_after_manifests_identical": True, "full_source_selection_reconstructed_from_frozen_plans": True,
                               "git_modes_blobs_sha256_and_live_bytes_verified": True, "union_source_records": source_count,
                               "native_node_source_manifests_identical": native["sources"] == node["sources"],
                               "checkout_unchanged_during_readonly_audit": True, "checkout_head_during_audit": initial_state["head"]},
            "runtime_binding": {"all_phase_before_after_manifests_identical": True, "complete_runtime_selection_reconstructed": True,
                                "all_recorded_values_match_live_readback": True, "union_runtime_records": len(environment_union),
                                "retained_restore_files_sha256_and_size_verified_live": len(self.retained),
                                "official_sdk_archive_verified_in_original_restore_receipt": True,
                                "verified_hosted_archives_in_original_restore_receipt": len(archives),
                                "package_test_launcher_bound_to_verified_hosted_package": True,
                                "dependency_lock_unchanged": True,
                                "scope": "Both saved host phases captured their complete declared runtime inputs before/after their own intervals. Live readback verifies all those values and all retained restore files; the original download is not repeated."},
            "fixture_binding": fixtures, "runtime_symlinks": self.runtime_symlinks, "stderr_diagnostics": self.diagnostics,
            "validation": {"strict_analysis_format_whitespace_commands_match_committed_plans": True,
                           "all_raw_compressed_stdout_stderr_case_error_and_manifest_hashes_verified": True,
                           "compressed_logs_match_raw_bytes": True, "exact_nonempty_suite_coverage": True,
                           "layout_tap_and_disposal_diagnostics": 0,
                           "all_test_stderr_empty": True,
                           "actual_browser_execution": False,
                           "scope": "This audit covers only the native/Node phases and their declared runtime fixtures. Separate outer-driver Python controls/browser compilation and historical runs are not added to these totals."},
            "case_inventory": {"file": casefile.name, "sha256": file_hash(casefile)},
            "auditor": {"file": str(Path(__file__).resolve()), "sha256": file_hash(Path(__file__))},
            "github_actions": "NOT QUERIED OR AWAITED",
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--node", type=Path, required=True)
    parser.add_argument("--runtime", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output = args.output.resolve()
    require(args.repo.resolve() not in args.output.parents,
            "Audit output must be outside the source checkout")
    require(not args.output.exists(), f"Refusing to overwrite audit evidence: {args.output}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    audit = None
    try:
        audit = Audit(args)
        result = audit.run()
    except Exception as error:
        result = {
            "accepted": False,
            "audited_at_utc": datetime.now(timezone.utc).isoformat(),
            "requested_source": args.head,
            "error": repr(error),
            "stderr_diagnostics": audit.diagnostics if audit is not None else [],
            "completed_cohorts_before_rejection": audit.cohorts if audit is not None else [],
            "auditor": {"file": str(Path(__file__).resolve()), "sha256": file_hash(Path(__file__))},
            "scope": "Rejected audit; no current qualification passes are accepted by this result.",
        }
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps({"accepted": False, "error": repr(error), "output": str(args.output)}, indent=2),
              file=sys.stderr)
        return 1
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"accepted": result["accepted"], "source": result["qualified_source"],
                      "counts": result["counts"], "output": str(args.output)}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
