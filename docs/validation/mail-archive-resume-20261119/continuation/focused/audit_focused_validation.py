#!/usr/bin/env python3
"""Independently replay the focused continuation gate and rehash current inputs.

Run only after the gate finishes and while its execution inputs remain available.
No product commands are rerun and no Git refs or tracked files are modified.
"""

import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
from urllib.parse import unquote, urlparse

SOURCE = "9b8853667b68c7bebff050e52445b47ea0bbd188"
RECONCILED_ANCESTORS = [
    "d3e90d0fc0a75e2abfc3efb52e495c032e20683f",
    "2cb7ed411afba8e81e19c28457ac632de78918bc",
]
PRIOR = "b2c05a0afa0ae606b061b13d5e50937c2a8eb1df"
PREFIX = "docs/validation/mail-archive-resume-20261119/"
PARSER = "docs/validation/mail-archive-portability-20261119/run-local-validation.py"
TARGETS = [
    "packages/quds_office_editor/example/lib/studio_downloads_manager.dart",
    "packages/quds_office_editor/example/lib/studio_spacy_host_native.dart",
    "packages/quds_office_editor/example/test/studio_downloads_manager_test.dart",
    "packages/quds_office_editor/example/test/studio_spacy_setup_test.dart",
]
TESTS = TARGETS[2:] + [
    "packages/quds_office_editor/example/test/studio_linguistic_analysis_test.dart",
]
CHANGED = sorted(TARGETS)
ROOT_INPUTS = {"pubspec.yaml", "pubspec.lock", "analysis_options.yaml", "melos.yaml",
               ".cursorrules", "CONTRIBUTING.md", ".fvmrc", "dart_test.yaml"}
