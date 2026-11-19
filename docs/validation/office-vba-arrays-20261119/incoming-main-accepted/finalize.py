#!/usr/bin/env python3
"""Bind a completed GUI qualification to its tested commit and retained files."""

from __future__ import annotations

from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess


OUTPUT = Path(__file__).resolve().parent
ROOT = OUTPUT.parents[3]
WORKSPACE = ROOT.parent / "flutter-validation-workspace"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load(name: str):
    return json.loads((OUTPUT / name).read_text())


def write(name: str, value: object) -> None:
    (OUTPUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def main() -> None:
    receipt = load("receipt.json")
    if receipt["success"] is not True:
        raise RuntimeError("A successful full qualification is required.")
    before = load("inputs-before.json")
    if before != load("inputs-after.json"):
        raise RuntimeError("The input snapshots differ.")
    head = load("source-frontier.json")["checkout_head_at_start"]
    files = {name.removeprefix("repository/"): digest
             for name, digest in before.items() if name.startswith("repository/")}
    process = subprocess.Popen(
        ["git", "cat-file", "--batch"], cwd=ROOT,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
    )
    bound = {}
    try:
        for name, expected in sorted(files.items()):
            process.stdin.write(f"{head}:{name}\n".encode())
            process.stdin.flush()
            header = process.stdout.readline().decode().split()
            if len(header) != 3 or header[1] != "blob":
                raise RuntimeError(f"Missing direct Git blob for {name}: {header}")
            data = process.stdout.read(int(header[2]))
            if process.stdout.read(1) != b"\n":
                raise RuntimeError(f"Incomplete Git response for {name}")
            actual = sha(data)
            if actual != expected:
                raise RuntimeError(f"Tested input does not match checkpoint: {name}")
            bound[name] = {"sha256": actual, "git_blob": header[0],
                           "git_blob_matches": True}
    finally:
        process.stdin.close()
        process.stdout.close()
        if process.wait() != 0:
            raise RuntimeError("git cat-file failed")
    write("source-binding.json", {
        "tested_source_head": head,
        "recorded_input_count": len(before),
        "repository_input_count": len(bound),
        "all_repository_inputs_match_commit": True,
        "files": bound,
    })

    distinct = {}
    suites = {}
    test_commands = {command["name"]: command for command in receipt["commands"]
                     if "test" in command["command"]}
    for cohort, command in test_commands.items():
        summary = load(f"{cohort}-summary.json")
        counts = Counter()
        for item in summary["tests"]:
            path = item["suite"]["path"]
            if "/packages/" in path:
                path = "packages/" + path.split("/packages/", 1)[1]
            elif not path.startswith("packages/"):
                package = Path(command["cwd"]).relative_to(WORKSPACE)
                path = str(package / path.removeprefix("./"))
            name = item["test"]["name"]
            result = item["result"]
            if result["result"] != "success" or result.get("skipped", False):
                raise RuntimeError(f"Non-passing accepted case: {path}::{name}")
            counts[path] += 1
            key = path + "::" + name
            distinct.setdefault(key, []).append(cohort)
        suites[cohort] = dict(sorted(counts.items()))
    write("suite-counts.json", suites)
    repeated = sum("repeated-studio-tests" in value for value in distinct.values())
    previous_path = OUTPUT.parent / "incoming-layout-theme-accepted/distinct-tests.json"
    previous = json.loads(previous_path.read_text())["tests"]
    missing = sorted(set(previous) - set(distinct))
    if missing:
        raise RuntimeError(f"Previous GUI cases were not requalified: {missing}")
    write("distinct-tests.json", {
        "distinct_passing_cases_in_this_run": len(distinct),
        "previous_gui_cases_requalified": len(previous),
        "new_cases_beyond_previous_gui": len(set(distinct) - set(previous)),
        "historical_mail_cases_repeated": repeated,
        "passing_cases_beyond_historical_mail": len(distinct) - repeated,
        "identity": "Repository suite path and test name",
        "tests": distinct,
    })

    native_hook = WORKSPACE / ".dart_tool/hooks_runner/sqlite3/6b4ebf10e7"
    if native_hook.is_dir():
        hook_input = json.loads((native_hook / "input.json").read_text())
        hook_output = json.loads((native_hook / "output.json").read_text())
        library = Path(hook_output["assets"][0]["encoding"]["file"])
        write("native-runtime.json", {
            "package": "sqlite3", "version": "3.9.1",
            "hook_input": hook_input, "hook_output": hook_output,
            "user_defines_empty": hook_input["user_defines"] == {},
            "downloaded_library_sha256": sha(library.read_bytes()),
        })
    artifacts = {}
    for path in sorted(OUTPUT.rglob("*")):
        if (path.is_file() and "__pycache__" not in path.parts
                and path.name != "artifacts-sha256.json"):
            data = path.read_bytes()
            artifacts[str(path.relative_to(OUTPUT))] = {
                "sha256": sha(data), "bytes": len(data),
            }
    write("artifacts-sha256.json", artifacts)
    print(json.dumps({"repository_inputs_bound": len(bound),
                      "distinct_passed": len(distinct),
                      "historical_mail_repeated": repeated,
                      "artifacts": len(artifacts)}))


if __name__ == "__main__":
    main()
