#!/usr/bin/env python3
"""Execute one already-published seal; preserve runtime and process evidence."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from freeze_candidate import ROOT, OUT, package_configuration, runtime, sha, sources


def sanitize(text: str) -> str:
    substitutions = {str(ROOT): "QUDS_REPOSITORY"}
    for key in ("QUDS_SPACY_LIBRARY", "QUDS_SPACY_BUNDLE", "PUB_CACHE", "FLUTTER_ROOT", "TMPDIR"):
        if os.environ.get(key):
            substitutions[os.environ[key]] = key
    for source in sorted(substitutions, key=len, reverse=True):
        text = text.replace(source, substitutions[source])
    return text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seal", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    seal_path, report_path = args.seal.resolve(), args.report.resolve()
    seal = json.loads(seal_path.read_text())
    if sources() != seal["source_sha256"]:
        raise RuntimeError("Source changed before invoking the sealed candidate")
    config_before = package_configuration()
    if config_before != seal["package_configuration"]:
        raise RuntimeError("Dart package configuration changed before execution")
    before = runtime()
    if any(seal[key] != value for key, value in before.items()):
        raise RuntimeError("Runtime changed before invoking the sealed candidate")
    receipt_path = Path(str(report_path) + ".runner.json")
    log_path = report_path.with_suffix(".log")
    if report_path.exists() or log_path.exists():
        raise RuntimeError("Refuse to overwrite an existing attempt")
    command = [
        "dart", f"--packages={ROOT / '.dart_tool/package_config.json'}",
        str(ROOT / "packages/quds_proofing_spacy/tool/evaluate_grammar.dart"),
        "--root", str(ROOT), "--phase", "qualification",
        "--panel", str(OUT / "qualification-panel.json"),
        "--library", os.environ["QUDS_SPACY_LIBRARY"],
        "--bundle", os.environ["QUDS_SPACY_BUNDLE"],
        "--seal", str(seal_path), "--report", str(report_path),
    ]
    receipt = {
        "schema": "quds.spacy.grammar.qualification-process.v1",
        "started_at": datetime.now(timezone.utc).isoformat(),
        "status": "pending",
        "command": [sanitize(value) for value in command],
        "candidate_commit": seal["candidate_commit"],
        "seal_sha256": sha(seal_path),
        "runner_sha256": sha(Path(__file__)),
        "runtime_before": before,
        "package_configuration_before": config_before,
        "native_acceptance_executions": 0,
        "ci_queries_waits_reruns": 0,
    }
    with receipt_path.open("x") as handle:
        handle.write(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    start = time.monotonic()
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, start_new_session=True)
    try:
        raw, _ = process.communicate(timeout=600)
        code = process.returncode
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            raw, _ = process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            raw, _ = process.communicate()
        code = 124
    output = sanitize(raw.decode("utf-8", "replace"))
    with log_path.open("x") as handle:
        handle.write(output)
    validation_errors = []
    after, config_after, source_matches, report = None, None, False, {}
    try:
        after = runtime()
    except Exception as error:
        validation_errors.append("Runtime validation: " + sanitize(str(error)))
    try:
        config_after = package_configuration()
        source_matches = sources() == seal["source_sha256"]
    except Exception as error:
        validation_errors.append("Source/configuration validation: " + sanitize(str(error)))
    try:
        report = json.loads(report_path.read_text()) if report_path.exists() else {}
    except Exception as error:
        validation_errors.append("Report validation: " + sanitize(str(error)))
    passed = (code == 0 and report.get("passed") is True and before == after and
              source_matches and config_before == config_after and not validation_errors)
    receipt.update({
        "status": "passed" if passed else "failed",
        "exit_code": code,
        "elapsed_seconds": time.monotonic() - start,
        "finished_at": datetime.now(timezone.utc).isoformat(),
        "runtime_after": after,
        "runtime_unchanged": before == after,
        "package_configuration_after": config_after,
        "package_configuration_unchanged": config_before == config_after,
        "source_still_matches_seal": source_matches,
        "validation_errors": validation_errors,
        "report_sha256": sha(report_path) if report_path.exists() else None,
        "log_sha256": sha(log_path),
    })
    pending = Path(str(receipt_path) + ".next")
    with pending.open("x") as handle:
        handle.write(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    pending.replace(receipt_path)
    print(output, end="")
    print(json.dumps({"process_status": receipt["status"], "exit_code": code,
                      "runtime_unchanged": before == after,
                      "elapsed_seconds": receipt["elapsed_seconds"]}))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
