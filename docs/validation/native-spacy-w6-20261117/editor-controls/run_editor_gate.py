#!/usr/bin/env python3
"""Run the real editor grammar gate, preserving each source-bound attempt."""
from __future__ import annotations

import argparse
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
GATE = "packages/quds_office_editor/example/test/studio_spacy_grammar_native_gate.dart"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def capture():
    paths = {ROOT / GATE, ROOT / "pubspec.lock", ROOT / "pubspec.yaml"}
    for package in ("quds_office_engine", "quds_office_editor", "quds_proofing_spacy"):
        base = ROOT / "packages" / package
        paths.update((base / "lib").rglob("*.dart"))
        paths.add(base / "pubspec.yaml")
    paths.update((ROOT / "packages/quds_office_editor/example/lib").glob("studio_spacy_config*.dart"))
    paths.add(ROOT / "packages/quds_office_editor/example/pubspec.yaml")
    return {str(p.relative_to(ROOT)): {"sha256": sha(p), "bytes": p.stat().st_size}
            for p in sorted(paths)}


def sanitize(text):
    substitutions = [(str(ROOT), "QUDS_REPOSITORY"),
                     (str(ROOT.parent / "w6-runtime"), "VALIDATION_RUNTIME")]
    for key in ("FLUTTER_ROOT", "PUB_CACHE", "TMPDIR", "QUDS_SPACY_BUNDLE", "QUDS_SPACY_LIBRARY"):
        if os.environ.get(key):
            substitutions.append((os.environ[key], key))
    for source, replacement in sorted(substitutions, key=lambda item: len(item[0]), reverse=True):
        text = text.replace(source, replacement)
    return text


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--attempt", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9-]+", args.attempt):
        raise SystemExit("Use a simple fresh attempt name")
    stem = OUT / args.attempt
    if any(OUT.glob(args.attempt + ".*")):
        raise SystemExit("Refuse to replace any retained attempt")
    before = capture()
    source = stem.with_suffix(".sources-before.json")
    source.write_text(json.dumps(before, indent=2, sort_keys=True) + "\n")
    stem.with_suffix(".gate.dart").write_bytes((ROOT / GATE).read_bytes())
    command = ["flutter", "test", "--no-pub", "--concurrency=1", GATE,
               "--reporter", "expanded"]
    record = {
        "schema": "quds.spacy.w6.real_editor_gate.v1",
        "scope": "Real installed native worker and actual manual editor proofing integration, using one authored development sentence. Delayed-reply cases are explicitly identified harness lifecycle controls; native output is never mocked.",
        "attempt": args.attempt,
        "head_before": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "source_count": len(before),
        "sources_before": source.name,
        "sources_before_sha256": sha(source),
        "gate_sha256": sha(ROOT / GATE),
        "runner_sha256": sha(Path(__file__)),
        "runtime_receipt_sha256": sha(OUT.parent / "runtime/runtime-restoration.json"),
        "native_library_before_sha256": sha(Path(os.environ["QUDS_SPACY_LIBRARY"])),
        "bundle_manifest_before_sha256": sha(Path(os.environ["QUDS_SPACY_BUNDLE"]) / "manifest.json"),
        "argv": command,
        "cwd": "repository root",
        "environment": {"TMPDIR": "task-owned writable temporary directory"},
        "ci_queried_or_waited": False,
        "acceptance_rerun": False,
        "qualification_panel_read": False,
        "implicit_pub": False,
        "status": "running",
    }
    result = stem.with_suffix(".json")
    result.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    start = time.monotonic()
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, start_new_session=True)
    try:
        raw, _ = process.communicate(timeout=300)
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
    log = stem.with_suffix(".log")
    log.write_text(output)
    after = capture()
    after_path = stem.with_suffix(".sources-after.json")
    after_path.write_text(json.dumps(after, indent=2, sort_keys=True) + "\n")
    counts = re.findall(r"\+(\d+)(?:\s+~\d+)?(?:\s+-\d+)?:", output)
    record.update({
        "exit_code": code,
        "elapsed_seconds": time.monotonic() - start,
        "log": log.name,
        "log_sha256": sha(log),
        "passed_tests": int(counts[-1]) if counts and code == 0 else None,
        "sources_after": after_path.name,
        "sources_after_sha256": sha(after_path),
        "source_unchanged": before == after,
        "native_library_after_sha256": sha(Path(os.environ["QUDS_SPACY_LIBRARY"])),
        "bundle_manifest_after_sha256": sha(Path(os.environ["QUDS_SPACY_BUNDLE"]) / "manifest.json"),
    })
    record["runtime_unchanged"] = (
        record["native_library_before_sha256"] == record["native_library_after_sha256"] and
        record["bundle_manifest_before_sha256"] == record["bundle_manifest_after_sha256"])
    passed = code == 0 and record["source_unchanged"] and record["runtime_unchanged"]
    record["status"] = "passed" if passed else "failed"
    result.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    print(json.dumps({key: record[key] for key in (
        "status", "exit_code", "passed_tests", "source_count", "source_unchanged",
        "runtime_unchanged", "elapsed_seconds", "log_sha256")}), flush=True)
    if not passed:
        print(output[-18000:], flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
