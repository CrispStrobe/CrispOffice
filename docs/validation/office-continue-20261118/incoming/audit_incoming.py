#!/usr/bin/env python3
"""Freeze and classify Quds branch/PR heads without using GitHub CI endpoints.

All comparisons use exact captured Git objects. Historical tree equivalence
accounts for squash merges; it does not propose restoring superseded product
trees. The one bounded field-successor exception is independently reverified.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess

PRINCIPAL_HEADS = {
    "saved_office": "8ad80eb29a3984d58d5564c6759e853c0a8ab4af",
    "current_main": "482e08176dea6bd8f5fc80d1c0064d96b712db43",
    "native_spacy_w6": "20026ff49ac37391e2a1fd0947560a587f2f7332",
    "later_office_union": "6d97fedccde17244a917ee7d3372adebe5494089",
    "concurrent_office_local": "401d012657881a54727d58bc35e537faa45d5fbe",
}
PREFIXES = {
    "refs/remotes/origin/": "fork_branch",
    "refs/remotes/origin-pr/": "fork_pr",
    "refs/remotes/upstream/": "upstream_branch",
    "refs/remotes/upstream-pr/": "upstream_pr",
}
FIELD_HEAD = "c34945761e7991f5fe49037d79529acdd260b31c"
FIELD_SUCCESSOR = "2c47165d01d01cc883135a434ac9f6591ce6e770"
FIELD_DELTA = {
    "docs/office-remaining-gaps.md",
    "packages/quds_office_engine/lib/src/sheet/legacy/ods_sheet_reader.dart",
    "packages/quds_office_engine/lib/src/sheet/legacy/ods_sheet_writer.dart",
    "packages/quds_office_engine/lib/src/sheet/model/sml_analysis.dart",
    "packages/quds_office_engine/lib/src/sheet/model/sml_conditional_format.dart",
    "packages/quds_office_engine/lib/src/sheet/serial/sheet_serial.dart",
    "packages/quds_office_engine/test/ods_sheet_writer_test.dart",
    "packages/quds_office_engine/test/sheet_save_cache_and_freeze_test.dart",
}
AOT_PATHS = [
    "packages/quds_proofing_aot",
    "packages/quds_office_editor/example/lib/studio_aot.dart",
    "packages/quds_office_editor/example/test/studio_aot_test.dart",
]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repo", required=True, type=Path)
    p.add_argument("--out", required=True, type=Path)
    p.add_argument("--inventory", type=Path)
    p.add_argument("--integrated-head")
    args = p.parse_args()
    repo, out = args.repo.resolve(), args.out.resolve()
    if repo == out or repo in out.parents:
        raise SystemExit("Audit output must be outside checkout")
    out.mkdir(parents=True, exist_ok=True)

    def git(*words):
        return subprocess.check_output(["git", "-C", str(repo), *words], text=True, timeout=90).strip()

    def dump(name, value):
        (out / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")

    if args.inventory:
        inventory = json.loads(args.inventory.read_text())
        principal_heads = inventory["principal_heads"]
        if any(PRINCIPAL_HEADS.get(k) != v for k, v in principal_heads.items()):
            raise SystemExit("Frozen principal-head mismatch")
    else:
        records, excluded = [], []
        raw = git("for-each-ref", "--format=%(refname) %(objectname) %(symref)", "refs/remotes")
        (out / "local-refs.tsv").write_text(raw + "\n")
        for row in raw.splitlines():
            fields = row.split()
            if len(fields) != 2:
                continue
            ref, sha = fields
            if ref.startswith("refs/remotes/origin/codex/office-continue-20261118"):
                excluded.append({"ref": ref, "sha": sha})
                continue
            category = next((v for k, v in PREFIXES.items() if ref.startswith(k)), None)
            if category:
                records.append({"ref": ref, "sha": sha, "category": category,
                                "tree": git("rev-parse", f"{sha}^{{tree}}")})
        inventory = {
            "schema": "quds.incoming.fixed_local_refs.v2",
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "repository": "CrispStrobe/quds_office_suite",
            "upstream": "MohammedAsaadAsaad/quds_office_suite",
            "principal_heads": PRINCIPAL_HEADS,
            "refs": sorted(records, key=lambda r: r["ref"]),
            "counts": dict(sorted(Counter(r["category"] for r in records).items())),
            "excluded_current_work_refs": excluded,
            "scope": "All fork/upstream branch and pull-request head refs fetched locally; no CI/status endpoint used.",
        }
        principal_heads = PRINCIPAL_HEADS
    dump("incoming-refs.json", inventory)
    inventory_bytes = (out / "incoming-refs.json").read_bytes()

    reachable = {}
    reachable_trees = {}
    for name, head in principal_heads.items():
        rows = git("log", "--format=%H %T", head).splitlines()
        reachable[name] = set()
        for row in rows:
            sha, tree = row.split()
            reachable[name].add(sha)
            reachable_trees.setdefault(tree, sha)
    delta = sorted(git("diff", "--name-only", FIELD_HEAD, FIELD_SUCCESSOR).splitlines())
    if set(delta) != FIELD_DELTA or FIELD_SUCCESSOR not in reachable["current_main"]:
        raise SystemExit("Bounded field-successor exception no longer verifies")

    classifications = []
    for r in inventory["refs"]:
        if git("rev-parse", r["sha"] + "^{tree}") != r["tree"]:
            raise SystemExit("Tree mismatch: " + r["ref"])
        contained = [k for k, values in reachable.items() if r["sha"] in values]
        item = {**r, "ancestor_of": contained}
        if contained:
            item["classification"] = "ancestor"
        elif r["tree"] in reachable_trees:
            item.update(classification="exact_tree_equivalent_in_history",
                        equivalent_commit=reachable_trees[r["tree"]])
        elif r["sha"] == FIELD_HEAD:
            item.update(classification="reviewed_later_spreadsheet_successor",
                        successor=FIELD_SUCCESSOR, differing_paths=delta,
                        interpretation="All Word implementation and evidence match an included successor; only later spreadsheet files and backlog differ.")
        else:
            item["classification"] = "unresolved"
        classifications.append(item)
    counts = Counter(r["classification"] for r in classifications)
    absent = {name: git("ls-tree", "-r", "--name-only", head, *AOT_PATHS).splitlines()
              for name, head in principal_heads.items()}
    report = {
        "schema": "quds.incoming.reconciliation_audit.v2",
        "inventory_sha256": hashlib.sha256(inventory_bytes).hexdigest(),
        "principal_heads": principal_heads,
        "reference_counts": inventory["counts"],
        "reference_total": len(classifications),
        "unique_captured_heads": len({r["sha"] for r in classifications}),
        "classification_counts": dict(sorted(counts.items())),
        "removed_aot_product_paths_at_principal_heads": absent,
        "classifications": classifications,
        "passed": not counts["unresolved"] and not any(absent.values()),
        "ci_queried_or_waited": False,
    }
    if args.integrated_head:
        integrated = git("rev-parse", args.integrated_head + "^{commit}")
        integrated_reachable = set(git("rev-list", integrated).splitlines())
        coverage = {k: sha in integrated_reachable for k, sha in principal_heads.items()}
        revived = git("ls-tree", "-r", "--name-only", integrated, *AOT_PATHS).splitlines()
        report.update(integrated_head=integrated,
                      integrated_tree=git("rev-parse", integrated + "^{tree}"),
                      integrated_head_contains_principal_heads=coverage,
                      integrated_head_aot_product_paths=revived)
        report["passed"] = report["passed"] and all(coverage.values()) and not revived
    dump("reconciliation-audit.json", report)
    (out / "classification.tsv").write_text(
        "category\tref\tsha\tclassification\tequivalent_or_successor\n" +
        "\n".join("\t".join([r["category"], r["ref"], r["sha"], r["classification"],
                              r.get("equivalent_commit", r.get("successor", ""))])
                  for r in classifications) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "classifications"}, indent=2))
    if not report["passed"]:
        print(json.dumps([r for r in classifications if r["classification"] == "unresolved"], indent=2))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
