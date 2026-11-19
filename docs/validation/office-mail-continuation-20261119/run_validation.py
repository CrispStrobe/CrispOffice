#!/usr/bin/env python3
"""Run the committed Office/Mail continuation plan without hosted CI.

The existing strict runner owns Dart reporter accounting, per-suite coverage,
analysis, formatting and source/runtime fingerprints. The existing Store driver
owns its complete VM/Node checks. This adapter binds the combined execution to
one clean source commit, preserves every raw log, and rejects skipped controls.
It does not download dependencies, query GitHub Actions or contact a mail account.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path: Path, value: object) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--head", required=True)
    parser.add_argument("--base", required=True)
    parser.add_argument("--runtime", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--command-timeout", type=int, default=900)
    args = parser.parse_args()
    if args.command_timeout <= 0:
        parser.error("--command-timeout must be positive")
    directory = Path(__file__).resolve().parent
    repo = directory.parents[2]
    runtime, output = args.runtime.resolve(), args.output.resolve()
    if output == repo or repo in output.parents:
        raise RuntimeError("Keep gate output outside the frozen source checkout")
    if output.exists() and any(output.iterdir()):
        raise RuntimeError("Choose an empty output directory; preserve prior attempts")
    output.mkdir(parents=True, exist_ok=True)

    def git(*arguments: str) -> str:
        return subprocess.check_output(
            ["git", "--no-replace-objects", "-C", str(repo), *arguments], text=True,
        ).rstrip("\n")

    def clean() -> bool:
        return not git("status", "--porcelain=v1", "--untracked-files=no")

    def untracked_product() -> list[str]:
        return [
            path for path in git("ls-files", "--others", "--exclude-standard", "-z").split("\0")
            if path.startswith(("packages/", "apps/", "third_party/"))
        ]

    head = git("rev-parse", "--verify", args.head + "^{commit}")
    base = git("rev-parse", "--verify", args.base + "^{commit}")
    if git("rev-parse", "HEAD") != head or not clean() or untracked_product():
        raise RuntimeError("Commit source, plans and harness before freezing HEAD")
    tracked = set(git("ls-files", "-z").split("\0")) - {""}
    plans = {name: directory / (name + "-plan.json") for name in ("native", "node")}
    plan_data = {name: json.loads(path.read_text()) for name, path in plans.items()}
    shared = repo / "docs/validation/document-review-notes-20261118"
    required = {
        str(path.relative_to(repo))
        for path in [Path(__file__), *plans.values(), shared / "run_checks.py", shared / "test_run_checks.py"]
    }
    if not required <= tracked:
        raise RuntimeError("Commit the driver, both plans and shared runner before execution")
    changed = {
        path for path in git("diff", "--name-only", "--diff-filter=ACMRT", "-z", base, head).split("\0")
        if path.endswith(".dart") and path.startswith(("packages/", "apps/", "third_party/"))
    }
    # The shared runner's 'changed' mode covers packages/apps. Explicit lists
    # are required if this continuation also changes vendored Dart source.
    for kind in ("analysis", "format"):
        requested = plan_data["native"][kind]
        checked = changed - {p for p in changed if p.startswith("third_party/")} if requested == "changed" else set(requested)
        if changed - checked:
            raise RuntimeError(f"Changed Dart inputs missing {kind}: {sorted(changed - checked)}")
    studio_root = "packages/quds_office_editor/example"
    studio_expected = {
        "test/" + path.name for path in (repo / studio_root / "test").glob("*_test.dart")
    }
    excluded = plan_data["native"].get("excluded_studio_suites", {})
    if not isinstance(excluded, dict) or any(not reason for reason in excluded.values()):
        raise RuntimeError("Every excluded Studio suite needs an explicit boundary")
    studio_requested = {
        suite for group in plan_data["native"]["groups"] if group["cwd"] == studio_root
        for suite in group["tests"]
    }
    if studio_requested != studio_expected - set(excluded) or set(excluded) - studio_expected:
        raise RuntimeError("The plan must cover every ordinary Studio suite exactly")
    receipt = json.loads((runtime / "runtime.json").read_text())
    if receipt.get("status") != "ready" or not receipt.get("archive", {}).get("verified"):
        raise RuntimeError("A verified ready runtime is required")
    if digest(repo / "pubspec.lock") != receipt["workspace_lock_sha256"]:
        raise RuntimeError("Workspace lock differs from the verified runtime")
    retained = json.loads((runtime / "retained-inputs.json").read_text())
    runtime_paths = {"runtime/" + name: runtime / name for name in retained}
    for name in ("runtime.json", "retained-inputs.json", "pub-cache-receipt.json", "cache-omissions.json", "archive-members.json", "env.sh", "bin/dart", "bin/flutter"):
        runtime_paths["runtime/" + name] = runtime / name
    runtime_paths.update({"additional/" + name: Path(name) for name in receipt.get("additional_inputs", {})})
    runtime_paths["python/executable"] = Path(sys.executable).resolve()
    runtime_paths["workspace/package_config.json"] = repo / ".dart_tool/package_config.json"
    runtime_paths["workspace/package_graph.json"] = repo / ".dart_tool/package_graph.json"
    runtime_paths["sdk/flutter_tools/package_config.json"] = runtime / "flutter/packages/flutter_tools/.dart_tool/package_config.json"
    source_paths = {
        name: repo / name for name in tracked
        if name.startswith(("packages/", "apps/", "third_party/", "tools/mail/", "tools/proofing/ayaspell/"))
        or ("/" not in name and Path(name).suffix in {".yaml", ".lock"}) or name == ".fvmrc"
    }
    for name in required | {n for plan in plan_data.values() for n in plan.get("extra_inputs", [])}:
        if name not in tracked:
            raise RuntimeError("Qualification input is not committed: " + name)
        source_paths[name] = repo / name

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
    for name in ("package_config.json", "package_graph.json"):
        shutil.copy2(repo / ".dart_tool" / name, output / name)
    env = dict(os.environ, PUB_CACHE=str(runtime / "pub-cache"), FLUTTER_ROOT=str(runtime / "flutter"),
               CI="true", DART_SUPPRESS_ANALYTICS="true", FLUTTER_SUPPRESS_ANALYTICS="true",
               DASH__SUPPRESS_ANALYTICS="true", XDG_CONFIG_HOME=str(runtime / "config"),
               XDG_CACHE_HOME=str(runtime / "cache"), XDG_DATA_HOME=str(runtime / "data"),
               TMPDIR=str(runtime / "tmp"))
    env["PATH"] = str(runtime / "bin") + os.pathsep + env.get("PATH", "")
    removed_environment = []
    for name in list(env):
        if name.startswith(("QUDS_HUNSPELL_", "QUDS_ARABIC_MORPH_", "QUDS_SHOTS_")):
            removed_environment.append(name)
            del env[name]
    sys.path.insert(0, str(repo / "tools/mail"))
    from check_store import execute

    index_tree = git("write-tree")
    record = {
        "status": "RUNNING", "source_commit": head, "source_base": base,
        "source_tree": git("rev-parse", head + "^{tree}"), "runs": [],
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_input_count": len(source_paths), "runtime_input_count": len(runtime_paths),
        "runtime_receipt_sha256": digest(runtime / "runtime.json"),
        "python_version": sys.version, "strict_changed_dart_inputs": sorted(changed),
        "excluded_studio_suites": excluded,
        "excluded_native_backend_suites": plan_data["native"].get("excluded_native_backend_suites", []),
        "removed_optional_native_environment_names": sorted(removed_environment),
        "historical_results_added_to_current_counts": 0,
        "github_actions_queried_or_awaited": False,
    }

    def save() -> None:
        write_json(output / "execution.json", record)

    def run(name: str, command: list[str], result: Path | None = None, *, unittest: bool = False) -> None:
        print("START " + name, flush=True)
        log = output / (name + ".log")
        row = {"name": name, "command": command, "log": log.name, "cwd": str(repo)}
        record["runs"].append(row)
        save()
        with log.open("wb") as stream:
            try:
                code = execute(command, cwd=repo, env=env, stdout=stream, timeout=args.command_timeout)
            except (OSError, subprocess.TimeoutExpired) as error:
                code = 124 if isinstance(error, subprocess.TimeoutExpired) else 127
                row["runner_error"] = repr(error)
        row.update(exit_code=code, log_sha256=digest(log), accepted=code == 0)
        if unittest:
            text = log.read_text(errors="replace")
            counts = re.findall(r"^Ran (\d+) tests? in ", text, re.MULTILINE)
            successful = re.search(r"^OK\s*$", text, re.MULTILINE) is not None
            skipped = re.search(r"\bskipped[= ]|^OK \(", text, re.MULTILINE) is not None
            row.update(python_tests=int(counts[-1]) if counts else 0, python_skips_detected=skipped)
            row["accepted"] = row["accepted"] and bool(counts) and successful and not skipped
        if result is not None:
            if result.is_file():
                content = json.loads(result.read_text())
                row.update(receipt=str(result.relative_to(output)), receipt_sha256=digest(result))
                row["accepted"] = row["accepted"] and (content.get("success") is True or content.get("status") == "PASS")
                if "passed" in content:
                    row["application_executions"] = content["passed"]
            else:
                row["accepted"] = False
        save()
        if not row["accepted"]:
            raise RuntimeError(name + " failed; preserve its raw evidence")

    save()
    try:
        run("shared-runner-controls", [sys.executable, "-B", str(shared / "test_run_checks.py")], unittest=True)
        run("runtime-replay-controls", [sys.executable, "-B", str(shared / "runtime/test_restore_runtime.py")], unittest=True)
        run("publisher-offline-controls", [sys.executable, "-B", "-m", "unittest", "discover", "-s", "tools/proofing/ayaspell", "-p", "test_build_bundle*.py", "-v"], unittest=True)
        run("hunspell-packaging-controls", [sys.executable, "-B", "-m", "unittest", "discover", "-s", "packages/quds_proofing_hunspell/tool", "-p", "test_build.py", "-v"], unittest=True)
        run("core-store", [sys.executable, "-B", str(repo / "tools/mail/check_store.py"),
                           "--flutter-sdk", str(runtime / "flutter"), "--offline", "--direct-tests",
                           "--command-timeout", str(args.command_timeout), "--output", str(output / "core-store")],
            output / "core-store/receipt.json")
        for name, path in plans.items():
            run(name, [sys.executable, "-B", str(shared / "run_checks.py"), "--head", head, "--base", base,
                       "--runtime", str(runtime), "--plan", str(path), "--output", str(output / name),
                       "--command-timeout", str(args.command_timeout)], output / name / "verification.json")
        record["status"] = "PASS"
    except BaseException as error:
        record.update(status="FAIL", error=repr(error))
    finally:
        after_source, after_runtime = snapshot(source_paths), snapshot(runtime_paths)
        write_json(output / "source-after.json", after_source)
        write_json(output / "runtime-after.json", after_runtime)
        record.update(
            source_unchanged=before_source == after_source, runtime_unchanged=before_runtime == after_runtime,
            source_head_unchanged=git("rev-parse", "HEAD") == head,
            source_index_unchanged=git("write-tree") == index_tree,
            tracked_worktree_clean_after=clean(), untracked_product_inputs_after=untracked_product(),
            finished_at_utc=datetime.now(timezone.utc).isoformat(),
        )
        record["manifest_sha256"] = {
            name: digest(output / name) for name in (
                "source-before.json", "source-after.json", "runtime-before.json", "runtime-after.json",
                "package_config.json", "package_graph.json",
            )
        }
        if record["untracked_product_inputs_after"] or not all(record[k] for k in (
            "source_unchanged", "runtime_unchanged", "source_head_unchanged", "source_index_unchanged", "tracked_worktree_clean_after",
        )):
            record["status"] = "FAIL"
        save()
    print(record["status"] + ": " + str(output / "execution.json"), flush=True)
    return 0 if record["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
