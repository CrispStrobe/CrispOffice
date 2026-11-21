#!/usr/bin/env python3
"""Account for captured fork/upstream branches and PR heads using Git objects."""
import argparse
import datetime
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
CANDIDATES = (
    "57c5729ab1aa1ea8c1e27a4c76b233060b843e11:"
    "docs/validation/zotero-odt-roundtrip-20261121/intake-equivalence.json"
)


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def ancestor(sha, target):
    result = subprocess.run(
        ["git", "merge-base", "--is-ancestor", sha, target], cwd=ROOT
    )
    if result.returncode not in (0, 1):
        raise RuntimeError(f"Cannot check ancestry for {sha}")
    return result.returncode == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", type=Path)
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    head = git("rev-parse", args.head)
    if args.snapshot:
        refs = json.loads(args.snapshot.read_text())["refs"]
    else:
        refs = [
            dict(zip(("ref", "sha"), row.split()))
            for row in git(
                "for-each-ref", "--format=%(refname) %(objectname)", "refs/remotes"
            ).splitlines()
            if not row.startswith("refs/remotes/origin/HEAD ")
        ]
    candidates = {
        item["head"]: item
        for item in json.loads(git("show", CANDIDATES))["equivalences"]
    }
    checked = []
    for ref in refs:
        sha = ref["sha"]
        item = {"ref": ref["ref"], "sha": sha, "disposition": "outstanding"}
        if ancestor(sha, head):
            item["disposition"] = "ancestor"
        elif sha in candidates:
            candidate = candidates[sha]
            replacement = candidate["replacement"]
            assert ancestor(replacement, head), replacement
            if candidate["proof"] == "identical_git_tree":
                assert git("rev-parse", sha + "^{tree}") == git(
                    "rev-parse", replacement + "^{tree}"
                ), sha
                proof = {"method": "identical_git_tree"}
            else:
                paths = git(
                    "diff", "--name-only", candidate["merge_base"], sha
                ).splitlines()
                assert len(paths) == candidate["changed_path_count"]
                for path in paths:
                    assert git("ls-tree", sha, "--", path) == git(
                        "ls-tree", replacement, "--", path
                    ), path
                proof = {
                    "method": "identical_changed_path_mode_type_blob",
                    "merge_base": candidate["merge_base"],
                    "paths": paths,
                }
            item.update(
                disposition="verified_historical_equivalent",
                replacement=replacement,
                proof=proof,
            )
        checked.append(item)
    counts = {
        key: sum(item["disposition"] == key for item in checked)
        for key in ("ancestor", "verified_historical_equivalent", "outstanding")
    }
    result = {
        "schema": 1,
        "repository": "CrispStrobe/quds_office_suite",
        "captured_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "head": head,
        "origin_main": git("rev-parse", "refs/remotes/origin/main"),
        "candidate_source": CANDIDATES,
        "summary": {"total_refs": len(checked), **counts},
        "refs": checked,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result["summary"]))
    return bool(counts["outstanding"])


if __name__ == "__main__":
    raise SystemExit(main())
