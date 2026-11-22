# Zotero parity continuation — 22 November 2026

## Baseline and preservation

Work starts from remote `main` at
`c522851d165b395a7f60422a1be969dffc39c9ff`, including PR #353.
The initial [ref inventory](intake.json) records all fetched fork branches,
353 fork pull-request heads, upstream branches and upstream pull-request heads.
Every fork/upstream branch captured at initial intake is already an ancestor
of this baseline.
There were no open fork PRs at intake. The independent
[historical equivalence audit](historical-intake-equivalence.md) accounts for
every captured ref: 366 direct ancestors, 13 identical-tree replacements and
one replacement with identical entries on all 37 original changed paths.
All 14 replacement commits are ancestors of this baseline. There is no
uncovered historical work to replay.

All implementation checkpoints are retained on
`codex/zotero-parity-20261122`. The
[publication map](checkpoint-publication.json) verifies identical local and
remote trees and ordered parents for each recorded checkpoint. Remote updates use an
expected head and never force a ref or delete a branch. GitHub Actions, check
statuses and their queues are not queried or awaited.

## Delivered behavior

Previously, a Refresh that expanded a citation before the caret could leave
the next keystroke inside the citation. Bibliography growth could move a
numeric paragraph index into a different paragraph, and applying an update
collapsed a deliberate selection. Notes selections could likewise drift or
retain a removed note.

The native session now captures writing endpoints by original paragraph
identity and transforms offsets through actual citation replacements,
deletions and supported note conversions. The controller resolves both body
selection endpoints and both active Notes endpoints before publishing the
detached result. It records the original and transformed selections in the
same undo command as the document update.

- Unaffected prose retains its writing position after multiple earlier fields
  expand, contract or disappear.
- Bibliography growth/shrinkage preserves subsequent paragraph identity.
  Passive frame and generated table-of-contents positions also survive;
  this does not enable active Zotero fields in those stories.
- Forward/backward body selections retain their endpoints. Notes selections
  also retain affinity and direction across their visible paragraph separators.
- Metadata-only and identical-visible-text updates preserve interior offsets.
  For changed field text, an exact start stays before it; an interior or ending
  endpoint follows the replacement end. Replaced bibliography-owned positions
  use the corresponding start/end boundary.
- A removed or converted sole-citation note returns its position to the body
  anchor, accounting for the actual marker length. Detached note targets are
  not retained.
- Undo restores the exact original selection; redo restores the mapped one.
  New citation/research insertion retains its explicit insertion destination.
  Cross-processor transfer retains its existing separate destination policy.
- `Document.canInsertField` accepts both documented/accepted driver forms,
  with or without the explicit `Http` argument. Unsupported explicit field
  types remain rejected. Two complete protocol replays cover driver-to-adapter
  agreement.

The engine API is `capturePosition(paragraph, offset)` followed by
`resolvePosition(token)` after successful application. Tokens belong to one
session and are bounded to eight endpoints; the controller uses at most four.
They are transaction results, not durable positions to retain across later
document edits.

## Local validation

The official repository-pinned Flutter **3.47.8** and bundled Dart **3.13.7**
were installed from the verified release archive. Workspace resolution used
`--enforce-lockfile`; all 22 captured manifests and the root lock remained
unchanged. See the [runtime provenance and commands](checks/runtime/README.md).

The initial editor control reproduced **16 failures and 5 passes across 21
cases** with the original controller and candidate engine. The same behavioral
expectations passed after controller integration. Later cast cleanup changed
types only; the exact original test source was reconstructed and its SHA-256
matches the baseline receipt. This is explicitly not an untouched-main test
run. The final editor test adds three passive-position integration cases.

The first broad editor attempt exposed two failures: endpoint capture ran
before the existing stale-note `StateError` check, and the new TOC-item fixture
retained a paragraph that controller initialization replaced. The controller
now checks `session.assertUnchanged()` before capturing endpoints, preserving
the existing error contract. The fixture now targets a real generated TOC item.
Both affected files then passed all **57 cases** (24 writing-position cases
and 33 existing note-target cases). The original 978-pass/2-failure broad
attempt is preserved and receives no credit in the accepted aggregate.

