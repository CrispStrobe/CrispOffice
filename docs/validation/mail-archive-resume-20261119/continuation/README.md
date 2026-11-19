# Mail restore-resume publication continuation — 2026-11-19

**Local acceptance and independent replay passed.** The final source is
9b8853667b68c7bebff050e52445b47ea0bbd188, tree
57d90e137f5b6c452a809080d4067f53c8209f09. It preserves the prior mail
milestone and latest main at 088d80905e3f76542dd9813e96584cd5c61454ff,
including PRs #214 and #215. Final publication and merge identities are
recorded in [PR #212](https://github.com/CrispStrobe/quds_office_suite/pull/212).
GitHub Actions were not queried, awaited or used as a gate.

## Validation results

| Evidence | Passed | Files | Required commands | Source binding |
| --- | ---: | ---: | ---: | --- |
| Preserved complete acceptance, freshly replayed | 2,243 | 121 | 42 | Original accepted source 71053bf6; published checkpoint b2c05a0a |
| Fresh continuation qualification | 50 | 3 | 4 | Final reconciled source 9b885366 |

Both sets have **zero failures and zero skips**. The new tests overlap earlier
cases, so their counts remain separate; they are not added into a new distinct
case count. Historical author evidence and interrupted attempts add no accepted
executions. The original six JavaScript programs and 24 mail UI capture hashes
were independently replayed or verified from their saved evidence, not rerun
or newly visually judged in this continuation.

The fresh gate passed read-only formatting, strict analysis of four files,
scoped whitespace verification and serial Flutter execution of three complete
test files:

| Test file | Passed |
| --- | ---: |
| studio_downloads_manager_test.dart | 11 |
| studio_spacy_setup_test.dart | 15 |
| studio_linguistic_analysis_test.dart | 24 |

Independent replay verified the raw JSON events, complete test lifecycles,
selected-file coverage, absence of hidden errors, exact command invocations,
exit codes and all retained command/result/log hashes. It rehashed all current
inputs against their before/after inventories:

- **4,493 source inputs**, bound to the frozen Git blobs and file modes.
- **9,298 dependency inputs**, with the same digest as the original complete
  acceptance: c400b0220ab948cd68a54521cda95e92ec96447acb4ea0c4c487a2fbb28292c2.
- **695 declared runtime inputs** and **21 generated native-asset/support files**.

Both default packaged SQLite library copies match the pinned asset hash; the
native asset mapping is captured. The root manifest and lockfile are unchanged.
The Flutter 3.47.8 / Dart 3.13.7 runtime was reconstructed from the verified
official SDK archive and exact locked package archives. Only the components
required for this focused Linux gate were restored. Preparation scripts,
checksums, omitted-component records and wrapper bytes are preserved separately.

## Exact integration changes

Work resumed from remote checkpoint
b2c05a0afa0ae606b061b13d5e50937c2a8eb1df, while PR #212 was still draft.
The original publication verifier passed again before any source changed:
all 4,493 inputs matched the accepted inventory and that checkpoint's Git
blobs, and only validation documents differed from the accepted source.

Main advanced twice during this continuation. PR #214 added model-specific
download labels and NER assertions. PR #215 then added lazy first-use
installation verification. The final product/test delta from the original
acceptance is exactly four files, all in the same qualified language-model
integration:

| Path under packages/quds_office_editor/example/ | Resolution |
| --- | --- |
| lib/studio_downloads_manager.dart | Exact latest-main implementation: model-specific German title and explanation when the native library is bundled, with the accepted model-only download size. |
| lib/studio_spacy_host_native.dart | Accepted mail _nerStatus() implementation plus the exact nine PR #215 additions. Saved installation status is verified before the first explicit analysis action. |
| test/studio_downloads_manager_test.dart | All earlier fixture functionality and five size/NER regressions retained. The title finder handles model/package labels, and the incoming label test uses the established fixture argument. |
| test/studio_spacy_setup_test.dart | Exact latest-main test file, preserving missing-NER assertions and first-analysis verification coverage. |

The third executed test file, studio_linguistic_analysis_test.dart, is unchanged
and checks the analysis consumer affected by the new first-use behavior.
The mail implementation and all mail tests remain byte-identical to the original
acceptance. Independent source review reconstructs the accepted native host by
removing only PR #215's additions and reconstructs every earlier manager test
by removing only the new label case and reversing its title-finder adaptation.

The three incoming documents under
docs/validation/language-downloads-20261119/ retain exact latest-main blobs.
Their macOS qualification results remain their authors' evidence and are not
added to this continuation's independently executed Linux counts.

## Branch reconciliation and preservation

All current fork branches and PR heads were fetched. The latest captured
inventory contains **14 branch heads and 215 PR heads**. Excluding this work's
two refs leaves **227 external refs: 200 ancestors, 23 freshly proved historical
equivalents, four exact unchanged reviewed draft refs, and zero unaccounted**.
All 14 historical equivalence proofs were recomputed. Main and PR #214/#215
heads are ancestors; five previously captured branch heads subsequently deleted
from the remote remain preserved in history.

The later draft work for PR #210 (3abffb94dcf33a2766a4579d296d0ef09c9e35cd)
and PR #211 (cacae8569814e4cb81f58d358734d31431f102be) retains its explicit
post-cutoff review and remains outside this milestone. Their earlier qualified
work is already in the accepted source. Four retained upstream refs remain
accounted separately as historical observations; no fresh upstream snapshot is
claimed. Ref advertisements and PR metadata are separate, non-atomic observations.

Every continuation checkpoint uses a non-forced remote update with the expected
previous head and an exact local/remote tree comparison. The checkpoint ledger
records the source history; subsequent validation-only publication descendants
remain in Git ancestry. The candidate verifier checks source, test, evidence,
review, runner and audit bindings and permits only this milestone's validation
documents after the final source freeze. The fetched main merge must have the
same complete tree as the final candidate.

## Preserved unsuccessful attempts

An early formatter preflight ran before package resolution and produced extra
formatting changes. Its complete output is retained under preflight-format/
as superseded; only the incoming declaration wrapping was retained, and the
resolved final formatting gate passed.

The first two-worker Flutter invocation was interrupted by a disk reserve guard.
Its events, receipt and executed runner remain under superseded/, contributing
**zero accepted executions**. The final gate ran all three files with
--concurrency=1 and passed. Preparation also records the bounded downloads and
removal of only newly created, unused SDK history/components and interrupted
compile-cache files. No product test was removed, skipped or weakened.

## Evidence and replay

- [Original publication re-verification](baseline-publication-verification.json)
- [Independent replay of the published complete acceptance](evidence-audit/published-acceptance-replay.json)
- [Combined source review](combined-resolution-source-review.json)
- [Fresh focused receipt](focused/receipt.json)
- [Fresh independent raw-event and identity audit](focused/independent-audit.json)
- [Exact executed focused runner](focused/executed-runner.py)
- [Current-reference reconciliation](current-reference-reconciliation.json)
- [Runtime preparation](runtime-preparation/)
- [Publication and merged-tree verifier](verify-continuation.py)

Executed scripts and receipts retain their original absolute execution paths.
The publication verifier rehashes the recorded current runtime and dependency
paths; it is intended for the reconstructed validation workspace. A later
reproduction needs a separately recorded runtime setup and its own receipts.

## Qualification boundary

This continuation independently qualifies Linux Flutter widgets and synthetic
native fixtures. It does not execute installed macOS/Windows/mobile apps,
native spaCy models or real-provider accounts. Original external runtime files
were unavailable in the fresh workspace: their preserved snapshot consistency
was checked, while the newly reconstructed gate's actual inputs were rehashed.
Incoming author macOS evidence is retained separately with its original scope.

The restore-resume feature's manifest, filesystem, quota and destination-integrity
boundaries are unchanged. See the [complete milestone report](../README.md)
and [archive guide](../../../roadmaps/mail/archive-search.md).
