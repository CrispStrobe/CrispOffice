#!/usr/bin/env python3
"""Run the identical fill witness against two exact Git source snapshots."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


EVIDENCE = Path(__file__).resolve().parent
ROOT = EVIDENCE.parents[2]
PREFIX = "packages/quds_office_engine/"
SOURCES = [
    "lib/src/sheet/styles/sml_styles.dart",
    "lib/src/xml/namespaces.dart",
    "lib/src/xml/xml_node.dart",
    "lib/src/xml/xml_reader.dart",
    "lib/src/xml/xml_writer.dart",
]
FIXTURE = PREFIX + "test/fixtures/fidelity/sheet-fill-native.xml"


def git(*args: str) -> bytes:
    return subprocess.check_output(["git", *args], cwd=ROOT)


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart", default="dart")
    parser.add_argument("--baseline", default="6e8ee9476c99676886f9d424abdb399cffe37882")
    parser.add_argument("--candidate", default="9219189e9a07103b029eaeb050658ab819356591")
    args = parser.parse_args()
    commits = {
        label: git("rev-parse", "--verify", ref + "^{commit}").decode().strip()
        for label, ref in [("baseline", args.baseline), ("candidate", args.candidate)]
    }
    harness = (EVIDENCE / "fill-control.dart.txt").read_bytes()
    fixture = git("show", f"{commits['candidate']}:{FIXTURE}")
    environment = os.environ | {
        "CI": "true",
        "BOT": "true",
        "DART_SUPPRESS_ANALYTICS": "true",
        "FLUTTER_SUPPRESS_ANALYTICS": "true",
    }
    runtime = subprocess.check_output(
        [args.dart, "--version"], stderr=subprocess.STDOUT, env=environment
    ).decode().strip()
    report = {
        "format_version": 1,
        "runtime": runtime,
        "harness": {"path": "fill-control.dart.txt", "sha256": digest(harness)},
        "collector_sha256": digest(Path(__file__).read_bytes()),
        "fixture": {
            "path": FIXTURE,
            "commit": commits["candidate"],
            "sha256": digest(fixture),
        },
        "snapshots": {},
        "scope": "Style derivation and native fill identity only; package/editor tests are separate.",
    }
    with tempfile.TemporaryDirectory(
        prefix="quds-fill-controls-", dir=environment.get("TMPDIR") or ROOT.parent
    ) as temp:
        work = Path(temp)
        fixture_path = work / "native-styles.xml"
        fixture_path.write_bytes(fixture)
        for label, commit in commits.items():
            snapshot = work / label
            snapshot.mkdir()
            (snapshot / "check.dart").write_bytes(harness)
            source_hashes = {}
            for path in SOURCES:
                source = git("show", f"{commit}:{PREFIX}{path}")
                destination = snapshot / path
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(source)
                source_hashes[PREFIX + path] = digest(source)
            result = subprocess.run(
                [args.dart, "check.dart", str(fixture_path)],
                cwd=snapshot,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=60,
                check=False,
            )
            log = result.stdout
            (EVIDENCE / f"{label}-controls.log").write_bytes(log)
            match = re.search(rb"Failures: (\d+)/(\d+)", log)
            failures, checks = (int(value) for value in match.groups()) if match else (None, None)
            report["snapshots"][label] = {
                "commit": commit,
                "source_sha256": source_hashes,
                "exit_code": result.returncode,
                "failed_checks": failures,
                "total_checks": checks,
                "log": f"{label}-controls.log",
                "log_sha256": digest(log),
            }
    baseline = report["snapshots"]["baseline"]
    candidate = report["snapshots"]["candidate"]
    report["accepted"] = (
        baseline["exit_code"] == 1
        and baseline["failed_checks"] == 9
        and baseline["total_checks"] == 13
        and candidate["exit_code"] == 0
        and candidate["failed_checks"] == 0
        and candidate["total_checks"] == 13
    )
    (EVIDENCE / "source-controls.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"accepted": report["accepted"], "baseline_failures": baseline["failed_checks"], "candidate_failures": candidate["failed_checks"]}))
    if not report["accepted"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
