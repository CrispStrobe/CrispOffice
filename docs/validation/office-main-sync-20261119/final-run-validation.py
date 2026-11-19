#!/usr/bin/env python3
"""Run the final captured Office/Mail/Arabic gates sequentially without hosted CI."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--head", required=True)
    parser.add_argument("--base", required=True)
    parser.add_argument("--runtime", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--command-timeout", type=int, default=600)
    args = parser.parse_args()
    if args.command_timeout <= 0:
        parser.error("--command-timeout must be positive")
    repo = Path(__file__).resolve().parents[3]
    directory = Path(__file__).resolve().parent
    runtime, output = args.runtime.resolve(), args.output.resolve()
    if output == repo or repo in output.parents:
        raise RuntimeError("Keep gate output outside the frozen source checkout")
    if output.exists() and any(output.iterdir()):
        raise RuntimeError("Choose an empty output directory; preserve prior attempts")
    output.mkdir(parents=True, exist_ok=True)

    def git(*arguments: str) -> str:
        return subprocess.check_output(["git", "-C", str(repo), *arguments], text=True).strip()

    head = git("rev-parse", "--verify", args.head + "^{commit}")
    base = git("rev-parse", "--verify", args.base + "^{commit}")
    if git("rev-parse", "HEAD") != head or git("status", "--porcelain=v1", "--untracked-files=no"):
        raise RuntimeError("Commit source, plans and harness before freezing HEAD")
    plans = {name: directory / ("final-" + name + "-plan.json") for name in ("native", "node")}
    plan_data = {name: json.loads(path.read_text()) for name, path in plans.items()}
    tracked = set(git("ls-files", "-z").split("\0"))
    untracked_product = [
        path for path in git("ls-files", "--others", "--exclude-standard", "-z").split("\0")
        if path.startswith(("packages/", "apps/", "third_party/"))
    ]
    if untracked_product:
        raise RuntimeError("Commit product inputs before execution: " + repr(untracked_product))
    analyzed = set(plan_data["native"]["analysis"])
    formatted = set(plan_data["native"]["format"])
    changed = {
        path for path in git("diff", "--name-only", "--diff-filter=ACMRT", "-z", base, head).split("\0")
        if path.endswith(".dart") and path.startswith(("packages/", "apps/", "third_party/"))
    }
    if changed - analyzed or changed - formatted:
        raise RuntimeError("Changed Dart paths missing strict checks: " + repr(sorted((changed - analyzed) | (changed - formatted))))
    required = {str(path.relative_to(repo)) for path in [Path(__file__), *plans.values()]}
    if not required <= tracked:
        raise RuntimeError("Commit the driver and both plans before execution")
    receipt = json.loads((runtime / "runtime.json").read_text())
    if receipt.get("status") != "ready" or not receipt.get("archive", {}).get("verified"):
        raise RuntimeError("A verified ready runtime is required")
    retained = json.loads((runtime / "retained-inputs.json").read_text())
    runtime_paths = {"runtime/" + name: runtime / name for name in retained}
    for name in ("runtime.json", "retained-inputs.json", "pub-cache-receipt.json", "cache-omissions.json", "archive-members.json", "env.sh", "bin/dart", "bin/flutter"):
        runtime_paths["runtime/" + name] = runtime / name
    runtime_paths.update({"additional/" + name: Path(name) for name in receipt.get("additional_inputs", {})})
    runtime_paths["python/executable"] = Path(sys.executable).resolve()
    runtime_paths["workspace/package_config.json"] = repo / ".dart_tool/package_config.json"
    runtime_paths["sdk/flutter_tools/package_config.json"] = runtime / "flutter/packages/flutter_tools/.dart_tool/package_config.json"
    source_paths = {
        name: repo / name for name in tracked
        if name.startswith(("packages/", "apps/", "third_party/", "tools/mail/"))
        or ("/" not in name and Path(name).suffix in {".yaml", ".lock"})
        or name == ".fvmrc"
    }
    source_paths.update({name: repo / name for name in required})
    for name in plan_data["native"]["extra_inputs"]:
        source_paths[name] = repo / name
    shared = repo / "docs/validation/document-review-notes-20261118"
    for path in (shared / "run_checks.py", shared / "test_run_checks.py"):
        source_paths[str(path.relative_to(repo))] = path

    def snapshot(paths: dict[str, Path]) -> dict[str, str]:
        return {name: digest(path) for name, path in sorted(paths.items())}

    before_source, before_runtime = snapshot(source_paths), snapshot(runtime_paths)
    for name, identity in retained.items():
        if before_runtime["runtime/" + name] != identity["sha256"]:
            raise RuntimeError("Retained runtime input changed: " + name)
    for name, expected in receipt.get("additional_inputs", {}).items():
        if before_runtime["additional/" + name] != expected:
            raise RuntimeError("Additional runtime input changed: " + name)
    write_json(output / "source-before.json", before_source)
    write_json(output / "runtime-before.json", before_runtime)
    env = dict(os.environ, PUB_CACHE=str(runtime / "pub-cache"), FLUTTER_ROOT=str(runtime / "flutter"),
               CI="true", DART_SUPPRESS_ANALYTICS="true", FLUTTER_SUPPRESS_ANALYTICS="true",
               DASH__SUPPRESS_ANALYTICS="true", XDG_CONFIG_HOME=str(runtime / "config"),
               XDG_CACHE_HOME=str(runtime / "cache"), XDG_DATA_HOME=str(runtime / "data"),
               TMPDIR=str(runtime / "tmp"))
    env["PATH"] = str(runtime / "bin") + os.pathsep + env.get("PATH", "")
    record = {"status": "RUNNING", "source_commit": head, "source_base": base,
              "source_tree": git("rev-parse", "HEAD^{tree}"), "runs": [],
              "started_at_utc": datetime.now(timezone.utc).isoformat(),
              "runtime_receipt_sha256": digest(runtime / "runtime.json"),
              "github_actions_queried_or_awaited": False,
              "python_executable": str(Path(sys.executable).resolve()), "python_version": sys.version}

    def save() -> None:
        write_json(output / "execution.json", record)

    def run(name: str, command: list[str], result: Path | None = None) -> None:
        log = output / (name + ".log")
        print("START " + name, flush=True)
        row = {"name": name, "command": command, "log": log.name}
        record["runs"].append(row)
        save()
        with log.open("wb") as stream:
            process = subprocess.run(command, cwd=repo, env=env, stdout=stream, stderr=subprocess.STDOUT)
        row.update(exit_code=process.returncode, log_sha256=digest(log))
        if result is not None and result.is_file():
            row.update(receipt=str(result.relative_to(output)), receipt_sha256=digest(result))
            content = json.loads(result.read_text())
            row["accepted"] = content.get("success") is True or content.get("status") == "PASS"
        else:
            row["accepted"] = result is None
        save()
        if process.returncode or not row["accepted"]:
            raise RuntimeError(name + " failed; preserve its raw evidence")

    save()
    try:
        for name, path in (("shared-runner-controls", shared / "test_run_checks.py"),
                           ("runtime-controls", shared / "runtime/test_restore_runtime.py")):
            run(name, [sys.executable, str(path)])
        run("bundle-controls", [sys.executable, "-B", "-m", "unittest", "discover",
                                "-s", "tools/proofing/ayaspell", "-p", "test_build_bundle*.py", "-v"])
        run("core-store", [sys.executable, str(repo / "tools/mail/check_store.py"),
                           "--flutter-sdk", str(runtime / "flutter"), "--offline", "--direct-tests",
                           "--command-timeout", str(args.command_timeout), "--output", str(output / "core-store")],
            output / "core-store/receipt.json")
        for name, path in plans.items():
            run(name, [sys.executable, str(shared / "run_checks.py"), "--head", head, "--base", base,
                       "--runtime", str(runtime), "--plan", str(path), "--output", str(output / name),
                       "--command-timeout", str(args.command_timeout)], output / name / "verification.json")
        record["status"] = "PASS"
    except BaseException as error:
        record.update(status="FAIL", error=repr(error))
    finally:
        after_source, after_runtime = snapshot(source_paths), snapshot(runtime_paths)
        write_json(output / "source-after.json", after_source)
        write_json(output / "runtime-after.json", after_runtime)
        record.update(source_unchanged=before_source == after_source, runtime_unchanged=before_runtime == after_runtime,
                      source_head_unchanged=git("rev-parse", "HEAD") == head,
                      tracked_worktree_clean_after=not git("status", "--porcelain=v1", "--untracked-files=no"),
                      finished_at_utc=datetime.now(timezone.utc).isoformat())
        if not all(record[key] for key in ("source_unchanged", "runtime_unchanged", "source_head_unchanged", "tracked_worktree_clean_after")):
            record["status"] = "FAIL"
        save()
    print(record["status"] + ": " + str(output / "execution.json"), flush=True)
    return 0 if record["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
