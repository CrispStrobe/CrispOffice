# Word VBA paragraph list formatting

## Incremental checkpoint

Work begins at `79e11935e16ea1d2fa576ead0712c83f22e15c28`, preserving remote
main `5c48058bedc42dd8cbf3fb9d6f1fb492b2ac1eb8` and the subsequent Zotero test-name
disambiguation. This working branch is saved incrementally; the initial compiler
checkpoint is not a claim of completed native implementation or validation.

The planned bounded extension adds typed `Range.ListFormat` selectors,
`ApplyBulletDefault`, `ApplyNumberDefault`, and `RemoveNumbers`. Matching list
types must toggle off at native execution time. New lists use Quds's deterministic
default scheme; customized Microsoft Word galleries and live document reads
remain outside this adapter.

## Initial source intake

The [capture](initial-capture.json) records 19 fork branch heads, 257 PR heads,
and four upstream heads. The [recomputed audit](initial-intake.json) accounts for
every captured head through ancestry or an explicit historical equivalence, with
zero uncovered heads. The 14 historical equivalences comprise 13 identical full
trees and the exact 37-path ODT continuation equivalence. All accepted equivalents
are ancestors of the intake head.

The [integration review](integration-review.json) confirms that the sole net
change since captured main is clearer labels in one Zotero editor test file.
The complete prior Word qualification input selection (1,110 paths and their
mode/type/blob identities) remains equal at the intake head. This is an input
identity check, not a fresh runtime validation of the new work.

GitHub Actions, workflow runs and status checks are neither queried nor awaited.
Local execution and final source reconciliation will be recorded before merge.
