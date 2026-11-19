#!/usr/bin/env python3
"""Retain the pre-fix regression and focused corrected DrawingML checks."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--dart", type=Path, required=True)
    parser.add_argument("--pub-cache", type=Path, required=True)
    parser.add_argument("--tmp", type=Path, required=True)
    parser.add_argument("--phase", choices=["before", "after"], required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    output = Path(__file__).resolve().parent
    if (output / f"{args.phase}-receipt.json").exists():
        raise SystemExit("This phase already has a retained receipt; refusing to overwrite it.")
    engine = repo / "packages/quds_office_engine"
    cwd = args.workspace.resolve() / "packages/quds_office_engine"
    production = "packages/quds_office_engine/lib/src/slide/shapes/drawingml.dart"
    source_head = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    old_source = subprocess.check_output(["git", "-C", str(repo), "show", f"{source_head}:{production}"])
    old_hash = hashlib.sha256(old_source).hexdigest()
    if args.phase == "before" and digest(repo / production) != old_hash:
        raise SystemExit("The baseline parser must exactly match its recorded Git blob.")
    files = list((engine / "lib").rglob("*.dart"))
    files += [engine / "test" / name for name in ["slide_test.dart", "slide_import_fidelity_test.dart", "slide_text_fidelity_test.dart"]]
    files += [path for path in [repo / "pubspec.yaml", repo / "analysis_options.yaml", engine / "pubspec.yaml", engine / "analysis_options.yaml"] if path.is_file()]

    def snapshot():
        return {str(path.relative_to(repo)): digest(path) for path in sorted(files)}

    before = snapshot()
    environment = os.environ.copy()
    overrides = {"PUB_CACHE": str(args.pub_cache.resolve()), "TMPDIR": str(args.tmp.resolve()),
                 "DART_SUPPRESS_ANALYTICS": "true", "CI": "true"}
    environment.update(overrides)
    commands = []

    def run(name, command):
        started = datetime.now(timezone.utc).isoformat()
        clock = time.monotonic()
        completed = subprocess.run(command, cwd=cwd, env=environment, capture_output=True, timeout=180)
        stdout = output / f"{args.phase}-{name}.stdout.log"
        stderr = output / f"{args.phase}-{name}.stderr.log"
        stdout.write_bytes(completed.stdout)
        stderr.write_bytes(completed.stderr)
        commands.append({"name": name, "command": command, "cwd": str(cwd),
                         "started_utc": started, "elapsed_seconds": round(time.monotonic() - clock, 3),
                         "exit_code": completed.returncode,
                         "stdout": stdout.name, "stdout_sha256": digest(stdout),
                         "stderr": stderr.name, "stderr_sha256": digest(stderr)})

    test_command = [str(args.dart), "test", "--reporter", "json", "--concurrency", "4", "test/slide_test.dart"]
    if args.phase == "before":
        test_command += ["--name", "table cell"]
    else:
        test_command += ["test/slide_import_fidelity_test.dart", "test/slide_text_fidelity_test.dart"]
    run("tests", test_command)
    if args.phase == "after":
        run("analysis", [str(args.dart), "analyze", "--fatal-infos", "lib/src/slide/shapes/drawingml.dart", "test/slide_test.dart"])
        run("format", [str(args.dart), "format", "--output=none", "--set-exit-if-changed", "lib/src/slide/shapes/drawingml.dart", "test/slide_test.dart"])
    after = snapshot()
    for suffix, values in [("inputs-before", before), ("inputs-after", after)]:
        (output / f"{args.phase}-{suffix}.json").write_text(json.dumps(values, indent=2) + "\n")
    source_diff = subprocess.check_output(["git", "-C", str(repo), "diff", "--", production, "packages/quds_office_engine/test/slide_test.dart"])
    (output / f"{args.phase}-source.diff").write_bytes(source_diff)
    receipt = {"phase": args.phase, "source_head": source_head,
               "production_path": production, "production_sha256": before[production],
               "production_git_blob": subprocess.check_output(["git", "-C", str(repo), "rev-parse", f"{source_head}:{production}"], text=True).strip(),
               "production_git_sha256": old_hash,
               "production_matches_recorded_git_blob": before[production] == old_hash,
               "commands": commands, "environment_overrides": overrides,
               "recorded_inputs": len(before), "inputs_stable": before == after,
               "dependency_config_sha256": digest(args.workspace / ".dart_tool/package_config.json"),
               "dependency_lock_sha256": digest(args.workspace / "pubspec.lock"),
               "success": before == after and all(command["exit_code"] == 0 for command in commands)}
    (output / f"{args.phase}-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({"phase": args.phase, "success": receipt["success"],
                      "commands": {command["name"]: command["exit_code"] for command in commands},
                      "inputs_stable": before == after, "receipt": str(output / f"{args.phase}-receipt.json")}))


if __name__ == "__main__":
    main()