| Gate | Scope | Result |
| --- | --- | --- |
| Focused engine position/HTTP contracts | 38 cases | Pass; included in the broad engine total |
| Focused editor before final passive cases | 21 cases | Pass; included in the broad editor total |
| Broad engine Zotero regression | 56 files | [1,494 passed](checks/engine-zotero-receipt.json); no failures/skips |
| Broad editor Zotero regression | 53 files | [980 passed](checks/editor-zotero-final-receipt.json); no failures/skips |
| Studio native transport, shortcuts, ODT and host ownership | 4 files | [55 passed after PR #356](checks/studio-zotero-main356-receipt.json); no failures/skips |
| Changed Dart source/tests | 5 files | [Strict analysis clean](checks/analysis-main356-receipt.json); [format changes zero files](checks/format-main356-receipt.json) |

The accepted broad cohorts contain **2,529 distinct passing cases across 113
test files**, with no failures or skipped cases. The 38 new engine cases and
24 new editor cases are included in those totals. Baseline, focused and failed
attempts are retained separately and are not added to that count.
The [independent aggregate](checks/aggregate-receipt.json) verifies every raw
event stream, complete lifecycle, selected suite, case identity and recorded
hash. Its [accepted case list](checks/accepted-cases.json.gz) excludes 127
successful loaders/hooks and does not credit repeated executions.

The source-bound [runner](checks/run_local_checks.py) retains exact commands,
raw compressed events, test identities, source/test/fixture/dependency/runtime
fingerprints and before/after equality. Suite loaders and fixture hooks are
excluded from substantive counts. Focused and repeated executions are not
added to the broad total. Original failures/setup attempts remain separate
from accepted results.

## Concurrent integration

While qualification was running, main advanced through Mail PR #354 to
`bcc55cb6e86e796056e2d75c3fdca50857dbf6e7`. Its 20 commits and all 19 changed
paths were merged without conflict and preserved as an ordinary parent of
published checkpoint `d1c9673c7caa24a3dc41f9255d2916846d6cdbaf`.
Every incoming file matches main exactly. No Zotero engine/editor code,
standalone tests or dependency manifest changed in that merge.

Main subsequently advanced through completed Word VBA PR #355 to
`ceddcd888c37f64e37a8d8d1669daaea31384daf`. Its seven incoming commits and 73
changed paths are retained in published merge checkpoint
`d4b4392fe538473a3accd15294288347e8bc2b56`. The sole merge conflict was the
engine changelog; both feature entries were retained. All other incoming paths
match that main exactly.

The engine's 1,494-case run precedes both main merges. The
[final carry-forward proof](checks/engine-zotero-carry-forward-final-receipt.json)
compares every captured input and recomputes the actual import/export/part
closure from all 56 test files. All **1,347 files** in that closure, all 8,634
dependency inputs, all 1,127 SDK inputs and both resolved configuration files
remain identical. The complete input delta is exactly the incoming Mail/VBA
files and the two controller/test fixes; the imported engine test inputs are
unchanged. The 1,494 passes are carried once, without claiming another execution.

The final editor and Studio cohorts run after both integrations and the fixes.
Studio compiles the incoming Mail chain; those Zotero/host cases do
not qualify every aspect of the new Mail or VBA features. Their own upstream
qualification remains separately attributed.

The first integrated Studio attempt exposed a missing direct import in the
incoming Mail cached-search dialog. Eighteen transport cases passed, but the
other three suites could not compile because `StudioMailMailboxStoreOwner`,
`StudioMailSyncStore` and `StudioMailMailboxStoreException` were not visible.
The first repair added the direct `studio_mail_mailbox_store.dart` import;
the retry exposed an interface-access compile error. The final repair adds
explicit typed access after the existing interface guards. That module was
already in the dependency graph, so these changes add no platform dependency.

Strict analysis of all five changed Dart files also identified two diagnostics
in the incoming method: the context-use check needed an explicit `mounted`
guard, and the coverage label needed string interpolation. Both were corrected
without changing the existing lifecycle policy or label text, and the official
formatter normalized the incoming method. Both failed Studio attempts and the
failed static attempt are retained and excluded from accepted results. The
qualified Studio retry and five-file static gates cover the repaired source;
engine/editor attribution explicitly accounts for this example-only change.
The intermediate repaired production source is published at
`99a285c07ad2c08999ae64a68785376123bed4f3`. The subsequent completed Mail
reconciliation below supersedes that dialog implementation; the intermediate
repairs and all of their evidence remain in the retained history.

The [concurrent intake](concurrent-intake.md) and its
[PR #355 addendum](concurrent-intake-355.md) record the branch activity at their
captured timestamps. Their outstanding-Mail disposition is historical and is
resolved by the final integration below.

### Final reconciliation with Mail PR #356

The [final intake addendum](concurrent-intake-356.md) records the exact branch,
commit, path and import-graph evidence for this integration.

The last pre-merge remote check found completed Mail PR #356 at
`82659acb0f617c57d4d241c91033338032b5caac`. That PR incorporated this branch's
Zotero implementation and stale-state guard through checkpoint
`3660a9d94e3100885e61b244f9dba7bdc5403cfb`. The engine, controller and both new
Zotero test files are byte-identical to the previously qualified source.

Its new Mail dialog replaces the old inline store-owner loop with a folder
catalog session and a dedicated picker, includes an explicit mounted guard,
and renders missing-folder coverage separately. The only merge conflict was
resolved by retaining that completed incoming dialog exactly. The old direct
import and casts are unnecessary because their code path no longer exists;
they were not reapplied over the newer implementation.

Published integration checkpoint
`fce7a97f297181f3524b31e90e7a49ce061b0954` has the **same complete Git tree** as
remote main `82659acb0f617c57d4d241c91033338032b5caac`:
`3a728f96ac95588e45c9ab0c7d12e0881f702783`. Every incoming file is preserved.
All 19 other fork branches and four upstream branches captured by the final
audit are now ancestors of main; no open PR remained at that observation.

The engine/editor results are attributed through unchanged import closures of
1,347 and 2,221 files respectively. Studio imports the newly reconciled Mail
code, so its four suites and the five-file static gates were re-executed and
passed on this combined source. All 16,096 captured inputs remained unchanged
during each final gate. Repeated Studio executions do not add to the 2,529-case
aggregate. The [final source attribution](checks/main356-source-carry-forward-receipt.json)
binds the accepted execution inputs to this integration checkpoint. The final PR publishes the
completed qualification record and retains this branch's remaining checkpoint
history; the implementation is already present in main through PR #356.

The final publication check also incorporated documentation-only Mail PR #357
at `171be42cf92ce875b7d5f6f3df216ff04d0204c5`. Its five changed paths only add
reconciliation evidence and preserve later checkpoint ancestry. The
[final remote intake](final-remote-intake.json) verifies that every runtime,
test, dependency and configuration path remains unchanged, so the accepted
qualification carries without another test execution.

## Remaining parity work

This completes a native writing-position and protocol-compatibility increment,
not full Word/LibreOffice plugin parity. The next everyday native-host gaps
are visible `Field.select` context during Zotero's repair/manual-edit prompts
and a structurally safe malformed-field recovery contract. The wider
[parity roadmap](../../roadmaps/zotero/word-processor-parity.md) retains content
and cross-application boundaries.

No installed Zotero, Word or LibreOffice acceptance, native release build,
or legacy Apache OpenOffice qualification was executed here. Those gates
need identified application/plugin versions and real host workflows. Local
protocol, model, controller and widget tests remain separately attributed.
