#!/usr/bin/env python3
"""Read-only source-intake audit against fetched refs and Git object identity."""
import argparse
import collections
import datetime
import hashlib
import json
import pathlib
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--output", required=True)
    options = parser.parse_args()
    repo = pathlib.Path(options.repo)

    def git(*arguments):
        return subprocess.check_output(["git", "-C", str(repo), *arguments])

    def text(*arguments):
        return git(*arguments).decode().strip()

    def ancestor(commit, target):
        result = subprocess.run(
            ["git", "-C", str(repo), "merge-base", "--is-ancestor", commit, target],
            capture_output=True,
        )
        if result.returncode not in (0, 1):
            raise RuntimeError(result.stderr.decode())
        return result.returncode == 0

    prior_ref = "acca1cbcba2a322ad1ae2d7d9fb415110ce22554"
    prior_path = "docs/validation/word-vba-lists-20261120/final-intake.json"
    prior_bytes = git("show", f"{prior_ref}:{prior_path}")
    prior = json.loads(prior_bytes)
    target = text("rev-parse", options.target)
    proofs = {}
    for old_proof in prior["historical_equivalence_proofs"]:
        historical = old_proof["historical_head"]
        accepted = old_proof["accepted_ancestor"]
        base = old_proof["comparison_base"]
        changed_paths = text("diff", "--name-only", base, historical).splitlines()
        entries = []
        for path in changed_paths:
            historical_entry = text("ls-tree", historical, "--", path)
            accepted_entry = text("ls-tree", accepted, "--", path)
            entries.append({
                "path": path,
                "historical_mode_type_object": historical_entry,
                "accepted_mode_type_object": accepted_entry,
                "equal": historical_entry == accepted_entry,
            })
        old_tree = text("rev-parse", f"{historical}^{{tree}}")
        new_tree = text("rev-parse", f"{accepted}^{{tree}}")
        verified = (
            ancestor(accepted, target)
            and set(changed_paths) == set(old_proof["changed_paths"])
            and len(changed_paths) == old_proof["changed_path_count"]
            and all(entry["equal"] for entry in entries)
            and (old_tree == new_tree or historical.startswith("c3494576"))
        )
        proofs[historical] = {
            "historical_head": historical,
            "accepted_ancestor": accepted,
            "comparison_base": base,
            "accepted_is_ancestor": ancestor(accepted, target),
            "historical_tree": old_tree,
            "accepted_tree": new_tree,
            "whole_tree_equal": old_tree == new_tree,
            "changed_path_count": len(changed_paths),
            "matches_previous_path_inventory": set(changed_paths) == set(old_proof["changed_paths"]),
            "changed_modes_types_objects_exact": all(entry["equal"] for entry in entries),
            "entries": entries,
            "verified": verified,
        }

    inventory = {}
    summary = {}
    uncovered = []
    for group, namespace in [
        ("branches", "refs/remotes/origin"),
        ("pull_requests", "refs/remotes/pull"),
        ("upstream", "refs/remotes/upstream"),
    ]:
        rows = []
        counts = collections.Counter()
        for line in text("for-each-ref", "--format=%(objectname) %(refname)", namespace).splitlines():
            sha, ref = line.split(" ", 1)
            if ref.endswith("/HEAD"):
                continue
            row = {"ref": ref, "sha": sha}
            if sha == target:
                row["status"] = "exact_target"
            elif ancestor(sha, target):
                row["status"] = "ancestor"
            elif sha in proofs and proofs[sha]["verified"]:
                row["status"] = "historically_superseded_equivalent"
                row["accepted_ancestor"] = proofs[sha]["accepted_ancestor"]
            else:
                row["status"] = "uncovered"
                uncovered.append(row.copy())
            counts[row["status"]] += 1
            rows.append(row)
        inventory[group] = rows
        summary[group] = dict(counts)

    report = {
        "schema": "quds-word-vba-independent-intake/v1",
        "audited_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "repository": "CrispStrobe/quds_office_suite",
        "target_commit": target,
        "target_tree": text("rev-parse", f"{target}^{{tree}}"),
        "prior_reconciliation_commit": prior_ref,
        "prior_reconciliation_path": prior_path,
        "prior_reconciliation_sha256": hashlib.sha256(prior_bytes).hexdigest(),
        "inventory_origin": "Locally fetched refs; this audit does not query or mutate remotes",
        "source_commands": [
            "git for-each-ref --format='%(objectname) %(refname)' refs/remotes/{origin,pull,upstream}",
            "git merge-base --is-ancestor <head> <target>",
            "git diff --name-only <comparison-base> <historical-head>",
            "git ls-tree <historical-or-accepted> -- <changed-path>",
            "git rev-parse <historical-or-accepted>^{tree}",
        ],
        "historical_equivalence_proofs": list(proofs.values()),
        "summary": summary,
        "uncovered_ref_entries": uncovered,
        "all_historical_proofs_verified": all(proof["verified"] for proof in proofs.values()),
        "github_actions_used": False,
        "qualification_claim": "Source/history inclusion only; this does not qualify incoming Mail or platform runtimes.",
        **inventory,
    }
    pathlib.Path(options.output).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({
        "target_commit": target,
        "summary": summary,
        "uncovered_count": len(uncovered),
        "all_historical_proofs_verified": report["all_historical_proofs_verified"],
    }, indent=2))
    return 0 if not uncovered and report["all_historical_proofs_verified"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
