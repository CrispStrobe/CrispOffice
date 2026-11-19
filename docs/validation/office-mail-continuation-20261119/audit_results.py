#!/usr/bin/env python3
"""Independently audit the fresh Office/Mail qualification and final continuity.

Reconstructs raw Dart events without importing the qualification runner or its
reporter parser. The event and native/Node boundary audit is adapted from the
incoming office-finish independent auditor. This version also verifies the
outer driver, Python controls, full core/store gate and browser compilation.
No test re-execution, remote access, GitHub Actions queries or source writes.
"""

import argparse
import collections
import gzip
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from urllib.parse import unquote, urlparse


RUNNER = "docs/validation/document-review-notes-20261118/run_checks.py"
AUDITOR = "docs/validation/office-mail-continuation-20261119/audit_results.py"
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
        return subprocess.check_output(["git", "--no-replace-objects", "-C", str(self.repo), *argv], input=data, env=env)

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

    def python_controls(self, path, label, row=None):
        text = path.read_text(encoding="utf-8")
        summaries = re.findall(r"^Ran (\d+) tests? in [^\n]+$", text, re.M)
        require(len(summaries) == 1 and int(summaries[0]) > 0,
                f"Missing, duplicate or empty Python control summary: {label}")
        require(len(re.findall(r"^OK\s*$", text, re.M)) == 1,
                f"Missing clean Python control result: {label}")
        require(not re.search(r"^OK \(|\bskipped[= ]|^FAILED\b|^ERROR:|^FAIL:", text, re.M),
                f"Failed or skipped Python controls: {label}")
        count = int(summaries[0])
        if row is not None:
            require(row.get("python_tests") == count and row.get("python_skips_detected") is False,
                    f"Python count differs from raw output: {label}")
        return {"name": label, "passed": count, "skipped": 0, "log_sha256": file_hash(path)}

    def outer(self, phases):
        directory = self.args.result.resolve()
        receipt = read_json(directory / "execution.json")
        require(receipt["status"] == "PASS" and not receipt.get("error"), "Outer gate did not pass")
        require(receipt["source_commit"] == self.source and receipt["source_tree"] == self.tree_id,
                "Outer source identity differs")
        require(all(phase["receipt"]["source_base"] == receipt["source_base"] for phase in phases),
                "Nested and outer base commits differ")
        for key in ("source_unchanged", "runtime_unchanged", "source_head_unchanged", "source_index_unchanged",
                    "tracked_worktree_clean_after", "web_sdk_dart_link_unchanged"):
            require(receipt[key] is True, "Outer boundary failed: " + key)
        require(receipt["untracked_product_inputs_after"] == [], "Untracked product inputs after gate")
        require(receipt["historical_results_added_to_current_counts"] == 0
                and receipt["github_actions_queried_or_awaited"] is False,
                "Unexpected historical/CI acceptance evidence")
        expected_manifests = {"source-before.json", "source-after.json", "runtime-before.json", "runtime-after.json",
                              "package_config.json", "package_graph.json"}
        require(set(receipt["manifest_sha256"]) == expected_manifests, "Outer manifest set differs")
        for name, expected in receipt["manifest_sha256"].items():
            local_file(directory / safe_relative(name), expected)
        sources = read_json(directory / "source-before.json")
        environment = read_json(directory / "runtime-before.json")
        require(sources == read_json(directory / "source-after.json"), "Outer source boundary changed")
        require(environment == read_json(directory / "runtime-after.json"), "Outer runtime boundary changed")
        require(receipt["source_input_count"] == len(sources), "Outer source count differs")
        require(receipt["runtime_input_count"] == len(environment), "Outer runtime count differs")
        gate = str(PurePosixPath(AUDITOR).parent)
        selected = self.controlled_paths(self.tracked)
        selected.update({gate + "/run_validation.py", gate + "/native-plan.json", gate + "/node-plan.json",
                         gate + "/web-sdk.json", gate + "/prepare_web_sdk.py", RUNNER,
                         "docs/validation/document-review-notes-20261118/test_run_checks.py"})
        selected.update(name for phase in phases for name in phase["plan"].get("extra_inputs", []))
        require(set(sources) == selected, "Outer source inventory differs from committed plans")
        require(AUDITOR in sources, "Independent auditor is not bound to the frozen source")
        source_rows = {}
        for name, value in sources.items():
            require(name in self.tracked, "Outer source not in Git: " + name)
            source_rows[name] = {"mode": self.tracked[name]["mode"], "git_blob": self.tracked[name]["git_blob"],
                                 "sha256": value, "materialized": True, "sparse_omission": False}
        for phase in phases:
            for name, row in phase["sources"].items():
                require(name in sources and sources[name] == row["sha256"],
                        "Nested source differs from outer bound: " + name)
                require(row["mode"] == self.tracked[name]["mode"] and row["git_blob"] == self.tracked[name]["git_blob"]
                        and row["materialized"] is True and row["sparse_omission"] is False,
                        "Nested source metadata differs from frozen Git object: " + name)
        changed = sorted(name for name in self.git(
            "diff", "--name-only", "--diff-filter=ACMRT", "-z", receipt["source_base"], self.source,
        ).decode().split("\0") if name.endswith(".dart") and name.startswith(("packages/", "apps/", "third_party/")))
        require(receipt["strict_changed_dart_inputs"] == changed, "Changed-source inventory differs")
        native = phases[0]
        require(set(changed) <= set(native["static"]["analysis"]) and set(changed) <= set(native["static"]["format"]),
                "Changed Dart input escaped strict analysis/formatting")
        ordinary = {"test/" + PurePosixPath(name).name for name in self.tracked
                    if PurePosixPath(name).parent.as_posix() == "packages/quds_office_editor/example/test"
                    and name.endswith("_test.dart")}
        excluded = native["plan"].get("excluded_studio_suites", {})
        requested = {test for group in native["plan"]["groups"]
                     if group["cwd"] == "packages/quds_office_editor/example" for test in group["tests"]}
        require(isinstance(excluded, dict) and all(isinstance(reason, str) and reason.strip() for reason in excluded.values()),
                "An excluded Studio suite lacks a boundary")
        require(set(excluded) <= ordinary and requested == ordinary - set(excluded),
                "Ordinary Studio suite coverage differs")
        require(receipt["excluded_studio_suites"] == excluded
                and receipt["excluded_native_backend_suites"] == native["plan"].get("excluded_native_backend_suites", []),
                "Outer exclusions differ from source plan")

        identity = json.loads(self.git("show", self.source + ":" + gate + "/web-sdk.json"))
        web_root = self.args.web_sdk.resolve()
        web_sdk = web_root / safe_relative(identity["sdk_directory"])
        web_link = web_root / safe_relative(identity["dart_sdk_link"])
        require(web_link.resolve() == (self.runtime / "flutter/bin/cache/dart-sdk").resolve()
                and receipt["web_sdk_dart_link_target"] == str(web_link.resolve()), "Web SDK Dart link differs")
        require(identity["engine_revision"] == self.runtime_receipt["runtime"]["engineRevision"], "Web engine differs")
        require(receipt["web_sdk_identity_sha256"] == file_hash(self.repo / gate / "web-sdk.json"), "Web identity file changed")
        paths = {"runtime/" + name: self.runtime / safe_relative(name) for name in self.retained}
        for name in ("runtime.json", "retained-inputs.json", "pub-cache-receipt.json", "cache-omissions.json",
                     "archive-members.json", "env.sh", "bin/dart", "bin/flutter"):
            paths["runtime/" + name] = self.runtime / name
        paths.update({"additional/" + name: Path(name) for name in self.runtime_receipt["additional_inputs"]})
        paths.update({"python/executable": Path(sys.executable).resolve(),
                      "workspace/package_config.json": self.repo / ".dart_tool/package_config.json",
                      "workspace/package_graph.json": self.repo / ".dart_tool/package_graph.json",
                      "sdk/flutter_tools/package_config.json": self.runtime / "flutter/packages/flutter_tools/.dart_tool/package_config.json"})
        paths.update({"web-sdk/" + name: web_sdk / safe_relative(name) for name in identity["files"]})
        paths["web-sdk/archive"] = web_root / "flutter-web-sdk.zip"
        require(set(environment) == set(paths), "Outer runtime selection differs from complete declared inputs")
        require(receipt["runtime_receipt_sha256"] == file_hash(self.runtime / "runtime.json"), "Outer runtime receipt changed")
        for name, expected in environment.items():
            self.runtime_file(paths[name], expected)
        for name, row in self.retained.items():
            require(environment["runtime/" + name] == row["sha256"], "Outer retained runtime binding differs: " + name)
            self.runtime_file(self.runtime / name, row["sha256"], row["bytes"])
        for name, expected in self.runtime_receipt["additional_inputs"].items():
            require(environment["additional/" + name] == expected, "Outer additional input differs: " + name)
        observed_web = {path.relative_to(web_sdk).as_posix() for path in web_sdk.rglob("*") if path.is_file()}
        require(observed_web == set(identity["files"]), "Web SDK member inventory changed")
        for name, row in identity["files"].items():
            local_file(web_sdk / name, row["sha256"], row["bytes"])
        local_file(paths["web-sdk/archive"], identity["archive_sha256"], identity["archive_bytes"])
        for name in ("package_config.json", "package_graph.json"):
            require(file_hash(directory / name) == environment["workspace/" + name], "Copied dependency mapping changed")
        for phase in phases:
            for name, expected in phase["environment"].items():
                if name in environment:
                    require(environment[name] == expected, "Nested runtime differs from outer bound: " + name)
                elif name == "workspace/pubspec.lock":
                    require(expected == sources["pubspec.lock"], "Nested lock binding differs")
                elif name == "workspace/native_assets.yaml":
                    require(expected == environment["additional/" + str(self.repo / ".dart_tool/native_assets.yaml")],
                            "Nested native-assets binding differs")
                else:
                    require(name.startswith("workspace/") and expected is None,
                            "Unexpected nested-only runtime input: " + name)
        names = ["shared-runner-controls", "runtime-replay-controls", "publisher-offline-controls", "hunspell-packaging-controls",
                 "core-store", "native", "node", "mail-browser-frontend", "mail-browser-javascript", "mail-browser-javascript-syntax"]
        require([row["name"] for row in receipt["runs"]] == names, "Outer run sequence incomplete or changed")
        controls = []
        control_arguments = {
            "shared-runner-controls": ["-B", str(self.repo / "docs/validation/document-review-notes-20261118/test_run_checks.py")],
            "runtime-replay-controls": ["-B", str(self.repo / "docs/validation/document-review-notes-20261118/runtime/test_restore_runtime.py")],
            "publisher-offline-controls": ["-B", "-m", "unittest", "discover", "-s", "tools/proofing/ayaspell", "-p", "test_build_bundle*.py", "-v"],
            "hunspell-packaging-controls": ["-B", "-m", "unittest", "discover", "-s", "packages/quds_proofing_hunspell/tool", "-p", "test_build.py", "-v"],
        }
        for row in receipt["runs"]:
            label = row["name"]
            require(row["accepted"] is True and row["exit_code"] == 0 and not row.get("runner_error"),
                    "Outer command failed: " + label)
            require(row["cwd"] == str(self.repo) and row["timeout_seconds"] > 0, "Outer command boundary differs: " + label)
            log = directory / safe_relative(row["log"])
            local_file(log, row["log_sha256"])
            if label.endswith("-controls"):
                controls.append(self.python_controls(log, label, row))
                require(file_hash(Path(row["command"][0]).resolve()) == environment["python/executable"], "Unbound Python executable")
                require(row["command"][1:] == control_arguments[label], "Python control selection differs: " + label)
            if "receipt" in row:
                local_file(directory / safe_relative(row["receipt"]), row["receipt_sha256"])
                require(row["receipt"] == ("core-store/receipt.json" if label == "core-store" else label + "/verification.json"),
                        "Outer receipt path differs: " + label)
        started = datetime.fromisoformat(receipt["started_at_utc"])
        finished = datetime.fromisoformat(receipt["finished_at_utc"])
        require(started < finished, "Outer execution interval is invalid")
        for phase in phases:
            value = phase["receipt"]
            require(started <= datetime.fromisoformat(value["started_at_utc"])
                    < datetime.fromisoformat(value["finished_at_utc"]) <= finished, "Nested execution is outside outer interval")
        self.browser(directory, receipt, web_sdk)
        return {"receipt": receipt, "sources": sources, "source_rows": source_rows, "environment": environment,
                "runtime_paths": paths, "controls": controls, "web_sdk_files": len(identity["files"])}

    @staticmethod
    def controlled_paths(tree):
        return {name for name in tree if name.startswith(("packages/", "apps/", "third_party/", "tools/mail/", "tools/proofing/ayaspell/"))
                or ("/" not in name and Path(name).suffix in {".yaml", ".lock"}) or name == ".fvmrc"}

    def browser(self, directory, receipt, web_sdk):
        browser = receipt["browser_compilation"]
        require(browser["accepted"] is True and browser["browser_session_executed"] is False,
                "Browser compilation boundary differs")
        require(set(browser["artifacts"]) == {"mail-web.dill", "mail-web.dill.deps", "mail-web.js", "mail-web.js.deps"},
                "Browser artifact inventory differs")
        for name, row in browser["artifacts"].items():
            require(row["bytes"] > 0, "Empty browser artifact: " + name)
            local_file(directory / safe_relative(name), row["sha256"], row["bytes"])
        path = directory / "mail-browser-import-closure.json"
        local_file(path, browser["import_closure_sha256"])
        closure = read_json(path)
        entries = set((directory / "mail-web.dill.deps").read_text().splitlines())
        required = ["packages/quds_office_editor/example/tool/mail_web_entry.dart",
                    "packages/quds_office_editor/example/lib/studio_mail.dart",
                    "packages/quds_office_editor/example/lib/studio_mail_web.dart",
                    "packages/quds_office_editor/example/lib/studio_saved_mail.dart",
                    "packages/quds_office_editor/example/lib/studio_mail_file_web.dart"]
        forbidden = ["packages/quds_office_editor/example/lib/studio_mail_native.dart",
                     "packages/quds_office_editor/example/lib/studio_mail_message_loader.dart",
                     "packages/quds_office_editor/example/lib/studio_mail_file_native.dart",
                     "third_party/enough_mail/lib/highlevel.dart", "third_party/enough_mail/lib/src/mail/mail_client.dart",
                     "third_party/enough_mail/lib/src/private/util/client_base.dart"]
        require(closure["required_web_paths"] == required and closure["forbidden_native_paths"] == forbidden,
                "Browser closure requirements differ")
        require(closure["passed"] is True and closure["missing_web_paths"] == closure["present_native_paths"] == [],
                "Browser closure did not pass")
        require(closure["dependency_count"] == len(entries)
                and closure["dependencies_sha256"] == file_hash(directory / "mail-web.dill.deps"), "Browser dependency log changed")
        require(all((self.repo / name).as_uri() in entries for name in required)
                and all((self.repo / name).as_uri() not in entries for name in forbidden), "Selected browser import graph differs")
        common = [str(self.runtime / "bin/dart"), "compile", "js", "--platform-binaries=" + str(web_sdk / "kernel"),
                  "--invoker=flutter_tool", "-Ddart.vm.product=true", "-O1"]
        expected = {
            "mail-browser-frontend": [*common, "--packages=" + str(self.repo / ".dart_tool/package_config.json"),
                                      "--cfe-only", "-o", str(directory / "mail-web.dill"), str(self.repo / required[0])],
            "mail-browser-javascript": [*common, "--no-source-maps", "-o", str(directory / "mail-web.js"), str(directory / "mail-web.dill")],
            "mail-browser-javascript-syntax": [self.runtime_receipt["node_runtime"]["path"], "--check", str(directory / "mail-web.js")],
        }
        for row in receipt["runs"]:
            if row["name"] in expected:
                require(row["command"] == expected[row["name"]], "Browser command differs: " + row["name"])

    def store(self, outer, phases):
        directory = self.args.result.resolve() / "core-store"
        receipt = read_json(directory / "receipt.json")
        require(receipt["status"] == "PASS" and receipt["active_check"] is None
                and receipt["starting_commit"] == self.source and not receipt.get("error"), "Core/store gate did not pass at frozen source")
        require(receipt["source_unchanged"] is True and receipt["source_before"] == receipt["source_after"], "Core/store source changed")
        require(receipt["github_actions"] == "NOT USED" and receipt["browser_runtime"].startswith("NOT RUN:"), "Store validation boundary differs")
        source_names = {".fvmrc", "analysis_options.yaml", "pubspec.yaml", "pubspec.lock",
                        "tools/mail/check_store.py", "tools/mail/check_reader.py", "tools/mail/test_check_store.py"}
        for package in ("quds_mail_core", "quds_mail_store"):
            prefix = "packages/" + package + "/"
            source_names.add(prefix + "pubspec.yaml")
            source_names.update(name for name in self.tracked if any(name.startswith(prefix + folder + "/") for folder in ("lib", "test", "tool"))
                                and not any(part in {".dart_tool", "build", "__pycache__"} for part in PurePosixPath(name).parts))
        require(set(receipt["source_before"]) == source_names, "Core/store source inventory differs")
        for name, expected in receipt["source_before"].items():
            require(outer["sources"].get(name) == expected, "Core/store source escapes outer binding: " + name)
        launcher = receipt["direct_launcher_inputs_before"]
        require(launcher == receipt["direct_launcher_inputs_after"] and not receipt.get("runtime_inputs_changed"), "Store launcher inputs changed")
        bound_paths = {str(path): outer["environment"][name] for name, path in outer["runtime_paths"].items()}
        for name, expected in launcher.items():
            path = Path(name)
            require(path.is_absolute(), "Nonabsolute store runtime input")
            if expected is None:
                require(not path.exists() and not path.is_symlink(), "Shadowing store native mapping: " + name)
            else:
                require(bound_paths.get(name) == expected, "Unbound store launcher input: " + name)
                self.runtime_file(path, expected)
        names = ["runtime", "runner-regressions", "locked-resolution", "core-analysis", "store-analysis", "format",
                 "core-vm", "core-node", "store-vm", "portable-node", "browser-entry", "browser-worker", "whitespace"]
        require([row["name"] for row in receipt["checks"]] == names, "Core/store run sequence differs")
        core = "packages/quds_mail_core"
        store = "packages/quds_mail_store"
        core_tests = sorted(name for name in self.tracked if name.startswith(core + "/test/") and name.endswith("_test.dart"))
        store_tests = sorted(name for name in self.tracked if PurePosixPath(name).parent.as_posix() == store + "/test"
                             and name.endswith("_test.dart") and PurePosixPath(name).name != "browser_problem_test.dart")
        selected = {"core-vm": (core, "vm", core_tests), "core-node": (core, "node", core_tests),
                    "store-vm": (store, "vm", store_tests), "portable-node": (store, "node", [store + "/test/" + name for name in
                                          ("codec_test.dart", "platform_configuration_test.dart", "browser_problem_test.dart")])}
        dart = str(self.runtime / "flutter/bin/cache/dart-sdk/bin/dart")
        config = str(self.repo / ".dart_tool/package_config.json")
        test_entry = phases[0]["receipt"]["test_launcher"]
        base = [dart, "--disable-dart-dev", "--packages=" + config, test_entry]
        executions = 0
        suites = []
        controls = None
        for row in receipt["checks"]:
            label = "core-store/" + row["name"]
            require(row["status"] == "PASS" and row["exit_code"] == 0 and not row.get("timed_out"), "Store command failed: " + label)
            log = directory / safe_relative(row["log"])
            local_file(log, row["log_sha256"])
            if row["name"] in selected:
                cwd, platform, requested = selected[row["name"]]
                command = [*base, *(["--compiler=kernel"] if platform == "vm" else []), "--platform", platform, "--reporter", "json"]
                if row["name"] == "store-vm":
                    command += ["--concurrency=2", *[str(PurePosixPath(name).relative_to(store)) for name in requested]]
                elif row["name"] == "portable-node":
                    command += [str(PurePosixPath(name).relative_to(store)) for name in requested]
                require(row["command"] == command and row["cwd"] == str(self.repo / cwd), "Store test command differs: " + label)
                raw = log.read_bytes()
                result, identities, case_rows = audit_events(raw, self.repo, cwd, requested, label, platform)
                require(row["tests"]["valid"] is True and row["tests"]["passed"] == result["passed_executions"], "Store raw count differs: " + label)
                details = read_json(directory / safe_relative(row["case_list"]))
                require({key: value for key, value in details.items() if key != "cases"} == row["tests"], "Store saved summary differs: " + label)
                suite_map = {}
                for line in raw.decode().splitlines():
                    value = line.strip()
                    while value.startswith(HOOK_PREFIXES):
                        value = value[len(next(prefix for prefix in HOOK_PREFIXES if value.startswith(prefix))):].lstrip()
                    if value:
                        event = json.loads(value)
                        if event["type"] == "suite":
                            suite_map[event["suite"]["id"]] = reporter_path(event["suite"]["path"], self.repo, cwd)
                saved = [{"suite": suite_map[item["suite_id"]], "name": item["name"], "result": item["result"], "skipped": item["skipped"]}
                         for item in details["cases"]]
                order = lambda item: (item["suite"], item["name"])
                require(sorted(saved, key=order) == sorted(case_rows, key=order), "Store case inventory differs: " + label)
                for identity in identities:
                    self.records[identity].append({"phase": "CORE_STORE", "group": row["name"], "platform": platform, "runner": "dart"})
                self.cohorts.append({"phase": "CORE_STORE", "name": row["name"], "platform": platform, "runner": "dart", **result})
                executions += result["passed_executions"]
                suites.extend(requested)
            elif row["name"] == "runner-regressions":
                controls = self.python_controls(log, label)
                require(row["command"][1:] == ["-m", "unittest", "discover", "-s", "tools/mail", "-p", "test_check_store.py", "-v"],
                        "Store Python control selection differs")
            elif row["name"].endswith("-analysis"):
                require("--fatal-infos" in row["command"] and "No issues found!" in log.read_text()
                        and not STATIC_DIAGNOSTICS.search(log.read_text()), "Store strict analysis differs: " + label)
            elif row["name"] == "format":
                counts = re.findall(r"Formatted (\d+) files? \((\d+) changed\)", log.read_text())
                require(len(counts) == 1 and int(counts[0][0]) > 0 and counts[0][1] == "0"
                        and "--set-exit-if-changed" in row["command"], "Store formatting differs")
            elif row["name"] == "locked-resolution":
                require(row["command"] == [dart, "pub", "get", "--enforce-lockfile", "--offline"], "Store dependency resolution was not locked/offline")
            elif row["name"] == "whitespace":
                require(row["command"] == ["git", "diff", "--check", "HEAD"] and log.read_bytes() == b"", "Store whitespace gate differs")
            elif row["name"] in {"browser-entry", "browser-worker"}:
                source = "tool/browser_compile_probe.dart" if row["name"] == "browser-entry" else "tool/mail_store_worker.dart"
                require(row["command"] == [dart, "compile", "js", source, "-o", str(directory / (row["name"] + ".js"))], "Store browser command differs")
                require((directory / (row["name"] + ".js")).stat().st_size > 0, "Missing store browser artifact")
        require(controls is not None, "Missing Store runner controls")
        return {"executions": executions, "suite_executions": len(suites), "suites": suites,
                "python_controls": controls, "receipt_sha256": file_hash(directory / "receipt.json"),
                "source_input_count": len(source_names), "launcher_input_count": len(launcher)}

    def run(self):
        initial_state = self.state()
        require(not initial_state["tracked_status"], "Independent audit requires a clean tracked checkout")
        final_ref = self.git("rev-parse", "--verify", self.args.final_ref + "^{commit}").decode().strip()
        require(subprocess.run(["git", "--no-replace-objects", "-C", str(self.repo), "merge-base", "--is-ancestor",
                                self.source, final_ref], check=False).returncode == 0,
                "Final reference does not retain the qualified source by ancestry")
        current_tree = self.tree(initial_state["head"])
        final_tree = self.tree(final_ref)
        controlled = self.controlled_paths(self.tracked)
        require(self.controlled_paths(current_tree) == controlled and self.controlled_paths(final_tree) == controlled,
                "Final/current source inventory adds or removes a controlled product or harness file")
        untracked = self.git("ls-files", "--others", "--exclude-standard", "-z").decode().split("\0")
        require(not any(name.startswith(("packages/", "apps/", "third_party/")) for name in untracked),
                "Untracked product inputs are present during audit")
        native = self.phase("NATIVE", self.args.native.resolve())
        node = self.phase("NODE", self.args.node.resolve())
        phases = (native, node)
        outer = self.outer(phases)
        bound_source = set(outer["sources"])
        for name in bound_source:
            require(final_tree.get(name) == self.tracked[name], "Final reference changed a qualified input: " + name)
            require(current_tree.get(name) == self.tracked[name], "Current checkout changed a qualified input: " + name)
        source_count = self.verify_sources(outer["source_rows"])
        require(self.runtime_receipt["status"] == "ready" and self.runtime_receipt["archive"]["verified"] is True,
                "Runtime restore provenance is not ready and verified")
        require(self.runtime_receipt["retained_runtime_input_count"] == len(self.retained), "Retained runtime count differs")
        for recorded, expected in self.runtime_receipt["executables_sha256"].items():
            target = self.runtime / "flutter" / Path(recorded).relative_to(Path(self.runtime_receipt["sdk"]))
            local_file(target, expected)
        archives = read_json(self.runtime / "pub-cache-receipt.json")
        require(bool(archives) and all(row["verified"] is True for row in archives)
                and len(archives) == self.runtime_receipt["hosted_archives_verified"], "Hosted archive provenance differs")
        require(outer["sources"]["pubspec.lock"] == self.runtime_receipt["workspace_lock_sha256"], "Verified dependency lock differs")
        config = self.repo / ".dart_tool/package_config.json"
        tests = [row for row in read_json(config)["packages"] if row["name"] == "test"]
        require(len(tests) == 1, "Ambiguous package:test mapping")
        uri = urlparse(tests[0]["rootUri"])
        require(uri.scheme in {"", "file"} and not uri.netloc and not uri.query and not uri.fragment, "Nonlocal package:test mapping")
        package_root = (Path(unquote(uri.path)) if uri.scheme else config.parent / unquote(uri.path)).resolve()
        launcher = package_root / "bin/test.dart"
        require(all(phase["receipt"]["test_launcher"] == str(launcher) for phase in phases), "Test launcher mapping differs")
        versions = {row["version"] for row in archives if row["name"] == "test"}
        require(package_root.parent == self.runtime / "pub-cache/hosted/pub.dev"
                and package_root.name in {"test-" + version for version in versions}, "Test launcher outside verified package cache")
        require(self.retained[launcher.relative_to(self.runtime).as_posix()]["sha256"] == file_hash(launcher), "Test launcher is not retained and bound")
        store = self.store(outer, phases)
        python_controls = [*outer["controls"], store["python_controls"]]
        total = sum(len(values) for values in self.records.values())
        require(total == native["executions"] + node["executions"] + store["executions"], "Current execution totals differ")
        repeated = []
        for suite in sorted(set(native["suites"]) & set(node["suites"])):
            vm = {identity for identity in native["cases"] if identity[0] == suite}
            js = {identity for identity in node["cases"] if identity[0] == suite}
            require(vm == js, "Shared native/Node scenario identities differ: " + suite)
            repeated.append({"suite": suite, "native_cases": len(vm), "node_cases": len(js)})
        suite_counts = {}
        for (suite, name), values in self.records.items():
            row = suite_counts.setdefault(suite, {"distinct_cases": 0, "executions": 0})
            row["distinct_cases"] += 1
            row["executions"] += len(values)
        final_changes = [name for name in self.git("diff", "--name-only", "-z", self.source, final_ref).decode().split("\0") if name]
        require(not (set(final_changes) & bound_source), "Final changes overlap qualified inputs")
        require(initial_state == self.state(), "Checkout HEAD/index/status changed during read-only audit")
        casefile = self.args.output.with_name(self.args.output.stem + "-cases.json")
        require(not casefile.exists(), "Refusing to overwrite case evidence: " + str(casefile))
        rows = [{"suite": suite, "name": name, "executions": values} for (suite, name), values in sorted(self.records.items())]
        casefile.write_text(json.dumps(rows, indent=2) + "\n")
        return {
            "accepted": True, "audited_at_utc": datetime.now(timezone.utc).isoformat(),
            "qualified_source": self.source, "qualified_tree": self.tree_id,
            "final_reference": final_ref, "final_tree": self.git("rev-parse", final_ref + "^{tree}").decode().strip(),
            "method": "Independent raw reporter reconstruction, full declared source/runtime hash verification, exact Git object identities and final source continuity; no test re-execution or remote/CI queries.",
            "counts": {"native_executions": native["executions"], "node_executions": node["executions"], "core_store_executions": store["executions"],
                       "total_current_application_executions": total, "distinct_current_scenarios": len(self.records),
                       "repeated_current_executions": total - len(self.records), "distinct_current_suites": len(suite_counts),
                       "suite_platform_executions": len(native["suites"]) + len(node["suites"]) + store["suite_executions"],
                       "python_controls": sum(row["passed"] for row in python_controls),
                       "failed": 0, "skipped": 0, "reporter_errors": 0, "unfinished": 0,
                       "historical_results_added": 0},
            "phases": [{"name": phase["name"], "receipt_sha256": phase["receipt_sha256"],
                        "plan": phase["receipt"]["plan"], "plan_sha256": phase["receipt"]["plan_sha256"],
                        "suites": phase["suites"], "executions": phase["executions"],
                        "analysis_paths": phase["static"]["analysis"], "format_paths": phase["static"]["format"]} for phase in phases],
            "core_store": store, "python_controls": python_controls, "cohorts": self.cohorts,
            "suite_counts": dict(sorted(suite_counts.items())), "native_node_repeated_suites": repeated,
            "source_binding": {"before_after_identical": True, "frozen_git_modes_blobs_hashes_and_live_bytes_verified": True,
                               "source_records": source_count, "changed_dart_inputs": outer["receipt"]["strict_changed_dart_inputs"],
                               "final_qualified_inputs_unchanged": True, "final_source_retained_by_ancestry": True,
                               "final_unqualified_input_changes": final_changes, "checkout_unchanged_during_audit": True},
            "runtime_binding": {"before_after_identical": True, "recorded_inputs_verified_live": len(outer["environment"]),
                                "retained_inputs": len(self.retained), "web_component_files": outer["web_sdk_files"],
                                "verified_hosted_archives": len(archives), "package_test_launcher_bound": True,
                                "scope": "Declared SDK, package cache, native-assets, Node, Python executable and browser component inputs; not an exhaustive operating-system dependency inventory."},
            "browser_compilation": outer["receipt"]["browser_compilation"],
            "runtime_symlinks": self.runtime_symlinks, "stderr_diagnostics": self.diagnostics,
            "validation": {"exact_nonempty_planned_suite_coverage": True, "all_raw_gzip_case_error_and_manifest_hashes_verified": True,
                           "duplicate_or_unfinished_reporter_events": 0, "layout_tap_disposal_diagnostics": 0,
                           "all_native_node_test_stderr_empty": True, "actual_browser_session": False,
                           "external_mail_provider_session": False, "macos_build_or_installed_application": False,
                           "word_or_libreoffice_reopening": False},
            "outer_execution_sha256": file_hash(self.args.result / "execution.json"),
            "case_inventory": {"file": casefile.name, "sha256": file_hash(casefile)},
            "auditor": {"file": AUDITOR, "sha256": file_hash(Path(__file__))},
            "github_actions_queried_or_awaited": False,
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--head", required=True)
    parser.add_argument("--result", type=Path, required=True, help="Complete fresh run_validation.py output directory")
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--web-sdk", type=Path, required=True)
    parser.add_argument("--final-ref", default="HEAD", help="Source or a later evidence-only merge to verify")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.result = args.result.resolve()
    args.native, args.node = args.result / "native", args.result / "node"
    args.output = args.output.resolve()
    require(args.repo.resolve() not in args.output.parents, "Audit outputs must remain outside the source checkout")
    require(not args.output.exists(), "Refusing to overwrite audit evidence: " + str(args.output))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    try:
        result = Audit(args).run()
    except Exception as error:
        result = {"accepted": False, "audited_at_utc": datetime.now(timezone.utc).isoformat(),
                  "error": type(error).__name__ + ": " + str(error), "github_actions_queried_or_awaited": False}
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("accepted", "counts", "error") if key in result}), flush=True)
    return 0 if result["accepted"] else 1


if __name__ == "__main__":
    sys.exit(main())
