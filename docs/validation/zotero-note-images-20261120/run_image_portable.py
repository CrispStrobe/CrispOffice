#!/usr/bin/env python3
"""Replay the pure-Dart image-note smoke at an exact committed source head.

This runner performs no dependency resolution and makes no network requests.
The ten portable behaviors are reported separately from application test totals.
"""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def git(repo, *args):
    return subprocess.check_output(["git", *args], cwd=repo, text=True).strip()


def snapshot(repo, expected_head):
    head = git(repo, "rev-parse", "HEAD")
    scope = [
        "packages/quds_office_engine/lib",
        "packages/legacy_doc_parser/lib",
        "packages/quds_office_engine/tool/zotero/image_note_portable_smoke.dart",
    ]
    paths = sorted(git(repo, "ls-files", "--", *scope).splitlines())
    tool_path = scope[-1]
    if tool_path not in paths:
        raise RuntimeError("Portable smoke must be committed before acceptance.")
    source = [
        {"path": path, "sha256": digest((repo / path).read_bytes())}
        for path in paths
    ]
    dependencies = []
    for path in [
        "pubspec.yaml",
        "pubspec.lock",
        "pubspec_overrides.yaml",
        ".dart_tool/package_config.json",
        ".dart_tool/package_graph.json",
        "packages/quds_office_engine/pubspec.yaml",
        "packages/quds_office_engine/pubspec_overrides.yaml",
        "packages/legacy_doc_parser/pubspec.yaml",
        "packages/legacy_doc_parser/pubspec_overrides.yaml",
    ]:
        file = repo / path
        dependencies.append({
            "path": path,
            "exists": file.exists(),
            "sha256": digest(file.read_bytes()) if file.exists() else None,
        })
    dirty = git(repo, "diff", "HEAD", "--name-only", "--", *scope)
    untracked = git(repo, "ls-files", "--others", "--exclude-standard", "--", *scope)
    return {
        "head": head,
        "expected_head": expected_head,
        "head_matches": head == expected_head,
        "tracked_source_changes": dirty.splitlines() if dirty else [],
        "untracked_source_files": untracked.splitlines() if untracked else [],
        "source": source,
        "source_manifest_sha256": digest(
            json.dumps(source, sort_keys=True, separators=(",", ":")).encode()
        ),
        "dependency_configuration": dependencies,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--dart", type=Path, required=True)
    parser.add_argument("--node", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    engine = repo / "packages/quds_office_engine"
    dart = str(args.dart.resolve())
    node = str(args.node.resolve())
    commands = []
    report = {
        "schema": 1,
        "suite": "zotero-image-note-portable",
        "qualification_kind": "VM/compiled-JavaScript equivalence",
        "expected_behavior_count": 10,
        "not_added_to_application_test_totals": True,
        "expected_head": args.expected_head,
        "runner_sha256": digest(Path(__file__).read_bytes()),
        "commands": commands,
        "passed": False,
    }

    def run(name, argv):
        stdout = output / f"{name}.stdout"
        stderr = output / f"{name}.stderr"
        with stdout.open("wb") as out, stderr.open("wb") as err:
            result = subprocess.run(argv, cwd=engine, stdout=out, stderr=err)
        entry = {
            "name": name,
            "argv": argv,
            "cwd": str(engine),
            "exit_code": result.returncode,
            "stdout": stdout.name,
            "stderr": stderr.name,
            "stdout_sha256": digest(stdout.read_bytes()),
            "stderr_sha256": digest(stderr.read_bytes()),
        }
        commands.append(entry)
        if result.returncode != 0:
            raise RuntimeError(f"{name} exited {result.returncode}.")
        return stdout.read_bytes()

    try:
        before = snapshot(repo, args.expected_head)
        write_json(output / "before.json", before)
        if not before["head_matches"]:
            raise RuntimeError("HEAD differs from the expected committed source.")
        if before["tracked_source_changes"] or before["untracked_source_files"]:
            raise RuntimeError("Portable source scope has uncommitted changes.")
        run("dart-version", [dart, "--version"])
        run("node-version", [node, "--version"])
        package_arg = "--packages=../../.dart_tool/package_config.json"
        source = "tool/zotero/image_note_portable_smoke.dart"
        vm = run("vm", [dart, package_arg, source])
        artifact = output / "image_note_smoke.js"
        run("compile-js", [
            dart, "compile", "js", "-O2", package_arg,
            "-o", str(artifact), source,
        ])
        js = run("javascript", [node, str(artifact)])
        vm_receipt = json.loads(vm)
        js_receipt = json.loads(js)
        valid = all(
            receipt.get("schema") == 1
            and receipt.get("suite") == "zotero-image-note-portable"
            and receipt.get("behavior_count") == 10
            and receipt.get("passed") == 10
            and len(receipt.get("results", [])) == 10
            and len({item.get("behavior") for item in receipt["results"]}) == 10
            and all(item.get("passed") is True for item in receipt["results"])
            for receipt in (vm_receipt, js_receipt)
        )
        after = snapshot(repo, args.expected_head)
        write_json(output / "after.json", after)
        report.update({
            "source_identity_stable": before == after,
            "source_manifest_sha256": before["source_manifest_sha256"],
            "byte_identical_receipts": vm == js,
            "json_identical_receipts": vm_receipt == js_receipt,
            "receipt_sha256": digest(vm),
            "behavior_count": vm_receipt.get("behavior_count"),
            "behaviors_passed": vm_receipt.get("passed"),
            "behavior_names": [item["behavior"] for item in vm_receipt["results"]],
            "compiled_javascript_sha256": digest(artifact.read_bytes()),
        })
        if before != after:
            raise RuntimeError("Source or dependency identities changed during the run.")
        if vm != js or not valid:
            raise RuntimeError("Portable receipts do not prove ten equivalent passing behaviors.")
        report["passed"] = True
    except Exception as error:
        report["error"] = f"{type(error).__name__}: {error}"
        try:
            write_json(output / "after.json", snapshot(repo, args.expected_head))
        except Exception as after_error:
            report["after_snapshot_error"] = str(after_error)
    finally:
        write_json(output / "acceptance.json", report)
    print(json.dumps({
        "passed": report["passed"],
        "behavior_count": report.get("behavior_count"),
        "behaviors_passed": report.get("behaviors_passed"),
        "byte_identical_receipts": report.get("byte_identical_receipts"),
        "source_identity_stable": report.get("source_identity_stable"),
        "evidence": str(output),
        "error": report.get("error"),
    }, sort_keys=True))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
