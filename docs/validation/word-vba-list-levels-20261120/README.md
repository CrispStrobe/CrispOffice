# Word VBA outline and list levels — work in progress

Working branch: `codex/word-vba-list-levels-20261120`.

## Reconciled starting source

The supplied baseline `acca1cbcba2a322ad1ae2d7d9fb415110ce22554` is preserved.
The latest captured Mail/Word continuation at
`46e98c8c7ec65e67e8f71dc386804693e8ef1163` is a descendant and was integrated
before implementation. Its Word namespace, numbering-suppression and style
projection preservation fixes and six regression cases remain included.

The initial audit accounts for 21 fork branch heads, all 260 existing PR heads,
and four upstream heads. Thirteen exact full-tree equivalences and one exact
37-path continuation equivalence account for historical heads whose changes
were already incorporated. See [initial-intake.json](initial-intake.json) and
the reproducible [audit script](audit_intake.py). No captured head is uncovered.

## Intended increment

Add bounded `ListFormat.ApplyOutlineNumberDefault`, write-only
`ListLevelNumber`, `ListIndent` and `ListOutdent` to explicitly selected body
paragraphs. New native operations will resolve the selected numbering instance
and levels, preserve existing definitions and unrelated XML, and reject
unsupported or ambiguous sources before mutation. Existing typed aliases,
helpers, `With`, native policy checks and detached publication apply.

Local compiler, native preservation, integration, VM/JavaScript and regression
qualification will be recorded here after execution. No passing validation is
claimed by this initial checkpoint. Incoming Mail/provider/Flutter work keeps
its separate qualification scope.

GitHub Actions, workflow runs and status endpoints are neither queried nor
awaited. Remote branch checkpoints are published through the connected GitHub
API because the local clone has read transport but no push credential.
