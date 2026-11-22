# Remembered Archive destinations — integration and local qualification

Work date: **22 November 2026**, Europe/Berlin.

Repository: `CrispStrobe/quds_office_suite`. Publication branch:
`work/mail-client-progress-20261122`. This continuation implements the next
organization milestone in the [Mail roadmap](../../roadmaps/mail/README.md).
The [workflow guide](../../roadmaps/mail/remembered-archive.md) describes the
user path and remaining product boundaries.

## Delivered behavior

- Connected IMAP, EWS and Microsoft 365 can remember an exact custom Archive
  destination per durable account. A localized toolbar setting supports save,
  change, clear and missing-folder repair without a selected message.
- Every saved route is validated against a fresh provider catalog. Archive
  confirms the exact account/source/count/destination, then rechecks the saved
  revision before creating durable single/bulk Move intent. Missing destinations,
  foreign identities, changed preferences and stale callbacks cannot substitute
  another target.
- Gmail retains Inbox-label removal and neither exposes nor reads the folder
  preference. The independent local archive-copy feature is unchanged.
- Schema 17 preserves preferences through restart, logout and cached-folder
  eviction; account/profile removal clears them. Revision tombstones prevent a
  stale dialog from recreating a cleared preference. Existing v16 Archive
  commands and pending journal entries survive migration.
- Provider Close retires transport authority and first-snapshot observers before waiting
  for pending account opening. Late owners and uncertain drafts remain owned
  through release. Failed saves, observer cancellation and owner release keep
  explicit recovery paths. A new account cannot enter before accepted pending
  writes and ownership release finish.

## Intake and preservation

