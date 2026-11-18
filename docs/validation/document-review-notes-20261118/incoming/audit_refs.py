#!/usr/bin/env python3
"""Capture/verify fetched Git refs without network access or Git mutations.

Run from anywhere in this checkout. Normal verification uses only the saved
snapshot and immutable Git objects; --capture deliberately replaces the snapshot.
An optional --head additionally verifies that a completed integration contains
the captured heads (or their independently rechecked historical equivalents).
"""

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess


HERE = Path(__file__).resolve().parent
ROOT = next(p for p in HERE.parents if (p / ".git").exists())
TASK_BRANCH = "codex/document-review-notes-20261118"
BASELINE = "690e6ac8a1f7d8f5c8d4bea69d989a6728f3b27e"
PROOF_SOURCE = (
    "a39f786d5707af308b1f9899c3461a72e62b4b68:"
    "docs/validation/mail-store-20261118/incoming/initial-audit.json"
)
COVERAGE_REFS = [
    "refs/remotes/origin/main",
    "refs/remotes/origin/codex/mail-reader-20261118",
    "refs/remotes/origin/codex/zotero-word-parity-20261118",
    "refs/remotes/origin/codex/offline-thesaurus-20261118",
]


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def text(*args):
    return git(*args).decode().strip()


def ancestor(commit, head):
    result = subprocess.run(
        ["git", "merge-base", "--is-ancestor", commit, head],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr.decode())
    return result.returncode == 0


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def capture():
    refs = []
    excluded = []
    for row in text(
        "for-each-ref", "--format=%(refname) %(objectname)",
        "refs/remotes/origin", "refs/remotes/pull", "refs/remotes/upstream",
    ).splitlines():
        ref, commit = row.split()
        if ref in ("refs/remotes/origin/HEAD", f"refs/remotes/origin/{TASK_BRANCH}"):
            excluded.append({"ref": ref, "sha": commit})
            continue
        group = (
            "origin_branches" if ref.startswith("refs/remotes/origin/") else
            "upstream_branches" if ref.startswith("refs/remotes/upstream/") else
            "pull_request_heads"
        )
        refs.append({"ref": ref, "sha": commit, "group": group})
    proof_bytes = git("show", PROOF_SOURCE)
    proofs = []
    for entry in json.loads(proof_bytes)["historical_equivalence_reverification"]:
        proof = {k: entry[k] for k in ("sha", "equivalent_commit")}
        proof["method"] = entry["disposition"]
        if "merge_base" in entry:
            proof["comparison_base"] = entry["merge_base"]
        proofs.append(proof)
    return {
        "schema": 1,
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "repository": "CrispStrobe/quds_office_suite",
        "scope": "Bounded snapshot of already fetched local origin, PR and upstream refs; no network or CI calls.",
        "excluded_refs": excluded,
        "excluded_task_branch": TASK_BRANCH,
        "baseline": BASELINE,
        "coverage_heads": [
            {"ref": ref, "sha": text("rev-parse", ref)} for ref in COVERAGE_REFS
        ],
        "historical_proof_seed": {"git_object": PROOF_SOURCE, "sha256": sha256(proof_bytes)},
        "historical_equivalences": proofs,
        "counts": dict(Counter(entry["group"] for entry in refs)),
        "refs": refs,
    }


def verify_proof(proof, baseline):
    source, equivalent = proof["sha"], proof["equivalent_commit"]
    result = dict(proof)
    result["equivalent_ancestor_of_baseline"] = ancestor(equivalent, baseline)
    method = proof["method"]
    if method == "all_commits_patch_equivalent":
        # Stronger than patch-id: exact modes, before/after blob IDs and paths.
        def raw_delta(commit):
            return git("diff", "--raw", "--no-abbrev", "--no-renames", "-z", commit + "^1", commit, "--")
        source_delta, equivalent_delta = raw_delta(source), raw_delta(equivalent)
        result["raw_delta_sha256"] = sha256(source_delta)
        result["equivalent_raw_delta_sha256"] = sha256(equivalent_delta)
        result["raw_delta_identical"] = source_delta == equivalent_delta
        # Include every missing predecessor, not only the branch tip's delta.
        cherry = text("cherry", baseline, source).splitlines()
        result["git_cherry"] = cherry
        equal = bool(cherry) and all(row.startswith("- ") for row in cherry) and source_delta == equivalent_delta
    elif method == "identical_tree_already_integrated":
        result["source_tree"] = text("rev-parse", source + "^{tree}")
        result["equivalent_tree"] = text("rev-parse", equivalent + "^{tree}")
        equal = result["source_tree"] == result["equivalent_tree"]
    elif method == "all_changed_files_identical_in_merged_pr_140":
        paths = git("diff", "--name-only", "-z", proof["comparison_base"], source, "--").decode().split("\0")
        checks = []
        for path in filter(None, paths):
            source_entry = git("ls-tree", "-z", source, "--", path)
            equivalent_entry = git("ls-tree", "-z", equivalent, "--", path)
            checks.append({
                "path": path,
                "source_entry": source_entry.decode().rstrip("\0"),
                "equivalent_entry": equivalent_entry.decode().rstrip("\0"),
                "equal": source_entry == equivalent_entry,
            })
        result["changed_file_count"] = len(checks)
        result["files"] = checks
        equal = len(checks) == 37 and all(entry["equal"] for entry in checks)
    else:
        raise ValueError(f"Unknown historical method: {method}")
    result["verified"] = equal and result["equivalent_ancestor_of_baseline"]
    return result


