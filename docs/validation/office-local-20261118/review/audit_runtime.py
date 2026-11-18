#!/usr/bin/env python3
"""Independently verify archived runtime bytes, receipts and live retained inputs."""
from __future__ import annotations
from datetime import datetime, timezone
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import shlex
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT / "quds_office_suite"
RUNTIME = ROOT / "native-consumers"
ARCHIVE = RUNTIME / "runtime-recovery.tar.xz"
INDEX = RUNTIME / "runtime-recovery.tar.index.json"
SOURCE = "401d012657881a54727d58bc35e537faa45d5fbe"
EXPECTED = "2afcb3bdcff2a88032521f9c660b9eb75a857b07e974254d2b69cecb5809f9b9"
failures = []

def digest(data):
    return hashlib.sha256(data).hexdigest()

def file_sha(path):
    with Path(path).open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()

def check(condition, label, detail=None):
    if not condition:
        failures.append({"check": label, "detail": detail})
    return bool(condition)

def git(*args):
    return subprocess.check_output(["git", "-C", str(REPO), *args], text=True).strip()

def source_bytes(path):
    path = Path(path)
    return subprocess.check_output(["git", "-C", str(REPO), "show", SOURCE + ":" + path.relative_to(REPO).as_posix()])

def check_file(path, expected, size=None):
    path = Path(path)
    result = {"path": str(path), "expected_sha256": expected, "exists": path.is_file()}
    if path.is_file():
        result.update(actual_sha256=file_sha(path), bytes=path.stat().st_size)
    result["matches"] = result.get("actual_sha256") == expected and (size is None or result.get("bytes") == size)
    check(result["matches"], "live-file", result)
    return result

head_before = git("rev-parse", "HEAD")
status_before = git("status", "--porcelain")
check(head_before == SOURCE, "frozen-source-before", head_before)
check(status_before == "", "clean-source-before", status_before)
index = json.loads(INDEX.read_text())
check(file_sha(ARCHIVE) == index["sha256"] == EXPECTED, "archive-sha")
check(ARCHIVE.stat().st_size == index["bytes"], "archive-size")
indexed = {row["path"]: row for row in index["members"]}
check(len(indexed) == len(index["members"]), "index-unique-paths")
contents = {}
member_checks = []
with tarfile.open(ARCHIVE) as archive:
    for member in archive:
        rel = PurePosixPath(member.name)
        check(member.isfile() and not rel.is_absolute() and ".." not in rel.parts,
              "safe-file-member", member.name)
        check(member.name not in contents, "unique-archive-member", member.name)
        data = archive.extractfile(member).read()
        contents[member.name] = data
        expected = indexed.get(member.name, {})
        actual = {"path": member.name, "bytes": len(data), "sha256": digest(data)}
        actual["matches"] = actual["bytes"] == expected.get("bytes") and actual["sha256"] == expected.get("sha256")
        check(actual["matches"], "archive-member", actual)
        member_checks.append(actual)
check(set(contents) == set(indexed), "member-path-set")
check(len(contents) == index["member_count"] == 72, "member-count")

def archived_json(name):
    return json.loads(contents[name])

native = archived_json("native-binary-recovery/recovery.json")
ready = archived_json("native-model-and-python/ready.json")
consumer = archived_json("consumer/recovery.json")
smoke = archived_json("consumer/smoke/receipt.json")
font_receipt = archived_json("consumer/font-prerequisites.json")
historical_archive = REPO / "docs/validation/office-union-resume-20261117/evidence/native-runtime-recovery.tar.xz"
with tarfile.open(fileobj=io.BytesIO(source_bytes(historical_archive)), mode="r:xz") as old:
    old_ready = json.load(old.extractfile("model-and-python/ready.json"))
    old_freeze = old.extractfile("model-and-python/python-freeze.txt").read()
    old_manifest = json.load(old.extractfile("model-and-python/gector-de-f32.gguf.manifest.json"))
    old_download = json.load(old.extractfile("model-and-python/model-download-verification.json"))

