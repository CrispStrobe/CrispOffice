# Office integration resume — 17 November 2026

This continuation resumes the unfinished combined Office, Zotero and proofing
qualification. It preserves the existing incremental history and uses a bounded
incoming snapshot so validation can bind to a stable source.

## Fixed incoming snapshot

`incoming-inventory.json` records remote refs observed between
2026-11-17 15:37:31 and 15:37:41 UTC. The fork read completed at 15:37:37 UTC.
The snapshot contains 289 references: 132 fork branches, 109 fork PR heads and
21 fork tag refs; four upstream branches, four upstream PR heads and 19 upstream
tag refs. Tag records retain their exact remote object IDs; the classification
also records each resolved commit and whole-tree identity.

The original continuation is `555eb728ce3ea872cb5ceb3e5fd2104b21f932aa`.
The selected incoming heads are:

| Source | Captured commit | Intended reconciliation |
| --- | --- | --- |
| German GECToR feature | `8801031a5c031ad5872f0e41ec182576ae8d4872` | Fast-forward base; includes original continuation and morphology |
| German morphology | `7808a8711c91d721e8bb2b7034349008be80895b` | Already ancestor of the feature head |
| Office fidelity | `cf60a17bcd825dc9b4ecdf840d54e6a0271d3647` | Integrate section/list/RTL and text-box extraction corrections with all evidence |
| Fork main | `379d3c8e5e46afb806f9ac181bc814288c9c8893` | Integrate landed ODT/ODP hyperlinks and document metadata |
| Vendor metadata mirror | `3a5cacc12c23e577903dcb6d9eba085da6e205a9` | Reconcile its history after proving represented source and retaining evidence differences |

`initial-ref-classification.json` records ancestry or exact whole-tree witnesses
for every captured ref against the original continuation and the selected union.
The two unresolved union refs are the vendor metadata mirror and its ODP-link
ancestor. Their histories must be reconciled explicitly; no source-equivalence
check is counted as whole-tree equivalence.

## Checkpoint status

This first checkpoint fast-forwards to the existing feature head and saves the
incoming inventory before merge changes. It adds documentation only to that
head. The following source checkpoints will record conflict resolutions and
source-preservation checks here. Incoming qualification evidence keeps its
original source attribution. Fresh combined-source runtime qualification is
pending at this checkpoint.

No GitHub Actions, workflow, check-run or CI-status endpoint was queried or
awaited. All local commits use `[skip ci]`; remote checkpoints are published
with an expected-head update.

## Integrated source checkpoints

The inventory checkpoint was published as
`9d057dfdd483e7e9c194c5b11baa2d5c1fe4c6c7`. The fidelity merge was
published as `a499549e184069e33234bd0304417fb0fefb8ca1`; its exact
writer combination and test relocation are recorded in `fidelity-merge.json`
and `fidelity-writer-combination.patch`.

The next combined checkpoint adds captured main and the vendor metadata
history as explicit parents. `main-and-vendor-merge.json` records its sole
test conflict and preservation decision. `vendor-equivalence.json` proves
the mirror's complete production tree equals captured main, while retaining
the current Zotero evidence and archiving the incoming README.

`final-ref-audit.json` accounts for all 289 captured refs using ancestry or
exact whole-tree witnesses in the combined checkpoint's parent closure.
All 14 preceding section cases remain executable in
`odt_section_continuation_test.dart`; the incoming section suite remains in
`odt_section_fidelity_test.dart`. The former's old source is also retained
verbatim for review. The section contract now applies the boundary to the
first supported owner: table, list paragraph, frame container or nested
control content. Equal continuous layouts reuse their current master.

Fresh runtime qualification of this combined source is still pending. The
formatting operations and source review recorded here are not substitutes
for those runtime checks; previous evidence remains attributed to its
original immutable source.

## Bounded destination-main amendment

The merged source was published as
`b32dee6f1fb6993c928a466b553226209cf27fb8`. The next checkpoint,
`104b239c971ef3b2d62495a27ad04b519398a1fc`, made four test files conform to the
resolved Dart 3.12 formatter after the first broad run stopped at formatting.
Its production source is unchanged.

