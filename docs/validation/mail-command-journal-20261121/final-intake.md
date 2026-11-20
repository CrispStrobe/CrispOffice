# Final frozen intake: all 327 captured refs covered

The complete remote inventory captured between **2026-11-20 23:32:18 and
23:32:20 UTC** is covered by checkpoint
[`19eccc016fd14bea52c095db917a28b5ce3cdd5c`](https://github.com/CrispStrobe/quds_office_suite/commit/19eccc016fd14bea52c095db917a28b5ce3cdd5c),
tree `39e5a1911a06c3a6888ed465d6dea9df06ff6b42`. There are **303 direct ancestor
refs**, **24 refs with independently recomputed exact equivalence proofs**, and
**zero uncovered refs or missing objects**. The remote capture used only
repository branch and pull-request collection endpoints; no GitHub Actions,
checks or status endpoints were queried or awaited.

| Captured category | Total | Direct ancestors | Exact equivalents | Uncovered |
| --- | ---: | ---: | ---: | ---: |
| Fork branches | 40 | 30 | 10 | 0 |
| Fork PR heads | 279 | 265 | 14 | 0 |
| Upstream branches | 4 | 4 | 0 | 0 |
| Upstream PR heads | 4 | 4 | 0 | 0 |
| **Total** | **327** | **303** | **24** | **0** |

[final-remote-refs.json](final-remote-refs.json) preserves every exact head SHA,
collection URL, page length and per-endpoint retrieval timestamp. The three fork
PR pages contain 100, 100 and 79 records; all final pages are shorter than the
100-record request limit. [final-intake.json](final-intake.json) records every
ref disposition, immutable target tree, snapshot hash and all sixteen
recomputed proof records. The earlier 325-ref snapshot and its report remain
unchanged as the initial intake record.

## Advances reconciled before this cutoff

| Captured head | Integration and retention |
| --- | --- |
| Fork main `383c0c0c5d3b4b1a6edccc8d09ffd1ca64029537` | Includes the native Mail tab/account-control update at `329d0391` and the published PR277 source/evidence union. Both are ancestors of the final target. |
| Zotero branch / PR277 `a7d9f37ecbaaf70544f4866d7d9e572696948184` | Preserves the newer vertical table layout, physical-row geometry and native border work. Reader reconciliation retains the bounded image behavior and the stronger current identity/receipt guards; focused Mail gates qualify that union separately. |
| Word branch / PR278 `0e4e999a08996a6b8696ca3adba11e303331b73e` | Includes the reviewed source/evidence continuation at `4163368b`, six Mail fixture alignments at `58cc4283`, and the final documentation/evidence commits `8206975d` and `0e4e999a`. Current stronger vertical-table source remains intact. |
| Milestone branch / PR279 `cc152e75dc6b7121fd5e6c6d58e304e9bb89de73` | Captures the durable Mail command journal, activity/recovery work and reviewed reconciliations before the last documentation-only intake merge. It is an ancestor of the final target. |

At the cutoff PR277 was merged, while PR278 and PR279 were open. Their captured
heads are covered regardless of later PR state changes. Upstream's four branches
and four PR heads are byte-for-byte unchanged from the initial snapshot.

The unit branch advanced to `0e4e999a` immediately before the capture. A candidate
audit at `cc152e75` correctly identified that branch and PR278 as the only two
uncovered refs. Inspection established the two new commits were documentation
and evidence only. Their merge produced the audited `19eccc01` checkpoint. The
cutoff was kept fixed rather than relabeling an earlier snapshot as current.

## Exact equivalence and source retention

The verifier independently repeats the fourteen inherited historical proofs:
thirteen complete-tree identities and the 37-path ODT equivalence proof. It also
verifies that `ec70b942` has the exact same complete binary patch and before/after
Git entries as accepted ancestor `e975cec1` at all three changed paths. The
concurrent PR277 merge at `37148e37` has the same complete tree as accepted
`e219e25`; both are now ancestors as well. A ref is classified as an ancestor
first, so redundant proofs do not inflate the 24-equivalent-ref count.

Ancestry establishes inclusion, not preservation of every overlapping line or
runtime behavior. The conflict review therefore retains the newer per-page
vertical-merge implementation and existing complete fixture coverage. The
incoming deserializer and two native regression suites from `52eace9e` are
already exactly present, with blobs:

| Retained file | Exact blob |
| --- | --- |
| `word_deserializer.dart` | `55df251ee1a958ef32736919d93b13d6728312d1` |
| `word_header_visual_reconciliation_test.dart` | `523bd9d43b12f3a544b5b08941f2908066fde738` |
| `word_table_style_import_regression_test.dart` | `223e47a428d66fc64d60362dcea86dbf45e31734` |

[final-intake-retention.json](final-intake-retention.json) separately verifies
52 incoming evidence/documentation paths: the 24 files from the earlier Mail and
Word bridge checkpoints, seventeen later Mail evidence files, ten Word delivery
files and the shared VBA documentation-link update. Added evidence files retain
their exact incoming Git blobs. The shared document retains the exact incoming
added link while preserving the integrated document around it. These historical
records are preserved as authored evidence; their case counts are not added to
the fresh acceptance runs.

The explicitly temporary golden-regeneration workflow remains absent. The
incoming 27-image baseline refresh was independently tested, causally attributed
and reconciled to the retained production padding. The exact no-update golden
gate and editor qualification are in
[office-qualification.md](office-qualification.md); they are separate from this
source-inclusion proof.

## Reproduce without network or CI

From a checkout containing the immutable Git objects:

```sh
python3 docs/validation/mail-command-journal-20261121/verify_intake.py \
  --repo . \
  --snapshot docs/validation/mail-command-journal-20261121/final-remote-refs.json \
  --target 19eccc016fd14bea52c095db917a28b5ce3cdd5c \
  --artifact-prefix final- \
  --output-dir /absolute/path/to/new/intake-replay

python3 docs/validation/mail-command-journal-20261121/verify_final_intake_retention.py --repo .
```

The verifier disables lazy Git fetching and performs only local immutable-object
reads. Later publication commits may add evidence while retaining the audited
checkpoint as an ancestor. The landing procedure guards remote main again
immediately before the authorized merge; that final remote readback is a separate
publication record.
