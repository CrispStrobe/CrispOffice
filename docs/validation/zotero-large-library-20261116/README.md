# Zotero large-library refresh and collection pagination

## Qualified source

Canonical implementation: `98079023680a549cb126752c1d4f539749f46938` on
`codex/zotero-optimization-20261116`, continuing PR #56. Subsequent commits in
this delivery add validation records only. CrispCloud consumes the same managed
source through its guarded Office manifest.

## Behavior

Basic author–year refresh now accepts **1,000 distinct linked sources**, up from
50. Each durable library scope is split into sequential requests of at most
50 keys. Repeated citations share metadata, while equal item keys in different
libraries remain separate. A single-library document with 51 sources makes two
requests, 101 makes three, and 1,000 makes twenty.

Preflight validates the complete operation before any metadata request. Every
batch retains exact identity-set verification and checks the original editor
target before and after awaiting its response. All results remain staged until
every batch succeeds, then apply in one undo step. Missing data, server errors,
API backoff, stale targets and closing the dialog discard staged work and stop
subsequent requests. The 1,001-source case is rejected before network activity.
Atomicity describes the document edit; sequential reads do not freeze the
Zotero library.

Collection pagination now merges by key. Later metadata replaces earlier
metadata in the original position, preserving the selected collection and
selected references. Duplicates within the first page and overlaps between
later pages no longer produce duplicate dropdown values. Continuation responses
are ignored after the client, library, catalog generation or dialog changes.

The formatted-bibliography API remains one complete request for at most 50
sources in one library. No independently rendered CSL bibliographies are joined.
Native Zotero document formatting, source URI preservation and the existing
desktop-profile checks are retained.

## Current local qualification

| Cohort | Passed |
| --- | ---: |
| All ten shared editor Zotero suites | 177 |
| Engine catalog, identity, metadata batching, saved searches and ODS reader | 171 |
| **Canonical total** | **348** |

Strict analysis passes for the dialog, both changed widget test files and the
two incoming ODS targets. Declared Dart 3.12 formatting reports three files and
zero changes. The companion app separately passes 39 Zotero host tests and 70
terminal reconciliation tests, for **457 current test executions across both
repositories**. Setup smoke runs and earlier overlapping runs are excluded.

The 1,000-source widget case verifies twenty bounded requests, repeated-source
deduplication and undo/redo. Other regressions cover cross-library key reuse,
late same-library missing CSL and server failure, backoff, closure during batch
two, stale targets preventing batch three, the 1,001-source preflight bound,
duplicate/renamed collections and stale collection responses.

Two controls ran against an isolated archive of editor source from
`18c76e886623ae3be9a41addd80e7f6837c2d3b0`. The old code fails the duplicate
collection test by retaining a second identical menu key, and fails the
51-source refresh test by making zero requests instead of two. Both are
behavioral failures after successful compilation. Their logs and receipt are
in [baseline/](baseline/); setup-only attempts do not contribute to the result.

[receipt.json](receipt.json) records exact commands, selected tests, log hashes,
source hashes, dependency inputs and remote source identities. The runtime is
Flutter **3.47.8** / Dart **3.13.7**, framework
`737ba8f885dc774b53b442759999a312c9461e4e`. Genuine harness lockfiles were enforced;
production dependency declarations were not changed.

## Reconciled incoming work

The [ref inventory](incoming-refs.json) accounts for **40 Quds branches and 58
advertised PR heads**, plus upstream main. It includes main through #58
(`bad2d9d30fd94db8de92a4f4bf83a55b0692b884`), the existing Zotero #50/#56 work and
the retained Office/terminal branches. PR #57 preserves worksheet tab colors;
#58 adds named expressions and was integrated when it arrived during this pass.
Squashed feature heads are verified with `git cherry`. The older
`vendor/ods-validation` draft remains explicitly superseded by its integrated,
bounded-range successor; its older implementation is not reintroduced.

Remote checkpoints include reconciliation `18c76e8`, implementation `11c45db`
and qualified source `9807902`. All use `[skip ci]`. GitHub Actions were not
queried, awaited or rerun.

## Reproduction and scope

The existing [bootstrap scripts](../zotero-continuation-20261116/setup/)
reconstruct the pinned runtime and genuine engine/editor/host harnesses. Pass
the workspace containing `quds_office_suite` and `CrispCloud` to
`bootstrap-local-tests.sh`, then source `zotero-toolchain/env.sh`. Run the exact
test commands in the receipt from their harness directories. Harness `lib` and
`test` links must resolve to the intended canonical checkout; the companion
host graph must use actual vendored bytes. Strict analysis temporarily uses an
absolute-root package configuration derived from that same locked graph, then
restores the original configuration.

This is focused local qualification with synthetic fixtures and mocked Zotero
responses. It does not claim a new full application build, live Zotero account
session, Word/LibreOffice interoperability run or private credential-store
acceptance. Earlier native scaling and live-desktop evidence retain their
original source pins in the preceding validation directories.