Opening draft PR #113 revealed destination main
`7cf48a2f7b73aafb8bd2019bda4e0ddc6698f9ad`. This exact observed commit is the
only addition to the bounded incoming set. The amendment merges it as an
explicit parent and preserves its historical evidence and ONNX diagnostic tools.
No additional remote-ref refresh or CI-status query was performed.

`destination-main-amendment.json` records the source delta and conflict
resolution. The sole library change relative to the prior published checkpoint
is the ODT writer: incoming PAGE fields, paragraph fills and borders, plus a
confirmed fix to paragraph-style cache identity. The cache includes the same
lower-case fill/border strings that XML serialization uses, treating null and
empty as the same absence. The incoming writer emitted those properties while
omitting them from the cache key, so otherwise-equal paragraphs could acquire
each other's decoration. The exact correction from incoming main is retained
in `paragraph-decoration-cache.patch`. The ODP test remains byte-exact to the
prior published version, retaining both its hyperlink and SMIL checks.

The new two-case regression checks red/green color independence, normalized
color reuse, null/empty absence, the other decoration's absence, paragraph text
and unchanged model properties. Identical final test bytes pass both cases with
the corrected writer and fail both by matcher assertion with the exact incoming
writer. The two earlier setup failures are preserved separately and excluded.
`cache-control-evidence.tar.xz` and its index retain all logs, runner code, source
bindings, package graphs, runtime hashes and the dependency map. All 43 archive
members were read back and hash-verified. The sole between-variant source change
is the writer; all 399 input files per variant and 5,099 dependency files stayed
unchanged during execution.

`canonical-controls-evidence.tar.xz` and its index also preserve the recovered
annotation/comment-note controls. The positive annotation suite has 11 passes;
the old-source suite has six matcher failures, the specific hidden-annotation
content-limit exception and four passes. Both positive note cases pass and both
old-writer note cases fail by matcher assertion. No cases are skipped and no
load failures are accepted. The original overstrict wrapper rejection and its
narrow follow-up log verification are both retained without rerunning or editing
the tests. All 38 archive members were read back and hash-verified.

These controls do not replace the broad immutable-source run, which remains
pending publication of this amended checkpoint. Imported diagnostic model
evidence retains its original input and runtime attribution.

## Isolated reconciliation of concurrent source

The destination-main/cache amendment was published as Git commit
`cc394ee2b8468d543ecd0b3ff1bc7f8ac10fd270`, with the same tree as local
`e013c43dd5c81bda37e686c9716101af264a525b`. Its expected-head branch update
correctly refused to overwrite concurrent continuation work. The candidate is
therefore on `codex/office-qualified-resume-20261117`, associated with draft
PR #116.

Before the final source freeze, two exact observed commits are incorporated as
additional parents: concurrent continuation
`f29373cf29048a6a6b133e2e75628d58c4b2b23f` and destination main
`2eb080e708257c36b54d3ade18b9e012ebc73ed3`. No other incoming head is refreshed.
`concurrent-source-reconciliation.json` records these observations, complete
source combinations, preservation checks and the limited test adaptation.

The concurrent source adds structured ODF frame tables and visibility guards,
an empty body for explicitly zero-section documents, German quotation casing
and three lexical forms. The later observed main adds ODT table borders and row
heights. Our paragraph decoration cache fix, its exact regression and both
control archives remain intact. The only textual conflict combines both sets of
CHANGELOG entries. All three section suites are retained; one existing
continuation case now asserts the incoming empty-body contract while retaining
all master/page geometry and model-immutability assertions. Its preceding source
is preserved under `incoming`, alongside the concurrent writer and exact patches.

The compressed first-party German supplement grows from 205 to 208 forms:
`Grüezi`, `Hof` and `grüezi`, with no removals. The morphology manifest remains
unchanged and continues to identify its original, earlier spelling inputs.
This integration does not regenerate or reattribute that morphology output.
The current lexical manifest identifies its updated supplement separately.

All incoming evidence outside this continuation report is byte-exact to the
captured concurrent commit. Those reports, model measurements, consumer checks
and native runner receipts keep their original source/runtime attribution; they
are not fresh evidence for the combined candidate. The two retained control
archives have unchanged bytes. Their indexes now explicitly record each tar
root prefix for unambiguous independent readback.

The broad runner's existing scope selects the four new suites automatically,
for an expected 179 unique test files. Fresh qualification remains pending the
published immutable combined checkpoint.
