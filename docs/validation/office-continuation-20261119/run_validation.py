#!/usr/bin/env python3
"""Run fresh local Office/Mail qualification on a committed source checkpoint.

Uses the existing strict reporter, timeout/process cleanup and core/store
harnesses without changing them. Every product test must pass without skips.
No GitHub Actions API, status, workflow or artifact is queried or awaited.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tarfile
import time


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--head", required=True)
    parser.add_argument("--base", default="b070e228a749e22cc8ce2098029a76ab5fb8eccb")
    parser.add_argument("--runtime", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--command-timeout", type=int, default=900)
    args = parser.parse_args()
    if args.command_timeout <= 0:
        parser.error("--command-timeout must be positive")
    directory = Path(__file__).resolve().parent
    repo = directory.parents[2]
    runtime, output = args.runtime.resolve(), args.output.resolve()
    for name, path in (("runtime", runtime), ("output", output)):
        if path == repo or repo in path.parents:
            raise RuntimeError(name + " must be outside the frozen source checkout")
    if output == runtime or runtime in output.parents or output in runtime.parents:
        raise RuntimeError("Keep output separate from the prepared runtime")
    if output.exists() and any(output.iterdir()):
        raise RuntimeError("Choose an empty output directory; preserve prior attempts")
    output.mkdir(parents=True, exist_ok=True)

    def git(*arguments: str) -> str:
        return subprocess.check_output(["git", "-C", str(repo), *arguments], text=True).rstrip("\n")

    head = git("rev-parse", "--verify", args.head + "^{commit}")
    base = git("rev-parse", "--verify", args.base + "^{commit}")
    if git("rev-parse", "HEAD") != head or git("status", "--porcelain=v1", "--untracked-files=no"):
        raise RuntimeError("Commit source, plans and harness before freezing HEAD")
    index_tree = git("write-tree")
    tracked = set(filter(None, git("ls-files", "-z").split("\0")))
    product_prefixes = ("packages/", "apps/", "third_party/", "tools/mail/", "tools/proofing/ayaspell/")

    def untracked_inputs() -> list[str]:
        return [name for name in git("ls-files", "--others", "--exclude-standard", "-z").split("\0")
                if name.startswith(product_prefixes)]

    if untracked_inputs():
        raise RuntimeError("Commit product inputs before execution: " + repr(untracked_inputs()))
    plans = {name: directory / (name + "-plan.json") for name in ("native", "node")}
    plan_data = {name: read_json(path) for name, path in plans.items()}
    changed = {name for name in git("diff", "--name-only", "--diff-filter=ACMRT", "-z", base, head).split("\0")
               if name.endswith(".dart") and name.startswith(("packages/", "apps/", "third_party/"))}
    for kind in ("analysis", "format"):
        missing = changed - set(plan_data["native"][kind])
        if missing:
            raise RuntimeError("Changed Dart paths missing " + kind + ": " + repr(sorted(missing)))
    for package in ("quds_office_editor/example", "quds_proofing_hunspell", "quds_arabic_morph"):
        cwd = "packages/" + package
        actual = {str(path.relative_to(repo / cwd)) for path in (repo / cwd / "test").glob("*_test.dart")}
        planned = {name for group in plan_data["native"]["groups"] if group["cwd"] == cwd for name in group["tests"]}
        if actual != planned:
            raise RuntimeError("Current native test selection differs for " + cwd + ": " + repr(sorted(actual ^ planned)))
    native_mail = [group for group in plan_data["native"]["groups"]
                   if group["cwd"].startswith("packages/quds_mail_") or group["cwd"] == "third_party/enough_mail"]
    if sum(len(group["tests"]) for group in native_mail) != 64:
        raise RuntimeError("The full 64-suite native Mail replay is required")

    receipt_path = runtime / "runtime.json"
    receipt = read_json(receipt_path)
    if receipt.get("status") != "ready" or not receipt.get("archive", {}).get("verified"):
        raise RuntimeError("A verified ready runtime is required")
    if digest(receipt_path) != digest(directory / "runtime/runtime.json"):
        raise RuntimeError("Commit the exact operational runtime receipt before execution")
    if digest(repo / "pubspec.lock") != receipt["workspace_lock_sha256"]:
        raise RuntimeError("The workspace lock differs from the prepared runtime")
    preparation_index = read_json(directory / "runtime/preparation-evidence.index.json")
    archive = directory / "runtime" / preparation_index["archive"]
    if archive.stat().st_size != preparation_index["archive_bytes"] or digest(archive) != preparation_index["archive_sha256"]:
        raise RuntimeError("The prepared runtime archive differs from its index")
    with tarfile.open(archive) as bundle:
        if {member.name for member in bundle.getmembers()} != set(preparation_index["members"]):
            raise RuntimeError("Runtime preparation archive membership changed")
        for name, identity in preparation_index["members"].items():
            data = bundle.extractfile(name).read()
            if len(data) != identity["bytes"] or hashlib.sha256(data).hexdigest() != identity["sha256"]:
                raise RuntimeError("Runtime preparation evidence changed: " + name)
    native_preparation = receipt["hunspell_preparation"]
    build_verification = read_json(Path(native_preparation["build_verification"]))
    for provenance in (build_verification, receipt["morphology_preparation"]):
        for name, expected in provenance["compiled_inputs"].items():
            if digest(repo / name) != expected:
                raise RuntimeError("Native compiled source changed; rebuild before execution: " + name)
    for environment, fixture in receipt["lifecycle_fixtures"].items():
        if (digest(repo / fixture["source"]) != fixture["source_sha256"]
                or digest(Path(fixture["library"])) != fixture["library_sha256"]
                or digest(Path(fixture["receipt"])) != fixture["receipt_sha256"]):
            raise RuntimeError("Native lifecycle fixture changed: " + environment)
    qualification = {**receipt["qualification_environment"], **receipt["morphology_environment"]}
    libraries = {"QUDS_HUNSPELL_TEST_LIBRARY", "QUDS_HUNSPELL_LIFECYCLE_LIBRARY",
                 "QUDS_HUNSPELL_OWNERSHIP_LIBRARY", "QUDS_HUNSPELL_PROVIDER_LIFECYCLE_LIBRARY",
                 "QUDS_ARABIC_MORPH_TEST_LIBRARY"}
    expected_environment = libraries | {"QUDS_HUNSPELL_TEST_DICTIONARY", "QUDS_HUNSPELL_LIVE_DOWNLOAD",
                                        "QUDS_ARABIC_MORPH_TEST_BUNDLE", "QUDS_ARABIC_MORPH_LIVE_DOWNLOAD"}
    if set(qualification) != expected_environment or any(not isinstance(value, str) for value in qualification.values()):
        raise RuntimeError("Bind the complete native qualification environment")
    for key in ("QUDS_HUNSPELL_LIVE_DOWNLOAD", "QUDS_ARABIC_MORPH_LIVE_DOWNLOAD"):
        if qualification[key] != "1":
            raise RuntimeError("Enable the pinned live-download qualification: " + key)
    for key in libraries:
        if qualification[key] not in receipt["additional_inputs"] or not Path(qualification[key]).stat().st_size:
            raise RuntimeError("Selected native library is not a nonempty bound input: " + key)
    for key, count in (("QUDS_HUNSPELL_TEST_DICTIONARY", 8), ("QUDS_ARABIC_MORPH_TEST_BUNDLE", 4)):
        files = list(Path(qualification[key]).iterdir())
        if len(files) != count or any(not path.is_file() or str(path) not in receipt["additional_inputs"] for path in files):
            raise RuntimeError("Bind every catalog file: " + key)

    shared = repo / "docs/validation/document-review-notes-20261118"
    required = {str(path.relative_to(repo)) for path in (Path(__file__), *plans.values())}
    required.update(name for plan in plan_data.values() for name in plan["extra_inputs"])
    if not required <= tracked:
        raise RuntimeError("Commit all driver/plan/evidence inputs: " + repr(sorted(required - tracked)))
    source_paths = {name: repo / name for name in tracked
                    if name.startswith(product_prefixes) or name.startswith(".github/")
                    or ("/" not in name and Path(name).suffix in {".yaml", ".lock"}) or name == ".fvmrc"}
    source_paths.update({name: repo / name for name in required})
    retained = read_json(runtime / "retained-inputs.json")
    runtime_paths = {"runtime/" + name: runtime / name for name in retained}
    for name in ("runtime.json", "retained-inputs.json", "pub-cache-receipt.json", "cache-omissions.json",
                 "archive-members.json", "env.sh", "native-env.sh", "bin/dart", "bin/flutter"):
        runtime_paths["runtime/" + name] = runtime / name
    runtime_paths.update({"additional/" + name: Path(name) for name in receipt["additional_inputs"]})
    runtime_paths["workspace/package_config.json"] = repo / ".dart_tool/package_config.json"
    runtime_paths["workspace/package_graph.json"] = repo / ".dart_tool/package_graph.json"
    runtime_paths["sdk/flutter_tools/package_config.json"] = runtime / "flutter/packages/flutter_tools/.dart_tool/package_config.json"
    runtime_paths["tools/python"] = Path(sys.executable).resolve()
    poppler = Path(receipt["tail_preparation"]["poppler_wrapper"])
    if str(poppler) not in receipt["additional_inputs"]:
        raise RuntimeError("The actual Poppler launcher must be bound")
    renderer_cwd, renderer_bin = output / "renderer-work", output / "renderer-bin"
    renderer_cwd.mkdir()
    renderer_bin.mkdir()
    renderer = renderer_bin / "pdftoppm"
    renderer.write_text("#!/bin/sh\nset -eu\ncd " + shlex.quote(str(renderer_cwd))
                        + "\nexec " + shlex.quote(str(poppler)) + ' "$@"\n')
    renderer.chmod(0o755)
    runtime_paths["generated/renderer-launcher"] = renderer
    gallery = runtime / "tmp/quds_gallery_shots"
    if gallery.exists():
        shutil.move(str(gallery), output / "preexisting-gallery-not-current-evidence")

    def snapshot(paths: dict[str, Path]) -> dict[str, str | None]:
        return {name: digest(path) if path.is_file() else None for name, path in sorted(paths.items())}

    before_source, before_runtime = snapshot(source_paths), snapshot(runtime_paths)
    if any(value is None for value in (*before_source.values(), *before_runtime.values())):
        raise RuntimeError("A required frozen source/runtime input is missing")
    for name, identity in retained.items():
        if before_runtime["runtime/" + name] != identity["sha256"]:
            raise RuntimeError("Retained runtime input changed: " + name)
    for name, expected in receipt["additional_inputs"].items():
        if before_runtime["additional/" + name] != expected:
            raise RuntimeError("Additional runtime input changed: " + name)
    write_json(output / "source-before.json", before_source)
    write_json(output / "runtime-before.json", before_runtime)
    env = dict(os.environ, PUB_CACHE=str(runtime / "pub-cache"), FLUTTER_ROOT=str(runtime / "flutter"),
               CI="true", DART_SUPPRESS_ANALYTICS="true", FLUTTER_SUPPRESS_ANALYTICS="true",
               DASH__SUPPRESS_ANALYTICS="true", XDG_CONFIG_HOME=str(runtime / "config"),
               XDG_CACHE_HOME=str(runtime / "cache"), XDG_DATA_HOME=str(runtime / "data"), TMPDIR=str(runtime / "tmp"))
    env["PATH"] = os.pathsep.join((str(renderer_bin), str(runtime / "bin"), env.get("PATH", "")))
    for name in list(env):
        if name.startswith(("QUDS_HUNSPELL_", "QUDS_ARABIC_MORPH_")):
            del env[name]
    env.update(qualification)
    env["QUDS_SHOTS_DIR"] = str(output / "studio-shots")
    sys.path.insert(0, str(repo / "tools/mail"))
    from check_store import execute

    record = {"status": "RUNNING", "source_commit": head, "source_base": base,
              "source_tree": git("rev-parse", "HEAD^{tree}"), "runs": [],
              "started_at_utc": datetime.now(timezone.utc).isoformat(),
              "runtime_receipt_sha256": digest(receipt_path), "source_input_count": len(before_source),
              "runtime_input_count": len(before_runtime), "qualification_environment": qualification,
              "planned_suite_files": {name: sum(len(group["tests"]) for group in plan["groups"])
                                      for name, plan in plan_data.items()},
              "mode": "fresh-current-source-execution", "historical_executions_added": 0,
              "github_actions_queried_or_awaited": False}

    def save() -> None:
        write_json(output / "execution.json", record)

    def run(name: str, command: list[str], result: Path | None = None,
            artifacts: list[Path] | None = None, timeout: int | None = None) -> None:
        log, stderr_log = output / (name + ".log"), output / (name + ".stderr.log")
        row = {"name": name, "command": command, "log": log.name, "stderr_log": stderr_log.name,
               "started_at_utc": datetime.now(timezone.utc).isoformat()}
        record["runs"].append(row)
        save()
        print("START " + name, flush=True)
        started = time.monotonic()
        with log.open("wb") as stream, stderr_log.open("wb") as error_stream:
            try:
                row["exit_code"] = execute(command, cwd=repo, env=env, stdout=stream, stderr=error_stream,
                                           timeout=timeout or args.command_timeout)
            except (OSError, subprocess.TimeoutExpired) as error:
                row.update(exit_code=124 if isinstance(error, subprocess.TimeoutExpired) else 127, error=repr(error))
        row.update(elapsed_seconds=round(time.monotonic() - started, 3),
                   log_sha256=digest(log), stderr_log_sha256=digest(stderr_log), accepted=row["exit_code"] == 0)
        if result is not None:
            row["accepted"] = row["accepted"] and result.is_file()
            if result.is_file():
                content = read_json(result)
                row.update(receipt=str(result.relative_to(output)), receipt_sha256=digest(result))
                row["accepted"] = row["accepted"] and (content.get("success") is True or content.get("status") == "PASS")
        if artifacts is not None:
            row["artifacts"] = {str(path.relative_to(output)): {"bytes": path.stat().st_size, "sha256": digest(path)}
                                for path in artifacts if path.is_file()}
            row["accepted"] = row["accepted"] and len(row["artifacts"]) == len(artifacts) and all(
                item["bytes"] > 0 for item in row["artifacts"].values())
        save()
        print(json.dumps({key: row[key] for key in ("name", "exit_code", "elapsed_seconds", "accepted")}), flush=True)
        if not row["accepted"]:
            raise RuntimeError(name + " failed; preserve its complete raw evidence")

    save()
    try:
        for name, script in (("shared-runner-controls", shared / "test_run_checks.py"),
                             ("runtime-controls", shared / "runtime/test_restore_runtime.py")):
            run(name, [sys.executable, str(script)])
        for name, path in (("ayaspell-offline-controls", "tools/proofing/ayaspell"),
                           ("hunspell-build-controls", "packages/quds_proofing_hunspell/tool")):
            run(name, [sys.executable, "-m", "unittest", "discover", "-s", path, "-p", "test_*.py", "-v"])
        run("locked-resolution", [str(runtime / "bin/dart"), "pub", "get", "--offline", "--enforce-lockfile"])
        for name, package, worker in (("hunspell", "quds_proofing_hunspell", "hunspell_worker.mjs"),
                                       ("arabic-morphology", "quds_arabic_morph", "arabic_morph_worker.mjs")):
            run(name + "-worker-syntax", [receipt["node_runtime"]["path"], "--check",
                                         str(repo / "packages" / package / "web" / worker)])
            javascript = output / (name + "-web-entry.js")
            run(name + "-web-entry", [str(runtime / "bin/dart"), "compile", "js",
                                     str(repo / "packages" / package / "tool/web_compile_check.dart"),
                                     "-o", str(javascript)], artifacts=[javascript])
        run("core-store", [sys.executable, str(repo / "tools/mail/check_store.py"),
                           "--flutter-sdk", str(runtime / "flutter"), "--offline", "--direct-tests",
                           "--command-timeout", str(args.command_timeout), "--output", str(output / "core-store")],
            output / "core-store/receipt.json", timeout=args.command_timeout * 16)
        for name, path in plans.items():
            run(name, [sys.executable, str(shared / "run_checks.py"), "--head", head, "--base", base,
                       "--runtime", str(runtime), "--plan", str(path), "--output", str(output / name),
                       "--command-timeout", str(args.command_timeout)], output / name / "verification.json",
                timeout=args.command_timeout * (len(plan_data[name]["groups"]) + 4))
        screenshots = output / "studio-shots"
        if {path.name for path in screenshots.glob("*.png")} != {"word.png", "excel.png", "powerpoint.png", "pdf.png"}:
            raise RuntimeError("Studio did not emit all four requested frame images")
        if not gallery.is_dir() or not any(gallery.glob("*.pdf")) or not any(gallery.glob("*.png")):
            raise RuntimeError("The gallery rendering suite did not produce fresh PDF/PNG artifacts")
        core = read_json(output / "core-store/receipt.json")
        counts = {"core-store": {key: sum(check.get("tests", {}).get(key, 0) for check in core["checks"])
                                 for key in ("passed", "failed", "skipped")}}
        for name in plans:
            result = read_json(output / name / "verification.json")
            counts[name] = {key: result[key] for key in ("passed", "failed", "skipped")}
        record["test_execution_counts"] = counts
        record["fresh_test_execution_total"] = sum(item["passed"] for item in counts.values())
        record["status"] = "PASS"
    except BaseException as error:
        record.update(status="FAIL", error=repr(error))
    finally:
        if gallery.is_dir():
            shutil.copytree(gallery, output / "gallery-renderings")
        record["rendered_artifacts"] = {
            str(path.relative_to(output)): {"bytes": path.stat().st_size, "sha256": digest(path)}
            for artifact_dir in (output / "studio-shots", output / "gallery-renderings")
            for path in sorted(artifact_dir.rglob("*")) if path.is_file()
        }
        after_source, after_runtime = snapshot(source_paths), snapshot(runtime_paths)
        write_json(output / "source-after.json", after_source)
        write_json(output / "runtime-after.json", after_runtime)
        record.update(source_unchanged=before_source == after_source, runtime_unchanged=before_runtime == after_runtime,
                      source_mismatches=[name for name in before_source if before_source[name] != after_source[name]],
                      runtime_mismatches=[name for name in before_runtime if before_runtime[name] != after_runtime[name]],
                      source_head_unchanged=git("rev-parse", "HEAD") == head,
                      source_index_unchanged=git("write-tree") == index_tree,
                      tracked_worktree_clean_after=not git("status", "--porcelain=v1", "--untracked-files=no"),
                      untracked_qualification_inputs_after=untracked_inputs(),
                      finished_at_utc=datetime.now(timezone.utc).isoformat())
        if record["untracked_qualification_inputs_after"] or not all(record[key] for key in (
                "source_unchanged", "runtime_unchanged", "source_head_unchanged", "source_index_unchanged", "tracked_worktree_clean_after")):
            record["status"] = "FAIL"
        record["manifest_sha256"] = {name: digest(output / name) for name in (
            "source-before.json", "source-after.json", "runtime-before.json", "runtime-after.json")}
        save()
    print(record["status"] + ": " + str(output / "execution.json"), flush=True)
    return 0 if record["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
