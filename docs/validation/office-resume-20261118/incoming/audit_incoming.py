#!/usr/bin/env python3
"""Capture/recheck local Git refs without fetching, changing refs, or running CI.

The inventory freezes the refs once. --inventory rechecks those exact objects
even after local remote-tracking refs advance. All classifications retain the
distinction between ancestry, historical tree equivalence and the one reviewed
successor exception; none means an old branch's product tree should be restored.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess

HEADS = {
    "main": "4b2b4e78839d2997a583b7ab1346e2fa537a8ac4",
    "gector_office": "205e913ec1525b5e5157a6f6d7ff84c883217e48",
    "office_union": "16c7b0fb48c72527645678b76e25b5c5cb7b9c22",
    "native_spacy": "e7c67f29b34f1c1909e51aa25997fc774bb8ac80",
}
PREFIXES = {
    "refs/remotes/origin/": "fork_branch",
    "refs/remotes/pull/": "fork_pr",
    "refs/remotes/upstream/": "upstream_branch",
    "refs/remotes/upstream-pr/": "upstream_pr",
}
EXPECTED_COUNTS = {
    "fork_branch": 183, "fork_pr": 149,
    "upstream_branch": 4, "upstream_pr": 4,
}
CURRENT_WORK_REFS = {"refs/remotes/origin/codex/office-resume-20261118"}
FIELD_HEAD = "c34945761e7991f5fe49037d79529acdd260b31c"
FIELD_SUCCESSOR = "2c47165d01d01cc883135a434ac9f6591ce6e770"
FIELD_ALLOWED_DELTA = {
    "docs/office-remaining-gaps.md",
    "packages/quds_office_engine/lib/src/sheet/legacy/ods_sheet_reader.dart",
    "packages/quds_office_engine/lib/src/sheet/legacy/ods_sheet_writer.dart",
    "packages/quds_office_engine/lib/src/sheet/model/sml_analysis.dart",
    "packages/quds_office_engine/lib/src/sheet/model/sml_conditional_format.dart",
    "packages/quds_office_engine/lib/src/sheet/serial/sheet_serial.dart",
    "packages/quds_office_engine/test/ods_sheet_writer_test.dart",
    "packages/quds_office_engine/test/sheet_save_cache_and_freeze_test.dart",
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--inventory", type=Path)
    parser.add_argument("--integrated-head")
    args = parser.parse_args()
    repo = args.repo.resolve()
    out = args.out.resolve()
    if out == repo or repo in out.parents:
        raise SystemExit("Audit output must be outside the repository checkout.")
    out.mkdir(parents=True, exist_ok=True)

    def git(*words: str) -> str:
        return subprocess.check_output(
            ["git", "-C", str(repo), *words], text=True
        ).strip()

    def ancestor(left: str, right: str) -> bool:
        result = subprocess.run(
            ["git", "-C", str(repo), "merge-base", "--is-ancestor", left, right],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        if result.returncode not in (0, 1):
            raise RuntimeError(result.stderr.decode())
        return result.returncode == 0

    if args.inventory:
        inventory_bytes = args.inventory.read_bytes()
        inventory = json.loads(inventory_bytes)
        if inventory["principal_heads"] != HEADS:
            raise SystemExit("Principal-head mismatch in frozen inventory.")
    else:
        refs = []
        excluded_current_work = []
        raw = git("for-each-ref", "--format=%(refname) %(objectname) %(symref)",
                  "refs/remotes")
        for row in raw.splitlines():
            fields = row.split()
            if len(fields) != 2:  # Skip symbolic origin/HEAD.
                continue
            ref, sha = fields
            if ref in CURRENT_WORK_REFS:
                excluded_current_work.append({"ref": ref, "sha": sha})
                continue
            category = next((v for k, v in PREFIXES.items() if ref.startswith(k)), None)
            if category is None:
                continue
            refs.append({"ref": ref, "sha": sha, "category": category,
                         "tree": git("rev-parse", f"{sha}^{{tree}}")})
        inventory = {
            "schema": "quds.incoming.fixed_local_refs.v1",
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "repository": "CrispStrobe/quds_office_suite",
            "upstream": "MohammedAsaadAsaad/quds_office_suite",
            "principal_heads": HEADS,
            "counts": dict(sorted(Counter(x["category"] for x in refs).items())),
            "refs": sorted(refs, key=lambda x: x["ref"]),
            "excluded_current_work_refs": excluded_current_work,
            "scope": "Already fetched local branch and PR head refs. No network or CI queries.",
        }
        inventory_bytes = (json.dumps(inventory, indent=2, sort_keys=True) + "\n").encode()
    if inventory["counts"] != EXPECTED_COUNTS:
        raise SystemExit(f"Unexpected capture counts: {inventory['counts']}")
    (out / "incoming-refs.json").write_bytes(inventory_bytes)

    reachable_trees: dict[str, str] = {}
    for row in git("log", "--format=%H %T", *HEADS.values()).splitlines():
        commit, tree = row.split()
        reachable_trees.setdefault(tree, commit)

    field_delta = sorted(git("diff", "--name-only", FIELD_HEAD, FIELD_SUCCESSOR).splitlines())
    if set(field_delta) != FIELD_ALLOWED_DELTA or not ancestor(FIELD_SUCCESSOR, HEADS["main"]):
        raise SystemExit("Reviewed field-successor exception no longer verifies.")

    classifications = []
    for record in inventory["refs"]:
        sha = record["sha"]
        if git("rev-parse", f"{sha}^{{tree}}") != record["tree"]:
            raise SystemExit(f"Tree mismatch for {record['ref']}")
        contained = [name for name, head in HEADS.items() if ancestor(sha, head)]
        item = {**record, "ancestor_of": contained}
        if contained:
            item["classification"] = "ancestor"
        elif record["tree"] in reachable_trees:
            equivalent = reachable_trees[record["tree"]]
            item.update(classification="exact_tree_equivalent_in_history",
                        equivalent_commit=equivalent,
                        equivalent_tree=record["tree"])
        elif sha == FIELD_HEAD:
            item.update(
                classification="reviewed_later_spreadsheet_successor",
                successor=FIELD_SUCCESSOR, differing_paths=field_delta,
                interpretation="All Word source and validation evidence are byte-identical. "
                "Successor adds the later main spreadsheet features and corresponding backlog update.",
            )
        else:
            item["classification"] = "unresolved"
        classifications.append(item)

    aot_paths = {}
    for name, head in HEADS.items():
        paths = git("ls-tree", "-r", "--name-only", head, "packages/quds_proofing_aot",
                    "packages/quds_office_editor/example/lib/studio_aot.dart",
                    "packages/quds_office_editor/example/test/studio_aot_test.dart")
        aot_paths[name] = paths.splitlines() if paths else []
    totals = Counter(x["classification"] for x in classifications)
    report = {
        "schema": "quds.incoming.reconciliation_audit.v1",
        "inventory_sha256": hashlib.sha256(inventory_bytes).hexdigest(),
        "principal_heads": HEADS, "reference_counts": inventory["counts"],
        "reference_total": len(classifications),
        "unique_captured_heads": len({r["sha"] for r in classifications}),
        "classification_counts": dict(sorted(totals.items())),
        "removed_aot_product_paths_at_principal_heads": aot_paths,
        "preservation_boundary": "Old histories and evidence are accounted for; historical "
        "tree equivalence does not restore old product code or reverse explicit AOT/RML removal.",
        "ci_queried_or_waited": False,
        "classifications": classifications,
        "passed": not totals["unresolved"] and not any(aot_paths.values()),
    }
    if args.integrated_head:
        integrated = git("rev-parse", f"{args.integrated_head}^{{commit}}")
        coverage = {name: ancestor(head, integrated) for name, head in HEADS.items()}
        report["integrated_head"] = integrated
        report["integrated_head_contains_principal_heads"] = coverage
        revived = git("ls-tree", "-r", "--name-only", integrated,
                      "packages/quds_proofing_aot",
                      "packages/quds_office_editor/example/lib/studio_aot.dart",
                      "packages/quds_office_editor/example/test/studio_aot_test.dart")
        report["integrated_head_aot_product_paths"] = revived.splitlines() if revived else []
        report["passed"] = report["passed"] and all(coverage.values()) and not revived
    (out / "reconciliation-audit.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

    lines = ["# Incoming reference audit", "",
             "This fixed snapshot captures 183 fork branches, 149 fork PR heads, four upstream "
             "branches and four upstream PR heads from local refs. The new continuation branch "
             "created by this session is excluded from incoming counts and recorded separately. "
             "No network or CI endpoint is used.", "",
             "## Exact principal heads", "", "| Source | SHA |", "| --- | --- |"]
    lines.extend(f"| {name} | `{sha}` |" for name, sha in HEADS.items())
    lines += ["", "## Accounting", "", "| Classification | References |", "| --- | ---: |"]
    lines.extend(f"| {kind} | {count} |" for kind, count in sorted(totals.items()))
    lines += ["", f"Total: **{len(classifications)} refs**, **{report['unique_captured_heads']} distinct heads**.", "",
              "The 22 equivalent refs are 11 branch/PR pairs with exact full-tree equality to "
              "commits in the integrated histories. The two reviewed exceptions are the branch and "
              "PR #140 at `c3494576`: their successor `2c47165d` differs only in seven later spreadsheet "
              "files plus the corresponding backlog documentation. All Word source and its evidence "
              "are identical. Exact paths and all per-ref proofs are in the JSON report.", "",
              "All four principal product trees retain the AOT/RML removal. Native spaCy is a "
              "separate optional, default-off analysis package, with no registered grammar provider.", "",
              "## Reproduction", "", "```sh",
              "python3 audit_incoming.py --repo /path/to/quds_office_suite --out /path/to/new-audit",
              "python3 audit_incoming.py --repo /path/to/quds_office_suite --out /path/to/recheck \\",
              "  --inventory /path/to/new-audit/incoming-refs.json --integrated-head EXACT_COMMIT", "```", "",
              "The recheck uses frozen SHAs even when remote-tracking refs have advanced. It fails "
              "on missing objects, changed inventory counts, unaccounted refs, an unexpected successor "
              "delta, revived AOT product files, or absent principal ancestry in an explicit integrated head.", ""]
    (out / "README.md").write_text("\n".join(lines))
    print(json.dumps({k: v for k, v in report.items() if k != "classifications"}, indent=2))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
