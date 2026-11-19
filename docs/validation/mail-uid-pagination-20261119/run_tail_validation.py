#!/usr/bin/env python3
"""Qualify the current Studio/proofing tail and carry forward exact Mail inputs.

Pass --replay-mail to execute the core/store and five Mail native cohorts afresh
instead of relying on the independently audited historical subset.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import gzip
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile


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
    parser.add_argument("--replay-mail", action="store_true")
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
    plans = {name: directory / ("tail-" + name + "-plan.json") for name in ("native", "node")}
    replay_plan = directory / "mail-replay-plan.json"
    plan_data = {name: json.loads(path.read_text()) for name, path in plans.items()}
    tracked = set(git("ls-files", "-z").split("\0"))
    def untracked_inputs() -> list[str]:
        return [
            path for path in git("ls-files", "--others", "--exclude-standard", "-z").split("\0")
            if path.startswith(("packages/", "apps/", "third_party/", "tools/proofing/ayaspell/"))
        ]

    untracked_product = untracked_inputs()
    if untracked_product:
        raise RuntimeError("Commit product inputs before execution: " + repr(untracked_product))
    analyzed = set(plan_data["native"]["analysis"])
    formatted = set(plan_data["native"]["format"])
    changed = {
        path for path in git("diff", "--name-only", "--diff-filter=ACMRT", "-z", base, head).split("\0")
        if path.endswith(".dart") and path.startswith(("packages/", "apps/", "third_party/"))
    }
    if changed - analyzed or changed - formatted:
        raise RuntimeError("Changed product Dart paths missing strict checks: " + repr(sorted((changed - analyzed) | (changed - formatted))))
    required = {str(path.relative_to(repo)) for path in [Path(__file__), *plans.values(), replay_plan]}
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
    runtime_paths["workspace/package_config.json"] = repo / ".dart_tool/package_config.json"
    runtime_paths["sdk/flutter_tools/package_config.json"] = runtime / "flutter/packages/flutter_tools/.dart_tool/package_config.json"
    source_paths = {
        name: repo / name for name in tracked
        if name.startswith(("packages/", "apps/", "third_party/", "tools/mail/", "tools/proofing/ayaspell/"))
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
    carryforward = None
    if not args.replay_mail:
        prior = directory / "attempt-162f53c0"
        audit_path = prior / "accepted-mail-audit.json"
        if digest(audit_path) != "c73e854e44d7d39979190fc946e691a8588d890e367d9e697245769788a06a7d":
            raise RuntimeError("The independently audited Mail carryforward receipt changed")
        audit = json.loads(audit_path.read_text())
        if (audit["status"] != "PASS" or audit["aggregate_attempt_status"] != "FAIL"
                or audit["source_commit"] != "162f53c0aff2314d88df912f9a64c0838e2a9da4"
                or audit["passed_executions"] != 953):
            raise RuntimeError("Unexpected historical Mail subset identity")
        cases_bytes = gzip.decompress((prior / "accepted-mail-cases.json.gz").read_bytes())
        if hashlib.sha256(cases_bytes).hexdigest() != audit["case_inventory_sha256"]:
            raise RuntimeError("The accepted Mail case inventory changed")
        cases = json.loads(cases_bytes)
        if len(cases) != 953 or any(c["result"] != "success" or c["skipped"] for c in cases):
            raise RuntimeError("The carried case inventory contains an invalid result")
        index = json.loads((prior / "attempt-162f53c0.tar.index.json").read_text())
        archive = prior / index["archive"]
        if digest(archive) != index["archive_sha256"]:
            raise RuntimeError("The retained source attempt archive changed")
        inventory = json.loads((prior / "evidence-files.json").read_text())
        if digest(prior / "evidence-files.json") != audit["evidence_file_inventory_sha256"]:
            raise RuntimeError("The audited attempt inventory changed")
        with tarfile.open(archive) as bundle:
            members = bundle.getmembers()
            if len(members) != len(inventory) or {m.name for m in members} != set(inventory):
                raise RuntimeError("Retained attempt archive membership changed")
            for name, expected in inventory.items():
                data = bundle.extractfile(name).read()
                if len(data) != expected["bytes"] or hashlib.sha256(data).hexdigest() != expected["sha256"]:
                    raise RuntimeError("Retained attempt evidence changed: " + name)
            previous_source = json.load(bundle.extractfile("source-before.json"))
            previous_runtime = json.load(bundle.extractfile("runtime-before.json"))
        prefixes = ("packages/quds_mail_core/", "packages/quds_mail_store/", "packages/quds_mail_transport/",
                    "packages/quds_mail_mime/", "packages/quds_mail_ui/", "third_party/enough_mail/")
        def mail_input(name: str) -> bool:
            return name.startswith(prefixes) or name == ".fvmrc" or (
                "/" not in name and Path(name).suffix in {".yaml", ".lock"})
        old_mail = {name: identity for name, identity in previous_source.items() if mail_input(name)}
        current_mail = {name: identity for name, identity in before_source.items() if mail_input(name)}
        if old_mail != current_mail:
            raise RuntimeError("Mail product/dependency input closure changed; use --replay-mail")
        runtime_differences = [name for name, identity in previous_runtime.items()
                               if name != "runtime/runtime.json" and before_runtime.get(name) != identity]
        if runtime_differences:
            raise RuntimeError("Previously qualified runtime inputs changed; use --replay-mail: " + repr(runtime_differences))
        carryforward = {"status": "PASS", "source_commit": audit["source_commit"],
                        "target_commit": head, "historical_aggregate_status": "FAIL",
                        "historical_final_node_gate": "NOT RUN", "accepted_executions": 953,
                        "accepted_distinct_scenarios": audit["distinct_scenarios"],
                        "audit_sha256": digest(audit_path), "case_inventory_sha256": audit["case_inventory_sha256"],
                        "mail_input_count": len(current_mail), "mail_inputs": current_mail,
                        "unchanged_runtime_records": len(previous_runtime) - 1,
                        "runtime_receipt_change": "Preserved prior receipt; added verified Poppler and workspace preparation metadata only",
                        "scope": "Core/store plus five accepted Mail native cohorts only; Arabic, editor and Hunspell are freshly executed"}
        write_json(output / "mail-carryforward-before.json", carryforward)
    native_preparation = receipt.get("hunspell_preparation", {})
    build_verification = json.loads(Path(native_preparation["build_verification"]).read_text())
    for name, expected in build_verification["compiled_inputs"].items():
        if digest(repo / name) != expected:
            raise RuntimeError("Hunspell compiled source changed after its build: " + name)
    lifecycle = json.loads(Path(native_preparation["lifecycle_receipt"]).read_text())
    if digest(repo / lifecycle["source"]) != lifecycle["source_sha256"]:
        raise RuntimeError("Rebuild the native lifecycle fixture after changing its source")
    for environment, fixture in receipt.get("lifecycle_fixtures", {}).items():
        if (digest(repo / fixture["source"]) != fixture["source_sha256"]
                or digest(Path(fixture["library"])) != fixture["library_sha256"]
                or digest(Path(fixture["receipt"])) != fixture["receipt_sha256"]):
            raise RuntimeError("Rebuild/rebind the changed lifecycle fixture: " + environment)
    write_json(output / "source-before.json", before_source)
    write_json(output / "runtime-before.json", before_runtime)
    env = dict(os.environ, PUB_CACHE=str(runtime / "pub-cache"), FLUTTER_ROOT=str(runtime / "flutter"),
               CI="true", DART_SUPPRESS_ANALYTICS="true", FLUTTER_SUPPRESS_ANALYTICS="true",
               DASH__SUPPRESS_ANALYTICS="true", XDG_CONFIG_HOME=str(runtime / "config"),
               XDG_CACHE_HOME=str(runtime / "cache"), XDG_DATA_HOME=str(runtime / "data"),
               TMPDIR=str(runtime / "tmp"))
    env["PATH"] = str(runtime / "bin") + os.pathsep + env.get("PATH", "")
    qualification_environment = receipt.get("qualification_environment", {})
    required_environment = {"QUDS_HUNSPELL_TEST_LIBRARY", "QUDS_HUNSPELL_TEST_DICTIONARY",
                            "QUDS_HUNSPELL_LIFECYCLE_LIBRARY", "QUDS_HUNSPELL_LIVE_DOWNLOAD",
                            "QUDS_HUNSPELL_OWNERSHIP_LIBRARY", "QUDS_HUNSPELL_PROVIDER_LIFECYCLE_LIBRARY"}
    if set(qualification_environment) != required_environment or any(
        not isinstance(value, str) for value in qualification_environment.values()
    ) or qualification_environment["QUDS_HUNSPELL_LIVE_DOWNLOAD"] != "1":
        raise RuntimeError("Bind and enable the genuine native Hunspell and dictionary qualification environment")
    for name in ("QUDS_HUNSPELL_TEST_LIBRARY", "QUDS_HUNSPELL_LIFECYCLE_LIBRARY",
                 "QUDS_HUNSPELL_OWNERSHIP_LIBRARY", "QUDS_HUNSPELL_PROVIDER_LIFECYCLE_LIBRARY"):
        path = qualification_environment[name]
        if path not in receipt.get("additional_inputs", {}):
            raise RuntimeError("The selected native library is not hash-bound: " + name)
    dictionary = Path(qualification_environment["QUDS_HUNSPELL_TEST_DICTIONARY"])
    if not dictionary.is_dir() or len(list(dictionary.iterdir())) != 8 or any(
        not path.is_file() or str(path) not in receipt.get("additional_inputs", {})
        for path in dictionary.iterdir()
    ):
        raise RuntimeError("Bind all eight dictionary catalog files before qualification")
    for name in list(env):
        if name.startswith("QUDS_HUNSPELL_"):
            del env[name]
    env.update(qualification_environment)
    env["QUDS_SHOTS_DIR"] = str(output / "studio-shots")
    poppler = Path(receipt["tail_preparation"]["poppler_wrapper"])
    if str(poppler) not in receipt["additional_inputs"]:
        raise RuntimeError("Bind the actual Poppler entry point before gallery rendering")
    env["PATH"] = str(poppler.parent) + os.pathsep + env["PATH"]
    record = {"status": "RUNNING", "source_commit": head, "source_base": base,
              "source_tree": git("rev-parse", "HEAD^{tree}"), "runs": [],
              "started_at_utc": datetime.now(timezone.utc).isoformat(),
              "runtime_receipt_sha256": digest(runtime / "runtime.json"),
              "qualification_environment": qualification_environment,
              "studio_screenshot_directory": env["QUDS_SHOTS_DIR"],
              "mail_qualification_mode": "fresh-replay" if args.replay_mail else "audited-carryforward",
              "carried_mail_executions": 0 if args.replay_mail else 953,
              "github_actions_queried_or_awaited": False}

    def save() -> None:
        write_json(output / "execution.json", record)

    def run(name: str, command: list[str], result: Path | None = None,
            artifacts: list[Path] | None = None) -> None:
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
            row["accepted"] = process.returncode == 0 and (content.get("success") is True or content.get("status") == "PASS")
        else:
            row["accepted"] = process.returncode == 0 and result is None
        if artifacts is not None:
            row["artifacts"] = {
                str(path.relative_to(output)): {"bytes": path.stat().st_size, "sha256": digest(path)}
                for path in artifacts if path.is_file()
            }
            row["accepted"] = row["accepted"] and len(row["artifacts"]) == len(artifacts) and all(
                item["bytes"] > 0 for item in row["artifacts"].values()
            )
        save()
        if process.returncode or not row["accepted"]:
            raise RuntimeError(name + " failed; preserve its raw evidence")

    save()
    try:
        for name, path in (("shared-runner-controls", shared / "test_run_checks.py"),
                           ("runtime-controls", shared / "runtime/test_restore_runtime.py")):
            run(name, [sys.executable, str(path)])
        run("ayaspell-offline-controls", [sys.executable, "-m", "unittest", "discover",
                                          "-s", "tools/proofing/ayaspell", "-p", "test_*.py", "-v"])
        if not args.replay_mail:
            run("mail-runner-controls", [sys.executable, "-m", "unittest", "discover",
                                          "-s", "tools/mail", "-p", "test_check_store.py", "-v"])
        run("locked-resolution", [str(runtime / "bin/dart"), "pub", "get", "--offline", "--enforce-lockfile"])
        run("hunspell-worker-syntax", [receipt["node_runtime"]["path"], "--check",
                                       str(repo / "packages/quds_proofing_hunspell/web/hunspell_worker.mjs")])
        hunspell_web_output = output / "hunspell-web-entry.js"
        run("hunspell-web-entry", [str(runtime / "bin/dart"), "compile", "js",
                                   str(repo / "packages/quds_proofing_hunspell/tool/web_compile_check.dart"),
                                   "-o", str(hunspell_web_output)], artifacts=[hunspell_web_output])
        if args.replay_mail:
            run("core-store", [sys.executable, str(repo / "tools/mail/check_store.py"),
                               "--flutter-sdk", str(runtime / "flutter"), "--offline", "--direct-tests",
                               "--command-timeout", str(args.command_timeout), "--output", str(output / "core-store")],
                output / "core-store/receipt.json")
            run("mail-replay", [sys.executable, str(shared / "run_checks.py"), "--head", head, "--base", base,
                                "--runtime", str(runtime), "--plan", str(replay_plan), "--output", str(output / "mail-replay"),
                                "--command-timeout", str(args.command_timeout)], output / "mail-replay/verification.json")
        for name, path in plans.items():
            run(name, [sys.executable, str(shared / "run_checks.py"), "--head", head, "--base", base,
                       "--runtime", str(runtime), "--plan", str(path), "--output", str(output / name),
                       "--command-timeout", str(args.command_timeout)], output / name / "verification.json")
        gallery = runtime / "tmp/quds_gallery_shots"
        if not gallery.is_dir() or not any(gallery.glob("*.pdf")) or not any(gallery.glob("*.png")):
            raise RuntimeError("The requested gallery rendering suite produced no PDF/PNG artifacts")
        shutil.copytree(gallery, output / "gallery-renderings")
        screenshots = output / "studio-shots"
        if {p.name for p in screenshots.glob("*.png")} != {"word.png", "excel.png", "powerpoint.png", "pdf.png"}:
            raise RuntimeError("The requested Studio rendering suite did not emit all four frames")
        record["rendered_artifacts"] = {
            str(path.relative_to(output)): {"bytes": path.stat().st_size, "sha256": digest(path)}
            for directory in (screenshots, output / "gallery-renderings")
            for path in sorted(directory.rglob("*")) if path.is_file()
        }
        record["status"] = "PASS"
    except BaseException as error:
        record.update(status="FAIL", error=repr(error))
    finally:
        after_source, after_runtime = snapshot(source_paths), snapshot(runtime_paths)
        write_json(output / "source-after.json", after_source)
        write_json(output / "runtime-after.json", after_runtime)
        if carryforward is not None:
            carried_after = {name: after_source[name] for name in carryforward["mail_inputs"]}
            carryforward_after = {**carryforward, "source_unchanged_during_gate": carried_after == carryforward["mail_inputs"]}
            write_json(output / "mail-carryforward-after.json", carryforward_after)
            record["mail_carryforward_unchanged"] = carryforward_after["source_unchanged_during_gate"]
        record.update(source_unchanged=before_source == after_source, runtime_unchanged=before_runtime == after_runtime,
                      source_head_unchanged=git("rev-parse", "HEAD") == head,
                      tracked_worktree_clean_after=not git("status", "--porcelain=v1", "--untracked-files=no"),
                      untracked_qualification_inputs_after=untracked_inputs(),
                      finished_at_utc=datetime.now(timezone.utc).isoformat())
        if record["untracked_qualification_inputs_after"] or not all(record[key] for key in ("source_unchanged", "runtime_unchanged", "source_head_unchanged", "tracked_worktree_clean_after")):
            record["status"] = "FAIL"
        save()
    print(record["status"] + ": " + str(output / "execution.json"), flush=True)
    return 0 if record["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
