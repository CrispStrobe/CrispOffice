#!/usr/bin/env python3
"""Recheck the bounded ref snapshot using local Git objects only.

Historical names are not merged merely to create ancestry. Rebased/squashed
work is checked by stable patch identity, identical trees, or every changed
file's Git blob at its landed equivalent. No network or CI APIs are used.
"""

import argparse
import collections
import datetime
import hashlib
import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
PATCH_HEADS = (
    "128a187d69555db80890c2a1945a442b951f9c74",
    "58fdddfbcf198a8c0e38e32f6fcc9d6604e95283",
    "69d14f84cabd3931b7640c1654b401c89faba766",
    "b8ddaaeb581e010467de304c828764d353149102",
    "a7f144cc983f2df7c16d88f8644ad67a9254c3d0",
    "74ce9ffb816c70c0d2ae50b91ec52a614f26d688",
    "0a53b8a70128870f3e1df6d18cdb177bb64290ee",
    "68a0db23408e4c95d6d283219504c79aea33a6fe",
    "005c708e9f747cb46cf02e12c869b0a2f85ac824",
    "7ef09f2408f467c65427700e65907531ecb26acb",
)
TREE_PAIRS = (
    (
        "cee6e2632f891a3fe21c5c02d6bf508805973051",
        "bb5556e8cc4cb73e2c668b5319a2844a20c6c50c",
    ),
    (
        "3abf8f43b0e79c10271bbd046f391e462b8fe6b9",
        "4b2b4e78839d2997a583b7ab1346e2fa537a8ac4",
    ),
    (
        "da9c956ec5d65c0e5a9f9ea84c2b0bca98e824a0",
        "23f3b4204fce45d38a103e3159bdc7f1e8d37c4e",
    ),
)
FILE_HEAD = "c34945761e7991f5fe49037d79529acdd260b31c"
FILE_EQUIVALENT = "2c47165d01d01cc883135a434ac9f6591ce6e770"
FILE_BASE = "e3a38789359adaa33b2da1345c952fa1c2d8aebb"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def ancestor(commit, head):
    result = subprocess.run(
        ["git", "merge-base", "--is-ancestor", commit, head], cwd=ROOT
    )
    if result.returncode not in (0, 1):
        raise RuntimeError(f"Cannot check ancestry for {commit}: {result.returncode}")
    return result.returncode == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--snapshot", type=Path, default=HERE / "captured-refs.json")
    parser.add_argument("--output", type=Path, default=HERE / "audit.json")
    args = parser.parse_args()
    head = git("rev-parse", "--verify", args.head + "^{commit}")
    snapshot_bytes = args.snapshot.read_bytes()
    snapshot = json.loads(snapshot_bytes)
    checks = []
    for commit in PATCH_HEADS:
        lines = git("cherry", head, commit).splitlines()
        checks.append({
            "sha": commit,
            "method": "all_non_ancestor_commits_patch_equivalent",
            "git_cherry": lines,
            "verified": ancestor(commit, head) or (
                bool(lines) and all(line.startswith("- ") for line in lines)
            ),
        })
    for commit, equivalent in TREE_PAIRS:
        tree = git("rev-parse", commit + "^{tree}")
        equivalent_tree = git("rev-parse", equivalent + "^{tree}")
        included = ancestor(equivalent, head)
        checks.append({
            "sha": commit,
            "method": "identical_tree_already_integrated",
            "tree": tree,
            "equivalent_commit": equivalent,
            "equivalent_tree": equivalent_tree,
            "equivalent_ancestor": included,
            "verified": tree == equivalent_tree and included,
        })
    paths = git("diff", "--name-only", FILE_BASE, FILE_HEAD).splitlines()
    files = []
    for path in paths:
        source_blob = git("rev-parse", FILE_HEAD + ":" + path)
        equivalent_blob = git("rev-parse", FILE_EQUIVALENT + ":" + path)
        files.append({
            "path": path,
            "source_blob": source_blob,
            "equivalent_blob": equivalent_blob,
            "equal": source_blob == equivalent_blob,
        })
    file_included = ancestor(FILE_EQUIVALENT, head)
    checks.append({
        "sha": FILE_HEAD,
        "method": "all_changed_files_identical_in_landed_equivalent",
        "comparison_base": FILE_BASE,
        "equivalent_commit": FILE_EQUIVALENT,
        "equivalent_ancestor": file_included,
        "changed_file_count": len(files),
        "files": files,
        "verified": bool(files) and file_included and all(f["equal"] for f in files),
    })
    verified = {c["sha"] for c in checks if c["verified"]}
    refs = []
    for row in snapshot["refs"]:
        is_ancestor = ancestor(row["sha"], head)
        disposition = (
            "ancestor" if is_ancestor else
            "historical_equivalent" if row["sha"] in verified else "unaccounted"
        )
        refs.append({**row, "disposition": disposition})
    counts = dict(collections.Counter(r["disposition"] for r in refs))
    report = {
        "checked_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "checked_head": head,
        "checked_tree": git("rev-parse", head + "^{tree}"),
        "snapshot_captured_at_utc": snapshot["captured_at_utc"],
        "snapshot_sha256": hashlib.sha256(snapshot_bytes).hexdigest(),
        "scope": snapshot["scope"],
        "snapshot_counts": snapshot["counts"],
        "total_refs": len(refs),
        "unique_heads": len({r["sha"] for r in refs}),
        "classification": counts,
        "historical_equivalence_checks": checks,
        "refs": refs,
        "all_captured_refs_accounted_for": counts.get("unaccounted", 0) == 0,
    }
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({
        "head": head, "counts": counts,
        "historical_checks_passed": sum(c["verified"] for c in checks),
        "historical_checks_total": len(checks),
        "unaccounted": [r for r in refs if r["disposition"] == "unaccounted"],
    }, indent=2))
    return 0 if report["all_captured_refs_accounted_for"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
