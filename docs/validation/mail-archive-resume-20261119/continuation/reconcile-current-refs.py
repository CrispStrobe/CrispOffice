#!/usr/bin/env python3
"""Reconcile one captured fork branch/PR-head inventory against an exact commit.

Read-only Git replay. No network requests, ref mutations, or CI operations.
Historical upstream references are checked separately without claiming freshness.
"""

import argparse
import collections
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--refs", type=Path, required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--basis", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    basis_path = args.basis or args.repo / (
        "docs/validation/mail-archive-resume-20261119/"
        "publication-ref-inventory.json"
    )

    def git(*arguments, check=True):
        return subprocess.run(
            ["git", *arguments], cwd=args.repo, check=check,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )

    def ancestor(older, newer):
        result = git("merge-base", "--is-ancestor", older, newer, check=False)
        if result.returncode not in (0, 1):
            raise RuntimeError(result.stderr.decode())
        return result.returncode == 0

    if not re.fullmatch(r"[0-9a-f]{40}", args.head):
        raise ValueError("--head must be the full exact commit SHA")
    head = git("rev-parse", args.head + "^{commit}").stdout.decode().strip()
    if head != args.head:
        raise ValueError("Resolved commit differs from requested exact head")
    basis_raw = basis_path.read_bytes()
    basis = json.loads(basis_raw)
    inherited_proofs = basis["historical_proofs"]
    if len(inherited_proofs) != 14:
        raise ValueError("Expected the 14 published historical mappings")

    proofs = {}
    allowed_methods = {
        "exact_complete_delta_path_mode_type_blob_identity",
        "exact_complete_tree_identity",
    }
    for inherited in inherited_proofs:
        original = inherited["original"]
        equivalent = inherited["equivalent"]
        method = inherited["method"]
        if original in proofs or method not in allowed_methods:
            raise ValueError("Duplicate or unsupported historical proof")
        common_base = git("merge-base", original, equivalent).stdout.decode().strip()
        changed = [p.decode() for p in git(
            "diff", "--name-only", "-z", common_base, original,
        ).stdout.split(b"\0") if p]
        mismatches = [p for p in changed if
                      git("ls-tree", original, "--", p).stdout !=
                      git("ls-tree", equivalent, "--", p).stdout]
        proof = {
            "original": original,
            "equivalent": equivalent,
            "method": method,
            "expected_common_base": inherited["common_base"],
            "fresh_common_base": common_base,
            "fresh_common_base_matches": common_base == inherited["common_base"],
            "fresh_complete_original_delta_path_count": len(changed),
            "fresh_delta_path_mode_type_blob_mismatches": mismatches,
            "fresh_equivalent_is_ancestor": ancestor(equivalent, head),
        }
        if method == "exact_complete_tree_identity":
            proof["fresh_complete_tree_equal"] = (
                git("rev-parse", original + "^{tree}").stdout ==
                git("rev-parse", equivalent + "^{tree}").stdout
            )
        proof["fresh_passed"] = (
            proof["fresh_common_base_matches"] and not mismatches and
            proof["fresh_equivalent_is_ancestor"] and
            proof.get("fresh_complete_tree_equal", True)
        )
        proofs[original] = proof

    # Only these four exact ref/SHA pairs may retain the earlier draft decision.
    permitted_draft_refs = {
        "refs/heads/codex/vba-arrays-foreach-20261119",
        "refs/pull/210/head",
        "refs/heads/codex/crispoffice-layout-theme-20261119",
        "refs/pull/211/head",
    }
    drafts = {
        (r["ref"], r["sha"]): r for r in basis["references"]
        if r["source"] == "fork" and r["ref"] in permitted_draft_refs
        and r["classification"] == "reviewed_post_cutoff"
        and r.get("prerequisite_for_mail_resume") is False
    }
    if len(drafts) != 4:
        raise ValueError("Published basis does not contain the four exact draft refs")

    def classify(record, allow_draft=True):
        result = dict(record)
        sha = record["sha"]
        if ancestor(sha, head):
            result["classification"] = "ancestor"
        elif sha in proofs and proofs[sha]["fresh_passed"]:
            result.update(
                classification="historical_equivalent",
                equivalent=proofs[sha]["equivalent"],
                proof_method=proofs[sha]["method"],
            )
        elif allow_draft and (record["ref"], sha) in drafts:
            previous = drafts[(record["ref"], sha)]
            result.update(
                classification="unchanged_reviewed_draft",
                accepted_source_includes_this_head=False,
                prerequisite_for_mail_resume=False,
                decision=previous["decision"],
                prior_review_status=previous["review_status"],
            )
        else:
            result["classification"] = "unaccounted"
        return result

    raw = args.refs.read_bytes()
    captured = {}
    for line in raw.decode().splitlines():
        sha, ref = line.split()
        if ref in captured or not re.fullmatch(r"[0-9a-f]{40}", sha):
            raise ValueError("Duplicate or malformed captured reference: " + ref)
        captured[ref] = sha
    selected = {ref: sha for ref, sha in captured.items()
                if ref.startswith("refs/heads/") or
                re.fullmatch(r"refs/pull/[0-9]+/head", ref)}
    ignored = [{"ref": ref, "sha": sha} for ref, sha in captured.items()
               if ref not in selected]
    own = {"refs/heads/codex/mail-archive-resume-20261119", "refs/pull/212/head"}
    excluded, references = [], []
    for ref, sha in selected.items():
        record = {"source": "fork", "ref": ref, "sha": sha}
        if ref in own:
            record.update(
                reason="Own mail branch/PR; excluded from external incoming work.",
                ancestor_of_checked_head=ancestor(sha, head),
            )
            excluded.append(record)
        else:
            references.append(classify(record))

    deleted = []
    for record in basis["references"]:
        if (record["source"] == "fork" and
                record["ref"].startswith("refs/heads/") and
                record["ref"] not in selected):
            current = classify({k: record[k] for k in ("source", "ref", "sha")})
            current["prior_classification"] = record["classification"]
            current["observed_in_current_capture"] = False
            current["preserved_in_checked_history"] = current["classification"] == "ancestor"
            deleted.append(current)

    historical_upstream = [
        classify({k: r[k] for k in ("source", "ref", "sha")}, allow_draft=False)
        for r in basis["references"] if r["source"] == "upstream"
    ]
    counts = collections.Counter(r["classification"] for r in references)
    for key in ("ancestor", "historical_equivalent", "unchanged_reviewed_draft", "unaccounted"):
        counts.setdefault(key, 0)
    main_record = next(r for r in references if r["ref"] == "refs/heads/main")
    pr214 = next(r for r in references if r["ref"] == "refs/pull/214/head")
    pr215 = next(r for r in references if r["ref"] == "refs/pull/215/head")
    checks = {
        "all_current_external_branch_and_pr_heads_accounted": counts["unaccounted"] == 0,
        "all_14_historical_proofs_recomputed_and_passed": all(p["fresh_passed"] for p in proofs.values()),
        "current_main_is_ancestor": main_record["classification"] == "ancestor",
        "pr214_is_ancestor": pr214["classification"] == "ancestor",
        "pr215_is_ancestor": pr215["classification"] == "ancestor",
        "own_branch_and_pr_excluded": len(excluded) == 2,
        "all_previous_deleted_branch_heads_preserved_as_ancestors": all(r["preserved_in_checked_history"] for r in deleted),
        "four_historical_upstream_refs_remain_accounted": len(historical_upstream) == 4 and all(r["classification"] != "unaccounted" for r in historical_upstream),
    }
    report = {
        "schema_version": 1,
        "status": "accounted_with_unchanged_reviewed_drafts" if all(checks.values()) else "failed",
        "replayed_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "repository": "CrispStrobe/quds_office_suite",
        "checked_commit": head,
        "checked_tree": git("rev-parse", head + "^{tree}").stdout.decode().strip(),
        "scope": "Current fork branch and PR heads from the supplied capture only. Historical upstream refs are a separate retained snapshot, not a fresh upstream inventory.",
        "capture": {"filename": args.refs.name, "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw), "raw_reference_count": len(captured)},
        "basis": {"path": "docs/validation/mail-archive-resume-20261119/publication-ref-inventory.json", "sha256": hashlib.sha256(basis_raw).hexdigest(), "prior_checked_commit": basis["checked_local_head"]},
        "replay_script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "selected_fork_reference_count": len(selected),
        "fork_branch_count": sum(ref.startswith("refs/heads/") for ref in selected),
        "fork_pr_head_count": sum(ref.startswith("refs/pull/") for ref in selected),
        "external_reference_count": len(references),
        "counts": dict(counts),
        "checks": checks,
        "excluded_own_references": excluded,
        "references": references,
        "historical_proofs": list(proofs.values()),
        "deleted_branches_since_prior_publication_capture": deleted,
        "historical_upstream": {"freshly_captured": False, "included_in_current_counts": False, "references": historical_upstream},
        "ignored_non_scope_refs": {"reason": "HEAD aliases, tags, and generated PR merge refs are not branch or PR head inventory.", "count": len(ignored), "references": ignored},
        "limits": [
            "This replay reads named captures and Git objects; it does not establish remote changes after the capture.",
            "The exact unchanged GUI/VBA draft heads are reviewed and accounted, but are not claimed merged or included in accepted test counts.",
            "Historical equivalence verifies the complete original changed-path mode/type/blob identity or complete tree identity, not original-commit ancestry.",
            "Ancestry and content preservation do not establish runtime correctness.",
        ],
        "network_or_ci_operations_performed": False,
    }
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "head": head, "counts": dict(counts), "external": len(references), "selected": len(selected), "deleted_branch_heads_preserved": len(deleted), "checks": checks}, indent=2))
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
