# Frozen publication intake

Target before late integration: `6ac854de0583b7955470648916c53c76b67c0fff`, tree `5bd40fb467d6710987e06634934e84c3dc513bfa`. Fork main remains `bf761552d22dcd1eb8cbb0ab00ddab6507e1d572` at this snapshot.

The complete fork/upstream Git advertisements contain **330 refs**. Against the target, **304 are ancestors, 24 have independently verified exact equivalents, and two external branch heads remain to integrate**. Our own new Zotero branch is counted once among the ancestors. Fork and upstream open-PR endpoints each returned an empty, complete first page.

Completed disposition: both captured incoming heads are ancestors of published
product checkpoint `a5dc721dd8e519dde4f019b82a89572fe9f570f4`. The
[final replay](final-audit.json) proves **306 ancestors, 24 exact historical
equivalents and zero uncovered refs**. Refreshed main
`3d01815908aeded5862d131109341365de637242` and later main
`ce1c37c6af1e2306d2c24231758f10ef6213f7dd` are separately included through
normal ancestry merges. The review below preserves the pre-integration snapshot and decisions;
the [current work record](../README.md) contains qualification and publication
applicability.

| Incoming branch | Frozen head | Feature |
| --- | --- | --- |
| `codex/word-vba-paragraph-pagination-20261121` | `c093f6387fcae69f04c63f4344476e4785906a54` | Guarded Word VBA section PageSetup writes, sparse native section preservation and namespace fidelity |
| `work/mail-parity-20261121` | `1df5e678906ff1def11deed085586dc733030595` | Optional fresh read-only flag observations and durable SQLite v7 reconciliation of uncertain commands |

The Word continuation adds exact twentieth-point dimensions/margins/header-footer distances, explicit section targeting and whole-run rollback through the existing macro host. The Mail continuation adds an optional observer interface, provider implementations, revision/epoch-bound reconciliation authority and durable observation receipts. It does not replay uncertain commands. These changes require local qualification and normal ancestry merges before publication. Neither continuation changes the Zotero product source.

## Merge review

Independent previews have only bounded overlaps: the semantically identical `remoteImageUris` alias validation, package changelogs, and one additional Mail compatibility assertion. Keep the current alias implementation, union changelog entries, and retain the incoming assertion that the item and stop report preserve the same original problem object. `incoming-review.json` records exact commit IDs, product/test paths and conflict paths; no large patches are copied into the evidence.

This is a frozen intake, not a claim that the target already includes the two new heads. Preserve the captured cutoff rather than repeatedly chasing active branches. Check main freshness separately before publication.

## Reproduce source coverage

The original branch/PR-head advertisements are retained as TSV files; `snapshot.json` normalizes them. `audit.json` records the pre-integration result, all 15 independently recomputed equivalence definitions, and every ref disposition. The verifier performs local immutable-object reads with lazy fetching disabled.

```sh
python3 docs/validation/zotero-multiparagraph-20261121/publication-intake/audit_intake.py \
  --head HEAD \
  --snapshot docs/validation/zotero-multiparagraph-20261121/publication-intake/snapshot.json \
  --output /path/to/publication-intake-replay.json
```

After both ancestry merges this frozen inventory must have zero uncovered refs. Historical equivalents remain exact-tree or exact-changed-path proofs; they are not inferred from narrative claims. GitHub Actions, status/check endpoints and workflows were neither queried nor awaited.
