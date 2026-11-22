#!/usr/bin/env python3
"""Run local Word Split qualification; never queries hosted CI.

Use a resolved repository workspace and an installed Dart SDK. An optional
test-wrapper permits the recorded isolated, exact-lock engine test runtime.
All subprocesses, raw outcomes and before/after input hashes are retained.
"""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--dart", default="dart")
    parser.add_argument("--node", default="node")
    parser.add_argument("--test-wrapper")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--concurrency", type=int, default=2)
    args = parser.parse_args()
    root = args.root.resolve()
    engine = root / "packages/quds_office_engine"
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    commands = []

    names = subprocess.check_output(
        ["git", "ls-files", "-z"], cwd=root
    ).decode().split("\0")
    prefixes = (
        "packages/quds_office_engine/lib/",
        "packages/quds_office_engine/test/",
        "packages/quds_office_engine/tool/macros/",
        "packages/quds_office_engine/example/macros/",
        "packages/legacy_doc_parser/",
    )
    manifests = {
        ".fvmrc", "pubspec.yaml", "pubspec.lock", "analysis_options.yaml",
        "packages/quds_office_engine/pubspec.yaml",
        "packages/quds_office_engine/analysis_options.yaml",
    }
    inputs = sorted(
        name for name in names
        if name and (name.startswith(prefixes) or name in manifests)
        and (root / name).is_file()
    )

    def snapshot():
        return {name: digest(root / name) for name in inputs}

    before = snapshot()
    write_json(output / "inputs-before.json", before)
    write_json(output / "invocation.json", {
        "source_commit": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=root
        ).decode().strip(),
        "runner_sha256": digest(Path(__file__).resolve()),
        "arguments": vars(args) | {"root": str(root), "output": str(output)},
        "dart_version": subprocess.check_output([args.dart, "--version"]).decode().strip(),
        "node_version": subprocess.check_output([args.node, "--version"]).decode().strip(),
        "package_config_sha256": digest(root / ".dart_tool/package_config.json"),
    })

    def run(name, command, timeout=2400):
        stdout = output / f"{name}.stdout"
        stderr = output / f"{name}.stderr"
        entry = {"name": name, "command": command, "cwd": str(engine), "started": time.time()}
        print(f"Starting {name}", flush=True)
        with stdout.open("wb") as out, stderr.open("wb") as err:
            try:
                result = subprocess.run(command, cwd=engine, stdout=out, stderr=err, timeout=timeout)
                entry["exit_code"] = result.returncode
            except subprocess.TimeoutExpired:
                entry["exit_code"] = None
                entry["timeout_seconds"] = timeout
        entry.update({"finished": time.time(), "stdout_sha256": digest(stdout), "stderr_sha256": digest(stderr)})
        commands.append(entry)
        write_json(output / "commands.json", commands)
        print(f"Finished {name}: {entry['exit_code']}", flush=True)
        if entry["exit_code"] != 0:
            raise RuntimeError(f"{name} failed; inspect retained raw streams")
        return stdout

    suites = sorted({
        str(path.relative_to(engine))
        for pattern in ("office_vba*_test.dart", "office_macro*_test.dart")
        for path in (engine / "test").glob(pattern)
    } | {
        "test/office_operations_test.dart", "test/office_steps_test.dart",
        "test/word_step_atomicity_test.dart", "test/word_structure_steps_test.dart",
        "test/table_grid_steps_test.dart", "test/word_table_grid_addressing_test.dart",
        "test/sheet_macro_preservation_test.dart", "test/word_directional_paragraph_io_test.dart",
        "test/odt_outline_compatibility_test.dart", "test/odt_reader_styles_test.dart",
        "test/odt_reader_script_styles_test.dart", "test/odt_reader_libreoffice_defaults_test.dart",
        "test/odt_reader_guards_test.dart", "test/odt_paragraph_properties_test.dart",
        "test/odt_document_reader_test.dart", "test/odt_merged_table_zotero_test.dart",
        "test/odt_zotero_note_numbering_test.dart", "test/odt_zotero_writer_test.dart",
    })
    write_json(output / "suite-selection.json", suites)
    try:
        test_command = [args.test_wrapper] if args.test_wrapper else [args.dart, "test"]
        log = run("tests", test_command + suites + [f"--concurrency={args.concurrency}", "--reporter=json"])
        events = [json.loads(line) for line in log.read_text().splitlines() if line.startswith("{")]
        started = {event["test"]["id"]: event["test"] for event in events if event.get("type") == "testStart"}
        completed = [event for event in events if event.get("type") == "testDone" and not event.get("hidden")]
        cases = [dict(started[event["testID"]], result=event["result"], skipped=event["skipped"]) for event in completed]
        write_json(output / "cases.json", cases)
        summary = {
            "selected_suites": len(suites), "cases": len(cases),
            "passed": sum(case["result"] == "success" and not case["skipped"] for case in cases),
            "failed": sum(case["result"] != "success" for case in cases),
            "skipped": sum(case["skipped"] for case in cases),
            "error_events": sum(event.get("type") == "error" for event in events),
            "terminal_success": any(event.get("type") == "done" and event.get("success") is True for event in events),
        }
        write_json(output / "test-summary.json", summary)
        if summary["failed"] or summary["skipped"] or summary["error_events"] or not summary["terminal_success"]:
            raise RuntimeError("Test event ledger did not satisfy the local acceptance gate")

        changed_dart = [
            "lib/src/automation/office_vba_language.dart", "test/office_vba_split_test.dart",
            "test/office_vba_word_split_integration_test.dart", "test/office_vba_word_split_cli_test.dart",
            "tool/macros/web_vba_split_conformance.dart", "tool/macros/web_vba_word_split_smoke.dart",
            "lib/src/word/serial/odt_reader_styles.dart", "test/odt_outline_compatibility_test.dart",
            "test/support/zotero_converter_fixtures.dart",
        ]
        run("analysis", [args.dart, "analyze", "--fatal-infos", *changed_dart])
        run("format", [args.dart, "format", "--output=none", "--set-exit-if-changed", *changed_dart])
        run("whitespace", ["git", "diff", "--check"])
        for name, source, define, driver in [
            ("split-corpus", "test/fixtures/vba_conformance/split_v1.json", "VBA_CONFORMANCE_BASE64", "tool/macros/web_vba_split_conformance.dart"),
            ("word-report", "example/macros/word_split_report.bas", "WORD_SPLIT_BAS_BASE64", "tool/macros/web_vba_word_split_smoke.dart"),
        ]:
            encoded = base64.b64encode((engine / source).read_bytes()).decode()
            flag = f"-D{define}={encoded}"
            vm = run(name + "-vm", [args.dart, flag, driver])
            javascript = output / (name + ".js")
            run(name + "-compile", [args.dart, "compile", "js", "-O1", flag, driver, "-o", str(javascript)])
            js = run(name + "-node", [args.node, "-e", "globalThis.self = globalThis; require(process.argv[1]);", str(javascript)])
            receipt = {
                "source_sha256": digest(engine / source),
                "equal_parsed_receipts": json.loads(vm.read_text()) == json.loads(js.read_text()),
                "byte_equal": vm.read_bytes() == js.read_bytes(),
                "vm_sha256": digest(vm), "js_sha256": digest(js),
            }
            write_json(output / (name + "-comparison.json"), receipt)
            if not receipt["equal_parsed_receipts"]:
                raise RuntimeError(f"{name} VM/JavaScript receipts differ")
    finally:
        after = snapshot()
        write_json(output / "inputs-after.json", after)
        write_json(output / "input-stability.json", {
            "count": len(before), "unchanged": before == after,
            "changed": [name for name in before if before[name] != after[name]],
        })
    if before != after:
        raise RuntimeError("Qualified inputs changed during the run")
    write_json(output / "accepted.json", {"accepted": True, "inputs": len(before), "tests": summary})


if __name__ == "__main__":
    main()
