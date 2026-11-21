# Word VBA sections: remote intake

The initial fork snapshot is `CrispStrobe/quds_office_suite` main
`84046975f286407e3c62e5e5352bc16bc89c0d26`. Before new Word macro edits, the
feature branch `codex/word-vba-sections-20261121` starts at
`2cd11ced136a30354169fd0043e002079bcabfa3`, preserving the three newer commits
shared by `perf/keystroke-trace-20261121` and
`work/mail-repository-sessions-20261121`.

## Snapshot and inclusion

The GitHub branch and pull-request collections were read to exhaustion for the
fork and `MohammedAsaadAsaad/quds_office_suite` upstream. The fork PR pages
contained 100, 100, and 83 records. No fork or upstream PR was open. The latest
fork PRs #281 (Word section PageSetup), #282 (Mail uncertain-action recovery),
and #283 (Zotero paragraph-range integration) were already merged into main.

| Captured category | Total | Ancestor of initial main | Verified historical equivalent | Included at feature start |
| --- | ---: | ---: | ---: | ---: |
| Fork branch heads | 44 | 32 | 10 | 2 |
| Fork PR heads | 283 | 269 | 14 | 0 |
| Upstream branch heads | 4 | 4 | 0 | 0 |
| Upstream PR heads | 4 | 4 | 0 | 0 |
| **Total** | **335** | **309** | **24** | **2** |

[intake-inventory.json](intake-inventory.json) retains every captured name and
head SHA, the exact replacement commits for historical equivalents, fresh
verification results, and the three newly included commit identities. The two
incoming branch heads identify the same commit, so they require one inclusion.
There are no uncovered heads in this initial snapshot.

Historical replacement mappings come from the previous section-PageSetup
intake, but their proofs were recomputed from local Git objects for this work.
Every replacement is an ancestor of the captured main. Complete Git tree
identities match for 14 unique replacement pairs; all 37 changed ODT paths
match for `c3494576` and its replacement `2c47165d`; the three-file
`ec70b942` / `e975cec1` patch has identical before/after entries and changed-path
sets. `git cherry` independently reports the ODS feature/docs branches and
`integrate/recent-pptx` as patch-equivalent. Reapplying those old patches is
unnecessary and would risk disturbing newer behavior.

## Newer commits retained

The included tip is a strict descendant of captured main, with no divergence:

1. `1a854c9f5abb1a23a74dcc3d5418900ae8a5d09c`: keystroke trace hooks,
   profile-mode typing integration test, report tooling, and workflow.
2. `48f4792a48361d84cc7261d9732d8ad85450379f`: push trigger for the trace workflow.
3. `2cd11ced136a30354169fd0043e002079bcabfa3`: mark a replaced document's layout
   stale and recompute on its next layout read; refuse incremental page reuse
   across different document identities.

These changes span eight files and include editor/layout behavior as well as
performance instrumentation. Their original commits and ancestry are retained.
The Word macro extension must preserve this baseline when modifying shared
engine code.

## Scope of this record

This intake establishes source inclusion, not fresh execution of historical
tests. New runtime and portable validation belong in the feature acceptance
record. GitHub Actions, workflow-run queues, and check statuses were not queried
or awaited for the audit. No repository policy was changed. Main and active
branches must be refreshed before final publication to reconcile later work.
