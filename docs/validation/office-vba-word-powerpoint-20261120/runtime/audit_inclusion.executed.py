#!/usr/bin/env python3
"""Audit a captured Git snapshot using local objects only; never fetch or write Git."""

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess


HISTORICAL = {
    "c34945761e7991f5fe49037d79529acdd260b31c": "2c47165d01d01cc883135a434ac9f6591ce6e770",
    "3abf8f43b0e79c10271bbd046f391e462b8fe6b9": "4b2b4e78839d2997a583b7ab1346e2fa537a8ac4",
    "58fdddfbcf198a8c0e38e32f6fcc9d6604e95283": "4eaca83b192897edad82658107dfeb5bcbed0920",
    "69d14f84cabd3931b7640c1654b401c89faba766": "52c73ae4dbadf2ca00a5d619144350ccc353b31a",
    "74ce9ffb816c70c0d2ae50b91ec52a614f26d688": "4584d5f319aab198f1d705f48b4d6647e6cbabea",
    "0a53b8a70128870f3e1df6d18cdb177bb64290ee": "b3f41eb4b4bca8ca13676b4114891ea6d9185043",
    "68a0db23408e4c95d6d283219504c79aea33a6fe": "d754bf15b07a24c8a86c8dce339ca749fecd9531",
    "005c708e9f747cb46cf02e12c869b0a2f85ac824": "c84d5e16024c502f6c451fd04b9807b1e65f20d3",
    "7ef09f2408f467c65427700e65907531ecb26acb": "34dc6b6806869570e9ec342e4d7ee0d6951c0ba6",
    "128a187d69555db80890c2a1945a442b951f9c74": "d790bca444eef0e160a75ce3d8cb555af541004f",
    "b8ddaaeb581e010467de304c828764d353149102": "d6010059644b34accd6f188e0e2a4863ab63e318",
    "a7f144cc983f2df7c16d88f8644ad67a9254c3d0": "0ff7d23929e4640af6c1d57f87c7ac71b73d2ed4",
    "cee6e2632f891a3fe21c5c02d6bf508805973051": "bb5556e8cc4cb73e2c668b5319a2844a20c6c50c",
    "da9c956ec5d65c0e5a9f9ea84c2b0bca98e824a0": "23f3b4204fce45d38a103e3159bdc7f1e8d37c4e",
}
EXPECTED_HISTORICAL_PRS = [134, 135, 136, 137, 138, 140, 141, 142, 145, 146, 147, 149, 151, 152]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--snapshot", type=Path, required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--checkpoint", action="append", default=[], metavar="LOCAL:REMOTE")
    args = parser.parse_args()
    env = dict(os.environ, GIT_NO_LAZY_FETCH="1", GIT_TERMINAL_PROMPT="0", GIT_OPTIONAL_LOCKS="0")

    def git(*command, raw=False):
        result = subprocess.check_output(["git", *command], cwd=args.repo, env=env)
        return result if raw else result.decode().strip()

    def ancestor(head, target):
        result = subprocess.run(
            ["git", "merge-base", "--is-ancestor", head, target],
            cwd=args.repo, env=env, capture_output=True,
        )
        if result.returncode not in (0, 1):
            raise RuntimeError(result.stderr.decode())
        return result.returncode == 0

    trees = {}

    def entries(commit):
        if commit not in trees:
            rows = git("ls-tree", "-r", "-z", commit, raw=True).split(b"\0")
            trees[commit] = {
                row.split(b"\t", 1)[1]: row.split(b"\t", 1)[0]
                for row in rows if row
            }
        return trees[commit]

    def changed_paths(before, after):
        return [path for path in git(
            "diff", "--no-renames", "--name-only", "-z", before, after, raw=True,
        ).split(b"\0") if path]

    target = git("rev-parse", args.target + "^{commit}")
    snapshot_bytes = args.snapshot.read_bytes()
    snapshot = json.loads(snapshot_bytes)
    captured_main = next(row["sha"] for row in snapshot["branches"] if row["branch"] == "main")
    failures = []
    proofs = {}
    for historical, accepted in HISTORICAL.items():
        bases = git("merge-base", "--all", historical, accepted).splitlines()
        if len(bases) != 1:
            raise RuntimeError(f"Ambiguous historical comparison base: {historical}")
        paths = changed_paths(bases[0], historical)
        old, landed = entries(historical), entries(accepted)
        mismatches = [p.decode("utf-8", "surrogateescape") for p in paths if old.get(p) != landed.get(p)]
        old_tree = git("rev-parse", historical + "^{tree}")
        accepted_tree = git("rev-parse", accepted + "^{tree}")
        accepted_ancestor = ancestor(accepted, target)
        original_ancestor = ancestor(historical, target)
        proof = {
            "historical_head": historical,
            "historical_is_ancestor": original_ancestor,
            "historical_committed_at": git("show", "-s", "--format=%cI", historical),
            "accepted_ancestor": accepted,
            "accepted_is_ancestor_of_target": accepted_ancestor,
            "accepted_is_ancestor_of_captured_main": ancestor(accepted, captured_main),
            "comparison_base": bases[0],
            "changed_path_count": len(paths),
            "all_changed_modes_types_objects_match": not mismatches,
            "changed_path_entry_sha256": hashlib.sha256(b"".join(
                p + b"\0" + old.get(p, b"<deleted>") + b"\n" for p in sorted(paths)
            )).hexdigest(),
            "whole_tree_equal": old_tree == accepted_tree,
            "historical_tree": old_tree,
            "accepted_tree": accepted_tree,
            "whole_tree_differing_path_count": len(changed_paths(historical, accepted)),
            "mismatched_changed_paths": mismatches,
        }
        proof["verified"] = accepted_ancestor and not mismatches
        proofs[historical] = proof
        if not proof["verified"]:
            failures.append({"kind": "historical_proof", "head": historical})

    def inclusion(head):
        if ancestor(head, target):
            return {"status": "ancestor", "is_ancestor": True}
        proof = proofs.get(head)
        if proof and proof["verified"]:
            return {
                "status": "historically_superseded_equivalent",
                "is_ancestor": False,
                "accepted_ancestor": proof["accepted_ancestor"],
                "changed_path_count": proof["changed_path_count"],
                "whole_tree_equal": proof["whole_tree_equal"],
            }
        return {"status": "uncovered", "is_ancestor": False}

    branches = [{**row, **inclusion(row["sha"])} for row in snapshot["branches"]]
    fetched = []
    for line in git("for-each-ref", "--format=%(refname) %(objectname)", "refs/remotes/pull").splitlines():
        name, head = line.split()
        number = int(name.rsplit("/", 1)[1])
        fetched.append({"number": number, "head": head, **inclusion(head)})
    fetched.sort(key=lambda row: row["number"])
    if [row["number"] for row in fetched] != list(range(1, 237)):
        failures.append({"kind": "unexpected_fetched_pr_inventory"})
    historical_numbers = [row["number"] for row in fetched if not row["is_ancestor"]]
    if historical_numbers != EXPECTED_HISTORICAL_PRS:
        failures.append({"kind": "unexpected_nonancestor_prs", "numbers": historical_numbers})
    fetched_by_number = {row["number"]: row for row in fetched}
    open_prs = []
    for row in snapshot["open_pull_requests"]:
        fetched_head = fetched_by_number[row["number"]]["head"]
        open_prs.append({
            **row, **inclusion(row["head"]),
            "fetched_ref_head": fetched_head,
            "fetched_ref_matches_captured_head": fetched_head == row["head"],
        })
    for kind, rows in [("branch", branches), ("fetched_pr", fetched), ("open_pr", open_prs)]:
        failures.extend({"kind": kind, **row} for row in rows if row["status"] == "uncovered")

    mappings = dict(snapshot["checkpoint_mappings"])
    for value in args.checkpoint:
        local, remote = value.split(":", 1)
        mappings[local] = remote
    checkpoints = []
    for local, remote in mappings.items():
        local_tree = git("rev-parse", local + "^{tree}")
        remote_tree = git("rev-parse", remote + "^{tree}")
        local_parents = git("show", "-s", "--format=%P", local).split()
        expected_parents = [mappings.get(parent, parent) for parent in local_parents]
        remote_parents = git("show", "-s", "--format=%P", remote).split()
        row = {
            "local": local, "published": remote, "tree": remote_tree,
            "trees_equal": local_tree == remote_tree,
            "mapped_parents": expected_parents,
            "published_parents_match": remote_parents == expected_parents,
            "published_is_ancestor": ancestor(remote, target),
        }
        checkpoints.append(row)
        if not all(row[key] for key in ("trees_equal", "published_parents_match", "published_is_ancestor")):
            failures.append({"kind": "checkpoint", **row})

    engine_path = "packages/quds_office_engine"
    frozen_engine = git("rev-parse", snapshot["source_commit"] + ":" + engine_path)
    target_engine = git("rev-parse", target + ":" + engine_path)
    summary = {
        "branches": dict(Counter(row["status"] for row in branches)),
        "fetched_prs": dict(Counter(row["status"] for row in fetched)),
        "open_prs": dict(Counter(row["status"] for row in open_prs)),
        "historical_full_tree_matches": sum(row["whole_tree_equal"] for row in proofs.values()),
        "historical_changed_path_matches": len(proofs),
        "published_checkpoints_verified": len(checkpoints),
        "uncovered_substantive_heads": [row for row in failures if row["kind"] in {"branch", "fetched_pr", "open_pr"}],
        "failure_count": len(failures),
    }
    receipt = {
        "schema": 1,
        "audited_at_utc": datetime.now(timezone.utc).isoformat(),
        "captured_at_utc": snapshot["captured_at_utc"],
        "snapshot_sha256": hashlib.sha256(snapshot_bytes).hexdigest(),
        "target_commit": target,
        "target_tree": git("rev-parse", target + "^{tree}"),
        "qualification_source_commit": snapshot["source_commit"],
        "qualification_engine_tree": frozen_engine,
        "target_engine_tree": target_engine,
        "engine_tree_unchanged": frozen_engine == target_engine,
        "read_only_git": True,
        "network_or_fetch_used": False,
        "github_actions_used": False,
        "method": "Actual inclusion uses merge-base --is-ancestor. Historical heads remain nonancestors: compare every changed path's mode, object type and object ID from its unique merge base against an accepted ancestor; record whole-tree identity separately. Published checkpoints require identical trees, correctly mapped parents and actual ancestry.",
        "summary": summary,
        "branches": branches,
        "open_pull_requests": open_prs,
        "fetched_pull_request_refs": fetched,
        "historical_equivalence_proofs": list(proofs.values()),
        "checkpoint_proofs": checkpoints,
        "failures": failures,
    }
    args.output.write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "target": target, **summary}))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
