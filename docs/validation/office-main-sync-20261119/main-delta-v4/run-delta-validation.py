#!/usr/bin/env python3
"""Qualify the frozen fourth main delta; retain all earlier source identities."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

PRIOR = "0669ac119da05f5eb777c8cfdbce32e0261df647"
MAIN = "9160eb0dba211225c85242114989631c0d14fb72"


def sha(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("repo", "runtime", "fixture-root", "pre-resolution", "prior-gate", "prior-audit", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--command-timeout", type=int, default=600)
    args = parser.parse_args()
    repo, runtime, output = args.repo.resolve(), args.runtime.resolve(), args.output.resolve()
    directory, fixture_root = Path(__file__).resolve().parent, args.fixture_root.resolve()
    if args.command_timeout <= 0 or output == repo or repo in output.parents:
        parser.error("Positive timeout and output outside the frozen checkout are required")
    if output.exists() and any(output.iterdir()):
        raise RuntimeError("Use an empty output directory; preserve prior attempts")
    output.mkdir(parents=True, exist_ok=True)

    def git(*values: str) -> str:
        return subprocess.check_output(["git", "--no-replace-objects", "-C", str(repo), *values], text=True).rstrip("\n")

    def clean() -> bool:
        return not git("status", "--porcelain=v1", "--untracked-files=no")

    head = git("rev-parse", "--verify", args.head + "^{commit}")
    if head != git("rev-parse", "HEAD") or not clean():
        raise RuntimeError("Commit all source, fixture identities, plans and driver before execution")
    tracked = set(git("ls-files", "-z").split("\0")) - {""}
    if any(p.startswith(("packages/", "apps/", "third_party/")) for p in git("ls-files", "--others", "--exclude-standard", "-z").split("\0")):
        raise RuntimeError("Untracked product inputs are not permitted")
    plans = {name: directory / ("delta-" + name + "-plan.json") for name in ("native", "node")}
    data = {name: json.loads(path.read_text()) for name, path in plans.items()}
    fixture_plan = json.loads((directory / "fixture-plan.json").read_text())
    required = {str(p.relative_to(repo)) for p in [Path(__file__), directory / "verify-delta-continuity.py", directory / "fixture-plan.json", directory / "reviewed-source-overrides.json", *plans.values()]}
    if not required <= tracked:
        raise RuntimeError("The complete delta plan must be committed")
    changed = set()
    for base in (PRIOR, MAIN):
        changed.update(p for p in git("diff", "--name-only", "--diff-filter=ACMRT", "-z", base, head).split("\0")
                       if p.endswith(".dart") and p.startswith(("packages/", "apps/", "third_party/")))
    if changed - set(data["native"]["analysis"]) or changed - set(data["native"]["format"]):
        raise RuntimeError("Strict analysis and formatting must cover changed Dart paths against both parents")
    for name, expected in fixture_plan["source_bindings"].items():
        if sha(repo / name) != expected:
            raise RuntimeError("Native build/catalog source no longer matches the frozen fixture: " + name)
    fixture_paths = {}
    for name, identity in fixture_plan["files"].items():
        path = (fixture_root / name).resolve()
        if fixture_root not in path.parents or path.stat().st_size != identity["bytes"] or sha(path) != identity["sha256"]:
            raise RuntimeError("Native fixture identity mismatch: " + name)
        fixture_paths["fixture/" + name] = path
    for name, relative in fixture_plan["environment_paths"].items():
        path = (fixture_root / relative).resolve()
        if fixture_root not in path.parents or not path.exists():
            raise RuntimeError("Native fixture environment is unavailable: " + name)
    receipt = json.loads((runtime / "runtime.json").read_text())
    if receipt.get("status") != "ready" or not receipt.get("archive", {}).get("verified"):
        raise RuntimeError("A verified runtime is required")
    retained = json.loads((runtime / "retained-inputs.json").read_text())
    runtime_paths = {"runtime/" + name: runtime / name for name in retained}
    for name in ("runtime.json", "retained-inputs.json", "pub-cache-receipt.json", "cache-omissions.json", "archive-members.json", "env.sh", "bin/dart", "bin/flutter"):
        runtime_paths["runtime/" + name] = runtime / name
    runtime_paths.update({"additional/" + name: Path(name) for name in receipt["additional_inputs"]})
    runtime_paths.update(fixture_paths)
    runtime_paths["python/executable"] = Path(sys.executable).resolve()
    runtime_paths["sdk/flutter_tools/package_config.json"] = runtime / "flutter/packages/flutter_tools/.dart_tool/package_config.json"
    source_paths = {name: repo / name for name in tracked
                    if name.startswith(("packages/", "apps/", "third_party/", "tools/mail/", "tools/proofing/ayaspell/"))
                    or ("/" not in name and Path(name).suffix in {".yaml", ".lock"}) or name == ".fvmrc"}
    source_paths.update({name: repo / name for name in required | set(data["native"]["extra_inputs"]) | set(data["node"]["extra_inputs"])})
    shared = repo / "docs/validation/document-review-notes-20261118"
    source_paths[str((shared / "run_checks.py").relative_to(repo))] = shared / "run_checks.py"

    def snapshot(paths: dict[str, Path]) -> dict[str, str]:
        return {name: sha(path) for name, path in sorted(paths.items())}

    before_source, stable_runtime = snapshot(source_paths), snapshot(runtime_paths)
    for name, identity in retained.items():
        if stable_runtime["runtime/" + name] != identity["sha256"]:
            raise RuntimeError("Verified runtime input changed: " + name)
    for name, expected in receipt["additional_inputs"].items():
        if stable_runtime["additional/" + name] != expected:
            raise RuntimeError("Native/Node runtime input changed: " + name)
    write(output / "source-before.json", before_source)
    write(output / "runtime-pre-resolution.json", stable_runtime)
    # These are preserved bytes copied by the integrator before its earlier
    # workspace resolution. This driver does not claim to have captured them.
    previous = json.loads((args.pre_resolution / "receipt.json").read_text())
    for name, identity in previous["files"].items():
        path = args.pre_resolution / name
        if path.stat().st_size != identity["bytes"] or sha(path) != identity["sha256"]:
            raise RuntimeError("Preserved pre-resolution bytes changed: " + name)
    shutil.copytree(args.pre_resolution, output / "prior-resolution")
    shutil.copy2(args.prior_audit, output / "prior-independent-summary.json")
    for name in ("execution.json", "source-before.json", "runtime-before.json"):
        shutil.copy2(args.prior_gate / name, output / ("prior-" + name))
    env = dict(os.environ, PUB_CACHE=str(runtime / "pub-cache"), FLUTTER_ROOT=str(runtime / "flutter"),
               CI="true", DART_SUPPRESS_ANALYTICS="true", FLUTTER_SUPPRESS_ANALYTICS="true",
               DASH__SUPPRESS_ANALYTICS="true", XDG_CONFIG_HOME=str(runtime / "config"),
               XDG_CACHE_HOME=str(runtime / "cache"), XDG_DATA_HOME=str(runtime / "data"), TMPDIR=str(runtime / "tmp"))
    env["PATH"] = str(runtime / "bin") + os.pathsep + env.get("PATH", "")
    env.update({name: str(fixture_root / value) for name, value in fixture_plan["environment_paths"].items()})
    env.update(fixture_plan["literal_environment"])
    sys.path.insert(0, str(repo / "tools/mail"))
    from check_store import execute

    record = {"status": "RUNNING", "source_commit": head, "source_tree": git("rev-parse", head + "^{tree}"),
              "source_base": MAIN, "prior_qualified_source": PRIOR, "runs": [],
              "started_at_utc": datetime.now(timezone.utc).isoformat(), "fixture_root": str(fixture_root),
              "runtime_receipt_sha256": sha(runtime / "runtime.json"),
              "python_executable": str(Path(sys.executable).resolve()), "python_version": sys.version,
              "native_environment": {name: env[name] for name in sorted(set(fixture_plan["environment_paths"]) | set(fixture_plan["literal_environment"]))},
              "github_actions_queried_or_awaited": False, "prior_application_cases_added_to_delta": 0,
              "prior_python_controls_added_to_delta": 0,
              "rejected_attempts_added_to_delta": 0,
              "rejected_attempt_sources": ["aea5d91af0083bc088d599ed767188f0bb071195", "c0c71a26e014cadda7a1f42244e710509dea5f6c", "fce543dedb1217804f67de088ef9c287e8a2edca", "26df787326f58a002b62241b7feb52acff089f2f"],
              "preserved_pre_resolution_receipt_sha256": sha(output / "prior-resolution/receipt.json")}

    def save() -> None:
        write(output / "execution.json", record)

    def run(name: str, command: list[str], result: Path | None = None) -> None:
        print("START " + name, flush=True)
        log = output / (name + ".log")
        row = {"name": name, "command": command, "cwd": str(repo), "log": log.name}
        record["runs"].append(row)
        save()
        with log.open("wb") as stream:
            try:
                code = execute(command, cwd=repo, env=env, stdout=stream, timeout=args.command_timeout)
            except (OSError, subprocess.TimeoutExpired) as error:
                code = 124 if isinstance(error, subprocess.TimeoutExpired) else 127
                row["runner_error"] = repr(error)
        row.update(exit_code=code, log_sha256=sha(log), accepted=code == 0)
        if result is not None:
            if result.is_file():
                value = json.loads(result.read_text())
                row.update(receipt=str(result.relative_to(output)), receipt_sha256=sha(result))
                row["accepted"] = row["accepted"] and (value.get("passed") is True or value.get("success") is True or value.get("status") == "PASS")
            else:
                row["accepted"] = False
        save()
        if not row["accepted"]:
            raise RuntimeError(name + " failed; preserve its raw evidence")

    save()
    before_runtime = None
    try:
        # Use Dart directly: Flutter's migration step would edit an unrelated
        # analysis_options.yaml. No source restoration is part of this gate.
        run("locked-workspace-resolution", [str(runtime / "bin/dart"), "pub", "get", "--offline", "--enforce-lockfile"])
        if snapshot(source_paths) != before_source or snapshot(runtime_paths) != stable_runtime or not clean():
            raise RuntimeError("Locked resolution changed source or stable runtime")
        for name in ("package_config.json", "package_graph.json"):
            runtime_paths["workspace/" + name] = repo / ".dart_tool" / name
            shutil.copy2(repo / ".dart_tool" / name, output / name)
        before_runtime = snapshot(runtime_paths)
        write(output / "runtime-before.json", before_runtime)
        run("delta-continuity", [sys.executable, "-B", str(directory / "verify-delta-continuity.py"),
                                "--repo", str(repo), "--runtime", str(runtime), "--source", head,
                                "--evidence", str(output), "--output", str(output / "continuity.json")], output / "continuity.json")
        run("bundle-controls", [sys.executable, "-B", "-m", "unittest", "discover", "-s", "tools/proofing/ayaspell",
                                "-p", "test_build_bundle*.py", "-v"])
        run("packaging-controls", [sys.executable, "-B", "-m", "unittest", "discover", "-s",
                                   "packages/quds_proofing_hunspell/tool", "-p", "test_build.py", "-v"])
        for name, path in plans.items():
            run(name, [sys.executable, "-B", str(shared / "run_checks.py"), "--head", head, "--base", MAIN,
                       "--runtime", str(runtime), "--plan", str(path), "--output", str(output / name),
                       "--command-timeout", str(args.command_timeout)], output / name / "verification.json")
        js = output / "hunspell-browser.js"
        run("hunspell-browser-compile", [str(runtime / "bin/dart"), "compile", "js", "-O2",
                                         "packages/quds_proofing_hunspell/tool/web_compile_check.dart", "-o", str(js)])
        if not js.is_file() or not js.stat().st_size:
            raise RuntimeError("Browser compile produced no executable")
        record["browser_compile_outputs"] = {p.name: {"bytes": p.stat().st_size, "sha256": sha(p)} for p in output.glob("hunspell-browser.js*") if p.is_file()}
        record["status"] = "PASS"
    except BaseException as error:
        record.update(status="FAIL", error=repr(error))
    finally:
        after_source, after_runtime = snapshot(source_paths), snapshot(runtime_paths)
        write(output / "source-after.json", after_source)
        write(output / "runtime-after.json", after_runtime)
        record.update(source_unchanged=before_source == after_source,
                      runtime_unchanged=before_runtime is not None and before_runtime == after_runtime,
                      source_head_unchanged=git("rev-parse", "HEAD") == head,
                      tracked_worktree_clean_after=clean(), finished_at_utc=datetime.now(timezone.utc).isoformat())
        if not all(record[k] for k in ("source_unchanged", "runtime_unchanged", "source_head_unchanged", "tracked_worktree_clean_after")):
            record["status"] = "FAIL"
        record["manifest_sha256"] = {p.name: sha(p) for p in output.iterdir() if p.is_file() and p.name in {
            "source-before.json", "source-after.json", "runtime-pre-resolution.json", "runtime-before.json", "runtime-after.json",
            "prior-execution.json", "prior-source-before.json", "prior-runtime-before.json", "prior-independent-summary.json",
            "package_config.json", "package_graph.json"}}
        save()
    print(record["status"] + ": " + str(output / "execution.json"), flush=True)
    return 0 if record["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