pack_root = Path(ready["pack"]["pack"])
pack_path = pack_root / "pack.json"
check(file_sha(pack_path) == ready["pack"]["manifest_sha256"] == old_ready["artifacts"]["pack_manifest"]["sha256"],
      "pack-manifest-pin")
pack = json.loads(pack_path.read_text())
pack_files = [check_file(pack_root / row["path"], row["sha256"], row["bytes"]) for row in pack["files"]]
check(len(pack_files) + 1 == ready["pack"]["sizes"]["file_count"] == 23, "pack-file-count")
baseline_path = pack_root / "evidence/native-build-v2.json"
baseline = json.loads(baseline_path.read_text())
check(file_sha(baseline_path) == native["baseline_receipt_sha256"], "native-baseline-receipt")
check(native["source_before"] == native["source_after"] == baseline["source_sha256"], "native-source-maps")
check(len(baseline["source_sha256"]) == 112, "native-source-count")
native_source = RUNTIME / "native-binary-recovery/CrispEmbed"
pruning_path = RUNTIME / "native-qualification-runtime/qualification-runtime-pruning.json"
pruning = json.loads(pruning_path.read_text())
check("native-binary-recovery/CrispEmbed" in pruning["removed_reproducible_directories"], "declared-source-cleanup")
source_checks = [check_file(native_source / path, expected) for path, expected in baseline["source_sha256"].items() if (native_source / path).is_file()]
released_source_files = [path for path in baseline["source_sha256"] if not (native_source / path).is_file()]
binary_checks = []
for kind, old_kind in [("library", "native_library"), ("quantizer", "quantizer")]:
    current = native["artifacts"][kind]
    previous = baseline[kind]
    check(current["sha256"] == previous["sha256"] == old_ready["artifacts"][old_kind]["sha256"], "native-artifact-pin", kind)
    binary_checks.append(check_file(RUNTIME / "native-binary-recovery/build" / current["file"], previous["sha256"], previous["size_bytes"]))
compile_entries = archived_json("native-binary-recovery/build/compile_commands.json")
compiled = []
for entry in compile_entries:
    argv = entry.get("arguments") or shlex.split(entry["command"])
    compiled.append({
        "file": Path(entry["file"]).relative_to(native_source).as_posix(),
        "compiler": Path(argv[0]).name,
        "flags": [arg for arg in argv if arg.startswith(("-D", "-O", "-m", "-f", "-std=")) and arg != native["declared_additional_flag"]],
    })
compiled.sort(key=lambda row: row["file"])
check(compiled == baseline["compiled_sources"], "native-semantic-compile-flags")
native_log_checks = []
for command in native["commands"]:
    path = "native-binary/" + command["log"]
    log = contents.get(path)
    matches = log is not None and digest(log) == command["log_sha256"] and command["exit_code"] == 0
    native_log_checks.append({"label": command["label"], "matches": matches})
    check(matches, "native-command-log", command["label"])
check("100% tests passed out of 1" in contents["native-binary/logs/20-native-contract.log"].decode(), "native-contract-raw-result")

f32 = archived_json("native-model-and-python/gector-de-f32.gguf.manifest.json")
check(f32["output"] == old_manifest["output"], "f32-model-prior-pin")
check(f32["source"] == old_manifest["source"], "f32-input-prior-pins")
check(f32["converter_sha256"] == old_manifest["converter_sha256"], "f32-converter-prior-pin")
check(f32["graph"]["converted_tensors"] == len(f32["tensors"]) == 201, "f32-tensor-count")
check(f32["output"]["sha256"] in contents["finish_native_runtime.py"].decode(), "f32-recovery-assertion")
download = archived_json("native-model-and-python/model-download-verification.json")
check(download == old_download, "download-manifest-prior-pins")
asset_checks = []
released_inputs = []
for row in download["manifest"]:
    path = RUNTIME / "native-qualification-runtime/proofbird" / row["file"]
    if row["file"] == "model.onnx" and not path.exists():
        released_inputs.append({"file": row["file"], "sha256": row["sha256"], "status": "released after recorded verification; not freshly rehashed"})
    else:
        asset_checks.append(check_file(path, row["sha256"], row["size"]))
