# Final intake reconciliation at source D

The published source checkpoint is
`192ea2aedbf0b1494627953c79a7042037a63301`, with tree
`1b8e807cd76f2bbc599780170d2a2e993ea4da62`. This report concerns source inclusion,
merge decisions, and exact Git object comparisons. Runtime qualification is
recorded separately; this report makes no final passing-test claim.

## Captured work and preserved history

The final branch/PR intake cutoff is **2026-11-20 13:14:35 UTC**. The
[immutable cutoff inventory](final-cutoff-inventory.json) records 16 live fork
branches, 249 PR heads, and four upstream heads. The Git branch capture matched
the independently read GitHub branch API response. GitHub Actions and check
queues were not queried or awaited.

The earlier capture contained 24 branches, 249 PR heads, and four upstream heads.
Nine branches have since been deleted and one Outbox branch was added. All nine
deleted captured heads remain ancestors of D. Five advanced branch refs and
three advanced PR refs also retain their earlier captured heads. The previous
24/249/4 inventory is checked independently against D, rather than being
silently replaced by the smaller live branch list.

The [final inclusion receipt](final-cutoff-inclusion.json) establishes:

| Captured set | Ancestors of D | Historical equivalents | Uncovered |
| --- | ---: | ---: | ---: |
| 16 live branch heads | 7 | 9 | 0 |
| 249 current PR heads | 235 | 14 | 0 |
| Four upstream heads | 4 | 0 | 0 |
| Nine deleted earlier branch heads | 9 | 0 | 0 |

All 14 historical equivalence proofs were recomputed from local Git objects.
Each verifies the accepted commit's ancestry and exact mode, object type, and
blob identity for every changed path. Thirteen also have identical complete
trees. The ODT continuation proof covers its 37 changed paths; it does not claim
complete-tree equality. The nine equivalent live branches are a subset of the
14 historical PR proofs.

D preserves the C9 qualification source
`c9cbeb1248d6b5f088d1084a8c113a743aa7a77f` and all four final incoming heads:

| Incoming work | Exact head |
| --- | --- |
| Captured main, including completed PRs 247 and 248 | `b42eca1db058f0def247b86c2f15dea90c11b4e8` |
| Mail account backend and host-boundary guards | `625f4d76d10ddf2144220f25ae8d867452eeed61` |
| Durable Outbox and explicit uncertain retries | `bda00b32911bcab4e748851d89af0dbdfc886d39` |
| Zotero tables, layout ownership, and selected-store concurrency | `2d617a31bce48a7312f31586f70f7472e3420406` |

The branch/PR cutoff is fixed. Later main advances, if any, require a separate
consistency observation and reconciliation before the final main merge.

## Source changes and conflict decisions

Compared with C9, D changes 92 paths. Eight belong to the recorded Office engine
input union; the other 84 are separately listed in the inclusion receipt.
Every changed entry records its before/after mode, object type, Git blob, and
SHA-256. The receipt also independently hashes all 1,164 target input entries;
1,156 retain their exact C9 entry and bytes.

The eight changed engine inputs are the engine changelog, the PowerPoint model
and DrawingML reader, both Word layout modules, the slide inset preservation
fixture, the incremental Word layout fixture, and the Zotero aggregate test
driver. Their exact paths and object identities appear in `engine_delta` and
`gate_input_delta` in the inclusion receipt. Validation must account for these
changes; the old C9 receipts cannot be presented as a complete D run.

The PowerPoint correction records the imported direct text margins in
`PmlTextSource`. An untouched imported margin is now compared with that source
baseline when deciding whether an edit was authored. Explicit same-value
assignments still retain their override mask. Three added regression cases
cover replacement text with imported nondefault margins, direct scalar margin
edits, explicit same-value edits, PDF placement, copying, and repeated saves.

The Word merge retains the C9 dirty/full-layout cache invalidation, the incoming
frame-wrap invalidation, and the checkpoint prefix-length guards for both lines
and frames. It also accepts the incoming engine identity on incremental states,
rejects reuse from another engine in incremental and ordinary section fallback,
and retires an obsolete cache on the empty-paragraph path. All three newly
incoming incremental regression cases are preserved. The existing two-case
prefix fixture is unchanged. The two Zotero table fixtures retain C9's strict
analysis corrections; the incoming alternatives changed only equivalent string
construction and would have reintroduced analysis information diagnostics.

The editor resolutions combine the Mail account and Zotero behaviors. The
credential manager retains the injectable system-store factory and generation
guard against a slow old initialization replacing a newer store. Its public
selection revision uses that same generation, so both protections observe one
successful selection commit. The already-loaded fast path and queued account
operation fences remain. Custom-keychain selection checks the actual native
host. The fixture retains the separate mocked native-adapter denial check and
the platform-specific options assertions.

The native Mail host retains both the external selection listener/reload flow
and the injectable credential-settings opener. Its Outbox submit, dialog, and
send method bodies are identical to the captured Outbox head. The external
store listener and reload method bodies are identical to the captured Zotero
head. Both changelog additions and the merged six-case credential-selection
fixture remain present. These comparisons are source review, not Flutter test
execution.

## Main inclusion and qualification limits

The [D main inclusion proof](final-cutoff-main-review.json) verifies that captured
main `b42eca1d` is already an ancestor of D. A standard Git object-only prospective
merge of D with that main head returns D's exact tree: zero changed paths and
zero changes to its 1,164 recorded input entries. A direct comparison of the two
snapshots differs in nine input paths; the proof explicitly records that fact.
The zero-difference statement applies to the prospective merge result, not to
the main snapshot itself.

The earlier [C9 inclusion receipt](qualified-source-inclusion.json) and
[C9 main review](final-main-review.json) remain unchanged historical evidence.
The C9 run exposed an imported-margin baseline regression before the D
correction. Earlier cache failures and partial runs retain their original
source identities and cannot be relabeled as final-source passes.

Newly integrated work-in-progress Outbox code in Mail core/store and the Flutter
host workflows are outside the Office engine qualification gate. Their incoming
logs and claims remain historical evidence for their own source snapshots.
No new Flutter UI, native keychain, live mail provider, installed Microsoft
Office, or Zotero application execution is established by this reconciliation.
Final runtime totals and any retained-versus-rerun qualification must come from
the separately verified final manifests and raw test events.
