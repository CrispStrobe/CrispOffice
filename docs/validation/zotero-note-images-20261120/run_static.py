#!/usr/bin/env python3
"""Analyze and format-check changed active Dart files at one committed source.

No dependencies are resolved. Full strict-runner input inventories are recorded
before and after, including this continuation's adapter and font strengthening.
Historical Dart copies under docs are evidence, not active analyzer targets.
"""
from __future__ import annotations

import argparse
import fcntl
import gzip
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--baseline", required=True)
    args = parser.parse_args()
    repo, output = args.repo.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    spec = importlib.util.spec_from_file_location("image_validation_adapter", Path(__file__).with_name("run_validation.py"))
    adapter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(adapter)
    runner = adapter.runner
    sdk = Path(os.environ["FLUTTER_ROOT"]).resolve()
    with (sdk.parent / "qualified-local-validation.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        head = runner.git_head(repo)
        if head != args.expected_head:
            raise RuntimeError(f"Expected {args.expected_head}, found {head}")
        names = runner.git(repo, "diff", "--name-only", "--diff-filter=ACMRT", args.baseline, head).decode().splitlines()
        targets = sorted(name for name in names if name.endswith(".dart") and not name.startswith("docs/") and (repo / name).is_file())
        if not targets:
            raise RuntimeError("No active changed Dart targets")
        inputs = runner.Inputs(repo, sdk, "engine-zotero", runner.select_tests(repo, "engine-zotero"))
        before = inputs.snapshot()
        matches = runner.source_matches_head(repo, head, before["source"])
        if not matches["matches"]:
            runner.write_json(output / "refused-source.json", matches)
            raise RuntimeError("Source differs from the committed head")
        runner.write_json(output / "targets.json", {"baseline": args.baseline, "source": head, "targets": targets, "target_count": len(targets)})
        (output / "inputs-before.json.gz").write_bytes(gzip.compress(runner.canonical_json(before) + b"\n", mtime=0))
        dart = str(sdk / "bin/cache/dart-sdk/bin/dart")
        commands = [
            ("analyze", [dart, "analyze", "--fatal-infos", "--fatal-warnings", *targets]),
            ("format", [dart, "format", "--output=none", "--set-exit-if-changed", *targets]),
        ]
        runs = []
        for name, command in commands:
            print(f"Running {name} for {len(targets)} active Dart targets", flush=True)
            started = time.monotonic()
            with (output / f"{name}.stdout").open("wb") as stdout, (output / f"{name}.stderr").open("wb") as stderr:
                result = subprocess.run(command, cwd=repo, stdout=stdout, stderr=stderr, timeout=1200)
            runs.append({"name": name, "command": command, "cwd": str(repo), "exit_code": result.returncode, "elapsed_seconds": time.monotonic() - started})
        after = runner.Inputs(repo, sdk, "engine-zotero", runner.select_tests(repo, "engine-zotero")).snapshot()
        (output / "inputs-after.json.gz").write_bytes(gzip.compress(runner.canonical_json(after) + b"\n", mtime=0))
        final_head = runner.git_head(repo)
        guards = {"head_unchanged": head == final_head, "source_matches_head": runner.source_matches_head(repo, final_head, after["source"])["matches"], **{f"{area}_unchanged": not paths for area, paths in runner.changed_paths(before, after).items()}}
        accepted = all(guards.values()) and all(run["exit_code"] == 0 for run in runs)
        receipt = {"status": "passed" if accepted else "failed", "source_head": head, "source_head_at_finish": final_head, "baseline": args.baseline, "target_count": len(targets), "runs": runs, "guards": guards, "changed_paths": runner.changed_paths(before, after), "artifacts": {path.name: runner.file_record(path) for path in sorted(output.iterdir()) if path.is_file()}, "no_dependency_resolution": True, "no_github_ci_or_status_endpoints": True}
        runner.write_json(output / "receipt.json", receipt)
        print(json.dumps({"status": receipt["status"], "target_count": len(targets), "guards": guards}), flush=True)
        return 0 if accepted else 1


if __name__ == "__main__":
    sys.exit(main())
