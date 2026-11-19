#!/usr/bin/env python3
"""Read-only Git/formatter audit of pinned tips; no compiler or tests run."""

from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


REPO = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
BASE = "37ac6ea8a08225a42098c455deb5375837912eec"
VBA = "ac9de9e000274718145659da0abc7c8cadb9e8c3"
MAIL = "0c77b3488eb534868a7f98271ba2923d06759b8d"
FORMAT = "358544a48466c942873a4718a87fa9d1c2be11f7"
MAIN_BEFORE_BASE = "cf59efa99232a3fd26cf21ce7f2382402e576f9b"
HISTORY = "docs/validation/office-vba-arrays-20261119/remote-initial/audit.json"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=REPO)


def text(*args):
    return git(*args).decode().strip()


def ancestor(old, new):
    return subprocess.run(
        ["git", "merge-base", "--is-ancestor", old, new], cwd=REPO,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0


def paths(old, new, *prefixes):
    return [path.decode() for path in git("diff", "--name-only", "-z", old, new, "--", *prefixes).split(b"\0") if path]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def blobs(ref, names):
    result = {}
    for entry in git("ls-tree", "-r", "-z", ref, "--", *names).split(b"\0"):
        if entry:
            metadata, name = entry.split(b"\t", 1)
            result[name.decode()] = metadata.decode().split()[2]
    return result


def commits(new):
    rows = []
    for line in text("log", "--format=%H%x09%P%x09%s", BASE + ".." + new).splitlines():
        commit, parents, subject = line.split("\t", 2)
        rows.append({"sha": commit, "parents": parents.split(), "subject": subject})
    return rows


head = text("rev-parse", "HEAD")
format_receipt_path = "docs/validation/mail-archive-restore-20261119/format-reconciliation.json"
format_receipt = json.loads(git("show", FORMAT + ":" + format_receipt_path))
format_checks = []
for record in format_receipt["paths"]:
    name = record["path"]
    before = git("show", BASE + ":" + name)
    after = git("show", FORMAT + ":" + name)
    formatter_argv = [
        str(REPO.parent / "toolchain/run_dart.sh"), "format", "--output=show",
        "--summary=none", "--stdin-name=" + str(REPO / name),
    ]
    formatted = subprocess.run(
        formatter_argv, input=before, cwd=REPO, capture_output=True, timeout=30,
    )
    format_checks.append({
        "path": name,
        "before_sha256": sha(before),
        "after_sha256": sha(after),
        "author_hashes_match": sha(before) == record["before_sha256"] and sha(after) == record["after_sha256"],
        "formatter_argv": formatter_argv,
        "formatter_exit_code": formatted.returncode,
        "formatter_stderr": formatted.stderr.decode(),
        "matches_pinned_formatter_output": formatted.returncode == 0 and formatted.stdout == after,
        "author_reports_exact_pinned_formatter_output": record["matches_official_formatter_output"],
    })

historical = json.loads(git("show", VBA + ":" + HISTORY))["historical_equivalence"]
history_checks = []
for proof in historical:
    common = text("merge-base", proof["head"], proof["accepted_merge"])
    changed = paths(common, proof["head"])
    original = blobs(proof["head"], changed)
    accepted = blobs(proof["accepted_merge"], changed)
    mismatches = [name for name in changed if original.get(name) != accepted.get(name)]
    history_checks.append({
        "branch": proof["branch"],
        "head": proof["head"],
        "accepted_pr": proof["pr"],
        "accepted_merge": proof["accepted_merge"],
        "comparison_merge_base": common,
        "accepted_merge_is_ancestor_of_local_head": ancestor(proof["accepted_merge"], head),
        "changed_paths_compared": len(changed),
        "matching_blob_ids": len(changed) - len(mismatches),
        "mismatched_paths": mismatches,
        "source_proof": HISTORY,
        "fresh_github_query_performed": False,
    })

restore_prefixes = [
    "packages/quds_mail_store/lib", "packages/quds_mail_store/test", "packages/quds_mail_store/tool",
    "packages/quds_office_editor/example/lib/studio_mail_archive_host.dart",
    "packages/quds_office_editor/example/lib/studio_mail_archive_native.dart",
    "packages/quds_office_editor/example/lib/studio_mail_archive_restore.dart",
    "packages/quds_office_editor/example/lib/studio_mail_archive_restore_strings.dart",
    "packages/quds_office_editor/example/test/studio_mail_archive_restore_test.dart",
    "packages/quds_office_editor/example/test/studio_mail_archive_restore_native_test.dart",
    "packages/quds_office_editor/example/test/studio_mail_archive_portability_visual_test.dart",
]
restore_paths = paths(MAIN_BEFORE_BASE, BASE, *restore_prefixes)
restore_hashes = []
for name in restore_paths:
    base_blob = git("show", BASE + ":" + name)
    restore_hashes.append({
        "path": name,
        "baseline_sha256": sha(base_blob),
        "vba_tip_matches_baseline": git("show", VBA + ":" + name) == base_blob,
        "mail_tip_matches_baseline": git("show", MAIL + ":" + name) == base_blob,
    })

evidence_paths = [
    "docs/validation/crispoffice-gui-20261119/reconciliation-final.json",
    "docs/validation/mail-archive-restore-20261119/reconciliation.json",
    "docs/validation/office-vba-control-flow-20261119/final-frontier.json",
]
preserved_evidence = []
for name in evidence_paths:
    original = git("show", BASE + ":" + name)
    preserved_evidence.append({
        "path": name,
        "baseline_sha256": sha(original),
        "vba_tip_identical": git("show", VBA + ":" + name) == original,
        "mail_tip_identical": git("show", MAIL + ":" + name) == original,
    })

toolchain = REPO.parent / "toolchain"
dart = str(toolchain / "run_dart.sh")
flutter = str(toolchain / "run_flutter.sh")
config = REPO / ".dart_tool/package_config.json"
test_cli = str(toolchain / "pub-cache/hosted/pub.dev/test-1.31.1/bin/test.dart")
vm = [dart, "--packages=" + str(config), test_cli, "--platform=vm", "--compiler=kernel", "--concurrency=1", "--reporter=json"]
node_tests = [dart, "--packages=" + str(config), test_cli, "--platform=node", "--compiler=dart2js", "--concurrency=1", "--reporter=json"]
vba_tests = [
    "test/office_vba_arrays_test.dart", "test/office_vba_arrays_boundaries_test.dart", "test/office_vba_arrays_integration_test.dart",
    "test/office_vba_language_test.dart", "test/office_vba_integration_test.dart",
    "test/office_vba_procedures_test.dart", "test/office_vba_procedure_boundaries_test.dart", "test/office_vba_procedures_integration_test.dart",
    "test/office_vba_control_flow_test.dart", "test/office_vba_control_flow_boundaries_test.dart", "test/office_vba_control_flow_integration_test.dart",
]
mail_tests = [
    "test/archive_multi_origin_test.dart", "test/archive_restore_native_test.dart", "test/archive_restore_adversarial_test.dart",
    "test/archive_repository_test.dart", "test/archive_native_test.dart", "test/archive_export_manifest_test.dart",
]
studio_tests = [
    "test/studio_mail_archive_restore_test.dart", "test/studio_mail_archive_restore_native_test.dart",
    "test/studio_mail_archive_portability_visual_test.dart",
]
gates = [
    {"id": "vba-scoped-analysis", "cwd": "packages/quds_office_engine", "argv": [dart, "analyze", "--fatal-infos", "--fatal-warnings", "lib/src/automation/office_vba_language.dart", *vba_tests[:3], "tool/macros/web_vba_arrays_smoke.dart"], "purpose": "New compiler and array entry points, without analyzing unrelated packages."},
    {"id": "vba-vm", "cwd": "packages/quds_office_engine", "argv": vm + vba_tests, "purpose": "Three new suites plus existing VBA syntax/procedure/control-flow paths sharing the changed compiler."},
    {"id": "archive-scoped-analysis", "cwd": ".", "argv": [dart, "analyze", "--fatal-infos", "--fatal-warnings", *restore_paths], "purpose": "Previously integrated restoration APIs, atomic repository changes, Studio host and their tests."},
    {"id": "archive-native", "cwd": "packages/quds_mail_store", "argv": vm + mail_tests, "purpose": "Atomic multi-origin writes, restoration, adversarial/process recovery, existing repository/native API compatibility, manifest contract."},
    {"id": "archive-portable", "cwd": "packages/quds_mail_store", "argv": node_tests + ["test/archive_export_manifest_test.dart", "test/browser_problem_test.dart"], "purpose": "Portable public manifest and declared browser boundary; do not run archive_query_test.dart on Node."},
    {"id": "archive-studio", "cwd": "packages/quds_office_editor/example", "argv": [flutter, "test", "--no-pub", "--concurrency=1", "--reporter=json", *studio_tests], "purpose": "Deliberate preview/start/cancel flow, genuine native MIME/SQLite restoration, localized narrow layouts."},
]
for stem in ["web_vba_arrays_smoke", "web_vba_control_flow_smoke"]:
    output = str(OUT / (stem + ".js"))
    gates += [
        {"id": stem + "-compile", "cwd": "packages/quds_office_engine", "argv": [dart, "compile", "js", "-O1", "tool/macros/" + stem + ".dart", "-o", output], "purpose": "Compile the portable compiler/runtime path."},
        {"id": stem + "-node", "cwd": "packages/quds_office_engine", "argv": [shutil.which("node") or "node", "-e", "globalThis.self = globalThis; require(" + json.dumps(output) + ");"], "purpose": "Execute and inspect the JSON assertions; exit code alone is not sufficient.", "required_json_true_fields": (["liveArraySlotsAndIndependentControlVariables", "rangeSnapshotAndRowMajorOrder", "exactArrayAllocationAndNegativeBounds", "boundedArraysAndRangeIteration", "staticInactiveChecks", "validationPreservedBytes", "lateFailurePreservedBytes", "mcpCompileAndRun"] if stem == "web_vba_arrays_smoke" else ["orderedCasesAndEagerRangeBounds", "sharedLoopWorkBudget", "staticInactiveChecks", "validationPreservedBytes", "lateFailurePreservedBytes", "mcpCompileAndRun"]), "coldDepthStress_contains": ["32", "63"]},
    ]

report = {
    "schema_version": 1,
    "audited_at_utc": datetime.now(timezone.utc).isoformat(),
    "repository": "CrispStrobe/quds_office_suite",
    "mode": "Read-only Git/source audit with pinned formatter replay through stdin; no source mutations, compiler, test, merge, push or GitHub Actions query performed.",
    "local_head_at_audit": head,
    "local_branch": text("branch", "--show-current"),
    "baseline": BASE,
    "main_before_baseline": MAIN_BEFORE_BASE,
    "tips": {"vba": VBA, "mail": MAIL, "common_frontier": text("merge-base", VBA, MAIL)},
    "baseline_is_ancestor": {"vba": ancestor(BASE, VBA), "mail": ancestor(BASE, MAIL), "local": ancestor(BASE, head)},
    "incoming_commits": {"vba": commits(VBA), "mail": commits(MAIL)},
    "changed_paths_from_baseline": {"vba": paths(BASE, VBA), "mail": paths(BASE, MAIL)},
    "format_receipt": {"path": format_receipt_path, "commit": FORMAT, "checks": format_checks},
    "mail_latest_commit_changes_product_or_tests": bool(paths(FORMAT, MAIL, "packages/quds_mail_store/lib", "packages/quds_mail_store/test", "packages/quds_office_editor/example/lib", "packages/quds_office_editor/example/test")),
    "archive_restore_already_in_baseline": restore_hashes,
    "historical_equivalence_rechecked": history_checks,
    "prior_full_frontier_evidence_preserved": preserved_evidence,
    "integration_recommendation": {"exact_tips": [VBA, MAIL], "method": "Merge both exact tips into the checkpointed GUI branch, retaining ancestry. VBA already contains the formatter commit; mail contributes its final docs/validation correction. Do not replay historical equivalent branches or replace GUI files with an incoming tree.", "refresh_required_before_final_publication": True},
    "qualification": {"performed_by_this_audit": False, "required_after_integration": "Run the focused gates serially on the final merged source and bind all receipts to its source hashes. Retain existing GUI acceptance and original evidence; unchanged historical paths need no replay.", "gates": gates},
    "scope_limits": ["This checks only the two pinned tips supplied by root; it is not a fresh all-refs internet inventory.", "Historical accepted PR mappings come from the preserved author audit. Ancestry and changed-path blob equality were recomputed locally; PR metadata was not re-queried.", "No new functionality is qualified by this read-only report."],
}
target = OUT / "audit.json"
target.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
print(json.dumps({
    "report": str(target.relative_to(REPO)),
    "format_hashes_match": all(row["author_hashes_match"] for row in format_checks),
    "format_replays_equal": sum(row["matches_pinned_formatter_output"] for row in format_checks),
    "format_files": len(format_checks),
    "historical_branches": len(history_checks),
    "historical_blobs_equal": sum(row["matching_blob_ids"] for row in history_checks),
    "historical_mismatches": sum(len(row["mismatched_paths"]) for row in history_checks),
    "archive_paths_unchanged": len(restore_hashes),
    "gates": len(gates),
}, indent=2))
