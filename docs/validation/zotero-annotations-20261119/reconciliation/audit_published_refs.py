#!/usr/bin/env python3
"""Fresh published-head ancestry and explicit landed-patch equivalence audit.

The previous audit supplies candidate equivalence identities only; none of its
boolean results are reused. Historical refs remain historical equivalents and
are not falsely promoted to ancestors. This script performs no network I/O,
index/worktree mutations, ref writes, or CI queries.
"""

import argparse
import collections
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--snapshot", type=Path, required=True)
    parser.add_argument("--prior-audit", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--local-equivalent", help="Optional retained local merge for extra tree/history comparison")
    args = parser.parse_args()
    repo = args.repo.resolve()

    def run(*git_args, acceptable=(0,)):
        result = subprocess.run(
            ["git", "--no-replace-objects", *git_args], cwd=repo,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode not in acceptable:
            raise RuntimeError(
                f"Git {git_args!r} exited {result.returncode}: {result.stderr}"
            )
        return result

    def git(*git_args):
        return run(*git_args).stdout.strip()

    def ancestor(commit, head):
        return run("merge-base", "--is-ancestor", commit, head,
                   acceptable=(0, 1)).returncode == 0

    def tree_entry(commit, path):
        # NUL output preserves paths exactly; these candidates are repository
        # text paths but do not need shell quoting or pathname inference.
        output = run("ls-tree", "-z", commit, "--", path).stdout
        rows = [entry for entry in output.split("\0") if entry]
        if not rows:
            return None
        if len(rows) != 1:
            raise RuntimeError(f"Ambiguous tree entry: {commit}:{path}")
        metadata, actual_path = rows[0].split("\t", 1)
        if actual_path != path:
            raise RuntimeError(f"Unexpected tree path: {actual_path!r}")
        mode, kind, object_id = metadata.split(" ")
        return {"mode": mode, "type": kind, "object": object_id}

    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    head = git("rev-parse", "--verify", args.head + "^{commit}")
    snapshot_bytes = args.snapshot.read_bytes()
    prior_bytes = args.prior_audit.read_bytes()
    snapshot = json.loads(snapshot_bytes)
    prior = json.loads(prior_bytes)
    refs = snapshot["refs"]
    if len({row["ref"] for row in refs}) != len(refs):
        raise RuntimeError("Snapshot contains duplicate ref names")
    observed_counts = dict(collections.Counter(
        row["ref"].split("/")[2] for row in refs
    ))
    if observed_counts != snapshot["counts"]:
        raise RuntimeError("Snapshot counts do not match its ref rows")
    unique_heads = sorted({row["sha"] for row in refs})
    reachable = set(git("rev-list", head).splitlines())
    ancestry = {commit: commit in reachable for commit in unique_heads}
    local_comparison = None
    if args.local_equivalent is not None:
        local = git("rev-parse", "--verify", args.local_equivalent + "^{commit}")
        local_tree = git("rev-parse", local + "^{tree}")
        head_tree = git("rev-parse", head + "^{tree}")
        local_only = git("rev-list", local, "--not", head).splitlines()
        local_only_non_merges = git("rev-list", "--no-merges", local,
                                   "--not", head).splitlines()
        local_comparison = {
            "local_head": local, "local_tree": local_tree,
            "published_head": head, "published_tree": head_tree,
            "same_tree": local_tree == head_tree,
            "local_only_commits": local_only,
            "local_only_non_merge_commits": local_only_non_merges,
            "verified": local_tree == head_tree and not local_only_non_merges,
        }
    # Candidate identities discovered from commit subjects are accepted only
    # after exact stable patch-ID comparison and landed-commit ancestry checks.
    landed_patches = {
        "128a187d69555db80890c2a1945a442b951f9c74": "d790bca444eef0e160a75ce3d8cb555af541004f",
        "58fdddfbcf198a8c0e38e32f6fcc9d6604e95283": "4eaca83b192897edad82658107dfeb5bcbed0920",
        "69d14f84cabd3931b7640c1654b401c89faba766": "52c73ae4dbadf2ca00a5d619144350ccc353b31a",
        "b8ddaaeb581e010467de304c828764d353149102": "d6010059644b34accd6f188e0e2a4863ab63e318",
        "a7f144cc983f2df7c16d88f8644ad67a9254c3d0": "0ff7d23929e4640af6c1d57f87c7ac71b73d2ed4",
        "74ce9ffb816c70c0d2ae50b91ec52a614f26d688": "4584d5f319aab198f1d705f48b4d6647e6cbabea",
        "0a53b8a70128870f3e1df6d18cdb177bb64290ee": "b3f41eb4b4bca8ca13676b4114891ea6d9185043",
        "68a0db23408e4c95d6d283219504c79aea33a6fe": "d754bf15b07a24c8a86c8dce339ca749fecd9531",
        "005c708e9f747cb46cf02e12c869b0a2f85ac824": "c84d5e16024c502f6c451fd04b9807b1e65f20d3",
        "7ef09f2408f467c65427700e65907531ecb26acb": "34dc6b6806869570e9ec342e4d7ee0d6951c0ba6",
    }
    patch_ids = {}

    def patch_id(commit):
        if commit not in patch_ids:
            patch = run("show", "--pretty=format:", "--binary", "--no-ext-diff",
                        "--no-textconv", commit).stdout
            result = subprocess.run(
                ["git", "--no-replace-objects", "patch-id", "--stable"],
                cwd=repo, input=patch, text=True, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, check=True,
            )
            rows = result.stdout.splitlines()
            if len(rows) != 1:
                raise RuntimeError(f"Expected one nonempty patch: {commit}")
            patch_ids[commit] = rows[0].split()[0]
        return patch_ids[commit]

    checks = []
    for candidate in prior["historical_equivalence_checks"]:
        commit = candidate["sha"]
        method = candidate["method"]
        check = {"sha": commit, "method": method,
                 "is_actual_ancestor": ancestry.get(commit,
                     ancestor(commit, head))}
        if method == "all_non_ancestor_commits_patch_equivalent":
            remaining = git("rev-list", commit, "--not", head).splitlines()
            merges = git("rev-list", "--min-parents=2", commit,
                         "--not", head).splitlines()
            pairs = []
            for source_commit in remaining:
                equivalent = landed_patches.get(source_commit)
                if equivalent is None:
                    raise RuntimeError(f"No candidate landed patch: {source_commit}")
                source_patch = patch_id(source_commit)
                equivalent_patch = patch_id(equivalent)
                pairs.append({
                    "source_commit": source_commit,
                    "equivalent_commit": equivalent,
                    "source_patch_id": source_patch,
                    "equivalent_patch_id": equivalent_patch,
                    "equivalent_ancestor": equivalent in reachable,
                    "equal": source_patch == equivalent_patch,
                })
            check.update({
                "verification": "Explicit stable patch IDs for every non-ancestor commit; each matching landed commit is an ancestor of the published head.",
                "non_ancestor_commits": remaining,
                "non_ancestor_merges": merges,
                "patch_pairs": pairs,
                "verified": bool(pairs) and not merges and all(
                    pair["equal"] and pair["equivalent_ancestor"] for pair in pairs
                ),
            })
        elif method == "identical_tree_already_integrated":
            equivalent = candidate["equivalent_commit"]
            tree = git("rev-parse", commit + "^{tree}")
            equivalent_tree = git("rev-parse", equivalent + "^{tree}")
            included = ancestor(equivalent, head)
            check.update({
                "tree": tree, "equivalent_commit": equivalent,
                "equivalent_tree": equivalent_tree,
                "equivalent_ancestor": included,
                "verified": tree == equivalent_tree and included,
            })
        elif method == "all_changed_files_identical_in_landed_equivalent":
            base = candidate["comparison_base"]
            equivalent = candidate["equivalent_commit"]
            paths = [p for p in run("diff", "--name-only", "-z",
                                   base, commit).stdout.split("\0") if p]
            files = []
            for path in paths:
                source = tree_entry(commit, path)
                landed = tree_entry(equivalent, path)
                files.append({"path": path, "source_entry": source,
                              "equivalent_entry": landed,
                              "equal": source == landed})
            included = ancestor(equivalent, head)
            check.update({
                "comparison_base": base, "equivalent_commit": equivalent,
                "equivalent_ancestor": included,
                "changed_file_count": len(files), "files": files,
                "verified": bool(files) and included and
                    all(row["equal"] for row in files),
            })
        else:
            raise RuntimeError(f"Unrecognized equivalence method: {method}")
        checks.append(check)

    verified = {row["sha"] for row in checks if row["verified"]}
    classified = [
        {**row, "disposition": "ancestor" if ancestry[row["sha"]] else
         "historical_equivalent" if row["sha"] in verified else "unaccounted"}
        for row in refs
    ]
    counts = dict(collections.Counter(row["disposition"] for row in classified))
    report = {
        "started_at_utc": started,
        "completed_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "checked_head": head, "checked_tree": git("rev-parse", head + "^{tree}"),
        "git_version": git("--version"), "python_version": sys.version,
        "local_integration_equivalence": local_comparison,
        "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "snapshot_captured_at_utc": snapshot["captured_at_utc"],
        "snapshot_sha256": hashlib.sha256(snapshot_bytes).hexdigest(),
        "prior_candidate_audit_sha256": hashlib.sha256(prior_bytes).hexdigest(),
        "scope": "Frozen local commit; full captured ref ancestry; fresh historical proof computations. No network, CI, index, worktree, or ref mutations.",
        "snapshot_counts": snapshot["counts"], "total_refs": len(refs),
        "unique_heads": len(unique_heads), "classification": counts,
        "historical_equivalence_checks": checks, "refs": classified,
        "all_historical_equivalences_verified": len(checks) == 14 and
            all(row["verified"] for row in checks),
        "all_captured_refs_accounted_for": counts.get("unaccounted", 0) == 0,
        "historical_refs_remain_non_ancestors": all(
            not ancestry[row["sha"]] for row in classified
            if row["disposition"] == "historical_equivalent"
        ),
    }
    passed = (report["all_historical_equivalences_verified"] and
              report["all_captured_refs_accounted_for"] and
              report["historical_refs_remain_non_ancestors"] and
              (local_comparison is None or local_comparison["verified"]))
    report["passed"] = passed
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({
        key: report[key] for key in (
            "checked_head", "checked_tree", "total_refs", "unique_heads",
            "classification", "all_historical_equivalences_verified",
            "all_captured_refs_accounted_for", "historical_refs_remain_non_ancestors",
            "passed",
        )
    }, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
