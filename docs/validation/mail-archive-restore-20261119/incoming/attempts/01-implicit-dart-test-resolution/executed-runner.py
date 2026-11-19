#!/usr/bin/env python3
"""Fresh focused incoming-branch checks; run after sourcing runtime/env.sh.

Usage: python run_incoming.py engine|editor|studio
Each phase refuses to replace existing evidence. Source snapshots bind the
actual working files, because unrelated mail implementation can proceed while
the independent engine checks run. A later publication must match these hashes.
"""

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

OUT = Path(__file__).resolve().parent
REPO = OUT.parents[3]
RUNTIME = REPO.parent / "runtime"
PARSER = REPO / "docs/validation/mail-archive-portability-20261119/run-local-validation.py"
spec = importlib.util.spec_from_file_location("mail_validation", PARSER)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


def now():
    return datetime.now(timezone.utc).isoformat()


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def compressed(path, value):
    Path(path).write_bytes(gzip.compress(json.dumps(value, sort_keys=True).encode(), mtime=0))


def capture(argv):
    return subprocess.check_output(argv, cwd=REPO, text=True).strip()


def snapshot(phase):
    packages = ["quds_office_engine", "legacy_doc_parser"]
    if phase in ("editor", "studio"):
        packages += ["quds_office_editor", "quds_reports"]
    if phase == "studio":
        packages = [p.name for p in (REPO / "packages").iterdir() if p.is_dir()]
    files = {REPO / "pubspec.yaml", REPO / "pubspec.lock", PARSER, Path(__file__).resolve()}
    for package in packages:
        root = REPO / "packages" / package
        files.update(root.glob("pubspec.yaml"))
        for child in ("lib", "test", "tool", "fonts", "templates", "assets"):
            files.update(p for p in (root / child).rglob("*") if p.is_file())
    if phase == "studio":
        root = REPO / "packages/quds_office_editor/example"
        files.add(root / "pubspec.yaml")
        for child in ("lib", "test", "assets", "fonts"):
            files.update(p for p in (root / child).rglob("*") if p.is_file())
    return {str(p.relative_to(REPO)): {"sha256": sha(p), "bytes": p.stat().st_size}
            for p in sorted(files) if p.is_file()}


