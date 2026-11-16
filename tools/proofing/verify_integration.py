#!/usr/bin/env python3
"""Run local proofing integration gates and bind their logs to exact sources.

Resolve the workspace with the pinned Flutter SDK first. This runner neither
queries GitHub Actions nor treats unavailable native/browser devices as tested.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
EDITOR = ROOT / "packages/quds_office_editor"
TESTS = [
    "test/word_proofing_session_test.dart",
    "test/word_proofing_dialog_test.dart",
    "test/word_proofing_correction_test.dart",
    "test/word_proofing_geometry_test.dart",
    "test/platform_spelling_provider_test.dart",
    "test/word_hyphenation_paint_test.dart",
    "test/word_hyphenation_source_presentation_test.dart",
    "test/editor_test.dart",
    "test/word_small_caps_test.dart",
    "test/word_note_numbering_test.dart",
]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources() -> dict[str, str]:
    paths = {ROOT / "pubspec.yaml", ROOT / "pubspec.lock", Path(__file__).resolve()}
    for package in ["legacy_doc_parser", "quds_office_engine", "quds_office_editor",
                    "quds_reports", "quds_proofing_harper"]:
        directory = ROOT / "packages" / package
        paths.add(directory / "pubspec.yaml")
        paths.update((directory / "lib").rglob("*.dart"))
        if (directory / "analysis_options.yaml").exists():
            paths.add(directory / "analysis_options.yaml")
    paths.update((EDITOR / "example/lib").rglob("*.dart"))
    paths.add(EDITOR / "example/pubspec.yaml")
    paths.update(EDITOR / name for name in TESTS)
    for directory in [ROOT / "packages/quds_office_engine/third_party/proofing",
                      ROOT / "packages/quds_office_engine/third_party/hyphenation",
                      ROOT / "packages/quds_proofing_harper/web"]:
        paths.update(p for p in directory.rglob("*") if p.is_file())
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(paths) if p.is_file()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=ROOT / "docs/validation/proofing-20261116/integration-resume")
    parser.add_argument("--skip-web-build", action="store_true")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, CI="true", FLUTTER_SUPPRESS_ANALYTICS="true",
               DART_SUPPRESS_ANALYTICS="true")
    if not shutil.which("flutter") or not shutil.which("dart"):
        parser.error("Put the repository-pinned Flutter SDK on PATH first.")
    before = sources()
    receipt: dict[str, object] = {
        "schema_version": 1,
        "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "source_sha256": before,
        "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "github_actions_used": False,
        "browser_execution": "not run: this runner compiles the host; Chromium socket restrictions are recorded separately",
        "commands": [],
    }
    lock = ROOT / "pubspec.lock"
    if lock.exists():
        shutil.copyfile(lock, output / "workspace-pubspec.lock")
        receipt["workspace_lock_sha256"] = digest(lock)
    commands = [
        ("flutter-version", ROOT, ["flutter", "--version", "--machine"]),
        ("engine-analysis", ROOT / "packages/quds_office_engine", ["dart", "analyze", "--fatal-infos"]),
        ("editor-analysis", EDITOR, ["dart", "analyze", "--fatal-infos", "lib", *TESTS]),
        ("host-analysis", EDITOR / "example", ["dart", "analyze", "--fatal-infos", "lib"]),
        ("editor-tests", EDITOR, ["flutter", "test", "--no-pub", "--reporter", "expanded", *TESTS]),
    ]
    if not args.skip_web_build:
        commands.append(("host-web-build", EDITOR / "example", ["flutter", "build", "web", "--no-pub"]))
    failures = []
    for name, cwd, command in commands:
        print(f"Running {name}…", flush=True)
        log = output / f"{name}.log"
        started = time.monotonic()
        with log.open("wb") as stream:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT, check=False)
        record = {"name": name, "cwd": str(cwd.relative_to(ROOT)), "command": command,
                  "exit_code": result.returncode, "seconds": round(time.monotonic() - started, 3),
                  "log": log.name, "log_sha256": digest(log)}
        receipt["commands"].append(record)
        if result.returncode:
            failures.append(name)
        print(f"{name}: exit {result.returncode}", flush=True)
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    after = sources()
    changed = [path for path in sorted(before.keys() | after.keys()) if before.get(path) != after.get(path)]
    receipt["inputs_unchanged_during_validation"] = not changed
    receipt["changed_sources"] = changed
    receipt["failed_commands"] = failures
    receipt["completed_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    if not args.skip_web_build and not failures:
        bundle = EDITOR / "example/build/web"
        receipt["host_web_artifact_sha256"] = {
            str(path.relative_to(bundle)): digest(path)
            for path in sorted(bundle.rglob("*")) if path.is_file()
        }
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({"passed": not failures and not changed, "failed_commands": failures,
                      "changed_sources": changed, "source_files": len(before)}), flush=True)
    return int(bool(failures or changed))


if __name__ == "__main__":
    raise SystemExit(main())