f32_path = RUNTIME / "native-qualification-runtime/gector-de-f32.gguf"
if f32_path.exists():
    check_file(f32_path, f32["output"]["sha256"], f32["output"]["size_bytes"])
else:
    released_inputs.append({"file": f32_path.name, "sha256": f32["output"]["sha256"], "status": "released after recorded verification; not freshly rehashed"})
finish_checks = []
for command in archived_json("native-model-and-python/finish-commands.json"):
    log = contents["native-model-and-python/" + command["label"] + ".log"]
    valid = command["exit_code"] == 0 and digest(log) == command["log_sha256"]
    finish_checks.append({"label": command["label"], "matches": valid})
    check(valid, "model-finish-log", command["label"])
check(digest(contents["native-model-and-python/reference-f32.json"]) == ready["reference_sha256"] == old_ready["reference_f32_sha256"], "native-reference-pin")
freeze = contents["native-model-and-python/python-freeze.txt"]
check(freeze == old_freeze, "python-freeze-prior-pin")
freeze_lines = freeze.decode().splitlines()
check(len(freeze_lines) == ready["python_frozen_packages"] == 27, "python-package-count")
env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", PIP_DISABLE_PIP_VERSION_CHECK="1")
actual_freeze = subprocess.check_output([str(RUNTIME / "native-qualification-runtime/venv/bin/python"), "-m", "pip", "freeze"], env=env, timeout=30)
removed_packages = set(pruning["uninstalled_build_only"])
check(removed_packages == {"cmake==4.4.5", "ninja==1.13.2"}, "only-declared-build-packages-removed")
runtime_expected = [line for line in freeze_lines if line not in removed_packages]
check(actual_freeze.decode().splitlines() == runtime_expected, "installed-python-runtime-subset")
check(len(runtime_expected) == pruning["qualification_python_packages"] == 25, "python-runtime-subset-count")
tool_release = archived_json("duplicate-build-tools-release.json")
tool_checks = []
for row in tool_release["comparisons"]:
    path = RUNTIME / "native-qualification-runtime/venv" / row["path"]
    if path.is_file():
        tool_checks.append(check_file(path, row["sha256"]))
    else:
        tool_checks.append({"path": str(path), "recorded_sha256": row["sha256"], "exists": False,
                            "status": "build-only package removed after original archive, as declared in pruning receipt"})

consumer_source = Path(consumer["source_archive"])
consumer_index_path = consumer_source.with_name(consumer_source.name.replace(".tar.xz", ".tar.index.json"))
consumer_archive_bytes = source_bytes(consumer_source)
consumer_index_bytes = source_bytes(consumer_index_path)
consumer_index = json.loads(consumer_index_bytes)
check(digest(consumer_archive_bytes) == consumer["archive_sha256"] == consumer_index["sha256"], "consumer-historical-archive")
check(digest(consumer_index_bytes) == consumer["source_index_sha256"], "consumer-historical-index")
consumer_indexed = {row["path"]: row for row in consumer_index["members"]}
consumer_member_rows = []
retained_root = RUNTIME / "consumer-runtime/retained-reference"
prior_runtime_map = None
with tarfile.open(fileobj=io.BytesIO(consumer_archive_bytes), mode="r:xz") as archive:
    for member in archive:
        data = archive.extractfile(member).read()
        expected = consumer_indexed[member.name]
        check(digest(data) == expected["sha256"] and len(data) == expected["bytes"], "consumer-historical-member", member.name)
        consumer_member_rows.append(check_file(retained_root / member.name, expected["sha256"], expected["bytes"]))
        if member.name == "qualification-1d8325d4-current7/inputs.json.gz":
            prior_runtime_map = json.loads(gzip.decompress(data))["runtime"]