SMOKES = {
    "web_smoke": {"revision": 1, "A1": 42, "A2": 84,
                  "lateFailurePreservedBytes": True, "mcpInspection": True},
    "web_vba_smoke": {"language": "vba-excel", "revision": 2, "A3": 42, "B1": 84,
                      "fill": "0A141E", "validationPreservedBytes": True,
                      "lateFailurePreservedBytes": True, "mcpCompileAndRun": True,
                      "numericBoundsAndPrecedence": True},
    "web_vba_procedures_smoke": {"language": "vba-excel", "revision": 2, "steps": 6,
                                 "byValCallerAmount": 21, "exitForCounter": 4, "formulaTotal": 126,
                                 "procedureScopesAndExits": True, "recursionRejected": True,
                                 "sharedWorkBudget": True, "numericBounds": True,
                                 "validationPreservedBytes": True, "lateFailurePreservedBytes": True,
                                 "mcpCompileAndRun": True},
    "web_vba_control_flow_smoke": {"language": "vba-excel", "revision": 2, "steps": 9,
                                   "formulaTotal": 100,
                                   "coldDepthStress": "32 procedure frames / 32 mixed blocks / 63 unary operators",
                                   "orderedCasesAndEagerRangeBounds": True,
                                   "sharedLoopWorkBudget": True, "staticInactiveChecks": True,
                                   "validationPreservedBytes": True, "lateFailurePreservedBytes": True,
                                   "mcpCompileAndRun": True},
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("phase", choices=["engine", "editor", "studio"])
    args = parser.parse_args()
    phase = args.phase
    destination = OUT / phase
    destination.mkdir(exist_ok=False)
    dart = RUNTIME / "bin/dart"
    flutter = RUNTIME / "bin/flutter"
    node = shutil.which("node")
    config = REPO / ".dart_tool/package_config.json"
    dependencies = helper.dependency_manifest(config, RUNTIME / "pub-cache", RUNTIME / "flutter", REPO)
    compressed(destination / "dependencies-before.json.gz", dependencies)
    receipt = {"phase": phase, "status": "running", "started_at_utc": now(),
               "head_at_start": capture(["git", "rev-parse", "HEAD"]), "commands": [],
               "runtime_receipt_sha256": sha(RUNTIME / "runtime.json"),
               "readiness_receipt_sha256": sha(RUNTIME / "readiness-receipt.json"),
               "package_config_sha256": sha(config),
               "runner_sha256": sha(__file__), "parser_sha256": sha(PARSER)}

    def save():
        write_json(destination / "receipt.json", receipt)

    def run(name, argv, cwd, files=None, expected=None, timeout=600):
        d = destination / name
        d.mkdir()
        before = snapshot(phase)
        compressed(d / "source-before.json.gz", before)
        record = {"name": name, "command": [str(x) for x in argv], "cwd": str(cwd),
                  "started_at_utc": now(), "timeout_seconds": timeout,
                  "head_before": capture(["git", "rev-parse", "HEAD"]),
                  "source_before_sha256": sha(d / "source-before.json.gz")}
        write_json(d / "command.json", record)
        start = time.monotonic()
        with (d / "stdout.log").open("wb") as out, (d / "stderr.log").open("wb") as err:
            try:
                result = subprocess.run([str(x) for x in argv], cwd=cwd, stdout=out, stderr=err,
                                        timeout=timeout)
                record["exit_code"] = result.returncode
            except subprocess.TimeoutExpired:
                record["exit_code"] = None
                record["timeout"] = True
        after = snapshot(phase)
        compressed(d / "source-after.json.gz", after)
        record.update(elapsed_seconds=round(time.monotonic() - start, 3), finished_at_utc=now(),
                      head_after=capture(["git", "rev-parse", "HEAD"]),
                      source_after_sha256=sha(d / "source-after.json.gz"),
                      stdout_sha256=sha(d / "stdout.log"), stderr_sha256=sha(d / "stderr.log"),
                      changed_source_paths=sorted(p for p in set(before) | set(after)
                                                  if before.get(p) != after.get(p)))
        record["accepted"] = record["exit_code"] == 0 and not record["changed_source_paths"]
        if files:
            parsed = helper.parse_tests(d / "stdout.log", REPO,
                                        [str((cwd / p).relative_to(REPO)) for p in files], cwd)
            compressed(d / "test-cases.json.gz", parsed)
            record["test_counts"] = {k: parsed[k] for k in ("passed", "failed", "skipped")}
            record["test_cases_sha256"] = sha(d / "test-cases.json.gz")
            record["expected_test_files"] = parsed["expected_files"]
            record["accepted"] &= parsed["accepted"]
        if expected is not None:
            try:
                record["observed"] = json.loads((d / "stdout.log").read_text())
                record["expected"] = expected
                record["accepted"] &= record["observed"] == expected
            except (ValueError, UnicodeError):
                record["accepted"] = False
        write_json(d / "result.json", record)
        receipt["commands"].append(record)
        save()
        print(json.dumps({"name": name, "accepted": record["accepted"],
                          "counts": record.get("test_counts"), "seconds": record["elapsed_seconds"]}), flush=True)
        if not record["accepted"]:
            raise RuntimeError("Required incoming check failed: " + name)

    def tests(name, package, files, widgets=False):
        executable = flutter if widgets else dart
        switches = ["--no-pub"] if widgets else []
        run(name, [executable, "test", *switches, "--concurrency=1", "--reporter=json", *files],
            REPO / "packages" / package, files=files)

    try:
        save()
        if phase == "engine":
            files = sorted(str(p.relative_to(REPO / "packages/quds_office_engine"))
                           for p in (REPO / "packages/quds_office_engine/test").glob("office_*_test.dart")
                           if p.name.startswith(("office_vba_", "office_macro_")))
            tests("macros-vba", "quds_office_engine", files)
            tests("branding-and-structure", "quds_office_engine", ["test/" + p for p in (
                "ods_sheet_reader_test.dart", "word_comment_test.dart", "word_revision_validation_test.dart",
                "word_revision_story_test.dart", "comment_thread_fidelity_test.dart", "odt_comment_fidelity_test.dart",
                "word_step_atomicity_test.dart", "word_structure_steps_test.dart")])
            output = RUNTIME / "incoming-javascript"
            output.mkdir(exist_ok=True)
            for name, expected in SMOKES.items():
                javascript = output / (name + ".js")
                run(name + "-compile", [dart, "compile", "js", "-O1", "tool/macros/" + name + ".dart",
                                       "-o", javascript], REPO / "packages/quds_office_engine")
                run(name + "-node", [node, "-e", "globalThis.self = globalThis; require(process.argv[1])",
                                    javascript], REPO / "packages/quds_office_engine", expected=expected)
                receipt.setdefault("javascript_sha256", {})[name] = sha(javascript)
            run("macos-build-script-syntax", ["bash", "-n", "packages/quds_office_editor/example/tool/build_macos_app.sh"], REPO)
        elif phase == "editor":
            tests("pdf-and-review", "quds_office_editor", ["test/" + p for p in (
                "pdf_save_state_test.dart", "pdf_surface_test.dart", "word_review_controller_test.dart",
                "word_review_dialog_test.dart")], widgets=True)
        else:
            tests("desktop-ribbon-lifecycle", "quds_office_editor/example", ["test/" + p for p in (
                "studio_desktop_menu_test.dart", "studio_file_menu_test.dart", "studio_ribbon_preferences_test.dart",
                "studio_ribbon_customization_test.dart", "widget_test.dart")], widgets=True)
        receipt["status"] = "passed"
    except BaseException as e:
        receipt["status"] = "failed"
        receipt["error"] = repr(e)
        raise
    finally:
        after = helper.dependency_manifest(config, RUNTIME / "pub-cache", RUNTIME / "flutter", REPO)
        compressed(destination / "dependencies-after.json.gz", after)
        receipt["dependencies_unchanged"] = dependencies == after
        receipt["package_config_unchanged"] = receipt["package_config_sha256"] == sha(config)
        receipt["runtime_receipts_unchanged"] = (receipt["runtime_receipt_sha256"] == sha(RUNTIME / "runtime.json")
                                                and receipt["readiness_receipt_sha256"] == sha(RUNTIME / "readiness-receipt.json"))
        if not all(receipt[k] for k in ("dependencies_unchanged", "package_config_unchanged", "runtime_receipts_unchanged")):
            receipt["status"] = "failed"
        receipt["test_totals"] = {key: sum(c.get("test_counts", {}).get(key, 0) for c in receipt["commands"])
                                  for key in ("passed", "failed", "skipped")}
        receipt["finished_at_utc"] = now()
        receipt["head_at_finish"] = capture(["git", "rev-parse", "HEAD"])
        save()


if __name__ == "__main__":
    main()
