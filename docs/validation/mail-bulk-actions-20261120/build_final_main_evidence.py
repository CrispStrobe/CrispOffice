#!/usr/bin/env python3
"""Build the main-reconciliation supplement, preserving the published archive.

  python3 docs/validation/mail-bulk-actions-20261120/build_final_main_evidence.py \
    --runtime /absolute/path/to/quds-mail-work-20261120/runtime

--inventory only lists the explicit selection and missing requirements. A full
build checks the unchanged baseline core/UI scopes, new host/font/visual/Word
qualification, source hashes and PNGs. It never writes evidence.tar.gz or its
original manifest and does not rerun tests or call the network.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile

import build_evidence as base


DOCS = (
    "acceptance-published-source-binding.json", "main-reconciliation.md",
    "main-reconciliation.json", "final-source-applicability.json",
    "final-main-word-validation.json", "final-main-word-summary.md",
    "final-main-portable-compiler-applicability.json",
    "final-main-layout-validation.json",
)
WORD_STEPS = (
    "format", "analyze", "vm", "node",
    "line_spacing-portable-vm", "line_spacing-portable-compile", "line_spacing-portable-node",
    "measurements-portable-vm", "measurements-portable-compile", "measurements-portable-node",
    "named_measurements-portable-vm", "named_measurements-portable-compile", "named_measurements-portable-node",
)
CONFIGS = base.CONFIGS


def inventory(repo, runtime, validation):
    rows = {}
    missing = []

    def add(path, name, category, source, required=True):
        if not path.exists():
            if required:
                missing.append(source)
            return
        base.require(path.is_file() and not path.is_symlink(), f"Not a regular evidence file: {source}")
        base.require(name not in rows and not name.startswith("/") and ".." not in Path(name).parts,
                     f"Unsafe or duplicate member: {name}")
        rows[name] = base.Member(path, name, category, source)

    def record(name, history=False, required=True):
        add(runtime / "records" / name,
            ("history/" if history else "") + "runtime/records/" + name,
            "historical-diagnostic" if history else "current-main-qualification",
            "runtime/records/" + name, required)

    for name in DOCS:
        add(validation / name, "validation/" + name, "reconciliation-or-qualification",
            str((validation / name).relative_to(repo)))
    for step in WORD_STEPS:
        for channel in ("stdout", "stderr"):
            name = f"final-main-word-{step}.{channel}.log"
            add(validation / name, "validation/" + name, "current-word-raw-log",
                str((validation / name).relative_to(repo)))
    for step in ("format", "analyze", "vm"):
        for channel in ("stdout", "stderr"):
            name = f"final-main-layout-{step}.{channel}.log"
            add(validation / name, "validation/" + name, "current-layout-raw-log",
                str((validation / name).relative_to(repo)))
    for path in sorted(validation.glob("final-main-layout-initial-*")):
        if path.suffix in {".json", ".log"}:
            add(path, "history/validation/" + path.name, "historical-diagnostic",
                str(path.relative_to(repo)))
    for name in ("final-main-layout-initial-validation.json",
                 "final-main-layout-initial-vm.stdout.log", "final-main-layout-initial-vm.stderr.log"):
        if not (validation / name).is_file():
            missing.append(str((validation / name).relative_to(repo)))

    record("final-main-host-receipt.json")
    for step in [*(f"analyze-{i}" for i in range(8)), "tests"]:
        for suffix in ("log", "stderr"):
            record(f"final-main-host-{step}.{suffix}")
    for suffix in base.STEP_FILES:
        record("final-main-visual-" + suffix)
    record("final-main-visual-inspection.json")
    record("final-main-font-receipt.json")
    for step in ("format", "analyze-loader", "analyze-tests", "tests"):
        for suffix in ("log", "stderr"):
            record(f"final-main-font-{step}.{suffix}")
    for suffix in ("validation-receipt.json", "format.log", "analyze.log", "tests-vm.log"):
        record("main-e975-deserializer-" + suffix)
    for suffix in ("before.log", "before-receipt.json", "spacing-before.log", "spacing-before-receipt.json"):
        record("main-e975-deserializer-" + suffix, history=True)
    for name in ("run_host_validation.py", "run_final_main_word_validation.py"):
        add(runtime / name, "reproduction/runtime/" + name, "runner", "runtime/" + name)
    for name in ("run_final_main_font_validation.py", "run_final_main_visual_validation.py",
                 "run_main_e975_deserializer_validation.py"):
        # Earlier runners consistently live in records; accept the runtime root
        # as an explicit alternate for the separately owned deserializer runner.
        candidates = [runtime / "records" / name, runtime / name]
        path = next((path for path in candidates if path.is_file()), candidates[0])
        add(path, "reproduction/" + name, "runner", "runtime/" + str(path.relative_to(runtime)))
    for name in ("build_evidence.py", "build_final_main_evidence.py"):
        add(validation / name, "reproduction/" + name, "builder", str((validation / name).relative_to(repo)))
    for relative in CONFIGS:
        add(repo / relative, "configuration/" + relative, "runtime-configuration", relative)
    # The original archive stays alongside this supplement. Its immutable
    # manifest is included as the reference for unchanged acceptance scopes.
    add(validation / "evidence-manifest.json", "baseline/evidence-manifest.json", "published-baseline",
        str((validation / "evidence-manifest.json").relative_to(repo)))
    images = sorted((runtime / "records/final-main-bulk-visuals").glob("*.png"))
    for image in images:
        base.require(bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*\.png", image.name)),
                     f"Unsafe PNG name: {image.name}")
        record("final-main-bulk-visuals/" + image.name)
    if len(images) != 21:
        missing.append(f"exactly 21 final-main PNGs (currently {len(images)})")
    return sorted(rows.values(), key=lambda row: row.name), missing


def bindings(repo, runtime, validation):
    load = base.load_json
    require = base.require
    records = runtime / "records"
    baseline = load(validation / "evidence-manifest.json")
    original = validation / "evidence.tar.gz"
    require(base.digest(original.read_bytes()) == baseline["archive"]["sha256"]
            and original.stat().st_size == baseline["archive"]["bytes"],
            "Published original archive no longer matches its manifest")
    hosts = load(records / "final-main-host-receipt.json")
    require(hosts["success"] and not hosts["changed_inputs"]
            and all(step["exit_code"] == 0 for step in hosts["checks"]),
            "Final-main host acceptance is incomplete or failed")
    host_tests = next(step for step in hosts["checks"] if step["name"] == "tests")
    require(host_tests["summary"]["passed"] == 352 and host_tests["summary"]["failed"] == 0
            and host_tests["summary"]["skipped"] == 0,
            "Expected six complete final-main host suites have not passed")
    font = load(records / "final-main-font-receipt.json")
    visual = load(records / "final-main-visual-receipt.json")
    for label, receipt, count in (("font", font, 9), ("visual", visual, 8)):
        require(receipt["success"] and receipt["inputs_unchanged"]
                and all(step["exit_code"] == 0 for step in receipt["steps"]),
                f"Final-main {label} acceptance is incomplete or failed")
        tests = receipt["steps"][-1]
        require(tests["counts"] == {"passed": count, "failed": 0, "skipped": 0}
                and tests["terminal_done"] and tests["terminal_done"][-1]["success"],
                f"Final-main {label} test terminal/count mismatch")
    images = visual["images"]
    require(len(images) == 21 and set(images) == {
        path.name for path in (records / "final-main-bulk-visuals").glob("*.png")
    }, "Final-main image inventory differs from its receipt")
    for name, image in images.items():
        require(bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*\.png", name)), f"Unsafe image path: {name}")
        path = records / "final-main-bulk-visuals" / name
        require(base.digest(path.read_bytes()) == image["sha256"] and path.stat().st_size == image["bytes"],
                f"Final-main image hash/size mismatch: {name}")
    load(records / "final-main-visual-inspection.json")
    load(validation / "final-source-applicability.json")
    word = load(validation / "final-main-word-validation.json")
    require(word["status"] == "PASS", "Final-main Word acceptance is not complete")
    if "source_unchanged" in word:
        stable = word["source_unchanged"]
        require(all(stable.values()) if isinstance(stable, dict) else stable,
                "Final-main Word source changed during acceptance")

    def source_map(receipt):
        for key in ("source_sha256_after", "source_after", "inputs_after",
                    "source_sha256_before", "source_before", "inputs"):
            if isinstance(receipt.get(key), dict):
                return receipt[key]
        raise ValueError("Qualification receipt has no source map")

    def vm_tests(receipt):
        tests = set()
        for command in receipt.get("commands", []):
            if command.get("label", command.get("name")) not in {"vm", "tests-vm"}:
                continue
            args = command.get("command", command.get("argv", []))
            tests.update("packages/quds_office_engine/" + arg for arg in args
                         if arg.startswith("test/") and arg.endswith(".dart"))
        return tests

    word_inputs = dict(source_map(word))
    # The Word runner records this configuration digest beside its source map.
    # Preserve that independent binding when proving the earlier full scope.
    package_config = word.get("package_config_sha256")
    require(isinstance(package_config, str) and bool(base.HEX_SHA256.fullmatch(package_config)),
            "Final Word receipt has no valid package configuration binding")
    require(word_inputs.get(".dart_tool/package_config.json", package_config) == package_config,
            "Final Word package configuration bindings disagree")
    word_inputs[".dart_tool/package_config.json"] = package_config
    layout = load(validation / "final-main-layout-validation.json")
    require(layout.get("status") == "PASS" and layout.get("source_unchanged") is True
            and all(command["exit_code"] == 0 for command in layout["commands"]),
            "Focused final-main layout receipt is not an unchanged-source PASS")
    layout_inputs = source_map(layout)
    deserializer = load(records / "main-e975-deserializer-validation-receipt.json")
    require(deserializer["all_passed"] and deserializer["source_unchanged"]
            and all(command["exit_code"] == 0 for command in deserializer["commands"]),
            "Focused deserializer qualification is incomplete or failed")
    focused_vm = next(command for command in deserializer["commands"] if command["name"] == "tests-vm")
    terminals = re.findall(r"\+(\d+): All tests passed!", (records / "main-e975-deserializer-tests-vm.log").read_text())
    require(focused_vm.get("passed") == 85 and focused_vm.get("failed") == 0
            and focused_vm.get("skipped") == 0 and terminals and int(terminals[-1]) == 85,
            "Focused deserializer receipt/raw terminal does not establish 85 VM passes")
    original_deserializer_inputs = source_map(deserializer)
    missing_word_coverage = sorted(set(original_deserializer_inputs) - set(word_inputs))
    require(not missing_word_coverage,
            "Final Word receipt does not bind the complete earlier deserializer scope: " + str(missing_word_coverage))
    rerun_tests = vm_tests(word)
    focused_tests = vm_tests(deserializer) | vm_tests(layout)
    require(vm_tests(deserializer) and vm_tests(layout) and focused_tests <= rerun_tests,
            "Final Word VM command does not rerun all focused deserializer/layout suites")
    require(focused_tests <= set(word_inputs), "Final Word receipt does not hash every focused suite")
    deserializer_drift = {
        path: {"earlier_qualified_sha256": expected, "final_word_sha256": word_inputs[path]}
        for path, expected in original_deserializer_inputs.items() if word_inputs[path] != expected
    }
    require(set(deserializer_drift) <= {"packages/quds_office_engine/lib/src/word/layout/word_layout.dart"},
            "Unexpected change after focused deserializer qualification: " + json.dumps(deserializer_drift, indent=2))
    scopes = {
        "unchanged-core-and-transport": baseline["source_bindings"]["qualification_inputs"]["core-and-transport"],
        "unchanged-shared-ui": baseline["source_bindings"]["qualification_inputs"]["shared-ui"],
        "final-main-hosts": hosts["inputs"],
        "final-main-fonts": font["inputs"],
        "final-main-visuals": visual["inputs"],
        "final-main-word": word_inputs,
        "focused-layout": layout_inputs,
    }
    current = {}
    differences = []
    for scope, inputs in scopes.items():
        for relative, expected in inputs.items():
            require(not Path(relative).is_absolute() and ".." not in Path(relative).parts
                    and bool(base.HEX_SHA256.fullmatch(expected)), f"Invalid source binding: {relative}")
            if relative not in current:
                path = repo / relative
                current[relative] = base.digest(path.read_bytes()) if path.is_file() else "MISSING"
            if current[relative] != expected:
                differences.append({"scope": scope, "path": relative, "expected": expected, "current": current[relative]})
    require(not differences, "Final-main source differs from qualified inputs:\n" + json.dumps(differences, indent=2))
    return {
        "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
        "tree": subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=repo, text=True).strip(),
        "baseline_archive": baseline["archive"],
        "baseline_manifest_sha256": base.digest((validation / "evidence-manifest.json").read_bytes()),
        "qualification_inputs": scopes, "current_sha256": dict(sorted(current.items())),
        "all_qualification_inputs_match_current": True,
        "source_binding_normalization": "Final Word source hashes include its separately recorded package_config_sha256 field for complete comparison with the earlier deserializer input scope.",
        "focused_deserializer_reconciliation": {
            "earlier_vm_passes": 85,
            "earlier_qualified_inputs": original_deserializer_inputs,
            "later_known_layout_changes": deserializer_drift,
            "final_word_rerun_suites": sorted(focused_tests),
            "complete_earlier_scope_covered_by_final_word": True,
            "applicability": "The focused run keeps its original source map. The later layout correction is explicitly recorded; final Word VM coverage replaces runtime applicability for the complete focused scope.",
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--inventory", action="store_true")
    args = parser.parse_args()
    base.require(args.runtime.is_absolute(), "--runtime must be an absolute path")
    runtime = args.runtime.resolve(strict=True)
    validation = Path(__file__).resolve().parent
    repo = validation.parents[2]
    selected, missing = inventory(repo, runtime, validation)
    if args.inventory:
        print(json.dumps({"members": [{"path": m.name, "source": m.source, "category": m.category} for m in selected],
                          "missing_required": missing}, indent=2))
        return
    base.require(not missing, "Missing final-main supplement evidence:\n" + "\n".join(missing))
    source = bindings(repo, runtime, validation)
    content = {member.name: member.path.read_bytes() for member in selected}
    content["source-bindings.json"] = base.json_bytes(source)
    content["EVIDENCE.md"] = (
        "# Main reconciliation evidence supplement\n\n"
        "The published evidence.tar.gz and its original manifest are immutable baseline evidence. "
        "This separate archive qualifies the integrated main font and Word changes and proves the "
        "baseline core/transport and shared-UI source scopes unchanged.\n\n"
        "The new six-suite host run supersedes the earlier combined host acceptance for source applicability. "
        "New font, Word and eight visual probes bind the reconciled source. The visual inspection record "
        "compares new images with the directly inspected baseline; changed images require separate inspection. "
        "Historical red tests remain under history/ and never contribute final pass totals.\n\n"
        "No SDK, package-cache archives, native libraries or compiled JavaScript are included. "
        "Run the included builder from its repository location with the exact current runtime root.\n"
    ).encode()
    rows = [{"path": m.name, "source": m.source, "category": m.category,
             "sha256": base.digest(content[m.name]), "bytes": len(content[m.name])} for m in selected]
    for name in ("source-bindings.json", "EVIDENCE.md"):
        rows.append({"path": name, "source": "generated", "category": "generated-index",
                     "sha256": base.digest(content[name]), "bytes": len(content[name])})
    target = validation / "evidence-final-main.tar.gz"
    manifest_path = validation / "evidence-final-main-manifest.json"
    temporary = validation / ".evidence-final-main.tar.gz.tmp"
    manifest_temporary = validation / ".evidence-final-main-manifest.json.tmp"
    try:
        base.write_archive(temporary, content)
        for member in selected:
            base.require(member.path.read_bytes() == content[member.name], f"Evidence changed while packing: {member.source}")
        base.require(bindings(repo, runtime, validation) == source, "Source or baseline changed while packing")
        with tarfile.open(temporary, "r:gz") as archive:
            actual = {entry.name: archive.extractfile(entry).read() for entry in archive.getmembers()}
        base.require(actual == content, "Supplement archive round-trip verification failed")
        manifest = {
            "schema": 1, "scope": "mail-bulk-actions-20261120 captured main reconciliation supplement",
            "archive": {"path": target.name, "bytes": temporary.stat().st_size,
                        "sha256": base.digest(temporary.read_bytes())},
            "baseline": source["baseline_archive"], "original_archive_unchanged": True,
            "members": sorted(rows, key=lambda row: row["path"]), "member_count": len(rows),
            "categories": dict(sorted(Counter(row["category"] for row in rows).items())),
            "source_bindings": source,
            "determinism": "Sorted PAX members, fixed mode/uid/gid/mtime, gzip mtime=0 and empty filename; no generated wall-clock timestamp.",
        }
        manifest_temporary.write_bytes(base.json_bytes(manifest))
        os.replace(temporary, target)
        os.replace(manifest_temporary, manifest_path)
    finally:
        temporary.unlink(missing_ok=True)
        manifest_temporary.unlink(missing_ok=True)
    print(json.dumps({"archive": manifest["archive"], "members": len(rows), "manifest": str(manifest_path),
                      "source_bindings_match": True, "original_archive_unchanged": True}, indent=2))


if __name__ == "__main__":
    main()
