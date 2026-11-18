#!/usr/bin/env python3
"""Run bounded incoming provider checks against one frozen repository commit.

This intentionally excludes the parent task's editor/Studio widget gates and
does not download models, invoke native inference, or contact GitHub CI.
Installer tests use their own loopback fixtures. Pack verification reads the
already bundled assets and writes its report outside the checkout.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


SPACY_TESTS = [
    "test/analysis_test.dart",
    "test/bundle_test.dart",
    "test/distribution_test.dart",
    "test/language_catalog_test.dart",
    "test/worker_test.dart",
    "test/grammar_provider_test.dart",
]


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def now():
    return datetime.now(timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--expect-commit", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    repo, output = args.repo.resolve(), args.output.resolve()

    def git(*command):
        return subprocess.check_output(
            ["git", *command], cwd=repo, text=True
        ).strip()

    expected = git("rev-parse", args.expect_commit)
    head = git("rev-parse", "HEAD")
    if head != expected:
        parser.error(f"Expected frozen commit {expected}, found {head}")
    if git("status", "--porcelain", "--untracked-files=no"):
        parser.error("Tracked source must be clean before the frozen gate.")
    if output == repo or repo in output.parents:
        parser.error("Keep output outside the tracked checkout.")
    output.mkdir(parents=True, exist_ok=False)

    sdk = Path(os.environ["FLUTTER_ROOT"]).resolve()
    dart = sdk / "bin/cache/dart-sdk/bin/dart"
    version = subprocess.check_output(
        [str(dart), "--version"], text=True, stderr=subprocess.STDOUT
    ).strip()
    if "Dart SDK version: 3.13.7 " not in version:
        parser.error(f"Unexpected Dart SDK: {version}")
    selected = {
        f"packages/quds_proofing_spacy/{name}" for name in SPACY_TESTS
    } | {"packages/quds_office_engine/test/office_thesaurus_test.dart"}
    tracked = git("ls-files").splitlines()
    source_paths = [
        name for name in tracked
        if name in {".fvmrc", "pubspec.yaml", "analysis_options.yaml"}
        or name in selected
        or (name.startswith("packages/") and name.endswith("/pubspec.yaml"))
        or (name.startswith("packages/") and "/lib/" in name and name.endswith(".dart"))
        or name.startswith("packages/quds_office_editor/assets/thesaurus/")
        or (name.startswith("tools/thesaurus/") and name.endswith(".py"))
    ]
    runtime_paths = [
        dart,
        repo / "pubspec.lock",
        repo / ".dart_tool/package_config.json",
    ]
    source_before = {name: digest(repo / name) for name in source_paths}
    runtime_before = {str(path): digest(path) for path in runtime_paths}
    (output / "source-before.json").write_text(
        json.dumps(source_before, indent=2) + "\n"
    )
    (output / "runtime-before.json").write_text(
        json.dumps(runtime_before, indent=2) + "\n"
    )
    gates = [
        (
            "spacy-providers",
            repo / "packages/quds_proofing_spacy",
            [str(dart), "test", *SPACY_TESTS, "--reporter", "expanded", "--concurrency=2"],
        ),
        (
            "thesaurus-provider",
            repo / "packages/quds_office_engine",
            [str(dart), "test", "test/office_thesaurus_test.dart", "--reporter", "expanded", "--concurrency=2"],
        ),
        (
            "thesaurus-compiler",
            repo,
            [sys.executable, "tools/thesaurus/test_build_packs.py", "-v"],
        ),
        (
            "thesaurus-pack-integrity",
            repo,
            [
                sys.executable,
                "tools/thesaurus/verify_packs.py",
                "--packs", "packages/quds_office_editor/assets/thesaurus",
                "--output", str(output / "pack-verification.json"),
            ],
        ),
    ]
    summary = {
        "started_at_utc": now(),
        "source_commit": head,
        "runtime": version,
        "python": sys.version,
        "source_file_count": len(source_before),
        "results": [],
        "external_model_downloads": False,
        "live_native_inference": False,
        "network_scope": "Controlled loopback HTTP fixture servers only",
        "github_actions_used": False,
    }
    for name, cwd, command in gates:
        if git("rev-parse", "HEAD") != head:
            raise RuntimeError("HEAD changed during provider gates")
        started = time.monotonic()
        log = output / f"{name}.log"
        with log.open("w") as stream:
            completed = subprocess.run(
                command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT
            )
        text = log.read_text(errors="replace")
        result = {
            "name": name,
            "command": command,
            "cwd": str(cwd),
            "exit_code": completed.returncode,
            "duration_seconds": time.monotonic() - started,
            "log": log.name,
            "log_sha256": digest(log),
        }
        dart_count = re.search(r"\+(\d+): All tests passed!", text)
        python_count = re.search(r"Ran (\d+) tests? in ", text)
        if dart_count:
            result["passed"] = int(dart_count.group(1))
        elif python_count and completed.returncode == 0:
            result["passed"] = int(python_count.group(1))
        summary["results"].append(result)
        (output / "results.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(json.dumps(result), flush=True)

    source_after = {name: digest(repo / name) for name in source_paths}
    runtime_after = {str(path): digest(path) for path in runtime_paths}
    (output / "source-after.json").write_text(json.dumps(source_after, indent=2) + "\n")
    (output / "runtime-after.json").write_text(json.dumps(runtime_after, indent=2) + "\n")
    summary.update(
        finished_at_utc=now(),
        source_commit_after=git("rev-parse", "HEAD"),
        tracked_status_after=git("status", "--porcelain", "--untracked-files=no"),
        source_mismatches=[name for name in source_before if source_before[name] != source_after[name]],
        runtime_mismatches=[name for name in runtime_before if runtime_before[name] != runtime_after[name]],
    )
    passed = (
        all(result["exit_code"] == 0 for result in summary["results"])
        and not summary["source_mismatches"]
        and not summary["runtime_mismatches"]
        and not summary["tracked_status_after"]
        and summary["source_commit_after"] == head
    )
    summary["status"] = "passed" if passed else "failed"
    (output / "results.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({"status": summary["status"], "source_commit": head}), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
