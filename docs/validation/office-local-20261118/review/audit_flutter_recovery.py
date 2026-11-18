#!/usr/bin/env python3
"""Audit Flutter recovery and rejected preflight without mutating frozen source."""
from datetime import datetime, timezone
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
import yaml

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT / "quds_office_suite"
DATA = ROOT / "flutter-qualification"
SDK = ROOT / "toolchains/flutter"
CACHE = ROOT / "toolchains/pub-cache"
CURRENT = "9a7c80be00258def2dcae3bb288c28558c83aa72"
FAILED = "401d012657881a54727d58bc35e537faa45d5fbe"
findings = []

def sha(data):
    return hashlib.sha256(data).hexdigest()

def file_sha(path):
    with Path(path).open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()

def check(value, name, detail=None):
    if not value:
        findings.append({"check": name, "detail": detail})
    return bool(value)

def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args])

def archive_check(stem, expected, expected_count):
    path = DATA / (stem + ".tar.xz")
    index_path = DATA / (stem + ".tar.index.json")
    index = json.loads(index_path.read_text())
    check(file_sha(path) == index["archive_sha256"] == expected, stem + "-archive-sha")
    check(path.stat().st_size == index["archive_bytes"], stem + "-archive-size")
    indexed = {r["path"]: r for r in index["members"]}
    check(len(indexed) == len(index["members"]), stem + "-unique-index")
    contents, rows = {}, []
    with tarfile.open(path) as t:
        for m in t:
            rel = PurePosixPath(m.name)
            check(m.isfile() and not rel.is_absolute() and ".." not in rel.parts, stem + "-safe-member", m.name)
            check(m.name not in contents, stem + "-unique-member", m.name)
            data = t.extractfile(m).read()
            contents[m.name] = data
            expected_row = indexed[m.name]
            row = {"path": m.name, "bytes": len(data), "sha256": sha(data)}
            row["matches"] = row["bytes"] == expected_row["bytes"] and row["sha256"] == expected_row["sha256"]
            check(row["matches"], stem + "-member-hash", m.name)
            rows.append(row)
    check(set(contents) == set(indexed) and len(rows) == expected_count, stem + "-exact-members")
    return contents, {"archive": path.name, "sha256": file_sha(path), "bytes": path.stat().st_size,
                      "index_sha256": file_sha(index_path), "members": rows, "member_count": len(rows)}

def git_tree(repo, commit):
    result = {}
    for row in git(repo, "ls-tree", "-r", "-z", commit).split(b"\0"):
        if row:
            left, path = row.split(b"\t", 1)
            mode, kind, blob = left.decode().split()
            if kind == "blob":
                result[path.decode()] = {"mode": mode, "blob": blob}
    return result