The initial capture inspected **47 fork heads, 100 recent PRs (#284–383), no open
PRs and four upstream heads**. All PR head refs and fork/upstream branch refs
were fetched. Of 151 captured reference records, 148 were already ancestors of
initial main `b4f1150b`; the three remaining branch tips were integrated with
their original commits retained as merge parents.

The subsequent captures incorporated main `ab3457c9` (PR #384), the updated
Zotero tip `96240d35`, account-workspace tips `415265e4` and `7c2f6e74`, and
connected-navigation tips `893cca7a` and `604a9399`. Incoming Office/Word/Zotero
work was preserved alongside the Mail continuation. Independent literal
converter expectations remain independent of actual output.

The last connected-navigation update keeps factory opening, draft loading,
cached-observer setup and selected-route compare-and-set under one pending
account owner. Restored drafts become active only after admission succeeds.
Its source was reconciled in an isolated checkout while the first full Studio
gate continued on its unchanged checkpoint. This preserves both the incoming
ownership correction and the Archive guards, including all six optional owner
identity checks before loading in each connected host.

`intake.json` records captured refs and final ancestry checks.
`publication-checkpoints.json` records incremental remote checkpoints and local
commit aliases created by the authenticated GitHub connector. Each published
tree was verified against the corresponding local Git tree before advancing the
branch; branch updates used the expected previous SHA and no force push.

## Executed qualification

**PASS: 5,685 distinct substantive cases across 253 suites**, with no accepted
failures, skips or incomplete cases. The final source checkpoint is
`3dca1265f7abfc2cdca7eb0c6b0b582f85f4b015` (tree
`b84647e6932218d083d32a12e934211fa798e607`). Subsequent publication commits
contain documentation and evidence only. `qualification.json` and
`source-continuity.json` record the counts and source bindings.

| Accepted cohort | Suites | Passes |
| --- | ---: | ---: |
| Mail core | 29 | 659 |
| Mail store, VM plus Node behavior | 53 | 1,190 |
| Mail transport, VM plus Node behavior | 26 | 618 |
| Shared Mail UI | 18 | 294 |
| Studio Mail | 113 | 2,538 |
| Incoming Word/Zotero engine and editor | 14 | 386 |
| **Total** | **253** | **5,685** |

All **43 changed Mail Dart files** pass formatting without edits and strict
analysis (`--fatal-infos`), with unchanged inputs and no issues. The final Studio
run passed **996 cases across 28 suites on its first attempt**. Its 6,043 scoped
inputs and 4,171 resolved dependency inputs remained unchanged and match the
qualified source. The 85 unaffected baseline suites contribute 1,542 cases;
their complete reachable dependency closures are unchanged. The additional
credential-selection race suite contributes six cases outside the original
112-suite selection.

The complete original Studio run observed 2,484 passes and seven failures. All
949 cases from its 27 overlapping suites, including 942 passes, are discarded
when constructing the accepted ledger; the complete final suites replace them.
The original failures are retained with their raw diagnostic events. Incoming
engine/editor counts likewise include 326 original cases plus 60 new outline
cases, without adding the overlapping later reruns.

Counts exclude test loaders and hidden lifecycle records. A rerun replaces its
earlier suite result; repeated focused cases are not added again. The first full
Studio run and the final affected-suite run remain separately available, including
the failed first-run records. The accepted Studio ledger uses the final result
for every rerun suite and retains only passing, unaffected suites from the first
run. Any test added outside the original selection is identified separately.

The full shared Mail gate executes actual SQLite child-process termination and
transaction recovery, loopback TLS and cancellation, native provider fixtures,
Node-only unsupported-host behavior, and shared Flutter UI. Portable checks
compile and execute core JavaScript and compile the store browser entry/worker.
The final Studio coverage includes all 36 new saved-Archive provider-host cases,
the 66 helper/dialog cases, persistence/migration/ownership checks and the
integrated account lifecycle regressions.

## Development failures retained

- Six first-snapshot Close regressions originally demonstrated a wait cycle:
  closing waited for restoration before canceling the observer on which
  restoration depended. Cancellation-before-waiting resolved the reproduced
  issue; the later pending-owner design preserves that invariant.
- The first new journal-host run had 35 failures from one test helper using
  Flutter's guarded asynchronous `expect` inside a pumping SQLite callback.
  The established synchronous assertion form fixed the helper. The corrected
  run passed all 147 cases (111 existing and 36 new), with no production change
  for that fixture repair.
- The first broad Studio gate exposed tests that attempted reconnect before a
  gated old provider reply and its durable receipt had drained, or checked route
  dismissal after a fixed number of pumps while a late owner was still closing.
  The corrected tests explicitly observe blocked admission and completed release
  before reconnecting, retain overlapping account/row identities and stale
  callbacks, and wait for actual route dismissal. They do not bypass cleanup.
- Review found a merge-time retry race: Close could silently retry a pending
  Refresh cancellation that failed after Close began. The final code captures
  retry authority at Close entry. Three provider regressions require the first
  failure to remain visible and another explicit Close before retrying.
- Pending-snapshot save assertions were adapted to the incoming staged-admission
  contract: an unadopted persisted draft is not resaved. Persisted content and
  uncertainty must survive unchanged; dirty-save failure remains tested after
  successful admission.
- Earlier runtime/bootstrap and DTO naming attempts remain historical. They are
  not counted as passing acceptance.

## Runtime and reproduction

The runs use the repository-pinned **Flutter 3.47.8 / Dart 3.13.7**, framework
`737ba8f885dc774b53b442759999a312c9461e4e`, with a verified official SDK archive.
The 204 hosted dependency archives were checked against lockfile hashes before
offline dependency resolution. Workspace manifests and lockfiles were unchanged.
Native SQLite 3.54.1 was built through the unmodified sqlite3 3.9.1 package hook,
with FTS5 available. Runtime and archive hashes are retained with the evidence.

Pure Dart tests use the locked `test` package's runner directly because the
ordinary `dart test` startup stalled in this environment. The command retains
the package configuration and kernel compiler. Flutter runs use `--no-pub`,
explicit test paths and JSON reporting. Recorded commands, working directories,
runtime identities, actual exit codes and raw stdout/stderr are authoritative.
Replay scripts contain the original absolute scratch paths; update those path
constants to the corresponding checkout and pinned SDK when replaying elsewhere.

The evidence captures scoped source/configuration hashes before and after runs,
and binds the final accepted inputs to committed Git blobs. These scopes are
explicit, not claims of a complete transitive compiler-input closure. The
affected-suite dependency map includes Dart imports, exports, parts and all
conditional branches relevant to the changed connected hosts.

Raw logs, case ledgers, input maps, runners, intermediate failures and runtime
receipts are compressed under `evidence/`. The index includes hashes for every
member and every archive part. Use `assemble_evidence.py` to verify and reconstruct
the archive before extracting it in a separate directory.

No GitHub Actions queue status or completion was used as an acceptance gate.
Final publication uses an ordinary ancestry-preserving PR merge and verifies
remote main's tree and included checkpoints.

## Remaining boundaries

This delivers a concrete Archive preference workflow and reconciles account
lifecycle work; it does not complete desktop-client parity or the shared M04W
workspace. Live-provider accounts, real-browser OPFS/quota/Web Locks, installed
desktop/mobile behavior and platform release acceptance remain separate gates.
No live credentials or messages were used in these local tests.

The next ordered work is provider-aware categories/tags and previewable rules
with durable partial outcomes, indexed body/provider search with visible
coverage, persistent cross-folder conversations, provider Drafts/Sent conflict
reconciliation, then simultaneous account-owned background work and a unified
live Inbox. Rich authoring and Office attachments, Calendar/People and release
qualification retain their roadmap dependencies.
