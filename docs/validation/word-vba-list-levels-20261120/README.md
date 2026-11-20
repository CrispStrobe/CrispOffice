# Word VBA outline and list levels — accepted engine checkpoint

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

## Implemented increment

Adds bounded `ListFormat.ApplyOutlineNumberDefault`, write-only
`ListLevelNumber`, `ListIndent` and `ListOutdent` to explicitly selected body
paragraphs. New native operations resolve the selected numbering instance
and levels, preserve existing definitions and unrelated XML, and reject
unsupported or ambiguous sources before mutation. Existing typed aliases,
helpers, `With`, native policy checks and detached publication apply.

The frozen Word source at `3c87debcd4d50cac88981ec39255c3c6890fe8fa` has passed
2,569 regression cases across 70 modules (zero failures/skips), strict whole-engine
analysis, formatting of all 9 changed Dart files, and exact-BAS VM/JavaScript
comparison with byte-identical 1,553-byte output. Independent evidence review
accepted the raw events, all 1,123 source input identities, and recorded runtime
bindings. The complete raw final Word records are preserved in
[word-gates-checkpoint.tar.xz](word-gates-checkpoint.tar.xz); the
[indexed checkpoint](word-gates-checkpoint.json) records their exact scope.

Final reconciliation and publication remain in progress. Concurrent Mail PR #262
at `2d3799af` preserves all qualified Word inputs but documents two pending Mail
corrections. Its captured history remains available and will be reconciled at
a corrected head before main publication. This engine gate does not qualify
Mail/provider/Flutter runtimes.

GitHub Actions, workflow runs and status endpoints are neither queried nor
awaited. Remote branch checkpoints are published through the connected GitHub
API because the local clone has read transport but no push credential.
