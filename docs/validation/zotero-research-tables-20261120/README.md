# Zotero research tables — 2026-11-20

## Scope

Continue Word/LibreOffice Zotero workflow parity by preserving bounded rectangular research-note and annotation tables as native Word structures. Add Note and Add Annotation retain active citations, rich cell content, lists, pictures, widths, fills and source order. Main-flow body and authored-note destinations retain surrounding prose, automatic note markers and a paragraph/caret after a trailing table. Application remains atomic and undoable.

The supported envelope and explicit refusals are documented in [Zotero support](../../zotero-support.md#tables-in-notes-and-annotations). Merged/nested tables, broader text selections, additional JPEG forms, active ODT transfer and live target-application acceptance remain separate work.

## Incoming work and remote preservation

The initial intake captured 18 fork heads, the 100 most recently updated pull request records and four upstream heads. [incoming-intake.json](incoming-intake.json) preserves the snapshot and historical equivalence references. All five recent divergent initial heads were reconciled with ancestry: Downloads `84d02025`, Mail accounts `a059c024`, selected credential stores `95bf6340`, parallel Downloads `4f5c1537` and incremental layout `d661e024`.

Later remote main `7e740a53` and the updated layout head `e6f70bff` were incorporated at `ab8d42ec`. This also incorporates the later Mail reply/forward and VBA ancestry that had entered main. The bounded follow-up and exact resolutions appear in [incoming-followup-review.json](incoming-followup-review.json) and [incoming-final-review.json](incoming-final-review.json). Older review records remain historical evidence of their own checkpoints.

The preserved remote branch is `codex/zotero-research-tables-20261120`; review is [PR #249](https://github.com/CrispStrobe/quds_office_suite/pull/249). Successive checkpoints preserve intake, implementation, review corrections, formatting and later incoming reconciliation. No GitHub Actions runs, statuses or queues have been queried or awaited.

## Review corrections

- Keep the canonical bounded account catalog and all-backend readback verification while binding queued operations to the selected credential-store revision. Once begun, each transaction uses one captured backend.
- Retain the incoming layout fix that adjusts carried line/frame prefix counts after splicing, and keep the original two regression cases.
- Invalidate paragraph break caches when dirty, empty or shaped around a wrapping frame. A later unwrapped layout must not resurrect earlier text.
- Bind incremental layout state to its producing engine. Foreign font/measurement state falls back from the first section.
- Request a frame when the trailing Word chrome timer expires while idle, so the post-frame refresh can execute at 400 ms.

Source review is recorded in [incoming-final-review.json](incoming-final-review.json) and [independent-source-review.json](independent-source-review.json). Source review alone is not counted as execution.

## Validation in progress

The original sandbox exhausted shared disk space before it could launch commands. The automatic approval review rejected a sandbox escalation to remove a disposable task file. Work continued through remote Git checkpoints. A recovered, isolated workspace then provided enough capacity for genuine Dart and Flutter runtimes.

The runner verifies the official Dart 3.13.7 and Flutter 3.47.8 distributions and uses locked genuine package sources, assets and native hooks. Early diagnostic runs surfaced a missing required property in one new marker fixture, corrected at `71243862`. The parser/Add Note diagnostic completed 104 visible cases. The Flutter Add Note/controller diagnostic completed 92 visible cases without assertion failures but returned a compiler-process error; it is **not an accepted successful gate**.

Final source formatting, isolated negative controls, complete engine/editor cohorts, incoming reconciliation checks and source-hash continuity are still being recorded. This section will be replaced by the final source-specific results before merge.

## Acceptance boundary

No live Zotero, Word, LibreOffice or Apache OpenOffice application round trip has been performed for this increment. Controlled native-protocol fixtures, engine DOCX serialization/reopening and real Flutter widget/controller tests do not establish that interoperability. Current Zotero supports Word and LibreOffice; any historical Apache OpenOffice plugin must be qualified separately with explicit versions. See the [parity roadmap](../../roadmaps/zotero/word-processor-parity.md).
