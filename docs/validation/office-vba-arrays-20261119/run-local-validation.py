#!/usr/bin/env python3
"""Run source-bound local macro acceptance without querying GitHub Actions.

The reduced Dart workspace must already be resolved. Its package source
directories point to the repository; this script does not edit dependencies,
source, branches, or GitHub state. Use a new output directory for each run so
original logs and failed attempts cannot be silently replaced.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


SDK_ARCHIVE_SHA256 = "eb99aed266efbcb615c6ae21c12f52cfe935b9f208bccc5fea7f64c21e867229"
SOURCE_DIRECTORIES = (
    "packages/quds_office_engine/lib",
    "packages/quds_office_engine/test",
    "packages/quds_office_engine/tool/macros",
    "packages/quds_office_engine/example/macros",
    "packages/legacy_doc_parser/lib",
)
SOURCE_FILES = (
    ".fvmrc",
    ".github/workflows/office-macros.yml",
    "analysis_options.yaml",
    "pubspec.yaml",
    "pubspec.lock",
    "packages/quds_office_engine/pubspec.yaml",
    "packages/quds_office_engine/example/pubspec.yaml",
    "packages/legacy_doc_parser/pubspec.yaml",
    "docs/MACROS.md",
    "docs/VBA_MACROS.md",
    "docs/validation/office-vba-arrays-20261119/run-local-validation.py",
)
FORMAT_FILES = (
    "lib/src/automation/office_vba_language.dart",
    "test/office_vba_arrays_test.dart",
    "test/office_vba_arrays_boundaries_test.dart",
    "test/office_vba_arrays_integration_test.dart",
    "tool/macros/web_vba_arrays_smoke.dart",
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def file_info(path: Path) -> dict:
    return {"sha256": digest(path), "bytes": path.stat().st_size}


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def source_snapshot(repo: Path) -> dict:
    paths = {repo / name for name in SOURCE_FILES}
    for directory in SOURCE_DIRECTORIES:
        paths.update(path for path in (repo / directory).rglob("*") if path.is_file())
    # Local package-specific analysis configuration is an input when present.
    for package in ("quds_office_engine", "legacy_doc_parser"):
        candidate = repo / "packages" / package / "analysis_options.yaml"
        if candidate.exists():
            paths.add(candidate)
    return {
        str(path.relative_to(repo)): file_info(path)
        for path in sorted(paths)
    }


def dependency_snapshot(workspace: Path) -> dict:
    names = ["pubspec.yaml", "pubspec.lock", "analysis_options.yaml",
             ".dart_tool/package_config.json", ".dart_tool/package_graph.json"]
    for package in ("legacy_doc_parser", "quds_office_engine",
                    "quds_office_engine/example", "quds_mail_core", "quds_mail_store"):
        names.extend((f"packages/{package}/pubspec.yaml",
                      f"packages/{package}/analysis_options.yaml"))
    return {
        name: file_info(workspace / name)
        for name in names if (workspace / name).is_file()
    }


def changed_inputs(before: dict, after: dict) -> list[str]:
    return [name for name in sorted(before.keys() | after.keys())
            if before.get(name) != after.get(name)]


def parse_tests(path: Path, expected_suites: list[str]) -> dict:
    suites: dict[int, str] = {}
    tests: dict[int, dict] = {}
    completed: dict[int, dict] = {}
    final_events = []
    reporter_errors = []
    unparsed = []
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            unparsed.append({"line": number, "content": line})
            continue
        kind = event.get("type")
        if kind == "suite":
            suite = event["suite"]
            suites[suite["id"]] = suite["path"]
        elif kind == "testStart":
            test = event["test"]
            tests[test["id"]] = test
        elif kind == "testDone":
            completed[event["testID"]] = event
        elif kind == "done":
            final_events.append(event)
        elif kind == "error":
            reporter_errors.append(event)
    records = []
    for test_id, event in completed.items():
        if event.get("hidden", False):
            continue
        test = tests[test_id]
        records.append({
            "suite": Path(suites[test["suiteID"]]).name,
            "name": test["name"],
            "result": event["result"],
            "skipped": event.get("skipped", False),
        })
    unique = {(item["suite"], item["name"]): item for item in records}
    by_suite = {}
    for item in unique.values():
        counts = by_suite.setdefault(item["suite"], {"passed": 0, "failed": 0, "skipped": 0})
        label = "skipped" if item["skipped"] else "passed" if item["result"] == "success" else "failed"
        counts[label] += 1
    wanted = {Path(name).name for name in expected_suites}
    missing = sorted(wanted - by_suite.keys())
    passed = sum(value["passed"] for value in by_suite.values())
    failed = sum(value["failed"] for value in by_suite.values())
    skipped = sum(value["skipped"] for value in by_suite.values())
    success = (len(final_events) == 1 and final_events[0].get("success") is True
               and not failed and not missing and not unparsed and not reporter_errors
               and len(records) == len(unique))
    return {
        "success": success,
        "passed_distinct": passed,
        "failed_distinct": failed,
        "skipped_distinct": skipped,
        "visible_completed_events": len(records),
        "duplicate_suite_name_pairs": len(records) - len(unique),
        "by_suite": dict(sorted(by_suite.items())),
        "missing_suites": missing,
        "reporter_done": final_events,
        "reporter_errors": reporter_errors,
        "unparsed_lines": unparsed,
        "tests": sorted(unique.values(), key=lambda item: (item["suite"], item["name"])),
    }


def smoke_receipt(path: Path, stem: str) -> dict:
    objects = []
    for line in path.read_text().splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            objects.append(value)
    required = {
        "web_smoke": ("lateFailurePreservedBytes", "mcpInspection"),
        "web_vba_smoke": ("validationPreservedBytes", "lateFailurePreservedBytes",
                          "mcpCompileAndRun", "numericBoundsAndPrecedence"),
        "web_vba_procedures_smoke": ("procedureScopesAndExits", "recursionRejected",
                                     "sharedWorkBudget", "numericBounds",
                                     "validationPreservedBytes", "lateFailurePreservedBytes",
                                     "mcpCompileAndRun"),
        "web_vba_control_flow_smoke": ("orderedCasesAndEagerRangeBounds", "sharedLoopWorkBudget",
                                       "staticInactiveChecks", "validationPreservedBytes",
                                       "lateFailurePreservedBytes", "mcpCompileAndRun"),
        "web_vba_arrays_smoke": ("liveArraySlotsAndIndependentControlVariables",
                                 "rangeSnapshotAndRowMajorOrder", "exactArrayAllocationAndNegativeBounds",
                                 "boundedArraysAndRangeIteration", "staticInactiveChecks",
                                 "validationPreservedBytes", "lateFailurePreservedBytes", "mcpCompileAndRun"),
    }[stem]
    result = objects[0] if len(objects) == 1 else {}
    success = len(objects) == 1 and all(result.get(key) is True for key in required)
    if stem in ("web_vba_control_flow_smoke", "web_vba_arrays_smoke"):
        success = success and isinstance(result.get("coldDepthStress"), str)
        success = success and "32" in result["coldDepthStress"] and "63" in result["coldDepthStress"]
    return {"success": success, "required_true_fields": list(required), "reported": objects}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-repo", type=Path, required=True)
    parser.add_argument("--validation-workspace", type=Path, required=True)
    parser.add_argument("--dart", type=Path, required=True)
    parser.add_argument("--node", type=Path, required=True)
    parser.add_argument("--pub-cache", type=Path, required=True)
    parser.add_argument("--tmp", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--sdk-archive", type=Path)
    parser.add_argument("--base", default="cf59efa99232a3fd26cf21ce7f2382402e576f9b")
    args = parser.parse_args()
    repo = args.source_repo.resolve()
    workspace = args.validation_workspace.resolve()
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("output directory is not empty; retain it and use a new directory")
    output.mkdir(parents=True, exist_ok=True)
    logs = output / "logs"
    logs.mkdir()
    build = args.tmp.resolve() / f"vba-arrays-acceptance-{time.time_ns()}"
    build.mkdir(parents=True)
    engine = workspace / "packages/quds_office_engine"
    environment = os.environ.copy()
    explicit_env = {"PUB_CACHE": str(args.pub_cache.resolve()), "TMPDIR": str(args.tmp.resolve()),
                    "DART_SUPPRESS_ANALYTICS": "true", "CI": "true"}
    environment.update(explicit_env)
    environment["PATH"] = str(args.dart.resolve().parent) + os.pathsep + environment.get("PATH", "")
    started = utc_now()
    head = git(repo, "rev-parse", "HEAD")
    before = source_snapshot(repo)
    dependencies_before = dependency_snapshot(workspace)
    write_json(output / "inputs-before.json", before)
    write_json(output / "dependencies-before.json", dependencies_before)
    shutil.copyfile(workspace / "pubspec.lock", output / "resolved-pubspec.lock")
    shutil.copyfile(workspace / "pubspec.yaml", output / "validation-pubspec.yaml")
    shutil.copyfile(workspace / ".dart_tool/package_config.json", output / "package-config.json")
    workflow = (repo / ".github/workflows/office-macros.yml").read_text()
    selection = workflow.split("- name: Macro and existing command regressions", 1)[1].split("- name:", 1)[0]
    tests = re.findall(r"^\s+(test/\S+_test\.dart)\s*$", selection, re.MULTILINE)
    smokes = re.findall(r"dart compile js -O1 (tool/macros/(\w+)\.dart)", workflow)
    if len(tests) != len(set(tests)) or len(smokes) != 5 or not tests:
        raise RuntimeError("Unexpected workflow selections; inspect before running")

    def run(name: str, command: list[str], cwd: Path, timeout: int = 600) -> dict:
        begin = time.monotonic()
        command_started = utc_now()
        stdout = logs / f"{name}.stdout.log"
        stderr = logs / f"{name}.stderr.log"
        timed_out = False
        with stdout.open("wb") as out, stderr.open("wb") as err:
            try:
                result = subprocess.run(command, cwd=cwd, env=environment, stdout=out, stderr=err,
                                        timeout=timeout, check=False)
                code = result.returncode
            except subprocess.TimeoutExpired:
                code = None
                timed_out = True
        receipt = {"name": name, "command": command, "cwd": str(cwd),
                   "started_utc": command_started, "completed_utc": utc_now(),
                   "elapsed_seconds": round(time.monotonic() - begin, 3),
                   "exit_code": code, "timed_out": timed_out,
                   "stdout": {"path": str(stdout.relative_to(output)), **file_info(stdout)},
                   "stderr": {"path": str(stderr.relative_to(output)), **file_info(stderr)}}
        write_json(output / f"{name}.json", receipt)
        print(json.dumps({"check": name, "exit_code": code, "elapsed_seconds": receipt["elapsed_seconds"]}), flush=True)
        return receipt

    runtime = {
        "dart": run("dart-version", [str(args.dart), "--version"], engine),
        "node": run("node-version", [str(args.node), "--version"], engine),
    }
    sdk_archive = None
    if args.sdk_archive:
        sdk_archive = {"path": str(args.sdk_archive.resolve()), **file_info(args.sdk_archive),
                       "expected_sha256": SDK_ARCHIVE_SHA256}
        sdk_archive["verified"] = sdk_archive["sha256"] == SDK_ARCHIVE_SHA256
        if not sdk_archive["verified"]:
            raise RuntimeError("SDK archive hash differs from verified Dart 3.13.7 archive")

    def test_task() -> dict:
        result = run("macro-tests", [str(args.dart), "test", "--reporter", "json", "--concurrency", "4", *tests], engine)
        summary = parse_tests(logs / "macro-tests.stdout.log", tests)
        write_json(output / "test-summary.json", summary)
        return {"commands": [result], "success": result["exit_code"] == 0 and summary["success"],
                "passed_distinct": summary["passed_distinct"]}

    def simple_task(name: str, command: list[str], cwd: Path) -> dict:
        result = run(name, command, cwd)
        return {"commands": [result], "success": result["exit_code"] == 0}

    def smoke_task(source: str, stem: str) -> dict:
        artifact = build / f"{stem}.js"
        compiled = run(f"{stem}-compile", [str(args.dart), "compile", "js", "-O1", source, "-o", str(artifact)], engine)
        commands = [compiled]
        if compiled["exit_code"] != 0:
            return {"commands": commands, "success": False}
        # Every run is a separate Node process, including the cold depth checks.
        code = "globalThis.self = globalThis; require(" + json.dumps(str(artifact)) + ");"
        executed = run(f"{stem}-run", [str(args.node), "-e", code], engine)
        commands.append(executed)
        parsed = smoke_receipt(logs / f"{stem}-run.stdout.log", stem)
        write_json(output / f"{stem}-assertions.json", parsed)
        return {"commands": commands, "success": executed["exit_code"] == 0 and parsed["success"],
                "generated_javascript": {"path": str(artifact), **file_info(artifact)},
                "assertions": parsed}

    scoped_diff = ["packages/quds_office_engine/" + name for name in FORMAT_FILES]
    scoped_diff.extend(("packages/quds_office_engine/example/macros/array_report.bas",
                        "docs/MACROS.md", "docs/VBA_MACROS.md", ".github/workflows/office-macros.yml"))
    checks = {}
    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = {
            executor.submit(test_task): "macro-tests",
            executor.submit(simple_task, "engine-analysis", [str(args.dart), "analyze", "--fatal-infos"], engine): "engine-analysis",
            executor.submit(simple_task, "format", [str(args.dart), "format", "--output=none", "--set-exit-if-changed", *FORMAT_FILES], engine): "format",
            executor.submit(simple_task, "whitespace", ["git", "diff", "--check", args.base, "--", *scoped_diff], repo): "whitespace",
        }
        for source, stem in smokes:
            futures[executor.submit(smoke_task, source, stem)] = stem
        for future in as_completed(futures):
            name = futures[future]
            try:
                checks[name] = future.result()
            except Exception as error:
                checks[name] = {"success": False, "harness_error": repr(error)}
            write_json(output / "checks-progress.json", checks)

    after = source_snapshot(repo)
    dependencies_after = dependency_snapshot(workspace)
    write_json(output / "inputs-after.json", after)
    write_json(output / "dependencies-after.json", dependencies_after)
    changed_source = changed_inputs(before, after)
    changed_dependencies = changed_inputs(dependencies_before, dependencies_after)
    success = (all(value["success"] for value in checks.values())
               and not changed_source and not changed_dependencies
               and all(value["exit_code"] == 0 for value in runtime.values()))
    receipt = {
        "success": success, "started_utc": started, "completed_utc": utc_now(),
        "source_commit_before": head, "source_commit_after": git(repo, "rev-parse", "HEAD"),
        "source_tree_before": git(repo, "rev-parse", f"{head}^{{tree}}"),
        "repository": str(repo), "validation_workspace": str(workspace),
        "environment": explicit_env, "dart_executable": file_info(args.dart),
        "node_executable": file_info(args.node), "sdk_archive": sdk_archive,
        "flutter_repository_pin": json.loads((repo / ".fvmrc").read_text())["flutter"],
        "runtime": runtime, "workflow_test_selection": tests,
        "workflow_javascript_selection": [source for source, _ in smokes],
        "source_input_count": len(before), "changed_source_inputs": changed_source,
        "changed_dependency_inputs": changed_dependencies,
        "dependency_resolution": "Pre-resolved reduced workspace; tracked repository manifests unchanged by this script.",
        "checks": checks,
        "github_actions": "Not queried, awaited, retried, or used as acceptance evidence.",
    }
    write_json(output / "receipt.json", receipt)
    evidence = {str(path.relative_to(output)): file_info(path)
                for path in sorted(output.rglob("*")) if path.is_file()}
    write_json(output / "artifact-manifest.json", evidence)
    print(json.dumps({"success": success, "passed_distinct": checks["macro-tests"].get("passed_distinct"),
                      "source_input_count": len(before), "receipt": str(output / "receipt.json")}), flush=True)
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
