#!/usr/bin/env python3
"""Read-only replay of the captured fork/upstream reference reconciliation."""

import argparse
import collections
import datetime
import hashlib
import json
import pathlib
import subprocess


def main():
    here = pathlib.Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=pathlib.Path, default=here.parents[2])
    parser.add_argument("--head", help="Exact local commit to audit; defaults to HEAD")
    parser.add_argument("--fork-refs", type=pathlib.Path,
                        default=here / "reconciliation-remote-final.txt")
    parser.add_argument("--upstream-refs", type=pathlib.Path,
                        default=here / "reconciliation-upstream-final.txt")
    parser.add_argument("--output", type=pathlib.Path,
                        default=here / "reconciliation-final.json")
    args = parser.parse_args()

    def git(*arguments, check=True):
        return subprocess.run(["git", *arguments], cwd=args.repo, check=check,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def ancestor(older, newer):
        return git("merge-base", "--is-ancestor", older, newer,
                   check=False).returncode == 0

    head = git("rev-parse", args.head or "HEAD").stdout.decode().strip()
    initial = "caf378f40fd5bda50f504a6816404d01d8bbb8f8"
    basis_path = "docs/validation/mail-archive-restore-20261119/reconciliation.json"
    basis_raw = git("show", initial + ":" + basis_path).stdout
    basis = json.loads(basis_raw)
    proofs = {}
    for inherited in basis["historical_proofs_reused"]:
        original = inherited["original"]
        equivalent = inherited["equivalent"]
        base = git("merge-base", original, equivalent).stdout.decode().strip()
        changed = [p.decode() for p in git("diff", "--name-only", "-z", base,
                                          original).stdout.split(b"\0") if p]
        mismatches = [p for p in changed
                      if git("ls-tree", original, "--", p).stdout !=
                      git("ls-tree", equivalent, "--", p).stdout]
        proof = {**inherited, "fresh_checked_head": head,
                 "fresh_common_base": base, "fresh_delta_paths": len(changed),
                 "fresh_delta_mismatches": mismatches,
                 "fresh_equivalent_is_ancestor": ancestor(equivalent, head)}
        if inherited["method"] == "exact_complete_tree_identity":
            proof["fresh_tree_equal"] = (
                git("rev-parse", original + "^{tree}").stdout ==
                git("rev-parse", equivalent + "^{tree}").stdout)
        proof["fresh_passed"] = (
            base == inherited["common_base"] and not mismatches and
            proof["fresh_equivalent_is_ancestor"] and
            proof.get("fresh_tree_equal", True))
        proofs[original] = proof

    references, excluded, captures = [], [], []
    own_refs = {"refs/heads/codex/mail-archive-resume-20261119", "refs/pull/212/head"}
    for source, path in (("fork", args.fork_refs), ("upstream", args.upstream_refs)):
        raw = path.read_bytes()
        captures.append({"file": path.name, "sha256": hashlib.sha256(raw).hexdigest(),
                         "bytes": len(raw)})
        seen = set()
        for line in raw.decode().splitlines():
            sha, ref = line.split()
            if ref in seen:
                raise ValueError("Duplicate captured ref: " + ref)
            seen.add(ref)
            record = {"source": source, "ref": ref, "sha": sha}
            if source == "fork" and ref in own_refs:
                record.update(
                    reason="Current mail resume branch/PR; excluded from external incoming work.",
                    ancestor_of_checked_head=ancestor(sha, head))
                excluded.append(record)
                continue
            if ancestor(sha, head):
                record["classification"] = "ancestor"
            elif sha in proofs and proofs[sha]["fresh_passed"]:
                record.update(classification="historical_equivalent",
                              equivalent=proofs[sha]["equivalent"],
                              proof_method=proofs[sha]["method"])
            else:
                record.update(classification="unaccounted", object_present=(
                    git("cat-file", "-e", sha + "^{commit}", check=False).returncode == 0))
            references.append(record)

    counts = collections.Counter(r["classification"] for r in references)
    counts.setdefault("unaccounted", 0)
    all_refs = references + excluded
    result = {
        "schema_version": 1,
        "replayed_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "scope": "Every advertised fork branch/PR head and upstream branch in the named captures. "
                 "The replay performs no network read, fetch, ref update or Actions operation.",
        "repository": "CrispStrobe/quds_office_suite",
        "upstream": "MohammedAsaadAsaad/quds_office_suite",
        "checked_local_head": head, "initial_main": initial,
        "status": "pending_external_integration" if counts["unaccounted"] else "accounted",
        "counts": dict(counts), "external_reference_count": len(references),
        "captured_reference_count": len(all_refs),
        "fork_branch_count": sum(r["source"] == "fork" and r["ref"].startswith("refs/heads/")
                                 for r in all_refs),
        "fork_pr_head_count": sum(r["source"] == "fork" and r["ref"].startswith("refs/pull/")
                                  for r in all_refs),
        "upstream_branch_count": sum(r["source"] == "upstream" for r in references),
        "excluded_own_references": excluded, "live_captures": captures,
        "historical_equivalence_basis": {
            "path": basis_path, "commit": initial,
            "sha256": hashlib.sha256(basis_raw).hexdigest(),
            "note": "Inherited mappings; all 14 original/equivalent proofs freshly recomputed "
                    "from available Git objects. No unavailable-original proof reused."},
        "historical_proofs": list(proofs.values()), "references": references,
        "observation_limits": [
            "Git ref advertisements and any separate API reads are not one atomic snapshot.",
            "Ancestry establishes incorporation, not runtime correctness; acceptance is separate.",
            "Refresh captures and expected main immediately before final publication."],
        "github_actions_queried_or_awaited": False,
    }
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"head": head, "counts": dict(counts),
                      "external": len(references), "captured": len(all_refs)}, indent=2))
    return 1 if counts["unaccounted"] or not all(p["fresh_passed"] for p in proofs.values()) else 0


if __name__ == "__main__":
    raise SystemExit(main())
