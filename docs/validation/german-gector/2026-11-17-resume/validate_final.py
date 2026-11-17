#!/usr/bin/env python3
"""Serial, receipt-producing local validation; no network or CI commands.

Activate the recovered runtime, provide an explicit suite manifest, and use a
fresh output directory for every attempt. --plan performs admission only.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import shutil
import subprocess
import sys
import time
import traceback
import unittest
from urllib.parse import unquote, urljoin, urlparse


def utc():
    return datetime.now(timezone.utc).isoformat()


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def pin(path):
    path = Path(path).resolve()
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": digest(path)}


def write_json(path, value):
    temporary = path.with_name(path.name + ".writing")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


def contained(root, relative):
    path = (root / relative).resolve()
    if not path.is_relative_to(root):
        raise ValueError("Path must stay within the checkout: " + str(relative))
    return path


def git(root, *arguments):
    return subprocess.check_output(["git", *arguments], cwd=root, text=True).strip()


def environment(activation):
    # The shell receives paths as positional arguments, never interpolated code.
    names = ["FLUTTER_ROOT", "PUB_CACHE", "PATH", "TMPDIR", "XDG_CONFIG_HOME",
             "XDG_CACHE_HOME", "CI", "DART_SUPPRESS_ANALYTICS",
             "FLUTTER_SUPPRESS_ANALYTICS", "GECTOR_TEST_LIBRARY",
             "GECTOR_TEST_LIBRARY_SHA256", "GECTOR_TEST_MODEL",
             "GECTOR_TEST_MODEL_SHA256", "GECTOR_PACK"]
    code = "import json,os; print(json.dumps({k:os.environ[k] for k in " + repr(names) + " if k in os.environ}))"
    raw = subprocess.check_output(
        ["bash", "-e", "-c", 'source "$1" >/dev/null; exec "$2" -c "$3"',
         "validation-runtime", str(activation), sys.executable, code], text=True)
    updates = json.loads(raw)
    updates["CRISPEMBED_GECTOR"] = "1"
    result = {**os.environ, **updates, "CI": "true", "PYTHONUNBUFFERED": "1"}
    for name in ("FLUTTER_ROOT", "TMPDIR"):
        if not result.get(name):
            raise ValueError("Runtime activation did not supply " + name)
    return result, updates


def snapshot(root, suite, selected):
    names = {"pubspec.yaml", "pubspec.lock", ".dart_tool/package_config.json"}
    names.add("tools/proofing/german_model/build_gector_aot.py")
    names.update(str(p.relative_to(root)) for p in root.glob("packages/**/analysis_options.yaml"))
    names.update(suite.get("sources", []))
    names.update(selected)
    for pattern in suite.get("source_globs", []):
        matches = [p for p in root.glob(pattern) if p.is_file()]
        if not matches:
            raise ValueError("Source glob matched no files: " + pattern)
        names.update(str(p.relative_to(root)) for p in matches)
    result = {}
    for name in sorted(names):
        path = contained(root, name)
        if not path.is_file():
            raise FileNotFoundError("Required validation input missing: " + str(path))
        result[name] = {"bytes": path.stat().st_size, "sha256": digest(path)}
    return result


def dependencies(root):
    """Bind every resolved library and reject package paths to another checkout."""
    config_path = root / ".dart_tool/package_config.json"
    config = json.loads(config_path.read_text())
    packages = {row["name"]: row for row in config["packages"]}
    text = (root / "pubspec.yaml").read_text()
    workspace = re.search(r"(?m)^workspace:\s*\n((?:[ \t]+.*\n|\n)+)", text)
    if workspace is None:
        raise ValueError("The known explicit workspace list is required")
    members = []
    for line in workspace[1].splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = re.fullmatch(r"\s+-\s+([A-Za-z0-9_./-]+)\s*", line)
        if match is None:
            raise ValueError("Unsupported workspace entry: " + line)
        members.append(contained(root, match[1]))
    verified = {}
    for directory in [root, *members]:
        name = re.search(r"(?m)^name:\s*([A-Za-z0-9_]+)\s*$", (directory / "pubspec.yaml").read_text())[1]
        uri = urlparse(urljoin(config_path.as_uri(), packages[name]["rootUri"]))
        if uri.scheme != "file" or uri.netloc not in ("", "localhost"):
            raise ValueError("Workspace package must resolve to a local directory")
        actual = Path(unquote(uri.path)).resolve()
        if actual != directory.resolve():
            raise ValueError("Workspace package resolves outside this checkout: " + name)
        verified[name] = str(directory.relative_to(root))
    spec = importlib.util.spec_from_file_location(
        "qualification_build", root / "tools/proofing/german_model/build_gector_aot.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return {"workspace_roots": verified, "resolved_libraries": module.dependency_snapshot(root)}


def package_inputs(root, destination, phase):
    result = {}
    for relative, label in [("pubspec.lock", "pubspec.lock"),
                            (".dart_tool/package_config.json", "package_config.json")]:
        source = contained(root, relative)
        target = destination / (phase + "-" + label)
        target.write_bytes(source.read_bytes())
        result[relative] = {"copy": target.name, **pin(target)}
    config = json.loads((root / ".dart_tool/package_config.json").read_text())
    result["resolved_packages"] = [{key: item.get(key) for key in
                                     ("name", "rootUri", "packageUri", "languageVersion")}
                                    for item in config.get("packages", [])]
    return result


def select_command(root, suite, dart, flutter_snapshot):
    cwd = contained(root, suite["cwd"])
    if not cwd.is_dir():
        raise ValueError("Suite cwd is missing: " + str(cwd))
    runner = suite["runner"]
    paths = suite.get("tests", []) if runner != "dart-analyze" else suite.get("paths", [])
    if not paths or len(set(paths)) != len(paths):
        raise ValueError("Suite must select explicit nonduplicate test/path entries")
    selected = []
    for relative in paths:
        path = contained(root, str(cwd.relative_to(root) / Path(relative)))
        if not path.is_file():
            raise FileNotFoundError("Selected file missing: " + str(path))
        selected.append(str(path.relative_to(root)))
    extra = suite.get("arguments", [])
    if runner == "dart-test":
        command = [str(dart), "test", "--reporter=json", *extra, *paths]
        parser = "test-json"
    elif runner == "flutter-test":
        command = [str(dart), str(flutter_snapshot), "test", "--no-pub",
                   "--reporter=json", *extra, *paths]
        parser = "test-json"
    elif runner == "python-unittest":
        command = [sys.executable, str(Path(__file__).resolve()),
                   "--unittest-worker", *paths]
        parser = "test-json"
    elif runner == "dart-analyze":
        command = [str(dart), "analyze", "--fatal-infos", "--fatal-warnings",
                   *extra, *paths]
        parser = "analysis"
    else:
        raise ValueError("Unsupported explicit runner: " + runner)
    return cwd, command, selected, parser


def parse_events(log):
    events = []
    non_json = 0
    for line in log.read_text(errors="replace").splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            non_json += 1
            continue
        if isinstance(event, dict) and isinstance(event.get("type"), str):
            events.append(event)
        else:
            non_json += 1
    names = {event["test"]["id"]: event["test"]["name"]
             for event in events if event["type"] == "testStart"}
    completed = [event for event in events if event["type"] == "testDone"]
    loading = [event for event in completed
               if names.get(event.get("testID"), "").startswith("loading ")]
    visible = [event for event in completed if event not in loading and not event.get("hidden", False)]
    failures = [event for event in visible if event.get("result") != "success"]
    done = [event for event in events if event["type"] == "done"]
    return {
        "event_count": len(events), "event_types": dict(sorted(Counter(e["type"] for e in events).items())),
        "non_json_log_lines": non_json,
        "passed_tests": sum(event.get("result") == "success" and not event.get("skipped", False) for event in visible),
        "skipped_tests": sum(bool(event.get("skipped", False)) for event in visible),
        "failed_tests": len(failures),
        "loading_failures": [{**event, "name": names.get(event.get("testID"))}
                             for event in loading if event.get("result") != "success"],
        "hidden_failures": [{**event, "name": names.get(event.get("testID"))}
                            for event in completed if event.get("hidden", False) and
                            event not in loading and event.get("result") != "success"],
        "failed_test_details": [{**event, "name": names.get(event.get("testID"))} for event in failures],
        "test_results": [{**event, "name": names.get(event.get("testID"))} for event in visible],
        "error_events": [event for event in events if event["type"] == "error"],
        "done_events": done,
        "complete_success_event": len(done) == 1 and done[0].get("success") is True,
    }


def runtime_pins(env, dart, flutter_snapshot, uses_flutter):
    result = {"dart": pin(dart), "sdk_version":
              (Path(env["FLUTTER_ROOT"]) / "bin/cache/dart-sdk/version").read_text().strip()}
    result["python"] = pin(sys.executable)
    result["python_version"] = sys.version
    result["python_invoked"] = sys.executable
    result["python_prefix"] = sys.prefix
    sdk_root = dart.parent.parent
    sdk_names = ["bin/dartvm", "bin/dartaotruntime", "bin/utils/gen_snapshot",
                 "bin/snapshots/dartdev_aot.dart.snapshot",
                 "bin/snapshots/gen_kernel_aot.dart.snapshot",
                 "bin/snapshots/analysis_server_aot.dart.snapshot",
                 "bin/snapshots/frontend_server_aot.dart.snapshot",
                 "lib/_internal/vm_platform.dill", "lib/_internal/vm_platform_product.dill"]
    result["sdk_payloads"] = {name: pin(sdk_root / name) for name in sdk_names if (sdk_root / name).is_file()}
    if node := shutil.which("node", path=env["PATH"]):
        result["node"] = pin(node)
        result["node_version"] = subprocess.check_output([node, "--version"], text=True).strip()
    if uses_flutter:
        result["flutter_tools_snapshot"] = pin(flutter_snapshot)
        engine = Path(env["FLUTTER_ROOT"]) / "bin/cache/artifacts/engine/linux-x64"
        result["flutter_engine"] = {name: pin(engine / name) for name in
            ("flutter_tester", "frontend_server_aot.dart.snapshot", "icudtl.dat")}
    for name in ("GECTOR_TEST_MODEL", "GECTOR_TEST_LIBRARY"):
        if env.get(name):
            result[name] = pin(env[name])
    return result


def run_suite(name, suite, root, out, env, updates, activation, definitions, dart, flutter_snapshot):
    destination = out / name
    destination.mkdir()
    cwd, command, selected, parser = select_command(root, suite, dart, flutter_snapshot)
    log = destination / ("events.jsonl" if parser == "test-json" else "analysis.log")
    receipt = destination / "receipt.json"
    record = {
        "schema_version": 1, "kind": "quds-final-local-validation", "suite": name,
        "completed": False, "passed": False, "started_utc": utc(),
        "root": str(root), "cwd": str(cwd), "command": command,
        "selected_tests": selected if parser == "test-json" else [],
        "selected_analysis_paths": selected if parser == "analysis" else [],
        "suite_definition": suite, "manifest": pin(definitions),
        "harness": pin(Path(__file__)), "activation": pin(activation),
        "runtime_environment": updates, "head_before": git(root, "rev-parse", "HEAD"),
        "worktree_status_before": git(root, "status", "--porcelain=v1", "--untracked-files=no"),
        "source_files_before": snapshot(root, suite, selected),
        "dependencies_before": dependencies(root),
        "runtime_before": runtime_pins(env, dart, flutter_snapshot, suite["runner"] == "flutter-test"),
        "resolved_inputs_before": package_inputs(root, destination, "before"),
    }
    write_json(receipt, record)
    print(json.dumps({"suite": name, "started_utc": record["started_utc"],
                      "selected_files": len(selected), "receipt": str(receipt)}), flush=True)
    started = time.monotonic()
    process = None
    try:
        with log.open("xb") as output:
            process = subprocess.Popen(command, cwd=cwd, env=env, stdout=output,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            try:
                record["exit_code"] = process.wait(timeout=suite.get("timeout_seconds", 1200))
            except subprocess.TimeoutExpired:
                record["timed_out"] = True
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                record["exit_code"] = process.returncode
    except BaseException as error:
        record["harness_error"] = repr(error)
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
    finally:
        record.update({"completed_utc": utc(), "elapsed_seconds": round(time.monotonic() - started, 6)})
        try:
            record.update({
                "head_after": git(root, "rev-parse", "HEAD"),
                "worktree_status_after": git(root, "status", "--porcelain=v1", "--untracked-files=no"),
                "source_files_after": snapshot(root, suite, selected),
                "dependencies_after": dependencies(root),
                "runtime_after": runtime_pins(env, dart, flutter_snapshot, suite["runner"] == "flutter-test"),
                "resolved_inputs_after": package_inputs(root, destination, "after"),
                "manifest_after": pin(definitions), "activation_after": pin(activation),
                "harness_after": pin(Path(__file__)),
            })
            record["source_stable"] = record["source_files_before"] == record["source_files_after"]
            record["dependencies_stable"] = record["dependencies_before"] == record["dependencies_after"]
            record["runtime_stable"] = record["runtime_before"] == record["runtime_after"]
            record["head_stable"] = record["head_before"] == record["head_after"]
            record["validation_inputs_stable"] = (record["manifest"] == record["manifest_after"] and
                record["activation"] == record["activation_after"] and record["harness"] == record["harness_after"])
            record["log"] = pin(log)
            if parser == "test-json":
                counts = parse_events(log)
                record["events"] = counts
                record["checks_passed"] = (counts["complete_success_event"] and counts["passed_tests"] > 0 and
                    counts["failed_tests"] == 0 and not counts["loading_failures"] and not counts["hidden_failures"] and
                    not counts["error_events"] and
                    (counts["skipped_tests"] == 0 or suite.get("allow_skips", False)))
            else:
                record["no_issues_found"] = "No issues found!" in log.read_text(errors="replace")
                record["checks_passed"] = record["no_issues_found"]
            record["completed"] = True
            record["passed"] = (record.get("exit_code") == 0 and not record.get("timed_out", False) and
                not record.get("harness_error") and record["source_stable"] and record["dependencies_stable"] and record["runtime_stable"] and
                record["head_stable"] and record["validation_inputs_stable"] and record["checks_passed"])
        except BaseException as error:
            record["receipt_error"] = repr(error)
        write_json(receipt, record)
    print(json.dumps({"suite": name, "passed": record["passed"], "exit_code": record.get("exit_code"),
                      "elapsed_seconds": record["elapsed_seconds"], "counts": {key: record.get("events", {}).get(key)
                      for key in ("passed_tests", "failed_tests", "skipped_tests")}, "receipt": str(receipt)}), flush=True)
    return record["passed"]


def unittest_worker(paths):
    """Emit per-test events for the existing unittest modules, without discovery."""
    sys.path.insert(0, str(Path.cwd()))
    def emit(kind, **data):
        print(json.dumps({"type": kind, **data}, ensure_ascii=False), flush=True)

    class Result(unittest.TestResult):
        def __init__(self):
            super().__init__()
            self.next_id = 0
            self.current_id = None

        def startTest(self, test):
            super().startTest(test)
            self.next_id += 1
            self.current_id = self.next_id
            self.current_result = "success"
            self.current_skipped = False
            name = test.id()
            if isinstance(test, unittest.loader._FailedTest):
                name = "loading " + name
            emit("testStart", test={"id": self.current_id, "name": name})

        def stopTest(self, test):
            emit("testDone", testID=self.current_id, result=self.current_result,
                 skipped=self.current_skipped, hidden=False)
            super().stopTest(test)
            self.current_id = None

        def record_error(self, test, error):
            # setUpClass/setUpModule can fail outside startTest/stopTest.
            # Preserve those as loading failures instead of losing the receipt.
            if self.current_id is None:
                self.next_id += 1
                emit("testStart", test={"id": self.next_id, "name": "loading " + str(test)})
                emit("error", testID=self.next_id, error="".join(traceback.format_exception(*error)))
                emit("testDone", testID=self.next_id, result="error", skipped=False, hidden=False)
                return
            self.current_result = "error"
            emit("error", testID=self.current_id, error="".join(traceback.format_exception(*error)))

        def addError(self, test, error):
            super().addError(test, error)
            self.record_error(test, error)

        def addFailure(self, test, error):
            super().addFailure(test, error)
            self.record_error(test, error)

        def addSubTest(self, test, subtest, error):
            super().addSubTest(test, subtest, error)
            if error is not None:
                self.record_error(subtest, error)

        def addSkip(self, test, reason):
            super().addSkip(test, reason)
            if self.current_id is None:
                self.next_id += 1
                emit("testStart", test={"id": self.next_id, "name": str(test)})
                emit("print", testID=self.next_id, message="Skipped: " + reason)
                emit("testDone", testID=self.next_id, result="success", skipped=True, hidden=False)
                return
            self.current_skipped = True
            emit("print", testID=self.current_id, message="Skipped: " + reason)

        def addExpectedFailure(self, test, error):
            super().addExpectedFailure(test, error)
            self.current_skipped = True
            emit("print", testID=self.current_id, message="Expected failure")

        def addUnexpectedSuccess(self, test):
            super().addUnexpectedSuccess(test)
            self.current_result = "failure"
            emit("error", testID=self.current_id, error="Unexpected success")

    emit("start", runner="python-unittest", paths=paths)
    names = [path.removesuffix(".py").replace("/", ".") for path in paths]
    suite = unittest.defaultTestLoader.loadTestsFromNames(names)
    result = Result()
    suite.run(result)
    emit("done", success=result.wasSuccessful(), tests_run=result.testsRun)
    return 0 if result.wasSuccessful() else 1


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--unittest-worker":
        return unittest_worker(sys.argv[2:])
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--suite", action="append", required=True,
                        help="Exact manifest suite name; repeat for serial cohorts, or all")
    parser.add_argument("--definitions", type=Path,
                        default=Path(__file__).with_name("final_validation_suites.json"))
    parser.add_argument("--activation", type=Path, default=Path(__file__).with_name("activate.sh"))
    parser.add_argument("--plan", action="store_true", help="Save exact commands/inputs without executing them")
    parser.add_argument("--keep-going", action="store_true")
    args = parser.parse_args()
    root, out = args.root.resolve(), args.out.resolve()
    definitions, activation = args.definitions.resolve(), args.activation.resolve()
    manifest = json.loads(definitions.read_text())
    available = manifest["suites"]
    names = list(available) if args.suite == ["all"] else args.suite
    if len(set(names)) != len(names) or any(name not in available for name in names):
        parser.error("Select nonduplicate exact manifest suites, or --suite all")
    env, updates = environment(activation)
    flutter = Path(env["FLUTTER_ROOT"])
    dart = flutter / "bin/cache/dart-sdk/bin/dart"
    flutter_snapshot = flutter / "bin/cache/flutter_tools.snapshot"
    plan = []
    for name in names:
        cwd, command, selected, event_parser = select_command(root, available[name], dart, flutter_snapshot)
        plan.append({"suite": name, "cwd": str(cwd), "command": command,
                     "selected_files": selected, "parser": event_parser,
                     "source_files": snapshot(root, available[name], selected)})
    out.mkdir(parents=True, exist_ok=False)
    (out / "suite-definitions.json").write_bytes(definitions.read_bytes())
    write_json(out / "plan.json", {"schema_version": 1, "created_utc": utc(), "root": str(root),
                                  "harness": pin(Path(__file__)), "manifest": pin(definitions), "suites": plan})
    if args.plan:
        print(json.dumps({"plan": str(out / "plan.json"), "executed": False}), flush=True)
        return 0
    results = {}
    for name in names:
        results[name] = run_suite(name, available[name], root, out, env, updates,
                                  activation, definitions, dart, flutter_snapshot)
        write_json(out / "summary.json", {"schema_version": 1, "updated_utc": utc(),
                   "requested_suites": names, "results": results,
                   "completed": len(results) == len(names),
                   "passed": len(results) == len(names) and all(results.values())})
        if not results[name] and not args.keep_going:
            break
    return 0 if len(results) == len(names) and all(results.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
