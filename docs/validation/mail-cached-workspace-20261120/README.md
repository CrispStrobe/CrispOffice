# Cached mailbox workspace — implementation and qualification record

**Date:** 20 November 2026 (Europe/Berlin). **Implementation:** complete through
the reviewed cache-recovery increment. **Final local acceptance:** passed,
including the complete 57-file Studio replacement run. GitHub Actions,
workflow runs and status checks were neither queried nor awaited.

The [feature and storage guide](../../roadmaps/mail/cached-mailboxes.md) explains
the user path. The [final qualification seal](final-qualification.json),
[final reconciliation](final-reconciliation.json), [evidence archive](evidence.tar.xz)
and [member index](evidence-files.json) identify accepted inputs, commands, raw results
and diagnostics. Earlier checkpoints do not substitute for full Studio acceptance.

## Delivered capability and acceptance boundary

Native Studio Mail now connects IMAP/SMTP, Exchange EWS, Gmail and Microsoft 365
foreground browsing to the existing durable account repository. It retains the
latest successfully saved ordered header window for each visited folder and the
original source, decoded body and attachment bytes of messages explicitly opened.
Initial pages, refreshes and **Load more** can replace the saved window. Listing,
filtering and keyboard focus alone do not download message bodies.

The verified-account chooser exposes **Cached mail** beside local drafts. Users
can reopen saved folders, filter retained headers and read available messages
without connection, discovery, credentials or OAuth. Missing bodies receive an
explicit explanation. English, German and Arabic cover navigation, cleanup and
failure controls, including narrow layouts and RTL dialogs.

Each account admits at most 1,000 visited folders; each window admits at most
1,000 headers and 2 Mi UTF-16 code units of metadata, subject to stricter configured
limits. Capture time, observed flags and the further-page indicator describe a
local observation. Order and capture time stay fixed until the next view save;
shared message metadata can receive later observations. Filters cover the retained
window. Complete offline mailboxes, account-wide search, authoritative sync and
unified inbox are outside this delivered scope.

## Identity, ownership and durability

Existing local-draft account fingerprints remain unchanged. Verified endpoints,
effective logins, senders, custom IMAP ports, EWS domains and cloud account routes
reopen the original database. Provider sessions keep ephemeral identities; the
bridge validates and maps full remote identities into the stable local account.
IMAP uses folder, UIDVALIDITY and UID; opaque providers retain complete IDs.
RFC Message-ID, sequence numbers and mutable fields never determine cache identity.
IMAP projections retain immutable original header records to prevent redirection.

Drafts and mailbox caching share one repository owner and serialized operations.
Hosts reject mismatched account owners before adoption. Offline close waits for
pending opens/reads. Disconnect and replacement invalidate leases before releasing
ownership; view and body writes check leases at the final transaction boundary.
Storage failure preserves the connected reader, with separate view/body warnings
that do not hide interrupted-send feedback.

Additive schema v5 preserves drafts, Outbox, blobs, search and sync data. Browse
metadata and ordered references are separate from authoritative memberships and
cursors. Replacing a limited window never declares omitted messages deleted or
stores a foreground continuation as a sync checkpoint. View references protect
retained headers from ordinary synchronization pruning.

Compare-and-set writes use a durable profile counter; cleanup and restart cannot
revive old confirmations. Unknown flags preserve the last complete observation.
Migration, quota, injected-fault and actual process-kill cases verify rollback before
commit and recovery after commit while preserving outgoing work.

## Explicit cache recovery and live composition

Confirmed **Clear cached mail** removes bounded batches of views, eligible bodies
and unreferenced headers. Drafts, Outbox, credentials, account-directory records,
authoritative memberships/cursors and pending operations remain intact. Editor
pins protect bodies; the report separates retained bodies from more eligible work.
The bridge respects configured page limits. Cleanup is one transaction and needs
no new account-byte or envelope admission.

Cleanup invalidates evicted bodies' search entries without decoding envelopes,
including oversized/malformed old envelopes under lowered quotas. Retained sync
or pending-command headers can be indexed again by bounded reindexing or later
synchronization. Ordinary eviction preserves header search. A failed cleanup
rolls back the entire step.

A save-failed composer offers recovery without closing its editor. It retains the
controller, attachments and edits, commits pending input, waits for existing saves,
clears one batch and retries local saving under account/draft-selection guards.
Cancellation or failure leaves the unsaved editor available. Prior Send, Queue or
Close intent is not resumed automatically. Connected cleanup does not refill the
removed cache; later refresh or reconnection establishes a fresh saved observation.

## Intake and incremental remote preservation

