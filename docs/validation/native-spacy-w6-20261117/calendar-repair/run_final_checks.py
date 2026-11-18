#!/usr/bin/env python3
"""Preserve the focused civil-date repair checks after incoming Office main."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
SOURCE = "packages/quds_office_engine/lib/src/sheet/model/sml_conditional_format.dart"
TEST = "packages/quds_office_engine/test/sheet_time_period_calendar_test.dart"
PROBE = "docs/validation/native-spacy-w6-20261117/main-refresh-controls/calendar_boundary_probe.dart"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def capture(paths):
    return {str(p.relative_to(ROOT)): sha(p) for p in sorted(paths)}


def main():
    destination = OUT / "final.json"
    if destination.exists():
        raise SystemExit("Refuse to overwrite retained final checks")
    paths = {ROOT / SOURCE, ROOT / TEST, ROOT / PROBE, ROOT / "pubspec.lock"}
    paths.update((ROOT / "packages/quds_office_engine/lib/src/proofing").rglob("*.dart"))
    paths.update((ROOT / "packages/quds_proofing_spacy/lib").rglob("*.dart"))
    before = capture(paths)
    record = {
        "schema": "quds.sheet.calendar_civil_date_repair.v1",
        "source_before": before,
        "incoming_main": "23f3b4204fce45d38a103e3159bdc7f1e8d37c4e",
        "initial_failure_receipt": "../main-refresh-controls/first.json",
        "initial_failure_receipt_sha256": sha(OUT.parent / "main-refresh-controls/first.json"),
        "original_source": "initial-resolver.dart",
        "original_source_sha256": sha(OUT / "initial-resolver.dart"),
        "scope": "Two civil-date constructor changes in incoming calendar-relative sheet code; no grammar/proofing changes.",
        "commands": [],
        "ci_queried_or_waited": False,
        "status": "running",
    }
    destination.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    tests = ["ods_sheet_writer_test.dart", "sheet_save_cache_and_freeze_test.dart",
             "sheet_conditional_fidelity_test.dart", "sheet_conditional_rendering_test.dart",
             "sheet_time_period_calendar_test.dart"]
    commands = [("sheet-regressions-utc", ["flutter", "test", "--no-pub", "--concurrency=1",
                 *["packages/quds_office_engine/test/" + name for name in tests],
                 "--reporter", "expanded"], {"TZ": "UTC"})]
    for label, zone in [("berlin", "Europe/Berlin"), ("los-angeles", "America/Los_Angeles")]:
        commands.append(("calendar-tests-" + label,
                         ["flutter", "test", "--no-pub", "--concurrency=1", TEST,
                          "--reporter", "expanded"], {"TZ": zone}))
    for label, zone in [("utc", "UTC"), ("berlin", "Europe/Berlin"), ("los-angeles", "America/Los_Angeles")]:
        commands.append(("retained-probe-" + label,
                         ["dart", "--packages=.dart_tool/package_config.json", PROBE], {"TZ": zone}))
    commands.append(("analysis", ["dart", "analyze", SOURCE, TEST], {}))
    for label, argv, extra_env in commands:
        started = time.monotonic()
        result = subprocess.run(argv, cwd=ROOT, env={**os.environ, **extra_env},
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        output = result.stdout.decode("utf-8", "replace")
        output = output.replace(str(ROOT.parent / "w6-runtime"), "VALIDATION_RUNTIME")
        output = output.replace(str(ROOT), "QUDS_REPOSITORY")
        log = OUT / (label + ".log")
        log.write_text(output)
        entry = {"label": label, "argv": argv, "environment": extra_env,
                 "exit_code": result.returncode, "elapsed_seconds": time.monotonic() - started,
                 "log": log.name, "log_sha256": sha(log)}
        counts = re.findall(r"\+(\d+)(?:\s+~\d+)?(?:\s+-\d+)?:", output)
        if counts and result.returncode == 0:
            entry["passed_tests"] = int(counts[-1])
        if label.startswith("retained-probe"):
            probe = json.loads(output)
            entry["passed_cases"] = probe["passed"]
            entry["failed_cases"] = probe["failed"]
        record["commands"].append(entry)
        destination.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
        print(json.dumps(entry), flush=True)
    record["source_after"] = capture(paths)
    record["sources_unchanged"] = before == record["source_after"]
    record["runner_sha256"] = sha(Path(__file__))
    record["status"] = "passed" if record["sources_unchanged"] and all(c["exit_code"] == 0 for c in record["commands"]) else "failed"
    destination.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": record["status"], "sources_unchanged": record["sources_unchanged"]}), flush=True)
    return 0 if record["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