DOCUMENT_INPUTS = {PARSER, PREFIX + "run-mail-validation.py", "docs/roadmaps/mail/archive-search.md"}
SOURCE_ROOTS = ("packages/", "third_party/", "apps/", "tool/", "tools/")
RUNTIME_DIRS = [
    "bin/cache/dart-sdk/bin", "bin/cache/dart-sdk/lib",
    "bin/cache/artifacts/engine/linux-x64",
    "bin/cache/artifacts/engine/common/flutter_patched_sdk",
    "bin/cache/artifacts/engine/common/flutter_patched_sdk_product",
    "bin/cache/artifacts/material_fonts",
]
SQLITE_NATIVE_PATHS = [
    "packages/quds_office_editor/example/build/native_assets/linux/libsqlite3.so",
    ".dart_tool/hooks_runner/shared/sqlite3/build/download-0a658527/libsqlite3.so",
]
SQLITE_NATIVE_SHA256 = "0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b"
NATIVE_MAPPING = "packages/quds_office_editor/example/build/native_assets/linux/native_assets.json"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def digest(value):
    return sha(json.dumps(value, sort_keys=True, separators=(",", ":")).encode())


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", type=Path, required=True)
    ap.add_argument("--focused", type=Path, required=True)
    ap.add_argument("--runner", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    repo = args.repo.resolve()
    workspace = repo.parent
    sdk = workspace / "runtime/flutter"
    cache = workspace / "runtime/pub-cache"
    folder = args.focused.resolve()
    failures = []
    identity_cache = {}

    def check(ok, message):
        if not ok:
            failures.append(message)

    def git(*words):
        return subprocess.check_output(["git", *words], cwd=repo)

    def obj(path):
        path = Path(path)
        data = path.read_bytes()
        return json.loads(gzip.decompress(data) if path.suffix == ".gz" else data)

    def identity(path):
        path = Path(path)
        if path not in identity_cache:
            if not path.is_file():
                failures.append("Missing input: " + str(path))
                return None
            count = path.stat().st_size
            sha256 = hashlib.sha256()
            blob = hashlib.sha1(b"blob " + str(count).encode() + b"\0")
            with path.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    sha256.update(block)
                    blob.update(block)
            identity_cache[path] = {"bytes": count, "sha256": sha256.hexdigest(), "git_blob": blob.hexdigest()}
        return identity_cache[path]

    def match(path, expected, label):
        actual = identity(path)
        if actual is None:
            return False
        wanted = {"sha256": expected} if isinstance(expected, str) else expected
        result = actual["sha256"] == wanted["sha256"] and ("bytes" not in wanted or actual["bytes"] == wanted["bytes"])
        check(result, label + ": current input identity differs")
        return result

    def tree(commit):
        entries = {}
        for record in git("ls-tree", "-rz", commit).split(b"\0"):
            if record:
                meta, path = record.split(b"\t", 1)
                entries[path.decode()] = tuple(meta.decode().split())
        return entries

    receipt = obj(folder / "receipt.json")
    check(receipt["status"] == "passed", "Focused gate did not pass")
    check(receipt["source_head"] == SOURCE, "Focused gate names a different source")
    source_tree = git("rev-parse", SOURCE + "^{tree}").decode().strip()
    check(receipt["source_tree"] == source_tree, "Focused source tree differs from Git")
    for ancestor in RECONCILED_ANCESTORS:
        check(subprocess.run(["git", "merge-base", "--is-ancestor", ancestor, SOURCE], cwd=repo).returncode == 0,
              "Focused source lost preserved ancestor " + ancestor)
    check(receipt["github_actions_used"] is False, "GitHub Actions entered the focused gate")
    check(receipt["dependency_resolution_during_validation"] is False, "Dependencies resolved during qualification")
    check(receipt["prior_acceptance_counted_again"] is False, "Historical counts reused as new executions")
    check(receipt["selected_test_files"] == TESTS, "Focused test selection differs")
    check(receipt["analysis_and_format_targets"] == TARGETS, "Analysis/format selection differs")
    check(receipt["differences_from_original_accepted_source"] == CHANGED, "Source-delta declaration differs")
    match(args.runner, receipt["runner_sha256"], "Executed runner")
    match(repo / PARSER, receipt["event_parser_sha256"], "Executed event parser")
    check(sha(git("show", SOURCE + ":" + PARSER)) == receipt["event_parser_sha256"],
          "Executed parser is not source-bound")
    check(obj(folder / "selection.json") == {
        "source_head": SOURCE, "tests": TESTS,
        "analysis_and_format_targets": TARGETS, "original_source_input_count": 4493,
    }, "Frozen selection record differs")
    for head_key in ("execution_head", "execution_head_after"):
        head = receipt[head_key]
        check(subprocess.run(["git", "merge-base", "--is-ancestor", SOURCE, head], cwd=repo).returncode == 0,
              head_key + ": missing source ancestry")
        paths = git("diff", "--name-only", SOURCE, head).decode().splitlines()
        check(all(p.startswith("docs/validation/") for p in paths), head_key + ": non-evidence source changes")
    check(git("rev-parse", receipt["execution_head"] + "^{tree}").decode().strip() == receipt["execution_tree"],
          "Execution head/tree disagree")

    dart = str(sdk / "bin/cache/dart-sdk/bin/dart")
    expected_commands = {
        "format": ([dart, "format", "--output=none", "--set-exit-if-changed", *TARGETS], repo),
        "analysis": ([dart, "analyze", "--fatal-infos", "--fatal-warnings", *TARGETS], repo),
        "whitespace": (["git", "diff", "--check", PRIOR, SOURCE, "--", *TARGETS], repo),
        "studio-downloads-spacy": ([str(workspace / "runtime/bin/flutter"), "test", "--no-pub", "--concurrency=1", "--reporter=json",
                                      *["test/" + Path(p).name for p in TESTS]],
                                     repo / "packages/quds_office_editor/example"),
    }
    check([s["name"] for s in receipt["steps"]] == list(expected_commands), "Missing, additional or reordered commands")
    commands = []
    test_case_rows = []
    test_totals = Counter(passed=0, failed=0, skipped=0)
    for step in receipt["steps"]:
        name = step["name"]
        subdir = folder / name
        check(step["accepted"] is True and step["exit_code"] == 0 and not step.get("interrupted_reason"),
              name + ": unsuccessful command")
        check(obj(subdir / "result.json") == step, name + ": result differs from receipt")
        command = obj(subdir / "command.json")
        check(all(step.get(k) == v for k, v in command.items()), name + ": invocation changed after launch")
        wanted, cwd = expected_commands[name]
        check(step["argv"] == wanted and step["cwd"] == str(cwd), name + ": exact invocation differs")
        started = datetime.fromisoformat(step["started_at_utc"])
        finished = datetime.fromisoformat(step["finished_at_utc"])
        check(datetime.fromisoformat(receipt["started_at_utc"]) <= started <= finished <= datetime.fromisoformat(receipt["finished_at_utc"]),
              name + ": command time outside gate interval")
        for stream in ("stdout", "stderr"):
            match(subdir / (stream + ".log"), step[stream + "_sha256"], name + "/" + stream)
        summary = {"name": name, "exit_code": step["exit_code"], "argv": step["argv"],
                   "stdout_sha256": step["stdout_sha256"], "stderr_sha256": step["stderr_sha256"]}
        if name == "studio-downloads-spacy":
            suites, starts, ends = {}, {}, {}
            terminal, errors, anomalies, non_json = [], [], [], []
            for number, line in enumerate((subdir / "stdout.log").read_text().splitlines(), 1):
                if not line.strip():
                    continue
                try:
                    event = json.loads(line)
                except ValueError:
                    non_json.append({"line": number, "text": line[:300]})
                    continue
                if not isinstance(event, dict):
                    anomalies.append([number, "non-object event"])
                    continue
                kind = event.get("type")
                if kind == "suite":
                    value = event["suite"]
                    if value["id"] in suites:
                        anomalies.append([number, "duplicate suite"])
                    suites[value["id"]] = value
                elif kind == "testStart":
                    value = event["test"]
                    if value["id"] in starts:
                        anomalies.append([number, "duplicate start"])
                    starts[value["id"]] = value
                elif kind == "testDone":
                    if event["testID"] in ends:
                        anomalies.append([number, "duplicate finish"])
                    ends[event["testID"]] = event
                elif kind == "error":
                    errors.append(event)
                elif kind == "done":
                    terminal.append(event)
            check(set(starts) == set(ends), "Focused tests contain incomplete lifecycles")
            hidden_failures = []
            for ident, ended in ends.items():
                began = starts.get(ident)
                if not began or began.get("suiteID") not in suites:
                    anomalies.append([ident, "unknown start or suite"])
                    continue
                suite = suites[began["suiteID"]]
                url = urlparse(suite["path"])
                path = Path(unquote(url.path)) if url.scheme == "file" else Path(suite["path"])
                if not path.is_absolute():
                    path = cwd / path
                filename = str(path.resolve().relative_to(repo))
                row = {"file": filename, "platform": suite.get("platform"), "name": began["name"],
                       "result": ended.get("result"), "skipped": bool(ended.get("skipped"))}
                if ended.get("hidden") or ended.get("isHidden") or began.get("isHidden"):
                    if row["result"] != "success" or row["skipped"]:
                        hidden_failures.append(row)
                    continue
                test_case_rows.append(row)
                test_totals["skipped" if row["skipped"] else "passed" if row["result"] == "success" else "failed"] += 1
            check(not anomalies and not errors and not hidden_failures and not non_json,
                  "Focused reporter has malformed events, failures or non-JSON lines")
            check(len(terminal) == 1 and terminal[0].get("success") is True, "Focused reporter lacks successful final done event")
            identities = [(r["file"], r["platform"], r["name"]) for r in test_case_rows]
            check(len(identities) == len(set(identities)), "Focused tests contain duplicate case identities")
            check({r["file"] for r in test_case_rows} == set(TESTS), "Focused observed files differ from selection")
            check(all(r["platform"] == "vm" for r in test_case_rows), "Focused tests used a different platform")
            check(test_totals["passed"] > 0 and test_totals["failed"] == test_totals["skipped"] == 0, "Focused tests failed, skipped or empty")
            parsed = obj(subdir / "test-cases.json")
            match(subdir / "test-cases.json", step["test_cases_sha256"], "Saved focused cases")
            check(parsed["cases"] == test_case_rows and parsed["accepted"] is True, "Saved parser output differs from independent replay")
            check(step["test_counts"] == dict(test_totals), "Focused command counts differ from replay")
            summary.update(test_counts=dict(test_totals), distinct_case_identities=len(set(identities)),
                           distinct_test_files=len({r["file"] for r in test_case_rows}),
                           error_events=errors, hidden_failures=hidden_failures, non_json_lines=non_json,
                           terminal_events=terminal)
        commands.append(summary)
    check(receipt["test_totals"] == dict(test_totals), "Focused receipt totals differ from replay")
    check(receipt["required_commands_passed"] == len(commands) == 4, "Focused command count differs")

    source_entries = tree(SOURCE)
    review_raw = git("show", SOURCE + ":" + PREFIX + "continuation/combined-resolution-source-review.json")
    review = json.loads(review_raw)
    check(review["status"] == "passed_source_review" and not review["findings"]
          and all(review["checks"].values()) and sorted(review["changed_paths"]) == CHANGED,
          "Combined source review failed or covers different paths")
    check(subprocess.run(["git", "merge-base", "--is-ancestor", review["incoming_main_parent"], SOURCE], cwd=repo).returncode == 0,
          "Focused source lost latest-main review ancestry")
    for reviewed in review["files"].values():
        path = reviewed["path"]
        check(source_entries[path][1:] == ("blob", reviewed["git_blob_sha"]),
              "Frozen source differs from reviewed Git blob: " + path)
        match(repo / path, reviewed["sha256"], "Reviewed source " + path)
    snapshots = {}
    inventories = {}
    for kind in ("source", "dependencies", "runtime"):
        before = obj(folder / (kind + "-before.json.gz"))
        after = obj(folder / (kind + "-after.json.gz"))
        check(before == after and bool(before), kind + ": unstable or empty snapshot")
        binding = receipt["bound_inputs"][kind]
        check(binding == {"inputs": len(before), "digest": digest(before), "before_after_equal": True, "changes": []},
              kind + ": receipt snapshot binding differs")
        inventories[kind] = before
    source_inventory = inventories["source"]
    expected_source_names = {name for name, entry in source_entries.items() if entry[1] == "blob" and (
        name in ROOT_INPUTS or name in DOCUMENT_INPUTS or (
            name.startswith(SOURCE_ROOTS) and "/docs/" not in name and "/doc/" not in name and not name.lower().endswith(".md")))}
    check(set(source_inventory) == expected_source_names, "Source inventory scope differs from source Git tree")
    for path, recorded in source_inventory.items():
        current = repo / path
        match(current, recorded, "Source " + path)
        check(not current.is_symlink(), "Source input became a symlink: " + path)
        mode, kind, oid = source_entries[path]
        actual = identity(current)
        check(actual is not None and kind == "blob" and oid == actual["git_blob"], "Source Git blob differs: " + path)
        check(bool(current.stat().st_mode & 0o100) == (mode == "100755"), "Source executable mode differs: " + path)
    prior_inventory = json.loads(gzip.decompress(git("show", PRIOR + ":" + PREFIX + "final/source-before.json.gz")))
    changed = sorted(p for p in set(prior_inventory) | set(source_inventory) if prior_inventory.get(p) != source_inventory.get(p))
    check(changed == CHANGED and set(prior_inventory) == set(source_inventory), "Actual source delta differs from exact four-file qualification")
    for path in ("pubspec.yaml", "pubspec.lock", TESTS[-1]):
        check(source_entries[path] == tree(PRIOR)[path], "Required unchanged source differs: " + path)

    dependency_paths = {}
    configurations = {"workspace": repo / ".dart_tool/package_config.json",
                      "flutter-tools": sdk / "packages/flutter_tools/.dart_tool/package_config.json"}
    for origin, configuration in configurations.items():
        for package in obj(configuration)["packages"]:
            parsed = urlparse(package["rootUri"])
            root = Path(unquote(parsed.path)).resolve() if parsed.scheme == "file" else (configuration.parent / unquote(package["rootUri"])).resolve()
            if root.is_relative_to(repo):
                continue
            check(root.is_relative_to(cache) or root.is_relative_to(sdk), "Dependency outside captured runtime: " + str(root))
            paths = set(root.glob("pubspec.yaml"))
            for sub in ("lib", "bin", "hook"):
                paths.update(p for p in (root / sub).rglob("*") if p.is_file())
            for path in paths:
                key = origin + "/" + package["name"] + "/" + str(path.relative_to(root))
                dependency_paths[key] = path
    check(set(dependency_paths) == set(inventories["dependencies"]), "Dependency snapshot scope differs from resolved packages")
    for key, value in inventories["dependencies"].items():
        if key in dependency_paths:
            match(dependency_paths[key], value, "Dependency " + key)

    runtime_paths = {sdk / "bin/cache/flutter_tools.snapshot", sdk / "bin/cache/flutter.version.json",
                     configurations["workspace"], configurations["flutter-tools"],
                     workspace / "runtime/bin/flutter", workspace / "runtime/bin/dart", workspace / "runtime/env.sh"}
    runtime_paths.update({repo / path for path in SQLITE_NATIVE_PATHS + [NATIVE_MAPPING]})
    principal = set(runtime_paths) | {sdk / "bin/cache/dart-sdk/bin/dart", sdk / "bin/cache/artifacts/engine/linux-x64/flutter_tester"}
    for path in principal:
        check(path.is_file(), "Missing principal runtime input: " + str(path))
    for name in RUNTIME_DIRS:
        directory = sdk / name
        check(directory.is_dir(), "Missing declared runtime scope: " + name)
        runtime_paths.update(p for p in directory.rglob("*") if p.is_file())
    check({str(p) for p in runtime_paths if p.is_file()} == set(inventories["runtime"]), "Runtime snapshot scope differs")
    for path, value in inventories["runtime"].items():
        match(Path(path), value, "Runtime " + path)
    for path in SQLITE_NATIVE_PATHS:
        match(repo / path, SQLITE_NATIVE_SHA256, "Default packaged SQLite " + path)
    for path, value in receipt["native_assets_generated"].items():
        match(Path(path), value, "Generated native asset " + path)
    for kind, inventory in inventories.items():
        snapshots[kind] = {"inputs": len(inventory), "digest": digest(inventory),
                           "before_after_equal": True, "current_files_rehashed": len(inventory),
                           "bound_to_source_git_blobs": len(inventory) if kind == "source" else 0}

    report = {
        "status": "passed" if not failures else "failed",
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_head": SOURCE, "source_tree": source_tree,
        "focused_receipt_sha256": sha((folder / "receipt.json").read_bytes()),
        "runner_sha256": receipt["runner_sha256"], "event_parser_sha256": receipt["event_parser_sha256"],
        "combined_source_review_sha256": sha(review_raw),
        "auditor_sha256": sha(Path(__file__).read_bytes()),
        "test_counts": dict(test_totals), "distinct_case_identities": len(test_case_rows),
        "distinct_test_files": len({r["file"] for r in test_case_rows}),
        "required_commands_passed": len(commands), "commands": commands,
        "source_changes_from_historical_acceptance": changed,
        "current_input_checks": snapshots,
        "generated_native_asset_files_rehashed": len(receipt["native_assets_generated"]),
        "failures": failures, "tests_rerun_by_auditor": False, "github_actions_used": False,
        "historical_2243_executions_included_in_these_counts": False,
        "superseded_attempt_executions_included_in_these_counts": False,
        "scope": "Independent raw-event replay and current-file rehash of focused Linux Flutter fixture qualification only. No installed macOS/native-model or real-account qualification.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "tests": dict(test_totals),
                      "commands": len(commands), "inputs": snapshots, "failures": failures}))
    raise SystemExit(bool(failures))


if __name__ == "__main__":
    main()