The continuation restored main at `bb5320a5`, then fast-forwarded to the reconciled
Word outline/list-level source at `3c87debc` before Mail implementation. Final
captured intake covers **23 fork heads, 40 recent PR heads and eight upstream
references**, with no uncovered heads. Historical equivalents were checked against
Git objects, including exact-tree or changed-path equivalence, rather than replayed.

Word later advanced to `273d78f5` with exactly three validation-file changes. The
ancestry merge is `c17e708e`. Independent inspection verified the archive and all
1,123 Word input identities against base, incoming and feature Git objects; this
documentation-only delta required no source rerun.

During the final Studio gate, PR #261 merged into main at `3ee4e362`, with Word
head `fff4a4af`. Its additional 23 changed paths contain validation artifacts
only. The main ancestry and final Word packet were incorporated at `2c0c9bed`;
all qualified production and test fingerprints remained unchanged.

Remote branch: `work/mail-cached-workspace-20261120`; continuation PR: **#262**.
Expected-head, non-forced updates and tree checks preserve work. Qualified source
checkpoints and intake targets are recorded in the manifests.

| Checkpoint | Preserved work |
| --- | --- |
| `ffa3140f` | Reconciled intake and bounded acceptance plan |
| `3467ab2c` | Durable views, stable bridge and store/adapter regressions |
| `6f5c763d` | Native capture and credential-free cached reader |
| `2d3799af` | First qualification, incoming Word evidence and diagnostics |
| `47d3fc0d` | Account/body identity guards and warning regressions |
| `0730e7f6` | Cleanup, metadata preflight and durable view counter |
| `5c9fafb8` | Workspace direction retained in cleanup confirmation |
| `9c2620e2` | Cleanup independent of old envelope admission |
| `c17e708e` | Incoming Word evidence merged with ancestry |
| `1f6a0130` | Quota-blocked draft recovery inside the live composer |
| `3730a4b9` | Provider identities restored in HTML test fixtures; assertions unchanged |
| `2c0c9bed` | New remote main ancestry and final Word validation packet |

## Nine review corrections and their regressions

1. **Wrong account owner:** reject a draft/mailbox owner mismatch before adoption
   and close the candidate. Injected-owner regressions cover both native hosts.
2. **Fetched-message identity:** reject missing, mismatched or stale account/provider
   and remote identities before publication/persistence. Immutable IMAP header
   records prevent mutable foreground projections from redirecting a body.
3. **Warning cross-clearing:** track view/body failures separately. Header refresh
   cannot clear a body-save failure or overwrite interrupted-send feedback.
4. **Cache consuming draft quota:** expose bounded cleanup, preserve work/pins and
   report partial completion. Real SQLite regressions show a blocked draft becoming
   savable after confirmed recovery; configured page limits remain effective.
5. **Unbounded cached JSON transfer:** preflight SQLite types/encoded sizes, then
   enforce decoded budgets. The independent 1 MiB corruption probe now returns
   `quotaExceeded` after transferring only ordinary bounded metadata.
6. **Cleanup/recreate revision reuse:** use the durable profile counter. Same-time
   cleanup, restart and recreation cannot revive an old CAS; exhaustion never wraps.
7. **RTL confirmation direction:** preserve the workspace direction instead of
   inheriting the navigator's LTR direction; Arabic/narrow-window regressions apply.
8. **Cleanup blocked by old envelope budgets:** discard the evicted search entry
   without reading its envelope. A valid 4,096-character subject clears after reopen
   with a 64-unit metadata budget and one-byte account quota; corrupt 1 MiB text/BLOB
   envelopes are removed without large transfer.
9. **Unsaved composer navigation trap:** recover inside the live editor, serialize
   against saves and retain state. Native, cloud/EWS and offline callbacks preserve
   account/selection guards and retry only local saving.

## Runtime, accepted gates and source binding

Qualification uses repository-pinned **Flutter 3.47.8 / Dart 3.13.7**, the existing
lockfile and offline enforced-lock resolution. The lockfile SHA-256 is
`0d64a732cd7f6c7cc4e1e01255276f081b59e6f43039636c3d36f6785a958ce2`.
Receipts preserve exact commands, SDK/package setup and launcher inputs. Native
runs use the original SQLite native-asset mapping and actual library. Before/after
fingerprints cover source, package configuration and launcher/runtime identities;
sealing recounts raw events and compares accepted inputs with the integrated tree.