check(len(consumer_member_rows) == consumer_index["member_count"] == consumer["restored_member_count"] == 710, "consumer-restored-member-count")
runtime_rows = consumer["retained_runtime_comparisons"]
runtime_checks = []
for row in runtime_rows:
    check(row["actual"] == row["expected"] == prior_runtime_map[row["path"]] and row["matches"], "runtime-comparison-receipt", row["path"])
    runtime_checks.append(check_file(row["path"], row["expected"]))
check(len(runtime_rows) == consumer["retained_runtime_comparison_count"] == 3504, "consumer-runtime-count")
check(len({row["path"] for row in runtime_rows}) == len(runtime_rows), "consumer-runtime-unique-paths")
font_checks = [check_file(row["path"], row["expected_sha256"]) for row in font_receipt]
check(len(font_checks) == 8 and all(row["expected_sha256"] == row["actual_sha256"] and row["matches"] for row in font_receipt), "font-receipt-consistency")
for command in smoke["commands"]:
    check(command["exit_code"] == command["expected_exit_code"], "smoke-exit-code", command["label"])
check([row["observed_exit_code"] for row in smoke["controls"]] == [0, 0, 1, 1], "smoke-positive-negative-controls")
check(digest(contents["consumer/smoke/toc-fields.pdf"]) == smoke["historical_render_pdf_sha256"], "smoke-pdf-hash")
check_file(retained_root / "tools/jing-20241231.jar", smoke["jing_sha256"])
check_file(retained_root / "schemas/OpenDocument-v1.3-schema.rng", smoke["schema_sha256"])
for row in smoke["controls"]:
    check_file(retained_root / "schema-controls" / (row["name"] + ".xml"), row["input_sha256"])
head_after = git("rev-parse", "HEAD")
status_after = git("status", "--porcelain")
check(head_after == head_before == SOURCE, "frozen-source-after", head_after)
check(status_after == status_before == "", "clean-source-after", status_after)
sparse_path = ROOT / "publication-files/sparse-checkout-receipt.json"
sparse = json.loads(sparse_path.read_text())
skip_paths = [row[2:] for row in git("ls-files", "-t").splitlines() if row.startswith("S ")]
check(all(path.startswith("docs/") for path in skip_paths), "sparse-only-historical-docs")
check(len(skip_paths) == sparse["omitted_historical_docs_files"] == 4799, "sparse-doc-count")

