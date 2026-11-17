#!/usr/bin/env python3
"""Run focused local controls for the reconciled Office merge, without Pub/CI."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time


ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
MERGE = "ec4aeefe1be6ce1868ee7eebf004c07b25d4108a"
SOURCES = [
    "packages/quds_office_editor/example/test/widget_test.dart",
    "packages/quds_office_engine/lib/src/sheet/model/sml_analysis.dart",
    "packages/quds_office_engine/lib/src/sheet/model/sml_conditional_format.dart",
    "packages/quds_office_engine/lib/src/sheet/model/sml_workbook.dart",
    "packages/quds_office_engine/lib/src/sheet/serial/sheet_serial.dart",
    "packages/quds_office_engine/lib/src/word/serial/odt_document_writer.dart",
    "packages/quds_office_engine/test/odt_complex_field_fidelity_test.dart",
    "packages/quds_office_engine/test/odt_section_fidelity_test.dart",
    "packages/quds_office_engine/test/sheet_conditional_fidelity_test.dart",
    "packages/quds_office_engine/test/sheet_conditional_rendering_test.dart",
]
COMMANDS = [
    ("engine", [
        "flutter", "test", "--no-pub", "--concurrency=1",
        "packages/quds_office_engine/test/sheet_conditional_fidelity_test.dart",
        "packages/quds_office_engine/test/sheet_conditional_rendering_test.dart",
        "packages/quds_office_engine/test/odt_complex_field_fidelity_test.dart",
        "packages/quds_office_engine/test/odt_section_fidelity_test.dart",
        "--reporter", "expanded",
    ]),
    ("studio", [
        "flutter", "test", "--no-pub", "--concurrency=1",
        "packages/quds_office_editor/example/test/widget_test.dart",
        "--reporter", "expanded",
    ]),
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot():
    return {name: {"sha256": sha(ROOT / name), "bytes": (ROOT / name).stat().st_size}
            for name in SOURCES}


def sanitize(text):
    replacements = [(str(ROOT), "QUDS_REPOSITORY")]
    for name in ("FLUTTER_ROOT", "PUB_CACHE", "QUDS_SPACY_BUNDLE", "QUDS_SPACY_LIBRARY"):
        value = os.environ.get(name)
        if value:
            replacements.append((value, name))
    for source, replacement in sorted(replacements, key=lambda p: len(p[0]), reverse=True):
        text = text.replace(source, replacement)
    return text


def main():
    result = OUT / "receipt.json"
    if result.exists() or any((OUT / (name + ".log")).exists() for name, _ in COMMANDS):
        raise SystemExit("Refuse to overwrite previous controls/evidence")
    before = snapshot()
    expected = {}
    for path in SOURCES:
        data = subprocess.check_output(["git", "show", MERGE + ":" + path], cwd=ROOT)
        expected[path] = hashlib.sha256(data).hexdigest()
    assert all(before[path]["sha256"] == expected[path] for path in SOURCES)
    record = {
        "schema": "quds.spacy.w6.office_merge_controls.v1",
        "scope": "Focused local tests for ten Office source/test files newly reconciled before W6. Unrelated grammar work may continue; these ten paths must stay exact throughout.",
        "source_commit": MERGE,
        "source_tree": subprocess.check_output(["git", "rev-parse", MERGE + "^{tree}"], cwd=ROOT, text=True).strip(),
        "source_before": before,
        "source_matches_merge_before": True,
        "workspace_lock_before_sha256": sha(ROOT / "pubspec.lock"),
        "runtime_receipt_sha256": sha(OUT.parent / "runtime/runtime-restoration.json"),
        "commands": [],
        "ci_queried_or_waited": False,
        "implicit_pub": False,
        "status": "running",
    }
    result.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    for label, command in COMMANDS:
        start = time.monotonic()
        process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        timed_out = False
        try:
            raw, _ = process.communicate(timeout=240)
            code = process.returncode
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                raw, _ = process.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                raw, _ = process.communicate()
            code = 124
        output = sanitize(raw.decode("utf-8", "replace"))
        log = OUT / (label + ".log")
        log.write_text(output)
        counts = re.findall(r"\+(\d+)(?:\s+~\d+)?(?:\s+-\d+)?:", output)
        total = int(counts[-1]) if counts else None
        record["commands"].append({
            "label": label, "argv": command, "cwd": "repository root",
            "exit_code": code, "timed_out": timed_out,
            "elapsed_seconds": time.monotonic() - start,
            "passed_tests": total if code == 0 else None,
            "log": log.name, "log_sha256": sha(log),
        })
        result.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
        print(json.dumps(record["commands"][-1]), flush=True)
    record["source_after"] = snapshot()
    record["source_unchanged"] = before == record["source_after"]
    record["workspace_lock_after_sha256"] = sha(ROOT / "pubspec.lock")
    record["workspace_lock_unchanged"] = (record["workspace_lock_after_sha256"] ==
                                          record["workspace_lock_before_sha256"])
    passed = (record["source_unchanged"] and record["workspace_lock_unchanged"] and
              all(c["exit_code"] == 0 for c in record["commands"]))
    record["status"] = "passed" if passed else "failed"
    record["runner_sha256"] = sha(Path(__file__))
    result.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": record["status"], "source_unchanged": record["source_unchanged"]}), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