| Qualification scope | Accepted result | Evidence scope |
| --- | --- | --- |
| Complete native Mail store | **714 passed** | Final recovery run, including actual process-kill recovery |
| Mail core | **67 VM + 67 Node passed** | Separate runtime executions |
| Store portability | **46 Node passed** | Codec/platform/error portability |
| Complete Studio Mail, saved-mail and credentials | **1,149 passed** | Complete 57-file rerun; source/runtime unchanged |
| Shared Mail UI | **96 passed** | Complete final shared cohort |
| MIME and transport | **486 passed** | Complete final codec/transport cohort |
| Evidence-runner Python controls | **48 passed** | Local runner regression gate |
| Strict core/store analysis, formatting and lock enforcement | **Passed** | Final store receipt |
| Browser store entry and worker | **Compiled** | JavaScript compilation, not browser-storage execution |
| Independent incoming Word regression | **679 passed across 19 files** | This continuation's incoming-source cohort |
| Independent Word portable/static checks | **Passed** | Exact BAS VM/Node output and JSON equality, analysis/format |
| Preserved Word author's checkpoint | **2,569 passed across 70 modules** | Separate author record; one serial shared VM suite |

Final store evidence is `mail-cached-store-final-recovery/receipt.json`; shared
evidence is `mail-cached-shared-final-recovery/receipt.json`. Both passed with unchanged
fingerprints. Studio's full replacement run against `3730a4b9` passed and uses
`mail-cached-studio-accepted/receipt.json`. The acceptance seal verifies all 5,648
unique source inputs against the integrated tree after main reconciliation.

The independent Word cohort and author checkpoint overlap and are not summed.
[Incoming Word qualification](incoming-word-qualification.json) explicitly selects
the independent regression and corrected portable/static run. The
[earlier author checkpoint](../word-vba-list-levels-20261120/word-gates-checkpoint.json)
preserves 83 verified archive members and 1,123 source identities. The
[final author packet](../word-vba-list-levels-20261120/README.md) is preserved
alongside it. The author's run uses Dart 3.14.1 and Node 24.22.3; our independent
679-case regression and portable checks use the repository-pinned runtime above.
The author's 70 modules share a VM isolate and process caches; separate-file
isolation is not claimed.

The final Word packet's 26 indexed delivery files and 226 members across four
archives were independently verified. Its Mail deferral records captured head
`0730e7f6`; this continuation qualifies the later corrected Mail source while
preserving that historical record.

## Retained failures and evidence accounting

Earlier store gates with 686 and then 711 passing native cases record prior sources;
they do not replace the final 714-case gate or contribute extra accepted cases.
Focused compile/assertion diagnostics, host/UI fixture diagnostics, missing native
mapping invocation attempts and original independent quota/metadata probes remain
with their corrections. Failing evidence is not silently removed.

The first Word Node command omitted the `globalThis.self` bootstrap and exited
without its async result. Byte/JSON equality rejected that attempt. Its passing
679-case regression is selected explicitly under unchanged source/runtime guards;
the corrected complete portable/static run is accepted separately.

An obsolete Studio attempt was interrupted for follow-up source corrections and
contributes no accepted count. The subsequent full 57-file attempt completed
**1,143 passes and six failures**: two cloud and four EWS HTML fixtures lacked
provider identities after raw MIME parsing. Checkpoint `3730a4b9` repairs fixtures
only; all six focused cases pass with production guards and original HTML, Bcc,
threading and no-send assertions unchanged. The entire 57-file cohort is rerun.
Neither the earlier full attempt nor the focused six is combined with acceptance.

The final archive contains **347 verified members**, occupies 2,396,488 bytes and
has SHA-256 `3b6859b86aabaf6bb52f11d6e1da879a141fc69ea3cf24ad9108b7f72e0d4d69`.
The member index binds paths, sizes and SHA-256 values. The final sealer verifies
selected receipts, raw counts, source manifests and runtime inputs against the
integrated tree. Git history retains prior evidence checkpoints. Final publication
must reverify accepted fingerprints after merging main.

## Next roadmap and platform boundaries

This is the first cached-read slice of the durable Mail workspace milestone.
Next come repository streams and recoverable provider synchronization commands,
with reset, retry, reconciliation and cancellation; then unified multi-account inbox
and durable remote read/flag/move/delete workflows. Provider Drafts needs stable
identities and conflict handling. Rich composition, signatures/templates, undo-send,
scheduling, broader search/rules and Calendar/People remain subsequent increments.

Native SQLite and synthetic-provider/widget execution provide local acceptance.
Installed-platform packaging, secure-vault interoperability and live IMAP/EWS/Gmail/
Microsoft 365 tests remain open. Node and browser compilation do not qualify actual
browser storage or an installed browser application. Local files retain the existing
unencrypted storage policy. These boundaries do not imply desktop-client parity.
