#!/usr/bin/env python3
"""Recompute retention of the two captured branch/latest-100-PR inventories.

Usage:
  python audit_captured_work.py --repo /path/to/clone --candidate <exact-sha> \
      --output /path/to/report.json

The adjacent inventory and historical-mappings files are portable inputs.
Only immutable Git objects are read. Missing objects are reported; this script
never fetches, changes refs, stages files, or changes the working tree.
"""
import argparse
import collections
import datetime
import functools
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


HERE = Path(__file__).resolve().parent
SNAPSHOTS = ("initial-remote-inventory.json", "remote-intake-02.json")


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.candidate):
        parser.error("candidate must be an exact 40-character commit SHA")
    repo = args.repo.resolve()
    candidate = args.candidate
    environment = {**os.environ, "GIT_NO_LAZY_FETCH": "1", "GIT_OPTIONAL_LOCKS": "0"}

    def git(*argv, check=True):
        result = subprocess.run(
            ["git", "-C", str(repo), *argv],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        )
        if check and result.returncode:
            raise RuntimeError(f"git {argv!r}: {result.stderr.decode(errors='replace')}")
        return result

    def text(*argv):
        return git(*argv).stdout.decode().strip()

    @functools.lru_cache(maxsize=None)
    def available(commit):
        if not re.fullmatch(r"[0-9a-f]{40}", commit):
            raise ValueError(f"Invalid captured commit SHA: {commit!r}")
        return git("cat-file", "-e", commit + "^{commit}", check=False).returncode == 0

    @functools.lru_cache(maxsize=None)
    def ancestor(older, newer):
        result = git("merge-base", "--is-ancestor", older, newer, check=False)
        if result.returncode not in (0, 1):
            raise RuntimeError(result.stderr.decode(errors="replace"))
        return result.returncode == 0

    @functools.lru_cache(maxsize=None)
    def tree_id(commit):
        return text("rev-parse", commit + "^{tree}")

    @functools.lru_cache(maxsize=None)
    def tree_entries(commit):
        # Include directory entries so a file-to-directory change cannot be
        # mistaken for an absent/deleted path. NUL framing preserves path names.
        result = {}
        for record in git("ls-tree", "-r", "-t", "-z", commit).stdout.split(b"\0"):
            if not record:
                continue
            metadata, path = record.split(b"\t", 1)
            mode, kind, oid = metadata.decode().split()
            result[path.decode(errors="surrogateescape")] = {
                "mode": mode, "type": kind, "oid": oid,
            }
        return result

    def delta_paths(base, head):
        return sorted(
            part.decode(errors="surrogateescape")
            for part in git(
                "diff", "--no-renames", "--no-ext-diff", "--no-textconv",
                "--name-only", "-z", base, head,
            ).stdout.split(b"\0") if part
        )

    if not available(candidate):
        raise RuntimeError(f"Audited candidate commit is not available: {candidate}")

    snapshot_inputs = {}
    snapshots = {}
    captures = collections.defaultdict(list)
    for name in SNAPSHOTS:
        raw = (HERE / name).read_bytes()
        snapshot_inputs[name] = sha256(raw)
        snapshot = snapshots[name] = json.loads(raw)
        if snapshot["repository"] != "CrispStrobe/quds_office_suite":
            raise ValueError("Unexpected captured repository")
        if len(snapshot["recent_prs"]) != snapshot["recent_pr_count"]:
            raise ValueError("PR inventory count does not match its rows")
        for row in snapshot["branches"]:
            captures[row["sha"]].append({
                "snapshot": name, "kind": "branch", "name": row["name"],
            })
        for row in snapshot["recent_prs"]:
            captures[row["head"]].append({
                "snapshot": name, "kind": "pull_request", "number": row["number"],
                "headBranch": row["head_branch"], "stateAtCapture": row["state"],
                "draftAtCapture": row["draft"],
                "headRepository": row["head_repository"],
            })

    raw_mappings = (HERE / "historical-mappings.json").read_bytes()
    mappings = {
        row["original"]: row for row in json.loads(raw_mappings)["mappings"]
    }
    proofs = []
    head_results = {}
    for head, occurrences in sorted(captures.items()):
        row = {"head": head, "captures": occurrences, "preserved": False}
        head_results[head] = row
        if not available(head):
            row["disposition"] = "missing_captured_commit_object"
            continue
        row["tree"] = tree_id(head)
        row["ancestorOfCandidate"] = ancestor(head, candidate)
        if row["ancestorOfCandidate"]:
            row.update(disposition="included_by_ancestry", preserved=True)
            continue
        mapping = mappings.get(head)
        if mapping is None:
            bases = text("merge-base", "--all", head, candidate).splitlines()
            row.update(
                disposition="nonancestor_without_verified_equivalence",
                candidateMergeBases=bases,
                completeDeltaPaths=(delta_paths(bases[0], head) if len(bases) == 1 else None),
            )
            continue
        equivalent = mapping["equivalent"]
        row["equivalentCommit"] = equivalent
        if not available(equivalent):
            row["disposition"] = "missing_equivalent_commit_object"
            continue
        bases = text("merge-base", "--all", head, equivalent).splitlines()
        if len(bases) != 1:
            row.update(disposition="ambiguous_equivalence_merge_base", mergeBases=bases)
            continue
        base = bases[0]
        paths = delta_paths(base, head)
        original_entries = tree_entries(head)
        equivalent_entries = tree_entries(equivalent)
        comparisons = [
            {
                "path": path,
                "original": original_entries.get(path),
                "equivalent": equivalent_entries.get(path),
                "equal": original_entries.get(path) == equivalent_entries.get(path),
            }
            for path in paths
        ]
        mismatches = [p["path"] for p in comparisons if not p["equal"]]
        equivalent_retained = ancestor(equivalent, candidate)
        whole_tree_equal = tree_id(head) == tree_id(equivalent)
        base_matches = base == mapping["expectedCommonBase"]
        count_matches = len(paths) == mapping["expectedCompleteOriginalDeltaPathCount"]
        passed = equivalent_retained and not mismatches and base_matches and count_matches
        proof = {
            "original": head, "equivalent": equivalent,
            "commonBase": base, "commonBaseMatchesPriorMapping": base_matches,
            "completeOriginalDeltaPathCount": len(paths),
            "pathCountMatchesPriorMapping": count_matches,
            "originalTree": tree_id(head), "equivalentTree": tree_id(equivalent),
            "wholeTreeEqual": whole_tree_equal,
            "method": ("exact_complete_tree_identity" if whole_tree_equal else
                       "exact_complete_delta_path_mode_type_object_identity"),
            "equivalentAncestorOfCandidate": equivalent_retained,
            "pathComparisons": comparisons, "mismatches": mismatches,
            "mappingProvenance": mapping["provenance"], "passed": passed,
        }
        proofs.append(proof)
        row.update(
            disposition=("included_by_recomputed_historical_equivalence" if passed else
                         "historical_equivalence_failed"),
            preserved=passed,
        )

    snapshot_results = []
    for name, snapshot in snapshots.items():
        branches = [
            {**row, "disposition": head_results[row["sha"]]["disposition"],
             "preserved": head_results[row["sha"]]["preserved"]}
            for row in snapshot["branches"]
        ]
        pull_requests = [
            {**row, "disposition": head_results[row["head"]]["disposition"],
             "preserved": head_results[row["head"]]["preserved"]}
            for row in snapshot["recent_prs"]
        ]
        snapshot_results.append({
            "file": name, "sha256": snapshot_inputs[name],
            "branchCount": len(branches), "pullRequestCount": len(pull_requests),
            "branchDispositions": dict(collections.Counter(r["disposition"] for r in branches)),
            "pullRequestDispositions": dict(collections.Counter(r["disposition"] for r in pull_requests)),
            "allCapturedWorkPreserved": all(r["preserved"] for r in branches + pull_requests),
            "branches": branches, "pullRequests": pull_requests,
        })

    unresolved = [row for row in head_results.values() if not row["preserved"]]
    missing = [row for row in unresolved if row["disposition"].startswith("missing_")]
    initial, latest = [snapshots[name] for name in SNAPSHOTS]
    initial_branches = {r["name"]: r["sha"] for r in initial["branches"]}
    latest_branches = {r["name"]: r["sha"] for r in latest["branches"]}
    initial_prs = {r["number"]: r["head"] for r in initial["recent_prs"]}
    latest_prs = {r["number"]: r["head"] for r in latest["recent_prs"]}
    report = {
        "schema": "quds.mail.attachments.captured-reconciliation.v1",
        "recordedAtUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "repository": "CrispStrobe/quds_office_suite",
        "candidate": candidate, "candidateTree": tree_id(candidate),
        "auditorSha256": sha256(Path(__file__).read_bytes()),
        "historicalMappingsSha256": sha256(raw_mappings),
        "snapshotSha256": snapshot_inputs,
        "summary": {
            "capturedSnapshotCount": len(snapshots),
            "branchCaptureRows": sum(len(d["branches"]) for d in snapshots.values()),
            "pullRequestCaptureRows": sum(len(d["recent_prs"]) for d in snapshots.values()),
            "distinctPullRequestNumbers": len(set(initial_prs) | set(latest_prs)),
            "distinctCapturedHeads": len(head_results),
            "headDispositions": dict(collections.Counter(r["disposition"] for r in head_results.values())),
            "historicalProofsRecomputed": len(proofs),
            "historicalDeltaPathComparisons": sum(p["completeOriginalDeltaPathCount"] for p in proofs),
            "historicalWholeTreeIdentities": sum(p["wholeTreeEqual"] for p in proofs),
            "missingCommitObjectCount": len(missing),
            "unresolvedCapturedHeadCount": len(unresolved),
            "allCapturedWorkPreserved": not unresolved,
        },
        "captureChanges": {
            "branchHeadChanges": [
                {"name": name, "initial": initial_branches[name], "later": latest_branches[name]}
                for name in sorted(initial_branches.keys() & latest_branches.keys())
                if initial_branches[name] != latest_branches[name]
            ],
            "branchesOnlyInInitialSnapshot": sorted(initial_branches.keys() - latest_branches.keys()),
            "branchesOnlyInLaterSnapshot": sorted(latest_branches.keys() - initial_branches.keys()),
            "pullRequestHeadChanges": [
                {"number": number, "initial": initial_prs[number], "later": latest_prs[number]}
                for number in sorted(initial_prs.keys() & latest_prs.keys())
                if initial_prs[number] != latest_prs[number]
            ],
            "pullRequestsOnlyInInitialSample": sorted(initial_prs.keys() - latest_prs.keys()),
            "pullRequestsOnlyInLaterSample": sorted(latest_prs.keys() - initial_prs.keys()),
        },
        "snapshots": snapshot_results,
        "heads": list(head_results.values()),
        "historicalEquivalenceProofs": proofs,
        "missingCommitObjects": missing,
        "unresolvedCapturedHeads": unresolved,
        "incomingFindings": {
            "genuinelyMissingWorkIdentified": False if not unresolved else None,
            "note": ("Every captured head is retained by ancestry or a freshly recomputed complete identity proof."
                     if not unresolved else
                     "Unresolved heads need review; nonancestry alone is not proof of unique missing work."),
        },
        "methodNotes": [
            "Scope is exactly the two adjacent saved inventories; no new head discovery is performed.",
            "Every branch row and every latest-100-PR head row is audited at its exact captured SHA.",
            "Historical ledgers supply only original/equivalent mappings and expected scope; all Git ancestry and identities are freshly computed.",
            "The complete original delta is every path changed from the unique original/equivalent merge base to the original head, with rename detection disabled.",
            "Identity includes full file mode, object type, object ID, and absence for deletions; full tree identity is also checked.",
            "An equivalent commit must be retained by ancestry; later intended edits need not retain historical bytes.",
            "Retention in Git history is distinct from behavioral qualification of the final product source.",
            "Only local read-only Git commands are used, with lazy fetching and optional locks disabled; no refs, index, source, CI/status endpoints, or remote state are changed.",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"candidate": candidate, **report["summary"]}, indent=2))
    return 0 if not unresolved else 1


if __name__ == "__main__":
    raise SystemExit(main())