head_before = git(REPO, "rev-parse", "HEAD").decode().strip()
status_before = git(REPO, "status", "--porcelain").decode().strip()
check(head_before == CURRENT and status_before == "", "current-source-clean-before", {"head": head_before, "status": status_before})
runtime, runtime_audit = archive_check("flutter-runtime-recovery", "58402817d7db88f96cf30d2433bff6f3e8bff577bc7c44182b98d8b645707bd9", 16)
failed, failed_audit = archive_check("canonical-preflight-401d0126", "6cca773d22116c3b11954b12d6bb3518e062427bb8827aa44daf2742d0be98b4", 27)
install = json.loads(runtime["runtime/flutter-install-receipt.json"])
ready = json.loads(runtime["runtime/ready.json"])
version = json.loads(runtime["runtime/flutter-version.log"])
check(ready["version"] == version, "version-receipt-consistency")
check(version["frameworkVersion"] == "3.47.8" and version["dartSdkVersion"] == "3.13.7", "sdk-version-pins")
check(version["frameworkRevision"] == "737ba8f885dc774b53b442759999a312c9461e4e", "sdk-revision-pin")
check(git(SDK, "rev-parse", "HEAD").decode().strip() == version["frameworkRevision"], "live-sdk-git-revision")
bootstrap_path = "docs/validation/proofing-20261116/integration-followup/flutter-setup/bootstrap_flutter.py"
bootstrap = git(REPO, "show", CURRENT + ":" + bootstrap_path).decode()
check(install["sha256"] == "baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2" and install["sha256"] in bootstrap, "official-archive-pin")
check(install["archive_bytes"] == 1581444364, "official-archive-byte-count")
check(install["url"] in bootstrap, "official-archive-url")
selection = json.loads(runtime["setup/compact-restoration-plan.json"])
adaptation = json.loads(runtime["setup/restore-adaptation.json"])
original_restore = git(REPO, "show", CURRENT + ":" + Path(selection["source"]).relative_to(REPO).as_posix())
check(sha(original_restore) == selection["source_sha256"] == adaptation["source_sha256"], "restoration-original-recipe-pin")
check(sha(runtime["setup/restore_flutter.py"]) == adaptation["adapted_sha256"], "restoration-adapted-recipe-pin")
check(sha(runtime["setup/restore_compact_flutter.py"]) == selection["adapted_sha256"], "restoration-compact-recipe-pin")
check(len(install["files"]) == selection["retained_files"] == 3277, "retained-sdk-count")
check(sum(r["bytes"] for r in install["files"]) == install["extracted_bytes"] == selection["retained_bytes"] == 572002795, "retained-sdk-bytes")
sdk_tree = git_tree(SDK, version["frameworkRevision"])
sdk_source_count = 0
sdk_crlf_matches = []
sdk_hashes = {}
for row in install["files"]:
    path = ROOT / "toolchains" / row["path"]
    check(path.is_file() and path.stat().st_size == row["bytes"], "retained-sdk-live-size", row["path"])
    if not path.is_file():
        continue
    data = path.read_bytes()
    sdk_hashes[row["path"]] = sha(data)
    relative = str(path.relative_to(SDK))
    if relative in sdk_tree:
        git_blob = hashlib.sha1(("blob " + str(len(data)) + "\0").encode() + data).hexdigest()
        matched = git_blob == sdk_tree[relative]["blob"]
        if not matched:
            attributes = git(SDK, "check-attr", "-z", "text", "eol", "--", relative).split(b"\0")
            attrs = {attributes[i + 1].decode(): attributes[i + 2].decode() for i in range(0, len(attributes) - 1, 3)}
            normalized = data.replace(b"\r\n", b"\n")
            normalized_blob = hashlib.sha1(("blob " + str(len(normalized)) + "\0").encode() + normalized).hexdigest()
            matched = attrs == {"text": "set", "eol": "crlf"} and normalized_blob == sdk_tree[relative]["blob"]
            if matched:
                sdk_crlf_matches.append({"path": relative, "archive_sha256": sha(data), "raw_git_blob": git_blob,
                                         "normalized_git_blob": normalized_blob, "attributes": attrs,
                                         "crlf_count": data.count(b"\r\n")})
        check(matched, "sdk-tracked-source-blob", relative)
        sdk_source_count += matched
for excluded in selection["excluded_prefixes"]:
    if excluded != "flutter/.git":
        check(not (ROOT / "toolchains" / excluded).exists(), "sdk-declared-omission", excluded)
for excluded in selection["excluded_files"]:
    check(not (ROOT / "toolchains" / excluded).exists(), "sdk-declared-omission", excluded)
required = [
    "bin/cache/artifacts/engine/linux-x64/flutter_tester",
    "bin/cache/dart-sdk/bin/dart",
    "bin/cache/dart-sdk/bin/dartaotruntime",
    "bin/cache/dart-sdk/bin/snapshots/analysis_server_aot.dart.snapshot",
    "bin/cache/dart-sdk/bin/snapshots/dart2js_aot.dart.snapshot",
    "bin/cache/artifacts/engine/common/flutter_patched_sdk/platform_strong.dill",
]
for relative in required:
    check((SDK / relative).is_file(), "required-test-analyzer-node-compiler-core", relative)
for command in json.loads(runtime["runtime/commands.json"]):
    check(command["exit_code"] == 0 and sha(runtime["runtime/" + command["label"] + ".log"]) == command["log_sha256"], "recovery-command-log", command["label"])
shallow = json.loads(runtime["runtime/flutter-shallow-identity.json"])
check(len(shallow) == 4 and all(row["exit_code"] == 0 for row in shallow), "shallow-tag-identity-commands")

