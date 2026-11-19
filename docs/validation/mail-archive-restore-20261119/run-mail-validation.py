#!/usr/bin/env python3
"""Run fresh mail acceptance offline against one preserved source commit.

Source the runtime environment first. This harness reuses the repository's
previously reviewed JSON-event parser and input hashing helpers. It runs no
GitHub Actions and performs no dependency resolution. Incoming GUI/VBA tests
have their own recorded harness and are not counted a second time here.
"""

import argparse
import concurrent.futures
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time


BASE = "0c29b5d8a0a92148dcd95f3282b4d43c462be20d"
SCRIPT = "docs/validation/mail-archive-restore-20261119/run-mail-validation.py"
HELPER = "docs/validation/mail-archive-portability-20261119/run-local-validation.py"
GUIDE = "docs/roadmaps/mail/archive-search.md"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expect-head", required=True)
    args = parser.parse_args()
    repo, output = args.repo.resolve(), args.output.resolve()
    if output.exists() or output.is_relative_to(repo):
        parser.error("output must be a new directory outside the repository")
    output.mkdir(parents=True)
    spec = importlib.util.spec_from_file_location("mail_validation_helpers", repo / HELPER)
    helpers = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helpers)
    helpers.DOCUMENT_INPUTS = {SCRIPT, HELPER, GUIDE}
    head = helpers.capture(["git", "rev-parse", "HEAD"], repo)
    if head != args.expect_head:
        raise RuntimeError("source HEAD changed before validation")
    product_dirty = helpers.git_paths(repo, [
        "diff", "--name-only", "HEAD", "--", "packages", "third_party", "apps", "tool", "tools",
    ])
    unknown_product = [name for name in helpers.git_paths(repo, [
        "ls-files", "--others", "--exclude-standard",
    ]) if name.startswith(helpers.SOURCE_ROOTS)]
    if product_dirty or unknown_product:
        raise RuntimeError(f"unpreserved product inputs: {product_dirty + unknown_product}")
    subprocess.run(["git", "merge-base", "--is-ancestor", BASE, head], cwd=repo, check=True)
    flutter_root = Path(os.environ["FLUTTER_ROOT"]).resolve()
    pub_cache = Path(os.environ["PUB_CACHE"]).resolve()
    dart = flutter_root / "bin/cache/dart-sdk/bin/dart"
    flutter = Path(shutil.which("flutter"))
    config = repo / ".dart_tool/package_config.json"
    test_package = next(p for p in json.loads(config.read_text())["packages"] if p["name"] == "test")
    test_cli = helpers.package_root(config, test_package) / "bin/test.dart"
    sqlite = helpers.sqlite_probe(repo / ".dart_tool/lib/libsqlite3.so")
    if sqlite["sha256"] != helpers.SQLITE_NATIVE_SHA256 or not sqlite["fts5"]:
        raise RuntimeError("default packaged SQLite identity/FTS5 check failed")

    def runtime_inputs():
        paths = {
            dart, flutter.resolve(), Path(shutil.which("node")).resolve(), config,
            repo / ".dart_tool/native_assets.yaml", repo / ".dart_tool/lib/libsqlite3.so",
            flutter_root / "bin/cache/flutter_tools.snapshot",
            flutter_root / "bin/cache/flutter.version.json",
        }
        for folder in [
            "bin/cache/dart-sdk/bin", "bin/cache/dart-sdk/lib",
            "bin/cache/artifacts/engine/linux-x64",
            "bin/cache/artifacts/engine/common/flutter_patched_sdk",
            "bin/cache/artifacts/engine/common/flutter_patched_sdk_product",
        ]:
            paths.update(p for p in (flutter_root / folder).rglob("*") if p.is_file())
        return {str(p): {"bytes": p.stat().st_size, "sha256": helpers.sha(p)} for p in sorted(paths)}

    before = helpers.source_manifest(repo)
    dependencies = helpers.dependency_manifest(config, pub_cache, flutter_root, repo)
    runtime = runtime_inputs()
    for name, value in [("source-before", before), ("dependencies-before", dependencies), ("runtime-before", runtime)]:
        helpers.write_manifest(output / (name + ".json.gz"), value)
    changed_dart = [p for p in helpers.changed_dart(repo, BASE) if p.startswith("packages/")]
    analysis = sorted(set([
        "packages/quds_mail_core", "packages/quds_mail_mime", "packages/quds_mail_store",
        "packages/quds_mail_ui", *changed_dart,
        *[str(p.relative_to(repo)) for p in (repo / "packages/quds_office_editor/example/lib").glob("studio_mail_archive*.dart")],
    ]))
    cohorts = []
    for package in ["quds_mail_core", "quds_mail_mime", "quds_mail_store"]:
        vm, node = [], []
        for path in sorted((repo / "packages" / package / "test").rglob("*_test.dart")):
            platform = re.search(r"@TestOn\(['\"]([^'\"]+)['\"]\)", path.read_text()[:4000])
            (node if platform and platform.group(1) in ("node", "js") else vm).append(str(path.relative_to(repo / "packages" / package)))
        cohorts.append((package + "-vm", "packages/" + package, vm, "vm"))
        if package == "quds_mail_store":
            # The query suite imports native SQLite and already runs on VM.
            # Only the manifest suite additionally exercises the portable API.
            node += ["test/archive_export_manifest_test.dart"]
        if node:
            cohorts.append((package + "-node", "packages/" + package, sorted(node), "node"))
    for name, package, pattern in [
        ("mail-ui", "packages/quds_mail_ui", "*_test.dart"),
        ("studio-mail", "packages/quds_office_editor/example", "studio_mail*_test.dart"),
    ]:
        files = [str(p.relative_to(repo / package)) for p in sorted((repo / package / "test").glob(pattern))]
        if name == "studio-mail":
            files.append("test/studio_saved_mail_test.dart")
        cohorts.append((name, package, sorted(files), "flutter"))
    helpers.write_json(output / "selection.json", {
        "source_head": head, "source_tree": helpers.capture(["git", "rev-parse", "HEAD^{tree}"], repo),
        "cohorts": [{"name": n, "package": p, "files": f, "platform": k} for n, p, f, k in cohorts],
        "analysis_targets": analysis, "formatted_files": changed_dart,
        "note": "The export-manifest suite additionally runs on Node to cover the portable public library. Native SQLite query tests run on VM only.",
    })

    def step(name, argv, cwd, files=(), env_add=None):
        folder = output / name
        folder.mkdir()
        env = {k: v for k, v in os.environ.items() if not k.startswith("QUDS_")}
        env.update(env_add or {})
        record = {"name": name, "argv": [str(a) for a in argv], "cwd": str(cwd),
                  "started_at_utc": helpers.now(), "expected_test_files": list(files),
                  "environment_overrides": env_add or {}}
        helpers.write_json(folder / "command.json", record)
        print(json.dumps({"started": name}), flush=True)
        start = time.monotonic()
        with (folder / "stdout.log").open("wb") as stdout, (folder / "stderr.log").open("wb") as stderr:
            process = subprocess.Popen(argv, cwd=cwd, env=env, stdout=stdout, stderr=stderr, start_new_session=True)
            try:
                record["exit_code"] = process.wait(timeout=1200)
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                record.update(exit_code=process.returncode, interrupted=True)
        record.update(elapsed_seconds=round(time.monotonic() - start, 3), finished_at_utc=helpers.now(),
                      stdout_sha256=helpers.sha(folder / "stdout.log"), stderr_sha256=helpers.sha(folder / "stderr.log"))
        record["accepted"] = record["exit_code"] == 0 and not record.get("interrupted")
        if files:
            parsed = helpers.parse_tests(folder / "stdout.log", repo, files, cwd)
            helpers.write_manifest(folder / "test-cases.json.gz", parsed)
            record["test_counts"] = {k: parsed[k] for k in ["passed", "failed", "skipped"]}
            record["accepted"] &= parsed["accepted"]
            record["test_cases_sha256"] = helpers.sha(folder / "test-cases.json.gz")
            record["missing_files"] = parsed["missing_files"]
            record["unexpected_files"] = parsed["unexpected_files"]
        helpers.write_json(folder / "result.json", record)
        print(json.dumps({"finished": name, "accepted": record["accepted"], "counts": record.get("test_counts")}), flush=True)
        return record

    steps = [step("format", [dart, "format", "--output=none", "--set-exit-if-changed", *changed_dart], repo),
             step("analysis", [dart, "analyze", "--fatal-infos", "--fatal-warnings", *analysis], repo),
             step("whitespace", ["git", "diff", "--check", BASE], repo)]
    if all(s["accepted"] for s in steps):
        def execute(cohort):
            name, package, files, kind = cohort
            if kind == "flutter":
                argv = [flutter, "test", "--no-pub", "--concurrency=1", "--reporter=json", *files]
            else:
                argv = [dart, "--disable-dart-dev", "--packages=" + str(config), test_cli,
                        "--platform=" + kind, "--compiler=" + ("dart2js" if kind == "node" else "kernel"),
                        "--concurrency=1", "--reporter=json", *files]
            extra = {"QUDS_MAIL_PORTABILITY_SHOTS": str(output / "screenshots")} if name == "studio-mail" else {}
            return step(name, argv, repo / package, [package + "/" + f for f in files], extra)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            steps.extend(pool.map(execute, cohorts))
    after = helpers.source_manifest(repo)
    dependencies_after = helpers.dependency_manifest(config, pub_cache, flutter_root, repo)
    runtime_after = runtime_inputs()
    for name, value in [("source-after", after), ("dependencies-after", dependencies_after), ("runtime-after", runtime_after)]:
        helpers.write_manifest(output / (name + ".json.gz"), value)
    source_changes = [k for k in set(before) | set(after) if before.get(k) != after.get(k)]
    dependency_changes = [k for k in set(dependencies) | set(dependencies_after) if dependencies.get(k) != dependencies_after.get(k)]
    runtime_changes = [k for k in set(runtime) | set(runtime_after) if runtime.get(k) != runtime_after.get(k)]
    stable = not source_changes and not dependency_changes and not runtime_changes and head == helpers.capture(["git", "rev-parse", "HEAD"], repo)
    unexecuted = [name for name, _, _, _ in cohorts if name not in {s["name"] for s in steps}]
    receipt = {
        "status": "passed" if stable and not unexecuted and all(s["accepted"] for s in steps) else "failed",
        "source_head": head, "source_tree": helpers.capture(["git", "rev-parse", "HEAD^{tree}"], repo),
        "finished_at_utc": helpers.now(), "github_actions_used": False, "dependency_resolution_performed": False,
        "source_inputs": len(before), "dependency_inputs": len(dependencies), "runtime_inputs": len(runtime),
        "source_digest": helpers.digest(before), "dependency_digest": helpers.digest(dependencies), "runtime_digest": helpers.digest(runtime),
        "inputs_stable": stable, "source_changes": source_changes, "dependency_changes": dependency_changes,
        "runtime_changes": runtime_changes, "unexecuted_cohorts": unexecuted,
        "test_totals": {k: sum(s.get("test_counts", {}).get(k, 0) for s in steps) for k in ["passed", "failed", "skipped"]},
        "unique_test_files": len({package + "/" + f for _, package, files, _ in cohorts for f in files}),
        "sqlite": sqlite, "steps": steps,
        "scope": "Linux native SQLite, synthetic/loopback mail and Flutter widgets; declared Node library boundaries. No installed macOS/Windows/mobile, real accounts, enterprise compliance or full repository qualification.",
    }
    helpers.write_json(output / "receipt.json", receipt)
    shutil.copyfile(repo / SCRIPT, output / "run-mail-validation.py")
    print(json.dumps({"status": receipt["status"], "test_totals": receipt["test_totals"], "inputs_stable": stable}), flush=True)
    return 0 if receipt["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