report = {
    "schema_version": 1, "kind": "independent-runtime-archive-readback",
    "created_utc": datetime.now(timezone.utc).isoformat(),
    "reviewer": "remote_review independent agent",
    "source_commit_context": SOURCE,
    "source_head_unchanged_and_clean": head_before == head_after == SOURCE and status_before == status_after == "",
    "archive": {"path": str(ARCHIVE), "sha256": file_sha(ARCHIVE), "bytes": ARCHIVE.stat().st_size,
                "index_sha256": file_sha(INDEX), "member_count": len(contents),
                "all_members_read_and_verified": all(row["matches"] for row in member_checks), "members": member_checks},
    "native": {"source_revision": native["source_revision"], "ggml_revision": native["ggml_revision"],
               "baseline_receipt_sha256": file_sha(baseline_path), "original_source_hashes_in_archived_before_after_maps": len(baseline["source_sha256"]),
               "original_source_files_independently_rehashed": len(source_checks), "source_files_released_before_live_review": len(released_source_files),
               "source_map_equals_historical_baseline": native["source_before"] == native["source_after"] == baseline["source_sha256"],
               "compiled_source_entries": len(compiled), "semantic_flags_equal_baseline": compiled == baseline["compiled_sources"],
               "declared_relocation_flag": native["declared_additional_flag"], "binaries": binary_checks,
               "command_logs": native_log_checks, "contract_raw_result": "1/1 passed, 100% tests passed"},
    "model": {"pack_manifest_sha256": file_sha(pack_path), "pack_files_independently_rehashed": len(pack_files),
              "mixed_model_sha256": pack["model"]["sha256"], "live_bundle_assets_independently_rehashed": len(asset_checks),
              "source_manifest_equals_historical": download == old_download, "f32_output_pin": f32["output"],
              "f32_manifest_tensor_count": len(f32["tensors"]), "released_inputs": released_inputs,
              "finish_commands": finish_checks, "reference_sha256": ready["reference_sha256"]},
    "python": {"original_archived_packages": freeze_lines, "original_package_count": len(freeze_lines),
               "archived_freeze_equals_historical": freeze == old_freeze,
               "current_qualification_packages": actual_freeze.decode().splitlines(), "current_package_count": len(runtime_expected),
               "current_packages_equal_original_minus_two_declared_build_tools": actual_freeze.decode().splitlines() == runtime_expected,
               "removed_build_packages": sorted(removed_packages), "pruning_receipt_sha256": file_sha(pruning_path),
               "freeze_sha256": digest(freeze), "released_build_tool_pins": tool_checks,
               "bytecode_cleanup_scope": "Original checkpoint has27 packages; qualification runtime retains25 exact versions after declared removal of cmake and ninja. Reproducible bytecode/source intermediates were also pruned."},
    "consumer": {"historical_archive_sha256": digest(consumer_archive_bytes), "historical_members_verified_and_rehashed_live": len(consumer_member_rows),
                 "runtime_files_independently_rehashed": len(runtime_checks),
                 "runtime_paths_and_expected_hashes_match_historical_input_map": all(row["expected"] == prior_runtime_map[row["path"]] for row in runtime_rows),
                 "runtime_live_map_sha256": digest(json.dumps({row["path"]: row["actual_sha256"] for row in runtime_checks}, sort_keys=True).encode()),
                 "font_checks": font_checks, "versions": consumer["versions"], "smoke_commands": len(smoke["commands"]),
                 "schema_controls": "2 valid accepted, 2 invalid rejected; unchanged historical render/extraction succeeded",
                 "current_product_qualification_claimed": False},
    "findings": failures, "runtime_archive_accepted": not failures,
    "sparse_checkout": {"receipt_sha256": file_sha(sparse_path), "source_commit": sparse["source_commit"],
                        "skip_worktree_entries": len(skip_paths), "all_skipped_paths_are_documentation": all(path.startswith("docs/") for path in skip_paths)},
    "initial_review_resolution": "Initial review expected the original27-package build environment and112 source files still to exist. The separate pruning receipt confirms intentional removal of the112 native build-source files and two build-only packages. The initial115 absence/subset findings are retained in runtime-review-initial.json; no archive hashes or retained runtime binary/model/consumer inputs failed. Current review reports the original archived environment and reduced live qualification environment separately.",
    "product_qualification_accepted": False, "github_actions_queried_or_awaited": False,
    "limitations": [
        "The ONNX and F32 conversion intermediates were deliberately released before this independent review. Their historical pins, archived conversion manifest and executable recovery assertions were checked; their removed bytes could not be freshly rehashed.",
        "All112 native build-source files had been deliberately removed before this review; archived before/after hashes match the historical baseline and rebuilt binaries match original pins, but those removed source bytes were not independently rehashed live.",
        "Runtime recovery and historical smoke controls do not establish current product correctness, model quality, performance acceptance, or release readiness.",
        "This review reads a local archive. Remote Git blob/tree readback is a separate later publication check."
    ],
}
out = Path(__file__).with_name("runtime-review.json")
out.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({"report": str(out), "archive_members": len(contents), "consumer_runtime_files": len(runtime_checks),
                  "consumer_reference_files": len(consumer_member_rows), "native_source_files": len(source_checks),
                  "python_packages": len(freeze_lines), "accepted": not failures, "findings": failures}))
raise SystemExit(0 if not failures else 1)