def verify(snapshot, snapshot_bytes, integrated_head):
    heads = [entry["sha"] for entry in snapshot["coverage_heads"]]
    proofs = [verify_proof(p, snapshot["baseline"]) for p in snapshot["historical_equivalences"]]
    equivalents = {entry["sha"]: entry for entry in proofs if entry["verified"]}
    head = text("rev-parse", integrated_head + "^{commit}") if integrated_head else None
    rows = []
    by_head = {}
    for entry in snapshot["refs"]:
        commit = entry["sha"]
        if commit not in by_head:
            included = [candidate for candidate in heads if ancestor(commit, candidate)]
            proof = equivalents.get(commit)
            record = {"covered_by_ancestry": included}
            if included:
                record["disposition"] = "ancestor"
            elif proof:
                record.update(disposition="historical_equivalent", equivalent_commit=proof["equivalent_commit"])
            else:
                record["disposition"] = "unaccounted"
            if head:
                record["included_in_integrated_head"] = ancestor(commit, head) or bool(proof and ancestor(proof["equivalent_commit"], head))
            by_head[commit] = record
        rows.append({**entry, **by_head[commit]})
    counts = Counter(row["disposition"] for row in rows)
    result = {
        "schema": 1,
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "snapshot_sha256": sha256(snapshot_bytes),
        "script_sha256": sha256(Path(__file__).read_bytes()),
        "scope": "Git ancestry and immutable historical source equivalence; not runtime qualification or a claim that merge resolutions preserve identical full trees.",
        "network_calls": 0,
        "github_actions_or_status_calls": 0,
        "counts": snapshot["counts"],
        "total_refs": len(rows),
        "distinct_heads": len(by_head),
        "classification": dict(counts),
        "coverage_heads": snapshot["coverage_heads"],
        "historical_equivalence_checks": proofs,
        "all_historical_equivalences_verified": len(proofs) == 14 and all(p["verified"] for p in proofs),
        "all_captured_refs_accounted_for": counts["unaccounted"] == 0,
        "refs": rows,
    }
    if head:
        result["integrated_head"] = head
        result["integrated_tree"] = text("rev-parse", head + "^{tree}")
        result["all_captured_refs_in_integrated_head"] = all(row["included_in_integrated_head"] for row in rows)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", action="store_true", help="Replace the snapshot using current fetched local refs.")
    parser.add_argument("--snapshot", type=Path, default=HERE / "captured-refs.json")
    parser.add_argument("--output", type=Path, default=HERE / "verification.json")
    parser.add_argument("--head", help="Optional completed local integration commit to verify.")
    args = parser.parse_args()
    if args.capture:
        save(args.snapshot, capture())
    snapshot_bytes = args.snapshot.read_bytes()
    result = verify(json.loads(snapshot_bytes), snapshot_bytes, args.head)
    save(args.output, result)
    passed = result["all_captured_refs_accounted_for"] and result["all_historical_equivalences_verified"] and result.get("all_captured_refs_in_integrated_head", True)
    print(json.dumps({k: result[k] for k in ("total_refs", "distinct_heads", "counts", "classification", "all_historical_equivalences_verified", "all_captured_refs_accounted_for")}))
    if args.head:
        print(json.dumps({"integrated_head": result["integrated_head"], "all_captured_refs_in_integrated_head": result["all_captured_refs_in_integrated_head"]}))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
