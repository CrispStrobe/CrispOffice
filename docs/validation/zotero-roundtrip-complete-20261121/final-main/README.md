# Final accepted main integration

The qualified source is
[`a7f69313ed2e610f82242c31be8ad5387ae5cea0`](https://github.com/CrispStrobe/quds_office_suite/commit/a7f69313ed2e610f82242c31be8ad5387ae5cea0),
tree `8f0acd00b505c230ea6ccd2db2d57e17d7475011`. It preserves both parents:
our frozen evidence checkpoint `8407500013cece3978b02c237abd37c93f7a61cf` and
accepted main `aa861c28e336b17bcd4c259351164380cd6b1438`.
The executed local commit `c9709f19a2e6eae03e1114d9e4c254090a1caad6` has the
same complete tree. Only documentation and evidence are added after this
checkpoint. The publication PR records the final main merge and readback.

## Reconciliation outcome

Main completed the previously deferred Word typography work and incorporated
the native Zotero continuation. All production/configuration bytes in this
merged checkpoint match that accepted main. The sole additional Dart file is
our independent `word_page_text_picture_cache_test.dart`.

The incoming typed per-page adaptive-ink snapshot subsumes the preceding
list-based correction, keeps mutable caret changes visible, and invalidates
only the affected page picture. Its additional live overlay-proofing fix is
retained. Both cache regression suites remain present. The merge also keeps
Word's native signed baseline Position propagation, completed native ODT
evidence, all independent changelog entries and both continuation roadmaps.

The unchanged **386-ref publication snapshot** now resolves to **372 actual
ancestors plus 14 independently verified historical equivalents**. Both
formerly deferred PR #336 aliases are ancestors. The original 383-ref intake
remains fully accounted for as 369 ancestors plus 14 equivalents. No captured
work remains deferred; [intake.json](intake.json) supplements the historical
snapshots rather than rewriting them.

## Final renderer qualification

| Suite | Passed |
| --- | ---: |
| Dark-document rendering | 3 |
| Incoming body-text cache | 9 |
| Independent retained/fresh page-text cache | 5 |
| Word positioning | 6 |
| Proofing capture cache | 4 |
| Proofing geometry | 13 |
| Selection painting | 10 |
| Selection-path cache | 1 |
| **Final-source execution** | **51** |

This run passed in one attempt with zero failures/skips/errors and empty
stderr. All **2,676 source/dependency hashes** and local HEAD stayed unchanged.
All 2,675 tracked inputs match the published source's Git blobs; the additional
input is the recorded runtime package configuration. No-write formatting and
fatal-info/fatal-warning analysis passed on the renderer and three relevant
test files. These tests cover direct mutable-caret repaint, entry and exit of
selected/edited states, live TOC proofing removal and position layout/painting.

## Current engine evidence and actual file replay

The incoming [Word qualification](../../word-vba-typography-20261121/README.md)
was independently checked against raw archives and exact Git objects. All
**366 current engine library files** match its source-bound inventories.

| Incoming gate | Recorded result | Final-source applicability |
| --- | ---: | --- |
| Word/native/compiler/layout | 998 passed | Production inputs match; two later test-only edits have recorded followups |
| Incoming ODT/Zotero/Word | 716 passed | Production inputs match, including current image/uppercase/note/table paths |
| ODT style matcher followup | 46 passed | All 980 tracked captured inputs match |
| Position test format followup | 33 passed | Current test hash matches the completed followup |
| Final incoming editor | 75 passed | All 584 tracked inputs match |

These are reused, verified incoming executions, not new runs attributed to
this continuation. Their overlapping counts are not added to its total. The
older 2,698-case engine population remains a historical milestone rather than
an unchanged-source claim for the new Position model.

To exercise the changed native serialization path directly, a fresh bounded
gate reused **22 immutable original/actual-host inputs**, independently matched
to the prior converter archive. It performed:

1. Current native reopening of all four preserved LibreOffice ODT fixtures,
   DOCX save/reopen and editable ODT reexport against the original oracles.
2. One new actual LibreOffice save of all four reexports with an isolated profile.
3. Current native verification of all four new host outputs, preserving **13
   active fields**, native models, metadata and exact ownership.
4. PNG and JPEG host-input verification through three current native DOCX/ODT
   cycles, retaining each fixture's two pictures and two active citations.

All **three Dart commands and one actual host-save command exited zero**.
All 22 reused inputs and **442 captured source/configuration files** stayed
unchanged. The source aggregate SHA-256 is
`ee65ff4fab19cdb71271d6af79bb9239b269a5d58a80785c6bd4221530358265`.
The converter remains LibreOfficeDev 26.8.0.0.alpha0,
build `2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`.
See the [converter summary](converter-summary.json),
[member index](converter-index.json) and [archive](converter.tar.gz).

## Counts, evidence and limits

The [independent accounting](case-accounting.json) derives case identities from
raw events: the 51 final cases overlap the preceding 3,452-case union by 36 and
add 15, producing **3,467 distinct accepted cases across documented checkpoints**.
This does not mean all 3,467 cases were rerun on this final tree.

| Recorded nonoverlapping scope | Distinct cases |
| --- | ---: |
| Native engine milestone | 2,698 |
| Editor/rendering milestones and final gate | 523 |
| Studio Zotero milestone | 41 |
| Mail intake milestone | 205 |
| **Union** | **3,467** |

The [source record](source-continuity.json) separates exact-source final checks,
verified incoming evidence, and earlier source-specific milestones. The
[execution archive](evidence.tar.gz), [index](index.json) and
[verifier](verify_evidence.py) retain raw commands/events, snapshots, independent
hash comparisons and intake proofs. Run from the repository root:

```sh
python docs/validation/zotero-roundtrip-complete-20261121/final-main/verify_evidence.py --repo .
```

For a fresh checkout, fetch the captured branch and PR-head refs listed in the
parent intake records first; the Git proof checks require those historical
objects as well as the main and checkpoint histories.

The initial and intermediate archives are unchanged. Rejected attempts remain
separate and contribute no accepted counts. No GitHub Actions, checks or status
queues were queried or awaited; no force update or protection change was used.

This does not establish installed Zotero/Word plugin acceptance, a supported
stable LibreOffice run, native reopening with active footnote separators,
native layout consumption of preserved table-cell padding, general ODT/RTF
Position interchange, arbitrary ODT fidelity or full plugin parity. The parent
[roadmap](../../../roadmaps/zotero/word-processor-parity.md) retains the next steps.
