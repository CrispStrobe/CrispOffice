#!/usr/bin/env python3
"""Classify refreshed pinned tips without changing source or running tests."""

from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess


REPO = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
ORIGINAL = OUT / "audit.json"
CAPTURE = OUT.parent / "remote-capture.json"
VBA = "ae4c8223d1814df4a500518c8b223831cbb0b51f"
MAIL = "1a99845fe628c9e539d4bca7e7c586c5616da267"
GUI = "4fd010fcae209b6ea033828d76908508b7327b9f"
PARSER_FIX = "c3eaf57c85d363b1453f2a3407ba62768b0e2c08"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=REPO)


def text(*args):
    return git(*args).decode().strip()


def ancestor(old, new):
    return subprocess.run(
        ["git", "merge-base", "--is-ancestor", old, new], cwd=REPO,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0


def changed(old, new, *prefixes):
    return [
        item.decode()
        for item in git("diff", "--name-only", "-z", old, new, "--", *prefixes).split(b"\0")
        if item
    ]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def blob_hash(ref, name):
    return sha(git("show", ref + ":" + name))


def classify(name):
    if name.startswith("docs/") or name.endswith(".md"):
        return "documentation_or_validation_evidence"
    if "/test/" in name:
        return "tests"
    if "/lib/" in name:
        return "product"
    return "tooling_or_configuration"


def frontier(old, new):
    names = changed(old, new)
    commits = []
    for row in text("log", "--format=%H%x09%P%x09%s", old + ".." + new).splitlines():
        commit, parents, subject = row.split("\t", 2)
        commits.append({"sha": commit, "parents": parents.split(), "subject": subject})
    return {
        "previous_tip": old,
        "refreshed_tip": new,
        "previous_tip_is_ancestor": ancestor(old, new),
        "parents": text("show", "-s", "--format=%P", new).split(),
        "commits_since_previous_tip": commits,
        "changed_path_count": len(names),
        "changed_path_counts_by_category": dict(Counter(classify(name) for name in names)),
        "changed_paths": [{"path": name, "category": classify(name)} for name in names],
    }


original_bytes = ORIGINAL.read_bytes()
original = json.loads(original_bytes)
capture_bytes = CAPTURE.read_bytes()
capture = json.loads(capture_bytes)
head = text("rev-parse", "HEAD")
base = original["baseline"]
tips = {"vba": VBA, "mail": MAIL}
source_checks = []
for record in original["archive_restore_already_in_baseline"]:
    source_checks.append({
        "path": record["path"],
        "baseline_sha256": record["baseline_sha256"],
        "refreshed_vba_matches_baseline": blob_hash(VBA, record["path"]) == record["baseline_sha256"],
        "refreshed_mail_matches_baseline": blob_hash(MAIL, record["path"]) == record["baseline_sha256"],
    })

formatter_checks = []
for record in original["format_receipt"]["checks"]:
    formatter_checks.append({
        "path": record["path"],
        "independently_replayed_formatter_sha256": record["after_sha256"],
        "refreshed_vba_matches_verified_output": blob_hash(VBA, record["path"]) == record["after_sha256"],
        "refreshed_mail_matches_verified_output": blob_hash(MAIL, record["path"]) == record["after_sha256"],
    })

evidence_checks = []
for record in original["prior_full_frontier_evidence_preserved"]:
    evidence_checks.append({
        "path": record["path"],
        "baseline_sha256": record["baseline_sha256"],
        "refreshed_vba_identical": blob_hash(VBA, record["path"]) == record["baseline_sha256"],
        "refreshed_mail_identical": blob_hash(MAIL, record["path"]) == record["baseline_sha256"],
    })

gui_paths = changed(base, GUI, "packages/quds_office_editor")
gui_checks = [{
    "path": name,
    "gui_checkpoint_sha256": blob_hash(GUI, name),
    "refreshed_vba_sha256": blob_hash(VBA, name),
    "identical": git("show", GUI + ":" + name) == git("show", VBA + ":" + name),
} for name in gui_paths]

fix_paths = changed(PARSER_FIX + "^", PARSER_FIX)
fix = {
    "commit": PARSER_FIX,
    "changed_paths": [{
        "path": name,
        "category": classify(name),
        "before_sha256": blob_hash(PARSER_FIX + "^", name),
        "after_sha256": blob_hash(PARSER_FIX, name),
        "refreshed_vba_preserves_fix": git("show", PARSER_FIX + ":" + name) == git("show", VBA + ":" + name),
    } for name in fix_paths],
    "behavior": "Track procedure-local declared array names so indexed assignment lookahead does not consume a bare helper call with a parenthesized comparison argument.",
    "added_regressions": [
        "preserves bare helper calls with parenthesized comparison arguments",
        "declared arrays accept parenthesized assignment subscripts",
    ],
    "covered_by_existing_gate": "vba-vm: test/office_vba_arrays_test.dart",
}

history_checks = [{
    "branch": row["branch"],
    "head": row["head"],
    "accepted_merge": row["accepted_merge"],
    "original_compared_paths": row["changed_paths_compared"],
    "original_matching_blob_ids": row["matching_blob_ids"],
    "accepted_merge_is_ancestor": {
        "local_head": ancestor(row["accepted_merge"], head),
        "refreshed_vba": ancestor(row["accepted_merge"], VBA),
        "refreshed_mail": ancestor(row["accepted_merge"], MAIL),
    },
} for row in original["historical_equivalence_rechecked"]]

report = {
    "schema_version": 1,
    "audited_at_utc": datetime.now(timezone.utc).isoformat(),
    "mode": "Read-only local Git/source audit. No source edits, compiler, tests, merge, push or GitHub Actions query.",
    "local_head_at_audit": head,
    "original_audit": {"path": str(ORIGINAL.relative_to(REPO)), "sha256": sha(original_bytes), "preserved_without_rewrite": True},
    "root_remote_capture": {
        "path": str(CAPTURE.relative_to(REPO)),
        "sha256": sha(capture_bytes),
        "captured_at_utc": capture["captured_at_utc"],
        "matching_references": [row for row in capture["references"] if row["sha"] in tips.values()],
        "capture_performed_by_this_auditor": False,
    },
    "refreshed_frontiers": {name: frontier(original["tips"][name], tip) for name, tip in tips.items()},
    "common_frontier": text("merge-base", VBA, MAIL),
    "mutual_ancestry": {"vba_contains_mail": ancestor(MAIL, VBA), "mail_contains_vba": ancestor(VBA, MAIL)},
    "new_functional_delta": fix,
    "inherited_gui_checkpoint": {"sha": GUI, "is_ancestor_of_vba": ancestor(GUI, VBA), "checks": gui_checks},
    "archive_restore_paths_still_unchanged": source_checks,
    "verified_formatting_still_unchanged": formatter_checks,
    "original_frontier_evidence_still_preserved": evidence_checks,
    "historical_accepted_ancestry": history_checks,
    "integration_recommendation": {
        "exact_tips": [VBA, MAIL],
        "method": "Merge both exact refreshed tips into the checkpointed GUI branch. Keep the earlier audit and inherited evidence. The VBA tip already contains the initial GUI checkpoint and older mail documentation; the newer mail evidence commit remains a separate tip.",
        "preserve_later_local_gui_work": True,
        "requires_no_additional_test_files_beyond_original_gate_selection": True,
    },
    "qualification": {
        "performed_by_this_audit": False,
        "command_source": str(ORIGINAL.relative_to(REPO)) + "#/qualification/gates",
        "run_after_integration_on_final_source": True,
        "gate_ids": [gate["id"] for gate in original["qualification"]["gates"]],
        "notes": [
            "The archive publication preserves prior author qualification; this read-only refresh does not requalify it against the final GUI merge.",
            "The two new VBA parser regressions are already selected by the existing arrays suite gate.",
            "The inherited eleven GUI core paths exactly match the independently tested GUI checkpoint; retain that evidence and the final GUI gate receipts.",
        ],
    },
}
target = OUT / "audit-refresh.json"
target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({
    "report": str(target.relative_to(REPO)),
    "mail_delta": report["refreshed_frontiers"]["mail"]["changed_path_counts_by_category"],
    "vba_delta": report["refreshed_frontiers"]["vba"]["changed_path_counts_by_category"],
    "gui_paths_unchanged": sum(row["identical"] for row in gui_checks),
    "archive_paths_unchanged": sum(row["refreshed_vba_matches_baseline"] and row["refreshed_mail_matches_baseline"] for row in source_checks),
    "formatter_paths_unchanged": sum(row["refreshed_vba_matches_verified_output"] and row["refreshed_mail_matches_verified_output"] for row in formatter_checks),
    "evidence_paths_preserved": sum(row["refreshed_vba_identical"] and row["refreshed_mail_identical"] for row in evidence_checks),
    "all_historical_ancestry_retained": all(all(row["accepted_merge_is_ancestor"].values()) for row in history_checks),
    "gate_count": len(original["qualification"]["gates"]),
}, indent=2))
