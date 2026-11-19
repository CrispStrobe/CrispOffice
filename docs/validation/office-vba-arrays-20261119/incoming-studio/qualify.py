#!/usr/bin/env python3
"""Qualify the incoming mail-restore Studio suites without editing sources."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.parse import unquote, urlparse


ROOT = Path(__file__).resolve().parents[4]
WORKSPACE = ROOT.parent / "flutter-validation-workspace"
RUNTIME = ROOT.parent / "runtime"
OUTPUT = Path(__file__).resolve().parent
SDK = RUNTIME / "flutter"
FLUTTER = SDK / "bin/flutter"
EXAMPLE = Path("packages/quds_office_editor/example")
ENGINE_SNAPSHOT = WORKSPACE / "packages/quds_office_engine/lib-studio-qualification-20261119"
TESTS = [
    "test/studio_mail_archive_restore_test.dart",
    "test/studio_mail_archive_restore_native_test.dart",
    "test/studio_mail_archive_portability_visual_test.dart",
]
OPTIONAL_TEST = "test/studio_mail_archive_portability_test.dart"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(name: str, value: object) -> None:
    (OUTPUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def run_git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def selected_tests() -> list[str]:
    return TESTS + ([OPTIONAL_TEST] if (ROOT / EXAMPLE / OPTIONAL_TEST).is_file() else [])


def workspace_members() -> list[str]:
    return [line.removeprefix("  - ").strip()
            for line in (WORKSPACE / "pubspec.yaml").read_text().splitlines()
            if line.startswith("  - ")]


def snapshot() -> dict[str, str]:
    tracked = run_git("ls-files", "-z").split("\0")
    source = []
    for name in tracked:
        if not name:
            continue
        path = Path(name)
        parts = path.parts
        in_packages = parts[0] in {"packages", "third_party", "apps"}
        is_source = (in_packages and "lib" in parts and path.suffix == ".dart"
                     and not name.startswith("packages/quds_office_engine/lib/"))
        is_configuration = path.name in {"pubspec.yaml", "analysis_options.yaml"}
        is_asset = name.startswith((
            "packages/quds_office_editor/fonts/",
            "packages/quds_office_editor/templates/",
            "packages/quds_office_editor/assets/",
            "packages/quds_office_editor/example/fonts/",
            "packages/quds_office_editor/example/assets/",
        ))
        if is_source or is_configuration or is_asset or name == "pubspec.lock":
            source.append(ROOT / path)
    source.extend(ROOT / EXAMPLE / test for test in selected_tests())
    source.extend(path for path in ENGINE_SNAPSHOT.rglob("*") if path.is_file())
    paths = source + [
        WORKSPACE / "analysis_options.yaml",
        WORKSPACE / "pubspec.yaml",
        WORKSPACE / "pubspec.lock",
        WORKSPACE / ".dart_tool/package_config.json",
        WORKSPACE / ".dart_tool/package_graph.json",
        SDK / "bin/cache/flutter_tools.snapshot",
        SDK / "bin/cache/dart-sdk/bin/dart",
        SDK / "bin/cache/dart-sdk/version",
        SDK / "bin/cache/flutter.version.json",
        SDK / "bin/cache/engine.stamp",
        SDK / "bin/cache/artifacts/engine/linux-x64/flutter_tester",
    ]
    paths.extend(WORKSPACE / member / "pubspec.yaml" for member in workspace_members())
    for name in [".flutter-plugins-dependencies"]:
        path = WORKSPACE / EXAMPLE / name
        if path.is_file():
            paths.append(path)
    config_path = WORKSPACE / ".dart_tool/package_config.json"
    config = json.loads(config_path.read_text())
    for package in config["packages"]:
        uri = urlparse(package["rootUri"])
        package_root = (Path(unquote(uri.path)) if uri.scheme == "file"
                        else config_path.parent / unquote(package["rootUri"]))
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
        "FLUTTER_SUPPRESS_ANALYTICS": "true",
        "CI": "true",
    }
    effective = {**os.environ, **environment}
    # Layout assertions always run; screenshots are an optional author fixture.
    effective.pop("QUDS_MAIL_PORTABILITY_SHOTS", None)
    started = time.time()
    with (OUTPUT / f"{name}.stdout.log").open("wb") as stdout:
        with (OUTPUT / f"{name}.stderr.log").open("wb") as stderr:
            result = subprocess.run(args, cwd=cwd, env=effective,
                                    stdout=stdout, stderr=stderr, check=False)
    receipt = {
        "name": name, "command": args, "cwd": str(cwd),
        "environment_overrides": environment,
        "removed_optional_environment": ["QUDS_MAIL_PORTABILITY_SHOTS"],
        "started_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started)),
        "elapsed_seconds": time.time() - started,
        "exit_code": result.returncode,
        "stdout": f"{name}.stdout.log", "stderr": f"{name}.stderr.log",
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
    for line in (OUTPUT / "studio-tests.stdout.log").read_text().splitlines():
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
        "passed": sum(item["result"]["result"] == "success"
                      and not item["result"].get("skipped", False) for item in visible),
        "failed": sum(item["result"]["result"] != "success" for item in visible),
        "skipped": sum(item["result"].get("skipped", False) for item in visible),
        "done_events": done, "non_json_stdout_lines": non_json_lines,
        "tests": visible,
    }
    write_json("test-summary.json", summary)
    return summary


def main() -> None:
    if not (WORKSPACE / ".dart_tool/package_config.json").is_file():
        raise RuntimeError("Full Flutter workspace dependencies are not ready.")
    engine_manifest = json.loads((OUTPUT / "engine-snapshot.json").read_text())
    for name, expected in engine_manifest["files"].items():
        if digest(ENGINE_SNAPSHOT / name) != expected:
            raise RuntimeError(f"Frozen engine input changed: {name}")
    lib = WORKSPACE / "packages/quds_office_engine/lib"
    if not lib.is_symlink():
        raise RuntimeError("Expected the isolated workspace's engine source link.")
    if lib.resolve() != ENGINE_SNAPSHOT:
        if lib.resolve() != Path(engine_manifest["original_link_target"]).resolve():
            raise RuntimeError("Engine source link points to an unexpected target.")
        lib.unlink()
        lib.symlink_to(ENGINE_SNAPSHOT, target_is_directory=True)
    before = snapshot()
    write_json("inputs-before.json", before)
    copied_manifests = {
        name: digest(ROOT / name) == digest(WORKSPACE / name)
        for name in ["pubspec.yaml", *(f"{member}/pubspec.yaml" for member in workspace_members())]
    }
    write_json("source-frontier.json", {
        "checkout_head_at_start": run_git("rev-parse", "HEAD"),
        "incoming_head": "358544a48466c942873a4718a87fa9d1c2be11f7",
        "selected_tests": selected_tests(),
        "optional_portability_test_exists": (ROOT / EXAMPLE / OPTIONAL_TEST).is_file(),
        "layout_assertions_enabled": True, "optional_screenshot_capture_enabled": False,
        "copied_manifests_match_repository": copied_manifests,
        "source_inputs": len(before),
        "engine_sources": "Isolated byte-verified snapshot; see engine-snapshot.json",
        "engine_snapshot_manifest_sha256": digest(OUTPUT / "engine-snapshot.json"),
    })
    print(json.dumps({"recorded_inputs": len(before)}), flush=True)
    commands = [execute(
        "studio-tests", [str(FLUTTER), "--no-version-check", "--suppress-analytics",
                         "test", "--no-pub", "--concurrency=1", "--reporter=json",
                         *selected_tests()], WORKSPACE / EXAMPLE,
    )]
    summary = test_summary()
    after = snapshot()
    write_json("inputs-after.json", after)
    changed = sorted(key for key in before.keys() | after.keys()
                     if before.get(key) != after.get(key))
    stability = {"before_count": len(before), "after_count": len(after),
                 "changed": changed, "unchanged": not changed}
    write_json("input-stability.json", stability)
    success = (not changed and all(copied_manifests.values())
               and all(command["exit_code"] == 0 for command in commands)
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
    try:
        main()
    finally:
        manifest = OUTPUT / "engine-snapshot.json"
        lib = WORKSPACE / "packages/quds_office_engine/lib"
        if manifest.is_file() and lib.is_symlink() and lib.resolve() == ENGINE_SNAPSHOT:
            original = json.loads(manifest.read_text())["original_link_target"]
            lib.unlink()
            lib.symlink_to(original, target_is_directory=True)
