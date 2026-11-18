#!/usr/bin/env python3
"""Preserve source-bound focused tests of the latest reconciled Office main."""
from pathlib import Path
import hashlib
import json
import os
import re
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
MAIN = "23f3b4204fce45d38a103e3159bdc7f1e8d37c4e"
BASE = "4b2b4e78839d2997a583b7ab1346e2fa537a8ac4"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def snapshot(paths):
    return {p: {"sha256": sha(ROOT / p), "bytes": (ROOT / p).stat().st_size}
            for p in paths}


def clean(text):
    for original, name in [(str(ROOT.parent / "w6-runtime"), "VALIDATION_RUNTIME"),
                           (str(ROOT), "QUDS_REPOSITORY")]:
        text = text.replace(original, name)
    return text


def main():
    result = OUT / "first.json"
    if result.exists():
        raise SystemExit("Refuse to overwrite a retained attempt")
    paths = git("diff", "--name-only", BASE, MAIN, "--", "packages").decode().splitlines()
    before = snapshot(paths)
    comparison = {}
    for path in paths:
        expected = hashlib.sha256(git("show", MAIN + ":" + path)).hexdigest()
        index = git("rev-parse", ":" + path).decode().strip()
        remote_blob = git("rev-parse", MAIN + ":" + path).decode().strip()
        comparison[path] = {"main_sha256": expected, "index_blob": index,
                            "main_blob": remote_blob,
                            "matches_main": before[path]["sha256"] == expected and index == remote_blob}
    assert all(item["matches_main"] for item in comparison.values())
    record = {
        "schema": "quds.spacy.w6.main_refresh_controls.v1",
        "source_head_before": git("rev-parse", "HEAD").decode().strip(),
        "incoming_main": MAIN,
        "incoming_base": BASE,
        "source_before": before,
        "index_and_worktree_comparison": comparison,
        "all_incoming_office_paths_match_main": True,
        "lock_before_sha256": sha(ROOT / "pubspec.lock"),
        "ci_queried_or_waited": False,
        "qualification_panel_read": False,
        "source_modified_by_runner": False,
        "commands": [],
        "status": "running",
    }
    result.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    tests = ["ods_sheet_writer_test.dart", "sheet_save_cache_and_freeze_test.dart",
             "odt_frame_common_style_test.dart", "odt_inline_field_fidelity_test.dart",
             "sheet_conditional_fidelity_test.dart", "sheet_conditional_rendering_test.dart",
             "odt_complex_field_fidelity_test.dart", "odt_section_fidelity_test.dart"]
    commands = [
        ("engine", ["flutter", "test", "--no-pub", "--concurrency=1",
                    *["packages/quds_office_engine/test/" + name for name in tests],
                    "--reporter", "expanded"], {}),
        ("studio", ["flutter", "test", "--no-pub", "--concurrency=1",
                    "packages/quds_office_editor/example/test/widget_test.dart",
                    "--reporter", "expanded"], {}),
    ]
    for label, zone in [("calendar-utc", "UTC"), ("calendar-berlin", "Europe/Berlin"),
                        ("calendar-los-angeles", "America/Los_Angeles")]:
        commands.append((label, ["dart", "--packages=.dart_tool/package_config.json",
                                str((OUT / "calendar_boundary_probe.dart").relative_to(ROOT))], {"TZ": zone}))
    for label, command, extra_env in commands:
        start = time.monotonic()
        process = subprocess.Popen(command, cwd=ROOT, env={**os.environ, **extra_env},
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            raw, _ = process.communicate(timeout=240)
            code = process.returncode
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                raw, _ = process.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                raw, _ = process.communicate()
            code = 124
        output = clean(raw.decode("utf-8", "replace"))
        log = OUT / (label + ".log")
        log.write_text(output)
        counts = re.findall(r"\+(\d+)(?:\s+~\d+)?(?:\s+-\d+)?:", output)
        entry = {"label": label, "argv": command, "environment": extra_env,
                 "exit_code": code, "elapsed_seconds": time.monotonic() - start,
                 "log": log.name, "log_sha256": sha(log)}
        if counts:
            entry["passed_tests"] = int(counts[-1]) if code == 0 else None
        if label.startswith("calendar-"):
            try:
                probe = json.loads(output)
                entry["passed_cases"] = probe["passed"]
                entry["failed_cases"] = probe["failed"]
            except (ValueError, KeyError):
                entry["probe_setup_failure"] = True
        record["commands"].append(entry)
        result.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
        print(json.dumps(entry), flush=True)
    record["source_after"] = snapshot(paths)
    record["source_unchanged"] = record["source_after"] == before
    record["lock_after_sha256"] = sha(ROOT / "pubspec.lock")
    record["lock_unchanged"] = record["lock_after_sha256"] == record["lock_before_sha256"]
    record["runner_sha256"] = sha(Path(__file__))
    record["calendar_probe_sha256"] = sha(OUT / "calendar_boundary_probe.dart")
    passed = record["source_unchanged"] and record["lock_unchanged"] and all(c["exit_code"] == 0 for c in record["commands"])
    record["status"] = "passed" if passed else "failed"
    result.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": record["status"], "source_unchanged": record["source_unchanged"]}), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
