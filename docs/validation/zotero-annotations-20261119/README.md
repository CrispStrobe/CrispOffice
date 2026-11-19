# Native Zotero annotation insertion

## Implementation checkpoint

This continuation adds Zotero's **Add Annotation** command to the existing Word
research-note workflow in PR #173. The native ribbon offers **Insert → References
→ Add Zotero annotation**; the Zotero workspace offers **Document → Add annotation
from Zotero…**. It requires Zotero 9 or later.

Selected text annotations, comments, supported formatting and active citations
use the same detached research-content transaction as Add Note. Inline,
footnote and endnote citations retain their document order. Completion applies
one undoable operation; a cancelled picker discards staged preferences and
temporary fields. Direct commands return focus to writing. The command does not
fall back to another picker when an older Zotero version rejects it.

The implementation and focused development checks are complete. **The frozen
98-file local qualification is pending at this checkpoint.** Development checks
are not included in final qualification totals. GitHub Actions have not been
queried or awaited.

## Recent work integrated first

Integration commit `f3b7dc3bf4a994781e40fa89e076ebe485ce3d0d` preserves the supplied
Zotero checkpoint `0abd0e592ad607a88a6a7db6a5bf235939efa5b9` and merges:

- Notes/document review: `840362cd74a3d4b4365cf2bc9a2ae326225009c3`.
- Thesaurus: `7e4adc08fce78fb95524f304962f9c1804e18691`.
- Mail: `086e15b7c059edd09cc77dea721f489b5ef97fa9`, already an ancestor of both.

The bounded inventory contains **391 refs**: 212 fork branches, 175 PR heads and
four upstream branches. The fresh published-head audit verifies **363 ancestors
+ 28 historical equivalents, zero unaccounted refs**, with all 14 historical
proofs recomputed. Historical equivalents remain non-ancestors.

The integration combines the stable Review layout and Notes subtree identity,
document-level Notes keyboard history, composition safeguards and the Zotero
RTL field-reveal regression. Incoming IME tests retain both tracking modes and
undo assertions. The new feature edits began only after integration.

- [Captured remote refs](reconciliation/remote-snapshot-20261119.json)
- [Published integration audit](reconciliation/published-source-audit.json)
- [Fresh-clone replay audit](reconciliation/published-replay-audit.json)
- [Merge-resolution review](reconciliation/merge-resolution-review.md)

## Local runtime and qualification plan

The verified runtime is Flutter **3.47.8** / Dart **3.13.7**. The official SDK
archive and 176 locked Pub archives were hash-checked. SDK-tool and workspace
resolution used `--offline --enforce-lockfile`; all 17 workspace manifest/lock
inputs remained unchanged. The workspace setup receipt names the local
integration commit whose tree is identical to published `f3b7dc3`.

The [plan](plan.json) retains all 98 test files from the preceding qualification,
including Zotero model/controller/widget tests, Notes and Review merge
regressions, Studio routes, thesaurus and Mail integration tests. Strict analysis
and format checks cover 33 targets. The existing
[`run_local.py`](../zotero-word-parity-20261118/run_local.py) verifies committed
clean source, raw test-event accounting, and source/runtime/dependency hashes.
The plan's whitespace baseline is the published integration checkpoint;
integration application/tool whitespace was checked separately against the
user-supplied checkpoint.

## Acceptance boundaries

Text annotation insertion requires a supported collapsed body caret outside an
existing field. Image and ink annotations, embedded images/tables, nested lists,
multi-paragraph list items and unsupported formatting remain atomically refused.
Existing Add Note, citation, bibliography, style and refresh commands retain
their existing behavior and older-version availability.

Qualification covers local model/controller/widget and controlled-transport
behavior, with Quds DOCX save/reopen. It does not establish a fresh live Zotero
session, installed OS shortcut acceptance, or reopening in Microsoft Word or
LibreOffice. The [Zotero guide](../../zotero-support.md) describes the exact
workflow, supported structures and embedding API.
