#!/usr/bin/env python3
"""Record an independent mail-store qualification without changing sources."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.parse import unquote, urlparse


ROOT = Path(__file__).resolve().parents[4]
WORKSPACE = ROOT.parent / "validation-workspace"
RUNTIME = ROOT.parent / "runtime"
OUTPUT = Path(__file__).resolve().parent
DART = RUNTIME / "dart-sdk/bin/dart"
PACKAGES = ("quds_mail_core", "quds_mail_store")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(name: str, value: object) -> None:
    (OUTPUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def run_git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def snapshot() -> dict[str, str]:
    paths = [
        ROOT / "analysis_options.yaml",
        ROOT / "pubspec.yaml",
        ROOT / "pubspec.lock",
        WORKSPACE / "analysis_options.yaml",
        WORKSPACE / "pubspec.yaml",
        WORKSPACE / "pubspec.lock",
        WORKSPACE / ".dart_tool/package_config.json",
        WORKSPACE / ".dart_tool/package_graph.json",
        DART,
        RUNTIME / "dart-sdk/version",
    ]
    for package in PACKAGES:
        base = ROOT / "packages" / package
        paths.extend(
            path for path in base.rglob("*")
            if path.is_file()
            and not any(part in {".dart_tool", "build", ".git"}
                        for part in path.relative_to(base).parts)
        )
        paths.append(WORKSPACE / "packages" / package / "pubspec.yaml")
    config_path = WORKSPACE / ".dart_tool/package_config.json"
    config = json.loads(config_path.read_text())
    for package in config["packages"]:
        uri = urlparse(package["rootUri"])
        if uri.scheme == "file":
            package_root = Path(unquote(uri.path))
        else:
            package_root = config_path.parent / unquote(package["rootUri"])
        manifest = package_root / "pubspec.yaml"
        if manifest.is_file():
            paths.append(manifest)
    result = {}
    for path in sorted(set(paths), key=str):
        if not path.is_file():
            raise RuntimeError(f"Missing recorded input: {path}")
        try:
            key = "repository/" + str(path.relative_to(ROOT))
        except ValueError:
            key = "workspace/" + str(path.relative_to(ROOT.parent))
        result[key] = digest(path)
    return result


def execute(name: str, args: list[str], cwd: Path) -> dict[str, object]:
    environment = {
        "PUB_CACHE": str(RUNTIME / "pub-cache"),
        "TMPDIR": str(RUNTIME / "tmp"),
        "DART_SUPPRESS_ANALYTICS": "true",
        "CI": "true",
    }
    started = time.time()
    with (OUTPUT / f"{name}.stdout.log").open("wb") as stdout:
        with (OUTPUT / f"{name}.stderr.log").open("wb") as stderr:
            result = subprocess.run(
                args, cwd=cwd, env={**os.environ, **environment},
                stdout=stdout, stderr=stderr, check=False,
            )
    receipt = {
        "name": name,
        "command": args,
        "cwd": str(cwd),
        "environment_overrides": environment,
        "started_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started)),
        "elapsed_seconds": time.time() - started,
        "exit_code": result.returncode,
        "stdout": f"{name}.stdout.log",
        "stderr": f"{name}.stderr.log",
        "stdout_sha256": digest(OUTPUT / f"{name}.stdout.log"),
        "stderr_sha256": digest(OUTPUT / f"{name}.stderr.log"),
    }
    write_json(f"{name}.json", receipt)
    print(json.dumps({"name": name, "exit_code": result.returncode}), flush=True)
    return receipt


def test_summary() -> dict[str, object]:
    tests = {}
    finished = {}
    done = []
    non_json_lines = 0
    for line in (OUTPUT / "store-tests.stdout.log").read_text().splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            non_json_lines += 1
            continue
        if event.get("type") == "testStart":
            tests[event["test"]["id"]] = event["test"]
        elif event.get("type") == "testDone":
            finished[event["testID"]] = event
        elif event.get("type") == "done":
            done.append(event)
    visible = [
        {"test": tests[test_id], "result": result}
        for test_id, result in sorted(finished.items())
        if not result.get("hidden", False)
        and not result.get("isHidden", False)
        and not tests[test_id].get("isHidden", False)
    ]
    summary = {
        "visible_test_count": len(visible),
        "passed": sum(
            item["result"]["result"] == "success"
            and not item["result"].get("skipped", False)
            for item in visible
        ),
        "failed": sum(item["result"]["result"] != "success" for item in visible),
        "skipped": sum(item["result"].get("skipped", False) for item in visible),
        "done_events": done,
        "non_json_stdout_lines": non_json_lines,
        "tests": visible,
    }
    write_json("test-summary.json", summary)
    return summary


def main() -> None:
    before = snapshot()
    write_json("inputs-before.json", before)
    write_json("source-frontier.json", {
        "checkout_head_at_start": run_git("rev-parse", "HEAD"),
        "incoming_head": "37ac6ea8a08225a42098c455deb5375837912eec",
        "qualification_scope": [f"packages/{package}" for package in PACKAGES],
        "source_inputs": len(before),
        "native_sqlite_override": False,
    })
    print(json.dumps({"recorded_inputs": len(before)}), flush=True)
    commands = [execute(
        "store-tests", [str(DART), "test", "--reporter", "json", "test"],
        WORKSPACE / "packages/quds_mail_store",
    )]
    for package in PACKAGES:
        commands.append(execute(
            f"analyze-{package}", [str(DART), "analyze", "--fatal-infos"],
            WORKSPACE / "packages" / package,
        ))
    summary = test_summary()
    after = snapshot()
    write_json("inputs-after.json", after)
    changed = sorted(key for key in before.keys() | after.keys()
                     if before.get(key) != after.get(key))
    stability = {
        "before_count": len(before), "after_count": len(after),
        "changed": changed, "unchanged": not changed,
    }
    write_json("input-stability.json", stability)
    success = (not changed and all(command["exit_code"] == 0 for command in commands)
               and summary["failed"] == 0 and summary["passed"] > 0
               and len(summary["done_events"]) == 1
               and summary["done_events"][0].get("success") is True)
    receipt = {"success": success, "commands": commands,
               "input_stability": stability,
               "tests": {key: value for key, value in summary.items() if key != "tests"}}
    write_json("receipt.json", receipt)
    print(json.dumps({"success": success, "passed": summary["passed"],
                      "failed": summary["failed"], "changed": changed}), flush=True)
    raise SystemExit(0 if success else 1)


if __name__ == "__main__":
    main()
