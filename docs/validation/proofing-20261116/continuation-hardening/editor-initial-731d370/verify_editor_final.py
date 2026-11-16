#!/usr/bin/env python3
"""Run source-bound local Flutter/editor validation without GitHub Actions.

Use a NEW output directory, preferably outside the checkout. Run this helper
as a background job in the surviving persistent shell; do not interrupt that
shell. Individual commands have timeouts and their own process groups.

This runner does not install or validate optional Harper runtime assets.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
from urllib.parse import unquote, urljoin, urlparse

EXPECTED_SOURCE = "731d3708513d00fde9ac32dcb32bac1d39631214"
EXPECTED_FLUTTER = "737ba8f885dc774b53b442759999a312c9461e4e"

def now():
    return datetime.now(timezone.utc).isoformat()

def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()

def write_json(path, value):
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")
    temporary.replace(path)

def differences(before, after):
    return [
        name for name in sorted(before.keys() | after.keys())
        if before.get(name) != after.get(name)
    ]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--flutter", required=True, type=Path)
    parser.add_argument("--dart", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--expected-source", default=EXPECTED_SOURCE)
    args = parser.parse_args()
    repo = args.repo.resolve()
    flutter = args.flutter.resolve()
    dart = args.dart.resolve()
    out = args.output.resolve()
    if out.exists() and any(out.iterdir()):
        parser.error("Use a new empty output directory so prior evidence is preserved.")
    if out.is_relative_to(repo):
        relative = out.relative_to(repo)
        if not relative.parts or relative.parts[0] not in {"docs", "doc"}:
            parser.error("Put output outside the checkout or under its docs directory.")
    out.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(Path(__file__).resolve(), out / "verify_editor_final.py")
    record = {
        "schema_version": 1,
        "started": now(),
        "status": "running",
        "expected_source_commit": args.expected_source,
        "repo": str(repo),
        "runner_sha256": digest(Path(__file__).resolve()),
        "commands": [],
        "errors": [],
        "environment": {
            name: os.environ.get(name)
            for name in (
                "CI", "PUB_CACHE", "TMPDIR", "FLUTTER_ROOT",
                "DART_SUPPRESS_ANALYTICS", "FLUTTER_SUPPRESS_ANALYTICS",
            )
        },
        "scope": {
            "engine": "Full lib, test and tool strict analysis under the real workspace.",
            "editor": "Library and exactly 31 committed selected test files: the prior 23 plus eight incoming text, direction, font, input ownership and unit regressions.",
            "host": "Example library analysis and release web compilation.",
            "ime": "Separate embed_test canvas IME reattachment regression.",
            "harper_runtime_assets": "Not installed or validated by this runner.",
            "browser_execution": "Not exercised by a successful web compilation.",
        },
    }
    contract = None
    source_before = None
    runtime_before = None
    lock_before = None
    config_before = None
    sdk_root = flutter.parent.parent
    node = shutil.which("node")
    editor = repo / "packages/quds_office_editor"
    engine = repo / "packages/quds_office_engine"
    example = editor / "example"
    web_root = example / "build/web"

    def save():
        write_json(out / "receipt.json", record)

    def git(*argv):
        return subprocess.check_output(
            ["git", *argv], cwd=repo, text=True, timeout=30).strip()

    def manifest(name, values):
        return contract.compressed_manifest(out, name, values)

    def capture_runtime():
        values = contract.runtime_hashes(str(flutter), str(dart), node) if node else {}
        paths = [
            flutter, dart, Path(sys.executable), dart.parent / "dartvm",
            dart.parent / "dartaotruntime",
            dart.parent / "snapshots/analysis_server_aot.dart.snapshot",
            dart.parent / "snapshots/kernel-service.dart.snapshot",
            dart.parent / "snapshots/frontend_server_aot.dart.snapshot",
            sdk_root / "bin/cache/flutter_tools.snapshot",
            sdk_root / "bin/cache/artifacts/engine/linux-x64/flutter_tester",
            sdk_root / "bin/internal/engine.version",
            sdk_root / "bin/cache/engine.stamp",
            sdk_root / "bin/cache/engine_stamp.json",
            sdk_root / "packages/flutter_tools/.dart_tool/package_config.json",
            repo / ".dart_tool/package_config.json",
        ]
        if node:
            paths.append(Path(node))
        for path in paths:
            if path.is_file():
                values[str(path.resolve())] = digest(path)
        return values

    def capture_web():
        if not web_root.is_dir():
            return {}
        return {
            str(path.relative_to(web_root)): {
                "sha256": digest(path), "bytes": path.stat().st_size,
            }
            for path in sorted(web_root.rglob("*"))
            if path.is_file()
        }

    def reported_tests(path):
        successful = contract.test_summary(path)
        if successful is not None:
            return {
                **successful, "complete_success_marker": True,
                "counts_kind": "final reported test summary",
            }
        text = re.sub(r"\x1b\[[0-9;]*m", "", path.read_text(errors="replace"))
        text = text.replace("\r", "\n")
        matches = re.findall(
            r"\+(\d+)(?:\s+~(\d+))?(?:\s+-(\d+))?:\s*([^\n]*)",
            text,
        )
        if not matches:
            return {
                "complete_success_marker": False,
                "counts_kind": "no test counters reported",
            }
        passed, skipped, failed, message = matches[-1]
        return {
            "passed": int(passed), "skipped": int(skipped or 0),
            "failed": int(failed or 0), "last_reported_message": message,
            "complete_success_marker": False,
            "counts_kind": "last reported counters; not a complete passing suite",
        }

    def run(label, argv, cwd, limit, tests=False):
        path = out / (label + ".log")
        row = {
            "label": label, "argv": argv, "cwd": str(cwd),
            "started": now(), "timeout_seconds": limit, "log": path.name,
        }
        began = time.monotonic()
        record["active_command"] = row
        save()
        print("START " + label, flush=True)
        process = None
        code = None
        timed_out = False
        try:
            with path.open("wb") as log:
                process = subprocess.Popen(
                    argv, cwd=cwd, stdout=log, stderr=subprocess.STDOUT,
                    start_new_session=True,
                    env={
                        **os.environ, "CI": "true",
                        "DART_SUPPRESS_ANALYTICS": "true",
                        "FLUTTER_SUPPRESS_ANALYTICS": "true",
                    },
                )
                row["pid"] = process.pid
                write_json(out / "active-process.json", {
                    "label": label, "pid": process.pid, "pgid": process.pid,
                })
                save()
                try:
                    code = process.wait(timeout=limit)
                except subprocess.TimeoutExpired:
                    timed_out = True
                    try:
                        os.killpg(process.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        try:
                            os.killpg(process.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        process.wait()
                    row["native_exit_code_after_timeout"] = process.returncode
                    code = 124
        except Exception as error:
            row["launch_or_wait_error"] = str(error)
            with path.open("ab") as log:
                log.write(("\nRUNNER ERROR: " + str(error) + "\n").encode())
            if process is not None and process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait(timeout=10)
                except (ProcessLookupError, subprocess.TimeoutExpired):
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                    except ProcessLookupError:
                        pass
        row.update({
            "exit_code": code, "timed_out": timed_out, "ended": now(),
            "elapsed_seconds": time.monotonic() - began,
            "log_sha256": digest(path),
        })
        passed = code == 0 and not timed_out and "launch_or_wait_error" not in row
        if tests:
            row["test_summary"] = reported_tests(path)
            passed = passed and row["test_summary"].get("complete_success_marker", False)
        row["status"] = "passed" if passed else "failed"
        record["commands"].append(row)
        record.pop("active_command", None)
        if not passed:
            record["errors"].append(label + " did not pass; see " + path.name)
        save()
        print(
            "END " + label + " status=" + row["status"] +
            " exit=" + str(code), flush=True)
        if tests:
            print(json.dumps({"label": label, "test_summary": row["test_summary"]}), flush=True)
        if not passed:
            print("\n".join(path.read_text(errors="replace").splitlines()[-25:]), flush=True)
        return row

    save()
    try:
        if not flutter.is_file() or not dart.is_file():
            raise ValueError("Prepared Flutter and Dart executables must exist.")
        if dart != (sdk_root / "bin/cache/dart-sdk/bin/dart").resolve():
            raise ValueError("--dart must be the Dart executable from the supplied Flutter SDK.")
        contract_path = repo / "tools/proofing/verify_integration.py"
        spec = importlib.util.spec_from_file_location("quds_editor_integration_contract", contract_path)
        if spec is None or spec.loader is None:
            raise ValueError("Could not import the committed integration helper.")
        contract = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = contract
        spec.loader.exec_module(contract)
        if Path(contract.REPO).resolve() != repo:
            raise ValueError("Integration helper resolved a different checkout.")
        record["integration_contract_sha256"] = digest(contract_path)
        record["source_commit"] = git("rev-parse", "HEAD")
        record["source_tree"] = git("rev-parse", "HEAD^{tree}")
        if record["source_commit"] != args.expected_source:
            raise ValueError("Checkout is not the expected frozen source commit.")
        contract.require_committed_sources()
        names = list(contract.EDITOR_TESTS)
        if len(names) != 23 or len(set(names)) != 23:
            raise ValueError("Expected exactly 23 unique baseline editor test paths.")
        names += [
            "host_fonts", "office_direction_chord", "office_input_ownership",
            "office_units", "paint_run_text_unicode", "word_run_metrics",
            "word_shaped_wrap", "word_underline_paint",
        ]
        if len(names) != 31 or len(set(names)) != 31:
            raise ValueError("Expected exactly 31 unique final editor test paths.")
        selected = ["test/" + name + "_test.dart" for name in names]
        missing = [name for name in selected if not (editor / name).is_file()]
        if missing:
            raise ValueError("Missing selected test files: " + ", ".join(missing))
        record["editor_test_files"] = selected
        lock = repo / "pubspec.lock"
        config = repo / ".dart_tool/package_config.json"
        if not lock.is_file() or not config.is_file():
            raise ValueError("Resolve the real repository workspace before this runner.")
        config_data = json.loads(config.read_text())
        indexed = {item["name"]: item for item in config_data["packages"]}
        expected_roots = {
            "legacy_doc_parser": repo / "packages/legacy_doc_parser",
            "quds_office_engine": engine,
            "quds_office_editor": editor,
            "quds_reports": repo / "packages/quds_reports",
            "quds_proofing_harper": repo / "packages/quds_proofing_harper",
            "quds_office_studio": example,
        }
        package_roots = {}
        for name, expected in expected_roots.items():
            if name not in indexed:
                raise ValueError("Real workspace configuration lacks package " + name)
            resolved_uri = urlparse(urljoin(config.as_uri(), indexed[name]["rootUri"]))
            if resolved_uri.scheme != "file":
                raise ValueError("Expected a local workspace package for " + name)
            resolved_root = Path(unquote(resolved_uri.path)).resolve()
            if resolved_root != expected.resolve():
                raise ValueError("Workspace package points outside the expected source: " + name)
            package_roots[name] = {
                "root": str(resolved_root),
                "language_version": indexed[name].get("languageVersion"),
            }
        record["workspace_packages"] = package_roots
        record["workspace_package_count"] = len(config_data["packages"])
        lock_before = digest(lock)
        config_before = digest(config)
        shutil.copyfile(lock, out / "workspace-before.pubspec.lock")
        shutil.copyfile(config, out / "workspace-before.package_config.json")
        record["lock_sha256_before"] = lock_before
        record["package_config_sha256_before"] = config_before
        source_before = contract.source_hashes()
        runtime_before = capture_runtime()
        record["source_before"] = manifest("source-before.json.gz", source_before)
        record["runtime_before"] = manifest("runtime-before.json.gz", runtime_before)
        web_before = capture_web()
        record["web_artifacts_before"] = manifest("web-artifacts-before.json.gz", web_before)
        record["preflight"] = "passed"
        save()

        run("flutter-version", [str(flutter), "--version", "--machine"], repo, 60)
        run("dart-version", [str(dart), "--version"], repo, 30)
        try:
            actual = json.loads((out / "flutter-version.log").read_text())
            record["actual_flutter_runtime"] = actual
            record["pinned_runtime_identity_matches"] = (
                actual.get("frameworkRevision") == EXPECTED_FLUTTER and
                actual.get("dartSdkVersion") == "3.13.7"
            )
            if not record["pinned_runtime_identity_matches"]:
                record["errors"].append("Actual Flutter/Dart identity differs from the pinned runtime.")
        except (ValueError, OSError) as error:
            record["errors"].append("Could not parse actual Flutter identity: " + str(error))

        run(
            "engine-analyze",
            [str(dart), "analyze", "--fatal-infos", "lib", "test", "tool"],
            engine, 300,
        )
        run(
            "editor-analyze",
            [str(dart), "analyze", "--fatal-infos", "lib", *selected],
            editor, 300,
        )
        run(
            "example-analyze",
            [str(dart), "analyze", "--fatal-infos", "lib"],
            example, 180,
        )
        run(
            "editor-tests",
            [str(flutter), "test", "--no-pub", "--concurrency=2",
             "--reporter=expanded", *selected],
            editor, 900, tests=True,
        )
        run(
            "editor-ime-reattachment",
            [str(flutter), "test", "--no-pub", "--reporter=expanded",
             "test/embed_test.dart", "--plain-name",
             "tapping the canvas reattaches IME after another client steals it"],
            editor, 240, tests=True,
        )
        build_row = run(
            "example-web-build",
            [str(flutter), "build", "web", "--release", "--no-pub",
             "--no-wasm-dry-run"],
            example, 900,
        )
        web_after = capture_web()
        record["web_artifacts_after"] = manifest("web-artifacts-after.json.gz", web_after)
        record["web_artifact_count"] = len(web_after)
        record["web_artifact_bytes"] = sum(item["bytes"] for item in web_after.values())
        record["web_artifact_interpretation"] = (
            "Successful build output" if build_row["status"] == "passed"
            else "Partial or pre-existing output; not a successful web bundle"
        )
        if build_row["status"] == "passed" and not {"index.html", "main.dart.js"}.issubset(web_after):
            record["errors"].append("Web command returned success but required JS build outputs are missing.")
    except Exception as error:
        record["errors"].append("Preflight or harness failure: " + str(error))
        if record.get("preflight") != "passed":
            record["preflight"] = "failed"
        print("HARNESS_ERROR " + str(error), flush=True)
    finally:
        if contract is not None and source_before is not None:
            try:
                source_after = contract.source_hashes()
                runtime_after = capture_runtime()
                record["source_after"] = manifest("source-after.json.gz", source_after)
                record["runtime_after"] = manifest("runtime-after.json.gz", runtime_after)
                record["source_differences"] = differences(source_before, source_after)
                record["runtime_differences"] = differences(runtime_before, runtime_after)
                record["source_unchanged"] = source_before == source_after
                record["runtime_unchanged"] = runtime_before == runtime_after
                record["source_commit_after"] = git("rev-parse", "HEAD")
                record["source_commit_unchanged"] = record["source_commit_after"] == args.expected_source
                lock = repo / "pubspec.lock"
                config = repo / ".dart_tool/package_config.json"
                record["lock_sha256_after"] = digest(lock) if lock.is_file() else None
                record["package_config_sha256_after"] = digest(config) if config.is_file() else None
                record["lock_unchanged"] = record["lock_sha256_after"] == lock_before
                record["package_config_unchanged"] = record["package_config_sha256_after"] == config_before
                if lock.is_file():
                    shutil.copyfile(lock, out / "workspace-after.pubspec.lock")
                if config.is_file():
                    shutil.copyfile(config, out / "workspace-after.package_config.json")
                for key in (
                    "source_unchanged", "runtime_unchanged",
                    "source_commit_unchanged", "lock_unchanged",
                    "package_config_unchanged",
                ):
                    if record.get(key) is not True:
                        record["errors"].append(key + " was not true.")
            except Exception as error:
                record["errors"].append("Final provenance capture failed: " + str(error))
        record["ended"] = now()
        record["test_summaries"] = {
            row["label"]: row["test_summary"]
            for row in record["commands"] if "test_summary" in row
        }
        record["command_results"] = {
            row["label"]: row["status"] for row in record["commands"]
        }
        record["status"] = (
            "passed" if record.get("preflight") == "passed" and
            len(record["commands"]) == 8 and not record["errors"] and
            all(row["status"] == "passed" for row in record["commands"])
            else "failed"
        )
        save()
        summary = {
            key: record.get(key) for key in (
                "status", "source_commit", "source_tree", "preflight",
                "command_results", "test_summaries", "source_unchanged",
                "runtime_unchanged", "lock_unchanged",
                "package_config_unchanged", "source_commit_unchanged",
                "web_artifact_count", "web_artifact_bytes",
                "web_artifact_interpretation", "errors",
            )
        }
        write_json(out / "summary.json", summary)
        print("VALIDATION_COMPLETE " + json.dumps(summary), flush=True)
    return 0 if record["status"] == "passed" else 1

if __name__ == "__main__":
    raise SystemExit(main())
