#!/usr/bin/env python3
"""Run a bounded local test cohort and bind its actual result to source inputs."""

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--package", required=True)
    parser.add_argument("--runner", choices=["dart", "flutter"], required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("tests", nargs="+")
    args = parser.parse_args()
    root = args.root.resolve()
    package = root / args.package
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    tracked = subprocess.check_output(
        ["git", "ls-files", "-z"], cwd=root
    ).decode().split("\0")
    paths = {
        root / name
        for name in tracked
        if name and (
            (name.startswith(("packages/", "apps/")) and any(
                part in name for part in ["/lib/", "/test/", "/tool/", "/assets/", "/example/macros/"]
            ))
            or (
                name.startswith(("packages/", "apps/"))
                and name.endswith(("pubspec.yaml", "pubspec.lock", "analysis_options.yaml"))
            )
            or name in {"pubspec.yaml", "pubspec.lock", "analysis_options.yaml"}
        )
    }
    paths.update(package / name for name in args.tests)
    fixtures = package / "test/fixtures"
    if fixtures.exists():
        paths.update(path for path in fixtures.rglob("*") if path.is_file())
    paths.add(root / ".dart_tool/package_config.json")
    paths.add(Path(__file__).resolve())

    def snapshot():
        return {
            str(path.relative_to(root)) if path.is_relative_to(root) else str(path): digest(path)
            for path in sorted(paths)
        }

    before = snapshot()
    write_json(output / "inputs-before.json", before)
    command = [args.runner, "test"]
    if args.runner == "flutter":
        command.append("--no-pub")
    command.extend(["--reporter=json", "--concurrency=2", *args.tests])
    receipt = {
        "source_commit": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=root, text=True
        ).strip(),
        "source_tree": subprocess.check_output(
            ["git", "rev-parse", "HEAD^{tree}"], cwd=root, text=True
        ).strip(),
        "package": args.package,
        "command": command,
        "tests": args.tests,
        "runtime_receipt": str(Path(os.environ["FLUTTER_ROOT"]).parent / "runtime.json"),
        "started_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "status": "running",
    }
    runtime = Path(receipt["runtime_receipt"])
    receipt["runtime_receipt_sha256"] = digest(runtime)
    write_json(output / "receipt.json", receipt)
    with (output / "events.jsonl").open("wb") as stdout, (output / "stderr.log").open("wb") as stderr:
        try:
            completed = subprocess.run(
                command, cwd=package, stdout=stdout, stderr=stderr,
                timeout=1800, check=False,
            )
            receipt["exit_code"] = completed.returncode
        except subprocess.TimeoutExpired:
            receipt["exit_code"] = None
            receipt["timed_out"] = True

    after = snapshot()
    write_json(output / "inputs-after.json", after)
    receipt["inputs_unchanged"] = before == after
    receipt["input_count"] = len(before)
    receipt["changed_inputs"] = [
        name for name in sorted(before.keys() | after.keys())
        if before.get(name) != after.get(name)
    ]
    cases = {}
    suites = {}
    errors = []
    completions = []
    non_json_lines = []
    for line in (output / "events.jsonl").read_text(errors="replace").splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            if line.strip():
                non_json_lines.append(line)
            continue
        kind = event.get("type")
        if kind == "suite":
            suites[event["suite"]["id"]] = event["suite"]
        elif kind == "testStart":
            cases[event["test"]["id"]] = dict(event["test"])
        elif kind == "testDone":
            cases.setdefault(event["testID"], {"id": event["testID"]}).update(event)
        elif kind == "error":
            errors.append(event)
        elif kind == "done":
            completions.append(event)
    visible = []
    for case in cases.values():
        if case.get("hidden") or case.get("name", "").startswith("loading "):
            continue
        suite = suites.get(case.get("suiteID"), {})
        visible.append({
            "suite": suite.get("path"),
            "name": case.get("name"),
            "result": case.get("result", "unfinished"),
            "skipped": case.get("skipped", False),
        })
    identities = [(case["suite"], case["name"]) for case in visible]
    counts = {
        "passed": sum(case["result"] == "success" and not case["skipped"] for case in visible),
        "failed": sum(case["result"] not in {"success", "unfinished"} and not case["skipped"] for case in visible),
        "skipped": sum(case["skipped"] for case in visible),
        "unfinished": sum(case["result"] == "unfinished" for case in visible),
    }
    receipt.update({
        "counts": counts,
        "loaded_suites": len({case["suite"] for case in visible}),
        "duplicate_identities": len(identities) - len(set(identities)),
        "error_event_count": len(errors),
        "done_events": completions,
        "non_json_lines": non_json_lines,
        "finished_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    })
    accepted = (
        receipt["exit_code"] == 0 and receipt["inputs_unchanged"]
        and len(completions) == 1 and completions[0].get("success") is True
        and counts["passed"] > 0 and not any(counts[key] for key in ["failed", "skipped", "unfinished"])
        and not errors and receipt["duplicate_identities"] == 0
    )
    receipt["status"] = "passed" if accepted else "not_accepted"
    write_json(output / "cases.json", visible)
    write_json(output / "errors.json", errors)
    for path in sorted(output.iterdir()):
        if path.suffix == ".jsonl" or path.name.startswith("inputs-"):
            with path.open("rb") as stream, gzip.open(str(path) + ".gz", "wb") as packed:
                packed.write(stream.read())
            path.unlink()
    receipt["artifacts_sha256"] = {
        path.name: digest(path) for path in sorted(output.iterdir())
        if path.is_file() and path.name != "receipt.json"
    }
    write_json(output / "receipt.json", receipt)
    print(json.dumps({"status": receipt["status"], "counts": counts, "input_count": len(before)}), flush=True)
    return 0 if accepted else 1


if __name__ == "__main__":
    raise SystemExit(main())
