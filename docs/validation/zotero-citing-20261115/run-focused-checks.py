#!/usr/bin/env python3
"""Qualify Zotero citing against genuine, already-resolved package harnesses.

This runner neither resolves dependencies nor invokes GitHub Actions. Set
FLUTTER_ROOT to the pinned, provisioned SDK and reconstruct the three harnesses
from setup-receipt.json. Their lib/test links must point to --source. Temporary
ignored analyzer configs reuse those resolved graphs and are restored on exit.
Use --plan to inspect the inputs and commands without running the cohort.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from urllib.parse import unquote, urljoin, urlparse


BASELINE = "f40aa887325982ea70c8285b25f8ff5b92a46eb9"
RUNTIME_PINS = {
    "frameworkVersion": "3.47.8",
    "frameworkRevision": "737ba8f885dc774b53b442759999a312c9461e4e",
    "engineRevision": "cf636b1dfb818dd6a3ff16e390e93b1a036969c8",
    "dartSdkVersion": "3.13.7",
}
ENGINE_TESTS = [
    # The preceding 232-case engine/field/import cohort, followed by citing.
    "word_zotero_test.dart",
    "word_zotero_simple_field_test.dart",
    "word_zotero_formatted_bibliography_test.dart",
    "zotero_client_test.dart",
    "zotero_identity_client_test.dart",
    "zotero_formatted_text_test.dart",
    "word_field_span_test.dart",
    "inline_field_fidelity_test.dart",
    "word_bibliography_fidelity_test.dart",
    "word_revision_story_test.dart",
    "word_fidelity_test.dart",
    "word_auxiliary_content_control_test.dart",
    "word_content_control_fidelity_test.dart",
    "header_footer_sdt_test.dart",
    "zotero_citing_test.dart",
    "word_zotero_document_data_test.dart",
    "word_zotero_citing_test.dart",
]
EDITOR_TESTS = [
    # The preceding 81-case shared editor cohort, followed by citing.
    "word_zotero_controller_test.dart",
    "word_zotero_format_test.dart",
    "word_zotero_dialog_test.dart",
    "word_zotero_citing_controller_test.dart",
    "word_zotero_citing_dialog_test.dart",
]
STUDIO_TESTS = ["studio_zotero_citing_transport_test.dart"]
# Incoming main changed ODS conditional-affix import and XLSX export. Keep its
# integration cohort separate from the Zotero/Word feature count.
INTEGRATION_TESTS = ["ods_sheet_reader_test.dart"]
PACKAGE_PATHS = {
    "legacy_doc_parser": "packages/legacy_doc_parser",
    "quds_office_engine": "packages/quds_office_engine",
    "quds_reports": "packages/quds_reports",
    "quds_office_editor": "packages/quds_office_editor",
    "quds_office_studio": "packages/quds_office_editor/example",
}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def git(source, *parts):
    return subprocess.check_output(["git", "-C", str(source), *parts])


def git_text(source, *parts):
    return git(source, *parts).decode().strip()


def git_paths(source, *parts):
    return [path.decode() for path in git(source, *parts).split(b"\0") if path]


def is_source_input(path):
    parts = Path(path).parts
    return (
        Path(path).name in {"pubspec.yaml", "pubspec.lock", "analysis_options.yaml"}
        or (
            len(parts) >= 4
            and parts[0] == "packages"
            and parts[2] in {"lib", "test"}
        )
        or path.startswith("packages/quds_office_editor/example/")
    )


def source_fingerprint(source):
    tracked = {p for p in git_paths(source, "ls-files", "-z") if is_source_input(p)}
    untracked = {
        p for p in git_paths(source, "ls-files", "--others", "--exclude-standard", "-z")
        if is_source_input(p)
    }
    hashes = {
        path: sha256((source / path).read_bytes()) if (source / path).is_file() else None
        for path in sorted(tracked | untracked)
    }
    dirty = {
        p for p in git_paths(source, "diff", "--name-only", "-z", "HEAD")
        if is_source_input(p)
    }
    return {
        "files": len(hashes),
        "aggregate_sha256": sha256(json_bytes(hashes)),
        "sha256_by_path": hashes,
        "untracked_paths": sorted(untracked),
        "modified_since_head": sorted(dirty),
        "matches_head": not dirty and not untracked,
    }


def write_source_map(output, name, value):
    path = output / (name + ".json")
    payload = json_bytes(value)
    path.write_bytes(payload)
    return {
        key: value[key] for key in
        ("files", "aggregate_sha256", "matches_head", "untracked_paths", "modified_since_head")
    } | {"map": path.name, "map_sha256": sha256(payload)}


def runtime_info():
    root = os.environ.get("FLUTTER_ROOT")
    if root is None:
        executable = shutil.which("flutter")
        if executable:
            root = str(Path(executable).resolve().parents[1])
    if root is None:
        raise ValueError("Set FLUTTER_ROOT to the provisioned official Flutter SDK.")
    root = Path(root).resolve()
    dart = root / "bin/cache/dart-sdk/bin/dart"
    snapshot = root / "bin/cache/flutter_tools.snapshot"
    version_file = root / "bin/cache/flutter.version.json"
    runtime = json.loads(version_file.read_text())
    for key, expected in RUNTIME_PINS.items():
        if runtime.get(key) != expected:
            raise ValueError(f"Runtime {key}: expected {expected}, got {runtime.get(key)!r}")
    revision = git_text(root, "rev-parse", "HEAD")
    engine_revision = (root / "bin/internal/engine.version").read_text().strip()
    dart_version = subprocess.check_output([str(dart), "--version"], stderr=subprocess.STDOUT).decode().strip()
    if revision != RUNTIME_PINS["frameworkRevision"] or engine_revision != RUNTIME_PINS["engineRevision"]:
        raise ValueError("The Flutter source or engine stamp does not match the recorded runtime pin.")
    if not re.search(r"Dart SDK version: " + re.escape(RUNTIME_PINS["dartSdkVersion"]) + r"\b", dart_version):
        raise ValueError("The executed Dart binary does not match the recorded version pin.")
    artifacts = [
        "bin/cache/dart-sdk/bin/dart", "bin/cache/flutter_tools.snapshot",
        "bin/cache/artifacts/engine/linux-x64/flutter_tester",
        "bin/cache/flutter.version.json", "bin/internal/engine.version",
    ]
    return dart, snapshot, {
        "root": str(root), "pins": RUNTIME_PINS, "version_cache": runtime,
        "framework_commit": revision, "engine_revision": engine_revision,
        "dart_version_output": dart_version,
        "artifact_sha256": {p: sha256((root / p).read_bytes()) for p in artifacts},
        "sdk_tracked_status": git_text(root, "status", "--porcelain", "--untracked-files=no"),
        "uses_shell_wrappers": False,
    }


def normalize_config(config_path, source):
    config = json.loads(config_path.read_text())
    if config.get("configVersion") != 2:
        raise ValueError(f"Unsupported package config: {config_path}")
    for package in config["packages"]:
        name = package["name"]
        if name in PACKAGE_PATHS:
            root = source / PACKAGE_PATHS[name]
        else:
            uri = urlparse(urljoin(config_path.as_uri(), package["rootUri"]))
            if uri.scheme != "file" or uri.netloc not in {"", "localhost"}:
                raise ValueError(f"Unsupported resolved package URI for {name}: {uri.geturl()}")
            root = Path(unquote(uri.path)).resolve()
        if not root.is_dir():
            raise ValueError(f"Resolved package root does not exist: {name}: {root}")
        package["rootUri"] = root.as_uri() + "/"
    return json_bytes(config)


def harness_info(name, harness, source, tests):
    canonical = source / PACKAGE_PATHS["quds_office_" + name]
    for directory in ("lib", "test"):
        if (harness / directory).resolve() != (canonical / directory).resolve():
            raise ValueError(f"{name} harness {directory} must link to {canonical / directory}")
    for test in tests:
        if not (harness / "test" / test).is_file():
            raise ValueError(f"Missing selected test: {harness / 'test' / test}")
    files = {}
    for filename in ("pubspec.yaml", "pubspec.lock", ".dart_tool/package_config.json"):
        payload = (harness / filename).read_bytes()
        files[filename] = {"sha256": sha256(payload), "text": payload.decode()}
    config = normalize_config(harness / ".dart_tool/package_config.json", source)
    return {
        "root": str(harness), "canonical_package": str(canonical),
        "inputs": files, "selected_tests": tests,
        "canonical_analysis_config_sha256": sha256(config),
    }, config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--engine-harness", type=Path)
    parser.add_argument("--editor-harness", type=Path)
    parser.add_argument("--studio-harness", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--plan", action="store_true", help="Validate and print the plan without running tests or writing configs.")
    args = parser.parse_args()
    source = args.source.resolve()
    harness_root = source.parent / "zotero-toolchain/harness"
    output = (args.output or source / "docs/validation/zotero-citing-20261115/final").resolve()
    harnesses = {
        name: (getattr(args, name + "_harness") or harness_root / ("quds_office_" + name)).resolve()
        for name in ("engine", "editor", "studio")
    }
    tests = {"engine": ENGINE_TESTS, "editor": EDITOR_TESTS, "studio": STUDIO_TESTS}
    try:
        git_text(source, "rev-parse", BASELINE + "^{commit}")
        dart, snapshot, runtime = runtime_info()
        inputs, configs = {}, {}
        for name, harness in harnesses.items():
            inputs[name], configs[name] = harness_info(name, harness, source, tests[name])
        for test in INTEGRATION_TESTS:
            if not (harnesses["engine"] / "test" / test).is_file():
                raise ValueError("Missing integration test: " + test)
        inputs["engine"]["integration_tests"] = INTEGRATION_TESTS
        changed = sorted({
            path for path in git_paths(source, "diff", "--name-only", "--diff-filter=ACMR", "-z", BASELINE)
            if path.endswith(".dart") and (source / path).is_file()
        } | {
            path for path in git_paths(source, "ls-files", "--others", "--exclude-standard", "-z")
            if is_source_input(path) and path.endswith(".dart")
        })
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.error(str(error))

    targets = {
        "engine": [p for p in changed if p.startswith("packages/quds_office_engine/")],
        "editor": [p for p in changed if p.startswith("packages/quds_office_editor/") and "/example/" not in p],
        "studio": [p for p in changed if p.startswith("packages/quds_office_editor/example/")],
    }
    other = sorted(set(changed) - {p for paths in targets.values() for p in paths})
    if other:
        parser.error("Changed Dart paths are outside this focused qualification: " + ", ".join(other))

    commands = []
    for name, harness in harnesses.items():
        command = [str(dart)]
        if name != "engine":
            command += [str(snapshot), "test", "--no-pub", "--concurrency=1"]
        else:
            command += ["test"]
        command += ["--reporter", "expanded", *["test/" + p for p in tests[name]]]
        commands.append({"name": name + "-tests", "cwd": str(harness), "command": command})
    commands.append({
        "name": "integration-tests", "cwd": str(harnesses["engine"]),
        "command": [str(dart), "test", "--reporter", "expanded",
                    *["test/" + p for p in INTEGRATION_TESTS]],
    })
    for name, paths in targets.items():
        if paths:
            commands.append({
                "name": name + "-analysis", "cwd": str(source),
                "command": [str(dart), "analyze", "--fatal-infos", *paths],
                "analysis_graph": name,
            })
    if changed:
        commands.append({
            "name": "format-check", "cwd": str(source),
            "command": [str(dart), "format", "--output=none", "--set-exit-if-changed", *changed],
        })
    commands.append({
        "name": "diff-check", "cwd": str(source),
        "command": ["git", "diff", "--check", BASELINE],
    })
    if args.plan:
        print(json.dumps({
            "source": str(source), "baseline": BASELINE, "output": str(output),
            "runtime_pins": runtime["pins"], "harnesses": {k: str(v) for k, v in harnesses.items()},
            "changed_dart_files": changed, "commands": commands,
            "will_run_tests": False,
        }, indent=2))
        return 0

    output.mkdir(parents=True, exist_ok=True)
    receipt_path = output / "receipt.json"
    before = source_fingerprint(source)
    receipt = {
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "source": str(source), "baseline": BASELINE,
        "source_commit": git_text(source, "rev-parse", "HEAD"),
        "source_tree": git_text(source, "rev-parse", "HEAD^{tree}"),
        "source_status_at_start": git_text(source, "status", "--porcelain"),
        "source_before": write_source_map(output, "source-before", before),
        "source_scope": "All tracked package lib/test trees, all Studio example files, pubspec manifests/locks and analysis options; untracked inputs in these scopes are recorded too.",
        "runtime": runtime, "harnesses": inputs,
        "environment": {key: os.environ.get(key) for key in (
            "FLUTTER_ROOT", "PUB_CACHE", "TMPDIR", "CI", "XDG_CONFIG_HOME",
            "FLUTTER_SUPPRESS_ANALYTICS", "DART_SUPPRESS_ANALYTICS",
        )},
        "changed_dart_files": changed, "commands": [],
        "runner_sha256": sha256(Path(__file__).read_bytes()),
        "uses_github_actions": False, "resolves_dependencies": False,
    }
    for name, payload in configs.items():
        (output / (name + "-analysis-package-config.json")).write_bytes(payload)
    config_paths = {
        "engine": source / ".dart_tool/package_config.json",
        "editor": source / ".dart_tool/package_config.json",
        "studio": source / "packages/quds_office_editor/example/.dart_tool/package_config.json",
    }
    originals = {path: path.read_bytes() if path.exists() else None for path in set(config_paths.values())}
    receipt["analysis_config_original_sha256"] = {
        str(path.relative_to(source)): sha256(data) if data is not None else None
        for path, data in originals.items()
    }

    def save_receipt():
        receipt_path.write_bytes(json_bytes(receipt))

    save_receipt()
    try:
        for item in commands:
            graph = item.get("analysis_graph")
            if graph is not None:
                config_path = config_paths[graph]
                config_path.parent.mkdir(parents=True, exist_ok=True)
                config_path.write_bytes(configs[graph])
            started = time.monotonic()
            path = output / (item["name"] + ".log")
            with path.open("wb") as stream:
                result = subprocess.run(item["command"], cwd=item["cwd"], stdout=stream, stderr=subprocess.STDOUT)
            log = path.read_text(errors="replace")
            passed = re.findall(r"\+(\d+)(?: -\d+)?: All tests passed!", log)
            entry = item | {
                "exit_code": result.returncode, "seconds": round(time.monotonic() - started, 3),
                "log": path.name, "log_sha256": sha256(path.read_bytes()),
            }
            if item["name"].endswith("-tests"):
                entry["passed_tests"] = int(passed[-1]) if passed else 0
                entry["has_test_completion_summary"] = bool(passed)
            receipt["commands"].append(entry)
            print(json.dumps(entry), flush=True)
            save_receipt()
    except (OSError, KeyboardInterrupt) as error:
        receipt["execution_error"] = str(error) or type(error).__name__
    finally:
        for path, data in originals.items():
            if data is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(data)
        after = source_fingerprint(source)
        receipt["source_after"] = write_source_map(output, "source-after", after)
        receipt["source_commit_after"] = git_text(source, "rev-parse", "HEAD")
        receipt["source_tree_after"] = git_text(source, "rev-parse", "HEAD^{tree}")
        receipt["source_status_at_end"] = git_text(source, "status", "--porcelain")
        receipt["source_unchanged"] = before["aggregate_sha256"] == after["aggregate_sha256"]
        receipt["head_unchanged"] = receipt["source_commit"] == receipt["source_commit_after"]
        receipt["harness_inputs_after_sha256"] = {
            name: {filename: sha256((harnesses[name] / filename).read_bytes()) for filename in info["inputs"]}
            for name, info in inputs.items()
        }
        receipt["harness_inputs_unchanged"] = all(
            receipt["harness_inputs_after_sha256"][name][filename] == details["sha256"]
            for name, info in inputs.items() for filename, details in info["inputs"].items()
        )
        receipt["all_commands_passed"] = len(receipt["commands"]) == len(commands) and all(
            entry["exit_code"] == 0 and entry.get("has_test_completion_summary", True)
            for entry in receipt["commands"]
        )
        receipt["total_tests_passed"] = sum(entry.get("passed_tests", 0) for entry in receipt["commands"])
        receipt["qualified"] = all(receipt[key] for key in (
            "all_commands_passed", "source_unchanged", "head_unchanged", "harness_inputs_unchanged",
        )) and before["matches_head"] and after["matches_head"] and "execution_error" not in receipt
        receipt["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
        save_receipt()
    print(json.dumps({key: receipt[key] for key in (
        "qualified", "all_commands_passed", "source_unchanged", "head_unchanged",
        "harness_inputs_unchanged", "total_tests_passed",
    )}), flush=True)
    return 0 if receipt["qualified"] else 1


if __name__ == "__main__":
    sys.exit(main())