pub = json.loads(runtime["runtime/pub-cache-receipt.json"])
entries = {}
for lock, expected in pub["locks"].items():
    path = Path(lock)
    data = path.read_bytes() if path.is_file() else git(REPO, "show", CURRENT + ":" + path.relative_to(REPO).as_posix())
    check(sha(data) == expected, "lock-hash", lock)
    for name, value in yaml.safe_load(data)["packages"].items():
        if value["source"] == "hosted":
            key = name + "-" + value["version"]
            row = {"name": name, "version": value["version"], "sha256": value["description"]["sha256"]}
            check(key not in entries or entries[key] == row, "consistent-two-locks", key)
            entries[key] = row
check(len(pub["packages"]) == len(entries) == 162, "pub-archive-count")
omitted_members = 0
for row in pub["packages"]:
    key = row["name"] + "-" + row["version"]
    check(entries[key]["sha256"] == row["sha256"] == row["actual_sha256"] and row["status"] == "verified-download", "pub-archive-pin", key)
    check((CACHE / "hosted-hashes/pub.dev" / (key + ".sha256")).read_text().strip() == row["sha256"], "live-pub-cache-marker", key)
    check((CACHE / "hosted/pub.dev" / key / "pubspec.yaml").is_file(), "live-pubspec", key)
    omitted_members += row["omitted_development_members"]

setup = json.loads(runtime["workspace/setup.json"])
check(setup["exit_code"] == 0 and "--offline" in setup["command"] and "--enforce-lockfile" in setup["command"], "offline-locked-workspace")
check(setup["lock_before_sha256"] == setup["lock_after_sha256"] == "344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130", "workspace-lock-unchanged")
link_checks = 0
for row in setup["links"]:
    path = Path(row["path"])
    check(path.is_symlink() and path.resolve() == Path(row["source"]).resolve(), "workspace-link-to-frozen-source", row)
    link_checks += 1

receipt = json.loads(failed["canonical-401d0126/receipt.json"])
failed_plan = json.loads(failed["canonical-401d0126/plan.json"])
check(sha(failed["canonical-401d0126/plan.json"]) == receipt["plan_sha256"], "failed-plan-receipt-binding")
check(failed_plan["source_commit"] == FAILED, "failed-plan-source-binding")
maps = {}
for kind in ["source", "dependencies", "runtime", "workspace", "harness", "system"]:
    before, after = [failed["canonical-401d0126/" + kind + "-" + stage + ".json"] for stage in ["before", "after"]]
    check(before == after, "failed-preflight-byte-identical-" + kind)
    maps[kind] = json.loads(before)
check(all(receipt["input_integrity"].values()), "reported-preflight-integrity")
check(receipt["source_commit"] == receipt["working_head_after"] == FAILED and receipt["source_matches_frozen_commit"], "failed-source-binding")
check(receipt["status"] == "failed" and not receipt["all_passed"], "rejected-status-retained")
check(receipt["raw_runner_success_total"] == receipt["substantive_success_total"] == 0 and receipt["tests_by_cohort"] == {}, "no-tests-before-lint")
check(maps["source"]["commit_mismatches"] == [] and maps["source"]["untracked_non_evidence_paths"] == [], "failed-source-no-mismatches")
old_tree = git_tree(REPO, FAILED)
current_tree = git_tree(REPO, CURRENT)
old_source_rows = maps["source"]["files"]
check(len(old_source_rows) == maps["source"]["count"] == 3514, "failed-source-count")
source_current_deltas = []
source_live_matches_current = 0
for path, row in old_source_rows.items():
    check(old_tree[path]["blob"] == row["git_blob"] and old_tree[path]["mode"] == row["git_mode"], "failed-git-source-blob-binding", path)
    if current_tree[path]["blob"] != row["git_blob"]:
        source_current_deltas.append(path)
    data = (REPO / path).read_bytes()
    old_data = data if current_tree[path]["blob"] == row["git_blob"] else git(REPO, "show", FAILED + ":" + path)
    check(sha(old_data) == row["sha256"], "failed-source-sha256-binding", path)
    actual_blob = hashlib.sha1(("blob " + str(len(data)) + "\0").encode() + data).hexdigest()
    check(actual_blob == current_tree[path]["blob"], "current-source-live-blob", path)
    source_live_matches_current += 1
