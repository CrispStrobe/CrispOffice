#!/usr/bin/env python3
"""Replay source coverage against a captured ref inventory, without CI calls."""

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import subprocess


os.environ["GIT_NO_LAZY_FETCH"] = "1"
os.environ["GIT_TERMINAL_PROMPT"] = "0"

def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def ancestor(a, b):
    result = subprocess.run(["git", "merge-base", "--is-ancestor", a, b])
    if result.returncode not in (0, 1):
        raise RuntimeError(f"Ancestry failed for {a} and {b}")
    return result.returncode == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--snapshot", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent
    snapshot = json.loads((args.snapshot or directory / "snapshot.json").read_text())
    equivalents = json.loads((directory / "historical-equivalents.json").read_text())
    head = git("rev-parse", args.head)
    proofs = {}
    for source, definition in equivalents.items():
        replacement = definition["replacement"]
        assert ancestor(replacement, head), (source, "replacement is not included")
        proof = {**definition, "replacement_ancestor": True}
        if definition["kind"] == "full_tree":
            proof["source_tree"] = git("rev-parse", source + "^{tree}")
            proof["replacement_tree"] = git("rev-parse", replacement + "^{tree}")
            assert proof["source_tree"] == proof["replacement_tree"], source
        else:
            base = definition.get("base") or git("merge-base", source, replacement)
            paths = git("diff", "--name-only", base, source).splitlines()
            assert paths, (source, "no changed paths")
            differences = git("diff", "--name-only", source, replacement, "--", *paths)
            assert not differences, (source, differences)
            proof.update(base=base, changed_paths=paths, exact_changed_paths=True)
        proofs[source] = proof
    refs = []
    for ref in snapshot["refs"]:
        disposition = (
            "ancestor" if ancestor(ref["sha"], head)
            else "verified_equivalent" if ref["sha"] in proofs
            else "uncovered"
        )
        refs.append({**ref, "disposition": disposition})
    counts = dict(Counter(ref["disposition"] for ref in refs))
    receipt = {
        "head": head,
        "tree": git("rev-parse", head + "^{tree}"),
        "snapshot_at": snapshot.get("captured_at"),
        "counts": counts,
        "proofs": proofs,
        "refs": refs,
        "github_actions": "Neither queried nor awaited",
    }
    args.output.write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({"head": head, "counts": counts}))
    if counts.get("uncovered", 0):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