check(source_current_deltas == ["packages/quds_office_editor/test/sheet_conditional_rendering_test.dart"], "only-expected-current-source-lint-delta", source_current_deltas)
live_dependency_count = 0
for path, expected in maps["dependencies"]["sha256_by_path"].items():
    check(Path(path).is_file() and file_sha(path) == expected, "live-dependency-hash", path)
    live_dependency_count += 1
runtime_checks = []
for path, expected in maps["runtime"].items():
    actual = file_sha(path) if Path(path).is_file() else None
    check(actual == expected, "live-core-runtime-hash", path)
    runtime_checks.append({"path": path, "sha256": actual, "matches": actual == expected})
for command in receipt["commands"]:
    for stream in ["stdout", "stderr"]:
        name = "canonical-401d0126/" + command["name"] + "/" + stream + ".gz"
        compressed = failed[name]
        check(sha(compressed) == command[stream + "_gzip_sha256"] and sha(gzip.decompress(compressed)) == command[stream + "_sha256"], "preflight-command-log", name)
check([(r["name"], r["exit_code"]) for r in receipt["commands"]] == [("engine-strict-analysis", 0), ("editor-strict-analysis", 1)], "exact-preflight-command-outcomes")
editor_log = gzip.decompress(failed["canonical-401d0126/editor-strict-analysis/stdout.gz"]).decode()
check("curly_braces_in_flow_control_structures" in editor_log and "1 issue found." in editor_log, "sole-recorded-editor-lint")
format_receipt = json.loads(failed["format-preflight-401d0126/receipt.json"])
check(format_receipt["exit_code"] == 0 and format_receipt["source_commit"] == FAILED, "format-receipt-source")
for stream in ["stdout", "stderr"]:
    check(sha(failed["format-preflight-401d0126/" + stream + ".log"]) == format_receipt[stream + "_sha256"], "format-log-hash", stream)
check("Formatted 145 files (0 changed)" in failed["format-preflight-401d0126/stdout.log"].decode(), "format-count")
format_warnings = failed["format-preflight-401d0126/stderr.log"].decode().count("Warning: Package resolution error")
dedup_path = DATA / "sdk-byte-identical-deduplication.json"
dedup = json.loads(dedup_path.read_text())
left, right = Path(dedup["left"]), Path(dedup["right"])
check(file_sha(left) == file_sha(right) == dedup["left_sha256"] == dedup["right_sha256"], "dedup-current-byte-identity")
check(os.path.samefile(left, right), "dedup-shared-inode")
check(left.stat().st_mode == right.stat().st_mode, "dedup-current-mode")
check(left.stat().st_size == dedup["bytes_reclaimed"] == 17153416, "dedup-byte-count")
raw_release_path = DATA / "published-attempt-raw-release.json"
raw_release = json.loads(raw_release_path.read_text())
check(raw_release["sha256"] == failed_audit["sha256"] and raw_release["all_members_verified"] == 27, "raw-release-archive-binding")
check(raw_release["remote_checkpoint"] == CURRENT, "raw-release-remote-checkpoint")
head_after = git(REPO, "rev-parse", "HEAD").decode().strip()
status_after = git(REPO, "status", "--porcelain").decode().strip()
check(head_before == head_after == CURRENT and status_before == status_after == "", "frozen-source-clean-after")

report = {
    "schema_version": 1, "kind": "independent-flutter-recovery-and-failed-preflight-review",
    "created_utc": datetime.now(timezone.utc).isoformat(), "reviewer": "remote_review independent agent",
    "current_source": CURRENT, "rejected_preflight_source": FAILED,
    "source_head_clean_and_unchanged": head_before == head_after == CURRENT and status_before == status_after == "",
    "runtime_archive": runtime_audit, "failed_preflight_archive": failed_audit,
    "sdk": {"version": version, "official_archive_url": install["url"], "official_archive_sha256": install["sha256"],
            "official_archive_bytes": install["archive_bytes"], "retained_files_fully_read": len(sdk_hashes),
            "retained_bytes": install["extracted_bytes"], "retained_sdk_tracked_files_matching_pinned_git_blobs": sdk_source_count,
            "retained_sdk_tracked_files_matching_without_normalization": sdk_source_count - len(sdk_crlf_matches),
            "tracked_sdk_matches_requiring_declared_crlf_normalization": sdk_crlf_matches,
            "restoration_recipe_pins_checked": {"original": sha(original_restore),
                                                "adapted": sha(runtime["setup/restore_flutter.py"]),
                                                "compact": sha(runtime["setup/restore_compact_flutter.py"])},
            "live_sdk_map_sha256": sha(json.dumps(sdk_hashes, sort_keys=True).encode()), "live_core_runtime_hashes": runtime_checks,
            "excluded_prefixes": selection["excluded_prefixes"], "excluded_files": selection["excluded_files"],
            "functional_scope": "Retained VM/Flutter tester, AOT analyzer and Dart2JS cores. No Flutter web-renderer, DevTools, sanitizer or desktop-GTK build qualification is claimed."},
    "pub": {"verified_archive_receipts": len(pub["packages"]), "all_pins_reconciled_to_two_locks": True,
            "all_download_receipts_have_actual_matching_sha256": True,
            "dependency_files_independently_rehashed_live": live_dependency_count, "package_roots_in_execution_map": len(maps["dependencies"]["package_roots"]),
            "omitted_development_members": omitted_members, "omitted_top_level_components": selection["pub_cache_omissions"],
            "offline_workspace_enforced_lock_sha256": setup["lock_before_sha256"], "frozen_source_links_checked": link_checks},
    "failed_preflight": {"input_map_groups_byte_identical": list(maps), "source_files": len(old_source_rows),
                         "source_blob_bindings_match_rejected_commit": True, "live_source_files_match_current_commit": source_live_matches_current,
                         "current_source_deltas_from_failed_snapshot": source_current_deltas,
                         "engine_strict_analysis_exit": 0, "editor_strict_analysis_exit": 1,
                         "editor_failure": "curly_braces_in_flow_control_structures in sheet_conditional_rendering_test.dart:133:9",
                         "planned_unique_test_files": failed_plan["unique_test_files"],
                         "planned_test_cohorts": len(failed_plan["cohorts"]),
                         "test_cohorts_started": 0, "substantive_tests_passed": 0,
                         "formatting": {"files": 145, "changed": 0, "exit": 0, "retained_package_resolution_warnings": format_warnings,
                                        "warning_scope": "Formatting could not resolve some flutter_lints include URIs; these warnings are retained and are not counted as a strict-analysis pass."}},
    "disk_recovery": {"dedup_receipt_sha256": file_sha(dedup_path), "dedup_file_sha256": file_sha(left),
                      "hardlink_same_inode_and_mode": os.path.samefile(left, right) and left.stat().st_mode == right.stat().st_mode,
                      "dedup_bytes_reclaimed": dedup["bytes_reclaimed"], "raw_release_receipt_sha256": file_sha(raw_release_path),
                      "raw_release_archived_member_count": 27, "released_raw_bytes": sum(r["bytes"] for r in raw_release["released"])},
    "findings": findings, "recovery_and_rejected_attempt_evidence_accepted": not findings,
    "current_source_qualification_accepted": False, "github_actions_queried_or_awaited": False,
    "limitations": [
        "The large official SDK and hosted dependency download archives were not downloaded again. Full-download hash assertions, archived receipts, exact lock pins, retained tracked SDK source blobs, live core runtime hashes and live execution dependency maps were independently checked.",
        "Selective SDK and dependency development-file omissions are explicit. This review does not establish support for omitted tooling or tests that require omitted development fixtures.",
        "The failed401 preflight is retained as a failure. The corrected9a source needs its own completed qualification receipts; no result is inferred from this audit.",
        "Archive byte readback here is local. Remote publication readback is a distinct check."
    ]
}
out = Path(__file__).with_name("flutter-recovery-review.json")
out.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({"report": str(out), "accepted": not findings, "findings": findings,
                  "sdk_files": len(sdk_hashes), "tracked_sdk_matches": sdk_source_count,
                  "dependencies": live_dependency_count, "source_files": len(old_source_rows)}))
raise SystemExit(0 if not findings else 1)

