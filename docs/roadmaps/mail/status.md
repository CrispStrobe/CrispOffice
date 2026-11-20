# Mail implementation status — 20 November 2026

## Cached mailbox views

The [cached mailbox continuation](cached-mailboxes.md) retains the ordered
loaded header window of each visited native IMAP, EWS, Gmail and Microsoft 365
folder. Explicitly opened message bodies, original source and attachment bytes
can be reopened through **Cached mail** in the verified-account chooser without
credentials or a provider. Capture times, partial scope, missing bodies and
storage failures are explicit. Draft/Outbox namespaces and sole ownership are
preserved; stale leases cannot commit after disconnect.

The additive schema-v5 view records remain separate from synchronization
cursors and authoritative memberships. This is limited cached reading;
repository-driven foreground streams, durable synchronization/remote commands
and a unified inbox remain open. See the
[source and local qualification record](../../validation/mail-cached-workspace-20261120/README.md)
for actual checks and the installed-platform/live-provider/browser boundaries.

## Outbox review and management

The [management continuation](outbox-management.md) adds read-only saved-message
review, exact EML export, a separately confirmed private recipient JSON export,
atomic **Edit as new draft**, and **Stop retrying** for unresolved acceptance.
Editing is available only when no attempt may have been accepted; it cancels
the original and creates a new draft in one SQLite transaction. Other drafts
and the original frozen MIME remain intact. Bcc is reconstructed from the
transport envelope, and supported attachment bytes/threading are retained.

Closing an uncertain record does not invent an accepted/rejected provider result
or resolve delivery. It records **Closed locally — delivery unknown** and disables
further sends for that entry. Separate confirmed cleanup remains possible.
Preview uses inert text and does not open attachments or load external resources;
unsupported projection keeps exact raw export available. The host routes cover
native SMTP, EWS, Gmail and Microsoft 365, with English/German/Arabic labels.

The [qualification record](../../validation/mail-outbox-management-20261120/README.md)
binds these workflows and the incoming draft/account/layout continuations to the
combined source. Undo-send, scheduling, provider Sent reconciliation, background
execution and live-provider/installed-platform gates remain open.

## Verified offline account entry

The [offline account continuation](offline-accounts.md) persists the exact local
draft identity after successful native connection and catalog open. **Drafts for
connected accounts** opens save-only local drafts for IMAP (including discovered
custom ports/logins), EWS, Gmail and Microsoft 365 without provider construction,
discovery, credential access or renewed OAuth authorization. Existing account
fingerprints and stored drafts are preserved. Confirmed shortcut removal leaves
mail, drafts, Outbox and credentials intact; stale removal snapshots, corrupt
metadata, ownership conflicts and storage failures are refused explicitly.

An additive schema-v4 directory stores non-secret metadata separately from
credentials and message content, with a 100-account limit and monotonic
connection revisions. Its local files are not encrypted. EN/DE/AR controls and
provider workflow fixtures are covered by the
[local qualification](../../validation/mail-offline-accounts-20261120/README.md).
Older accounts need one successful reconnect to establish missing metadata.
Provider Drafts synchronization, cached/offline mailbox sessions, installed
platforms and live-provider qualification remain open; this does not close
M04W, M06 or M07.

## Multiple local drafts and offline composition

The [multiple-draft continuation](multiple-drafts.md) adds a bounded,
account-scoped draft chooser to native IMAP/SMTP and the shared EWS/Gmail/
Microsoft 365 host. New messages and replies have independent IDs, revisions,
attachment snapshots and earlier-send uncertainty. Selection and confirmed
deletion reject stale account/revision snapshots; Outbox handoff affects only
the chosen draft. The previous single-slot draft remains recoverable.

Remembered explicit-server and preset IMAP accounts additionally offer **Local
drafts** before connecting. This save-only workspace never creates a provider or
invokes discovery; it releases its store lease before returning to connection
setup. The later verified-account continuation above adds offline draft entry for
autodiscovered IMAP, EWS and cloud accounts after one successful reconnect.
Provider Drafts synchronization and the repository-driven offline inbox remain
future work. See the
[source and validation record](../../validation/mail-multiple-drafts-20261120/README.md).

## Durable foreground Outbox

The [Outbox continuation](outbox.md) connects native Studio Send and Queue in
Outbox to atomic SQLite draft transfer, frozen MIME/transport recipients,
durable pre-provider attempt markers and a visible account-scoped list for SMTP,
EWS, Gmail and Microsoft 365. Recovery never sends automatically. Uncertain
attempts require explicit delivery-check acknowledgement on every retry;
rejection of a later attempt cannot erase earlier uncertainty. Safe pre-send
cancellation and confirmed terminal-record cleanup are available.

The production native host reuses its existing draft-store lease and account
identity. Reconnect to that identity to inspect its queue after restart. This
supersedes historical statements below that no visible durable outbox existed;
their original qualification scope remains unchanged. The multiple-draft and
limited offline-entry continuation is described above. Rich authoring,
scheduling/undo-send, detailed SMTP recipient outcomes,
Sent reconciliation and installed/live-provider qualification remain open.
See the [local evidence](../../validation/mail-outbox-20261120/README.md).

## Reply and forwarding fidelity

The [reply/forward continuation](reply-forward.md) completes two existing
composition paths across native IMAP/SMTP, EWS, Gmail and Microsoft 365.
Reply, Reply all and both forward choices can quote HTML-only mail through a
bounded inert body projection. An explicitly empty plain-text alternative stays
authoritative. The body projection excludes envelope headers, Bcc and attachment
metadata; forwards add explicit From/Date/Subject attribution. Source-status and
strict HTML admission refuse incomplete HTML quotations.

**Forward text only** retains its attachment-free behavior. **Forward with
attachments** requires a complete MIME parse and admits every decoded attachment
before copying any payload, including inline parts as ordinary files. The same
ten-file/10 MiB aggregate composer limits apply. Unsupported names/types, missing
parts or excess size/count refuse the whole action with localized feedback.
Complete attachment-only messages can forward their files with attribution and
an empty quote. Forwards require an explicit recipient and start a new thread.

Both paths reuse local draft autosave/recovery and the existing uncertain-send
guards. No new transport, automatic retry or account state is introduced.
The [source and qualification record](../../validation/mail-reply-forward-20261120/README.md)
records incremental remote checkpoints, actual tests and remaining boundaries.
This closes text quotation and explicit file-forwarding gaps; rich HTML
composition, preserved inline layout and signatures/templates remain open. The
later durable Outbox increment is described above.

## Remembered native IMAP/SMTP accounts

The [remembered-account continuation](remembered-accounts.md) adds a bounded
catalog in the selected credential backend and explicit account switching to
native Studio Mail. Each backend's catalog can hold up to 20 IMAP/SMTP
configurations. Selecting an account fills setup and remembers the selection;
only Connect starts a provider session. Successful password updates replace
the same identity, New account preserves the existing catalog, and Forget
removes only the selected saved account.

Credential storage offers the system credential store, a custom macOS
keychain, an encrypted credential vault unlocked with a master password, or
session-only memory. The persistent options retain credentials across app
sessions when their selected backend is available. Session-only accounts are
intentionally temporary even though the non-secret mode preference can persist.
Storage changes do not copy or delete another backend's accounts, and an
unavailable selected store never silently falls back to a different backend.

Entries with the same sender and IMAP host show differing effective logins,
TLS settings or SMTP routes. Hover/long-press and accessibility descriptions
expose complete sender and IMAP/SMTP route details, including the exact Forget
target, without passwords or internal account IDs.

The old single-account record migrates within its selected backend only after
the complete v2 replacement is written and read back exactly. Every v2 write
uses that verification; it checks acknowledged contents without claiming
installed-OS durability or making session storage persistent. An empty v2
catalog prevents stale legacy resurrection; unreadable, corrupt or newer-version
data blocks mutations instead of silently replacing stored accounts. Operations
serialize across host store instances in one isolate, keep one backend per
transaction, and use fixed error messages that do not expose credentials.

Switch account saves a retained draft before retiring the connection. Failure
keeps the current session available. The existing provider/incoming-endpoint/
login/sender draft identity is unchanged. Changing credential storage clears
the old catalog selection and Forget association before reloading. Disconnected
setup credentials are cleared; a live connection and newer edits made while
loading remain protected. Delayed completions cannot
replace newer settings or redirect an initialized backend into the new store's
cache. Storage controls wait for busy Mail operations, including initial draft
restore, pending credential operations and connections.
English, German and Arabic copy covers the account chooser and catalog failure
states; the new credential-storage settings and menus remain English.

This native IMAP/SMTP chooser supersedes earlier statements that only one
account could be remembered or that persistent account switching was
unavailable. Earlier sections retain their historical source and validation
scope; broader mailbox sessions and other providers' authentication remain open.

The [local record](../../validation/mail-accounts-20261120/README.md) tracks
source, tests and integrated branches. M04W remains open: this increment does
not provide simultaneous connected accounts, a unified/offline inbox,
repository-driven mailbox sessions, persistent EWS/cloud tokens or bulk
commands. Installed-OS packaging, keychain permissions/unlocking, encrypted-vault
unlock/durability and live providers remain separate qualification scopes.

## Shared foreground mailbox navigation

The [mailbox workspace continuation](mailbox-workspace.md) adds one reusable
`MailMessageList` to the native IMAP/SMTP, EWS, Gmail and Microsoft 365 hosts.
Users can search loaded subjects/senders, combine Unread and Flagged filters,
move keyboard focus without fetching a body, explicitly open the focused row,
and load another bounded page even when the current filter has no matches.
Stable message identities preserve selection across appends and compact
reader/Back transitions. Folder/account changes reset the list's local scope.
English, German and Arabic copy describes the loaded-only search and limits.

The production IMAP path now browses newest UIDs first in explicit pages of
up to 50, independent of the ascending synchronization cursor. Its fixed
initial ceiling excludes later arrivals until Refresh. Discovery is bounded
by the existing UID-count, protocol-line and response-byte budgets; sparse
empty windows retain an older-range continuation. The host stops at 1,000
loaded messages. Invalid, repeated or cross-account/provider continuations
are rejected before adopting a page, and transient failures retain prior rows.

IMAP read/unread and flag/unflag controls use confirmed transport outcomes.
Cloud/EWS and IMAP hosts preserve unknown read/flag observations independently;
confirming one flag cannot manufacture an observation for the other. Stale
callbacks cannot update a replaced connection, and uncertain IMAP mutations
require Refresh before further mutation or paging. Navigation/filtering never
implicitly sends a provider request.

The [acceptance report](../../validation/mail-workspace-20261120/README.md)
separates the fresh Mail gate, incoming Office qualification and retained
development probes. M04W is still open: durable repository-driven lists,
persistent account switching, a unified inbox, offline mailbox entry and bulk
commands are not implemented by this foreground-list increment. Draft recovery
and send safety retain their existing contracts below.

## Durable local drafts and safe reconnect

The [draft recovery continuation](draft-recovery.md) connects the existing
transactional SQLite store to the shared native Studio composer for IMAP/SMTP,
Exchange EWS, Gmail and Microsoft 365. One draft per provider/endpoint/login/
sender identity now survives closing Mail and reconnecting. To/Cc/Bcc editor
text is preserved even while incomplete, along with subject, plain body,
reply-thread metadata and immutable attachment bytes. The optional typed editor
payload is backward compatible with existing stored drafts; no database schema
reset or dependency change is required.

Edits autosave after 500 ms, with visible pending/saved/failure feedback. Close
and Send wait for the latest revision. Storage failure keeps the composer open
and blocks sending; an explicit confirmed unsaved close remains possible. A
possible-submission marker commits before transport invocation. Interrupted or
ambiguous sends remain guarded after reconnect and never resend automatically.
Confirmed acceptance clears the draft; cleanup failure retains guarded content
and tells the user not to resend. A matching definite rejection retires only
that attempt's marker, retaining uncertainty from any earlier attempt.

The [local report](../../validation/mail-draft-recovery-20261120/README.md)
separates persistence, host fixtures and actual provider/installed-OS limits.
This is native local recovery after reconnect, not server-side Drafts sync,
offline account navigation, a multiple-draft manager or a queued outbox. M04W
and M07 remain open. The historical session-only boundaries below describe
their original increments and are superseded for local drafts by this section.

## Outgoing file attachments

The shared native Studio composer now supports [bounded file attachments](attachments.md)
for SMTP, EWS, Gmail and Microsoft 365. Users can select and remove files, inspect
their names/sizes and send immutable byte snapshots with the existing To/Cc/Bcc
and reply-thread handling. Ten files and 10 MiB of combined payload are admitted
per draft; selection is all-or-none, reads are bounded/cancellable, and failed or
uncertain submissions retain the complete draft for the current session.

MIME uses a mixed root containing the alternative body and base64 attachments,
with ASCII-safe RFC 2231 filenames and no Bcc in the canonical wire. A scoped
quoted-printable correction preserves terminal whitespace and bounds Unicode
line wrapping. The [current local validation](../../validation/mail-attachments-20261120/README.md)
records the pinned Flutter/Dart runtime, actual locked workspace and final-source
checks, including the narrow/right-to-left composer, IME and resize regressions.
The incoming Zotero and earlier mail receipts retain their own original source
identities and scope.

The attachment increment originally used session-only composition; the draft
recovery continuation above now persists it locally. Explicit complete
attachment forwarding is covered by the reply/forward continuation above.
Durable outbox, current-document/PDF attachment commands and the VBA mail
surface remain open. Live-provider delivery and installed-OS
picker interoperability remain separate gates. M07 and M08 remain open.

## Durable archive, indexing and search

The [archive guide and parity matrix](archive-search.md) describe the new
independent native archive and Studio workflows. Exact original MIME bytes,
source provenance and FTS5 projections commit atomically. EML/streamed MBOX
imports, selected-message and selected-folder collection, field/Boolean/phrase
search, filters, saved searches, EML export, integrity verification and index
rebuilding are implemented. Repeated collection deduplicates identical bytes;
account/cache removal leaves explicit archived copies intact.

Read limits, quotas, session leases, cancellation, redacted structured logs,
corruption handling and real process-crash tests are part of this increment.
The [local validation record](../../validation/mail-archive-search-20261119/README.md)
binds the fresh checks to their source and runtime. Full MailStore parity,
PST/MSG ingestion, general PDF/Office attachment extraction, automatic schedules,
recursive collection and enterprise retention/legal-hold/access controls remain
open. Browser archive persistence and live account interoperability are separate
qualification boundaries.

## Gmail, Microsoft 365 and additional presets

The [cloud providers](cloud-providers.md) add Gmail API and Microsoft Graph,
desktop browser OAuth/PKCE, bounded reads/sync, confirmed actions, safe MIME
sending and redacted diagnostics. Studio reuses the guarded foreground mailbox
and composer. Yahoo, iCloud and Fastmail have explicit TLS presets.

See [source-bound validation](../../validation/mail-providers-20261119/README.md).
Live accounts, installed desktop packaging, durable cloud accounts/outbox,
shared mailboxes, Calendar/People and web cloud authorization remain separate.
Registration client IDs are deployment-owned; none are provisioned by this code.

## On-premises Exchange EWS

The [EWS implementation](exchange-ews.md) adds a native provider and a Studio
entry with explicit HTTPS configuration, NTLMv2 by default, host-owned
credentials, folder/header browsing, incremental message sync, on-demand MIME,
guarded mailbox mutations and EWS sending with Sent filing. Existing opaque
identities and atomic storage transactions require no schema migration. Browser
EWS remains explicitly unsupported. Connection state remains session-only;
drafts now use the local recovery continuation above, and explicit archived
copies use the independent durable archive.

The [focused validation record](../../validation/mail-ews-20261119/README.md)
separates new source-bound checks from historical IMAP/Office evidence. No live
Exchange endpoint was supplied; server interoperability, Calendar/People,
Kerberos, Autodiscover and the durable mailbox/outbox host are not claimed.

## Previous mail continuations

The current [UID discovery continuation](../../validation/mail-uid-pagination-20261119/README.md)
adds bounded discovery, atomic stored-range reconciliation and monotonic v3
cursor revisions. Combined qualification follows the fully retained first
1,000-execution checkpoint. The inherited main source and qualification are
recorded in the [19 November completion report](../../validation/office-main-completion-20261119/README.md).
Subsequent incoming-ref reconciliation and direct TLS-rejection cleanup are
qualified in the [current reconciliation report](../../validation/office-current-reconciliation-20261119/README.md),
with their own fresh gate and source identity. The concurrent
[synchronization record](../../validation/office-main-sync-20261119/README.md)
is preserved separately. Earlier qualification totals
remain attached to their original source checkpoints.
Fetch the canonical repository's current refs before resuming.
The source of product scope remains [README.md](README.md) and the ordered work
remains [implementation-plan.md](implementation-plan.md).

## Studio foreground-session follow-up

The [current Studio continuation](../../validation/office-mail-continuation-20261119/README.md)
reconciles the later `10bd0cc4` and `004b2ad6` branches and concurrent
PRs #192–#194 with main `b070e228`.
It preserves their independent source-bound evidence and restores saved EML
reading beside the newly introduced account view. The browser entry supports
saved messages and explicitly declines direct IMAP/SMTP accounts.

The native Studio host lists folders and fifty envelope records per load through
the existing high-level client. Selected bodies and read-flag writes use the
bounded shared IMAP provider with a frozen mailbox/UIDVALIDITY/UID identity.
Body reads preserve exact original octets; mark-read verifies the remote flag
before changing the displayed header and never automatically retries a write.
Connection and read callbacks cannot publish into a replaced session. Secure
account discovery is required before credentials are used, public failures are
redacted, and legacy protocol print output is scoped away from application logs.

Its plain-text composer uses the shared Word RenderBox editing surface. It
validates bounded ASCII To/Cc/Bcc mailbox lists and headers, snapshots the body,
generates quoted-printable MIME, and submits with an explicit complete envelope and no concurrent
Sent-folder append. Successful submission means the sending server accepted the
message, not delivery to the recipient. A typed outcome confirms acceptance even
when subsequent cleanup fails: the draft clears and the user is told not to
resend it. Other exceptions after a submission attempt remain conservatively
uncertain; the session retains the draft and requires an explicit delivery-check
acknowledgement before another attempt. DATA and BDAT must return final SMTP 250
acceptance; an earlier positive reply or a recorded command failure cannot
certify submission.

At that checkpoint, Reply and text-only forwarding quote the fetched message's plain-text part,
preserve complete Unicode characters at their explicit quote limit, and do not
copy Bcc or attachments. Replies now retain bounded, validated `In-Reply-To`
and `References` metadata through editing, explicit uncertain retries and the
shared MIME builder; forwards start independent conversations. Unsupported
parent IDs leave the reply unthreaded, and an unsupported ancestor token drops
the inherited chain. [Reply threading](reply-threading.md) records the supported
identifier subset, limits and source qualification. The recipient continuation
originally exercised only a pure threading subset; the attachment continuation
now qualifies the complete threading/MIME cases and composer/host suites against
the locked workspace, as recorded below.
HTML-only quotation was outside that historical increment; the current
reply/forward continuation above adds bounded inert text quotation. A retained uncertain draft
cannot be silently replaced by a reply/forward; Compose resumes it, and an
explicit confirmed discard removes only the session draft without cancelling
a message already submitted.

The [recipient-groups continuation](recipients-and-reply-all.md) adds multiple
To recipients, Cc, Bcc and Reply all across the native SMTP and shared EWS/cloud
hosts. Canonical MIME excludes Bcc while the explicit envelope includes hidden
recipients. Reply all uses normalized visible participants, removes the connected
sender, preserves To/Cc roles and rejects unsupported decoded mailboxes before
joining them into editable fields. Its original recipient/reply/thread subset
ran on pinned Dart through a separate cached dependency graph; unavailable
dependencies prevented MIME/provider and Flutter widget qualification then.
The [original validation record](../../validation/mail-recipients-20261119/README.md)
retains that boundary and its PPTX reconciliation. The
[20 November attachment continuation](../../validation/mail-attachments-20261120/README.md)
subsequently ran the complete recipient/reply/threading, provider-host and
composer suites against the actual locked workspace, without omitted cases.

This does **not** close M04W or M07: accounts/drafts remain session-only, there is
no repository-driven mailbox or durable outbox, and no automatic resend is added.
On-demand body reads and mark-read use the bounded provider. The high-level folder,
envelope and SMTP paths retain their own reconnect behavior and do not acquire
the provider's protocol-byte limits. Session release attempts both owned
low-level transport aborts independently of high-level disconnect, including
after stale connection completions; this does not establish a bounded physical
shutdown time or disable those clients' reconnect policies.
Real provider accounts, OAuth/PKCE, native credential vaults, actual browser
persistence and installed-platform distribution remain separate acceptance gates.
The earlier Studio continuation saved its combined source remotely, but its
aggregate qualification failed before completion and subsequent filesystem tool
launches reported no space left on device. No accepted aggregate result is
claimed for that earlier source. Its report retains exact source identities,
attempts and replay instructions; the combined qualification record above documents its captured cohorts, and
previous totals below remain historical. Later changes have separately bound
results.

## Delivered code

| Area | Current implementation | Acceptance limits |
| --- | --- | --- |
| M00 baseline | The reader foundation reconciled its captured Office heads; the M05 continuation captures and reconciles incoming main, branch and PR history separately before implementation | Capture-specific dispositions and subsequent changes belong to the dated reconciliation receipts; historical test reports are not new results |
| M01 fork | Pinned enough_mail 3.0.0 source, retained MPL/provenance, supported public `mime_core.dart`, content-redacted diagnostics, strict charset admission, RFC2231 and date corrections, selected dependency/source inventory | Actual browser execution and per-product shipped dependency/notice clearance remain open |
| M02 core | Pure-Dart immutable DTOs, exact-byte ownership, profile/account/IMAP identity, nullable standard flag snapshots, budgets/capabilities, typed host/provider/store ports, cancellation leases, cursor compare-and-set and tested outbox state machine | M05 implements persistence; the initial M06 IMAP adapter passed combined local qualification; Studio foreground sending exists, while repository-backed queued sending remains open |
| M03 codec | Bounded byte-range scanning, public upstream header parsing, strict transfer/charset decoding, exact raw export and attachment snapshots, deterministic multipart alternatives/CID metadata | Synchronous bounded work; no streaming claim or low-memory-device qualification |
| M04 reader | Account-free full/compact reader, custom RenderBox selection, decoded search/copy, static HTML projection, local bounded CID PNG/JPEG, immutable source/attachment callbacks, policy-approved links, actual MIME example | Browser runtime no-fetch gate remains unqualified; host parity is a separate task |
| M05 store | Drift/SQLite transactional repository, immutable drafts/outbox blobs, memberships/tombstones/cursor CAS, bounded FTS5, pending-operation and vault-cleanup journals, account/profile retirement, cache/editor pins and schema v3 with nullable durable flags | Schema v3 and the integrated flags/transport source passed local qualification; browser storage and power-loss durability are unqualified; the database is unencrypted |
| M06 native foundation | Manual IMAP configuration, scoped host-vault lookup, selectable folders, bounded discovered-UID synchronization with atomic stored-range reconciliation, exact on-demand message literals, guarded UID flag/move commands and a conditional unsupported browser entry | Integrated qualification and real Linux TLS loopback checks passed; external-provider/other-OS interoperability, IMAP OAuth authorization hosts, discovery beyond the configured SEARCH budget and the repository-driven mailbox/SMTP adapter remain open; Studio's foreground session is separate |

M06 is partially implemented, not complete. M04W and M07–M13 still require the
repository-driven mailbox workspace, durable draft/autosave and queued sending,
Office attachment editing,
standalone full Office host, CrispCloud migration, additional providers,
Calendar/People and Apple distribution work. M14 evidence continues for each
increment; it does not qualify those later products.

## M05 storage and recovery

The new [store package](../../../packages/quds_mail_store/README.md) uses
Drift 2.35.4 and sqlite3 3.9.1. Native setup requires an explicitly supplied
application container and holds an exclusive owner lease across the database
lifetime. Profiles include their host identity, and removed account IDs remain
retired so stale callbacks cannot recreate deleted accounts.

Message changes, mailbox memberships, tombstones and the next cursor commit
together. The transaction compares the cursor read before provider work and
checks its account lease before commit. Conflicting concurrent pages fail
without overwriting a newer mailbox state. Repository streams publish after a
successful commit. Local pending operations survive resets and tombstones in an
explicit reconciliation state.

Drafts use revision comparison. Outbox entries retain their frozen wire bytes,
envelope and draft revision, with validated state transitions and durable attempt
history. Reopening records interrupted submission candidates; recovery persists
them as `uncertain` and never makes them automatically retryable. Work started by
the current live owner is not mistaken for interrupted work. This implements
storage semantics; it does not submit mail or claim exactly-once delivery.

The FTS5 index covers bounded metadata and decoded plain text. Search has no
provider or network port, and header updates/reindexing read metadata without
loading attachment or original-message BLOBs. Logical quotas include identity,
cursor, journal and reference metadata. Payload reads validate stored lengths
before transferring BLOBs and then verify their integrity hashes. Cache eviction
preserves outgoing and pinned content. Logout retains work and journals host-vault
cleanup; explicit account/profile removal deletes local content and retains the
markers needed to finish cleanup after restart.

The current schema is v3, with transactional upgrades from v1 and v2. Existing
rows receive unknown flags; an omitted provider observation preserves known
flags for the same remote identity, while an observed empty set clears them.
Read, flagged, answered, draft and deleted are durable; IMAP Recent is not.
Header listings, streams and search expose the stored snapshot. Existing v2
FTS data is preserved, and v1 backfill remains explicit and bounded. Unknown
future schemas are rejected without reset. The added v3 migration/reopen and
flag transaction tests passed in the qualification recorded below.

The passing baseline includes native file-backed migration/recovery and five
Linux SIGKILL scenarios at transaction boundaries. These results establish the
tested process-crash behavior, not disk failure, operating-system power loss,
mobile suspension or Apple packaging.

Browser setup has a separate public entry, explicit same-origin SQLite Wasm and
worker assets, and a required Web Locks owner lease. Unsafe concurrent IndexedDB
and in-memory fallback are rejected. The browser entry and worker compile, and
portable policy/error-mapping tests run in Node. **Actual browser persistence,
quota, reload, cross-tab ownership and recovery remain NOT RUN/unqualified.**

The database is **not encrypted**. App-container access and a separate credential
vault do not establish database encryption or secure erasure. The host must
execute and acknowledge credential cleanup and supply platform assets/services.

## M06 native IMAP foundation

The new [transport package](../../../packages/quds_mail_transport/README.md)
provides `createMailImapProvider` through a conditional public entry. Manual
configuration contains an explicit DNS/IP host, port, TLS mode, login identity,
authentication mechanism and account-scoped vault reference. Each operation
loads current host credentials and opens a fresh connection. Password,
XOAUTH2 and OAUTHBEARER protocol paths are present; token acquisition, refresh,
system-browser PKCE and platform vault integration remain host work. Required
STARTTLS and implicit TLS expose no certificate bypass or cleartext fallback.
Separate real Linux loopback tests exercise successful TLS, stalled-handshake
cancellation/deadlines, trust and hostname refusal, credential sequencing and
write lifecycle. These do not establish external-provider or other-OS acceptance.

Synchronization discovers existing UIDs with strict bounded simple SEARCH, then
fetches at most the requested number of header/flag records. Scoped v3 cursors
retain UIDVALIDITY and a fixed sweep ceiling and can resume persisted v1 numeric
window and v2 discovery cursors. Each returned page advances a monotonic cursor
revision, including completed or empty sweeps, so cursor comparison rejects stale
concurrent observations instead of reusing the same completed-sweep value.
An authoritative `MailImapSyncRange`, upserts, actual stored
absence tombstones and the next cursor commit atomically through the coordinator
and store. Numeric gaps create no synthetic tombstone rows. Pending local edits
for expunged messages retain their reconciliation state.

The default `maxDiscoveredUids` is **10,000**, configurable up to **100,000**;
it limits the existing UIDs admitted by each remaining-sweep SEARCH response,
independently of their numeric values. Line/response budgets also apply and can
bind first. An oversized response fails with `quotaExceeded` before FETCH or
commit. There is no default numeric UID ceiling; an explicitly supplied legacy
`maxUidScan` retains its numeric meaning and `unsupported` outcome. This fallback
repeats remaining-range discovery per page; scalable ESEARCH/PARTIAL is separate.

Completed sweeps restart to observe old flag changes and expunges without
claiming IDLE, CONDSTORE, QRESYNC or snapshot semantics. New arrivals above the
frozen ceiling wait for the next sweep. Direct retrieval of a specified high UID
retains the exact full-message literal before bounded MIME parsing; partial
projections fail explicitly.

Flag mutations use UID STORE and verify the resulting observation. Delete
sets `\Deleted` only; it does not expunge mail or issue mailbox-wide CLOSE.
MOVE requires the advertised capability and confirms source absence; destination
identity mapping and synchronization remain separate. Operations have finite
timeouts and account-lease cancellation, with no automatic retry. Ambiguous
mutation outcomes return `conflict` for host reconciliation. The browser entry
returns typed `unsupported` without accessing the vault or codec.

The integrated transport/flags source passed local controlled-parser,
SQLite/coordinator and Node qualification. Coverage includes unsolicited flag
notifications, EXPUNGE ambiguity, exact literal bytes, strict FETCH structure and
decimal UID validation. The default owned transport also passed real TLS and
abort-lifecycle tests. Actual disposable-account interoperability, OAuth
redirects/refresh, other operating systems, SMTP, the mailbox UI and actual browser
persistence remain separate gates.

## Local verification

### Discovered-UID and cursor-freshness continuation — qualification in progress

The [discovery source report](../../validation/mail-uid-pagination-20261119/README.md)
records the incoming discovery/range implementation. The
[complete synchronization report](../../validation/office-main-sync-20261119/README.md)
adds the completed-sweep cursor freshness fix and records 1,372 application
executions plus 90 separate Python controls at `0669ac11`. Earlier counts below retain their original source identities
and are not evidence for this increment.


### Historical integration — PASS at `ac1e4c8c`

The [Office integration report](../../validation/office-main-integration-20261119/README.md)
binds both fresh gates to `ac1e4c8c788ea608402c2260488235c0189efcba`: **632
executions / 562 distinct cases / 47 distinct suites**. The focused gate passed
433 cases across 35 suites: 86 native transport, 26 TLS/ownership, three Node
boundary, 256 shared IMAP/POP/SMTP/byte-reader, 32 MIME and 30 Mail UI cases.
The fresh full core/store gate passed 199 executions representing 129 distinct
cases, including 70 VM/Node repeats. Strict analysis/formatting of 26 changed
Dart paths, 42 launcher controls, offline dependency resolution and browser
entry/worker compilation passed.

The final Socket-compatible facade retains its owned TCP transport, and rejected
TLS upgrades now abort and clear connection/authentication state. Immediate
physical stalled-handshake cancellation applies to the default owned transport;
a manual SDK Socket has the documented narrower handoff boundary. All 5,031
source and 11,164 focused runtime records remained unchanged. Later main evidence
is reconciled without modifying any qualified input. Earlier checkpoint counts
remain separate; browser, installed Studio/IME, live Zotero, external-provider
and human linguistic acceptance remain open.

### Retained Socket-compatible checkpoint — PASS

The [completion report](../../validation/office-main-completion-20261119/README.md)
binds all final execution to `5569c055a021c893e941fc54d40499ad9d96a5db`:
**836 application executions across 85 suite/platform executions and 73 distinct
files**, plus **78 separate Python controls**. The native gate passed 602 cases,
the Node gate 35, and a fresh full core/store gate 199. All 35 changed Dart files
passed strict analysis and formatting. Browser entry/worker compilation passed;
actual browser persistence remains outside this gate.

The separate audit recounts the raw events, verifies exact source/runtime
bindings and accounts for all 392 refs at the recorded cutoff. No historical or
development cases contribute to these totals. Real TLS checks use Linux
loopback; external mail services, installed Office/OS integrations and other
platforms retain their separate acceptance requirements.

### Earlier integrated flags and native IMAP qualification — PASS

The [Office integration report](../../validation/office-main-integration-20261119/README.md)
binds the final **32-suite / 389-case** focused pass to source
`7d279e084bae438d383630726ad7b0514da77d35`. It covers 80 native transport cases,
three Node unsupported-entry cases, 244 shared IMAP/POP/SMTP and byte-reader
regressions, 32 MIME cases and 30 Mail-reader cases. Strict analysis, formatting
and whitespace checks also passed, with the source and runtime inputs unchanged.

The retained core/store gate records **199 passing executions / 129 distinct
scenarios**, with source continuity checked for the integrated tree. Its VM/Node
repetitions are separate executions. The report retains raw events, receipts,
source/runtime identities, failed reproductions and independent audit records;
it does not add earlier Office, Notes or thesaurus results to this qualification.
Controlled streams, Node and Flutter tests do not close actual browser, live TLS,
installed Studio/OS IME, live Zotero or human linguistic acceptance.

### Earlier baseline qualification — PASS

The [19 November continuation](../../validation/mail-m06-resume-20261119/README.md)
binds the fresh results to source
`479e1e038af0467b7f07b35d80bac9e4cc60a198`, before the schema v3 and transport
additions. Its [Mail receipt](../../validation/mail-m06-resume-20261119/baseline/mail-receipt.json)
records **186 passing test executions**, with zero failures and zero skips:

| Cohort | Passing cases |
| --- | ---: |
| Core VM | 30 |
| Core Node | 30 |
| Native store VM | 87 |
| Portable store policy/codec Node | 39 |

The **42 Python launcher regressions**, enforced offline lock resolution,
strict analysis, formatting, browser entry/worker compilation and whitespace
checks also passed. VM and Node repetitions are separate executions, not
distinct scenarios. The [72-suite Office/reader run](../../validation/mail-m06-resume-20261119/baseline/office-verification.json)
passed on the same frozen source with **1,230 cases**, zero failures and zero
skips: 233 engine, 887 editor, 99 Studio and 11 Mail-reader cases. Raw evidence,
case lists, archive indexes and source/runtime identity checks are retained in
that dated record. No historical totals are included in these fresh results.

The old runner/formatting blockage was resolved for that baseline. Its results
predate schema v3 and the M06 adapter; the integrated qualification above supplies
the subsequent source-bound evidence.

### Historical store attempt — failed before recovery

The combined local attempt exercised source
`8a6105a7ec217b48105d171703c8d0294c7d2dc6`. Its observed test cohorts were:

| Cohort | Observed result |
| --- | --- |
| Core VM | 30 passed |
| Core Node | 30 passed |
| Store VM | 87 passed |
| Portable store Node | 39 passed |

These are separate runtime cohorts, not a count of distinct cases summed across
platforms. The 87 store VM cases include 32 codec, 16 repository, 16 adversarial,
seven native-platform, four configuration, seven migration and five transaction-
crash cases. The 39 Node cases cover 32 codec, four configuration and three
browser-error-policy cases; they do not execute browser persistence.

**The overall run failed.** Store analysis reported two test lint infos
(an unnecessary sqlite3 import and missing braces); the format check found a
mismatch in `native_platform_test.dart`. Disk exhaustion then prevented a new
executor process from starting. The lint repairs and stricter qualification-event
parser, with 18 new parser regressions, were saved remotely in recovery checkpoint
`7848eca0eec8e291cd88ed6e353151508b77784e`, but had not run at that checkpoint.
The native-platform formatting repair and complete qualification rerun were
also open then. The fresh baseline record above validates the subsequent
repairs; it does not rewrite this historical attempt as a PASS.

See the [M05 report](../../validation/mail-store-20261118/README.md) and
[recovered qualification summary](../../validation/mail-store-20261118/checks/receipt.json).
That summary was reconstructed from observed tool results after the filesystem
became inaccessible; **it is not the original raw qualification receipt**.
The original aggregate raw logs and source manifest remain local and were not
uploaded. Additional review/late Office raw evidence was also not recoverable
through the remaining tools. Remote source checkpoints are preserved, but the
final remote tree was not verified against the local working tree after the
filesystem failure.

The [runtime record](../../validation/mail-store-20261118/runtime/README.md)
retains the earlier verified Flutter 3.47.8/Dart 3.13.7 setup, SQLite 3.54.1 Linux
x64 binary, dependency-resolution comparison and platform checks. Incoming
Office work has [separate reconciliation and regression evidence](../../validation/mail-store-20261118/incoming/).
Retain this failed-attempt evidence and its recovery limitations separately from
the newer source-bound baseline and integrated M06 passes.

### Earlier reader checkpoint

Exact commands, raw results, source hashes and environment limits are retained
under [the reader evidence directory](../../validation/mail-reader-20261118/).
The results below belong to that earlier reader checkpoint and are not new
qualification results for the M05 tree.
The fork's own [verification receipt](../../../third_party/enough_mail/verification/receipt.json)
and [dependency inventory](../../../third_party/enough_mail/DEPENDENCIES.json)
are separate from original Quds tests.

- Core: clean fatal-infos analysis; 28 tests on the native VM and the same 28 in
  Node/JavaScript; public-entry JavaScript and native executable compilation.
- Fork: 170 native tests across 14 files, clean native library analysis, public
  portable JavaScript compilation and equal native/Node fixture projections.
- MIME: 32 tests on the native VM and the same 32 in Node cover original octets,
  raw/decode/body/attachment/
  part/header/depth limits, malformed encodings, alternatives, CID metadata,
  cancellation and review regressions. Both runtimes produce identical public
  fixture projections and hashes.
- Reader: 30 native Flutter tests cover actual MIME integration, search,
  graphemes, immutable callbacks, resource denial with a positive control,
  host-approval invalidation, full/preview budgets and enlarged RTL layouts.
  Two additional visual fixtures were captured and inspected. The release web
  target and browser guard compile; neither is an actual browser runtime pass.
- Initial incoming integration: 190 targeted engine/editor/Studio regressions
  and scoped analysis passed on the initial review/thesaurus merge. The later
  captured head passed a separate 344-test cohort: 74 engine, 148 editor,
  71 Studio and 51 spaCy tests. Its `checks/late-*` receipts retain source
  hashes, initial failures, narrow repairs and final passing results. The
  Studio coverage includes an explicit Linux modal/desktop resize with real
  Material scrollbars. Earlier test totals are not presented as a new run on
  the later source.

See the [reader verification receipt](../../validation/mail-reader-20261118/verification.json)
for that source identity and links to each completed cohort. The imported
draft-proofing flow received numeric limit feedback and responsive chrome;
the navigation sheet keeps its state current and uses separate PDF thumbnail
controllers across resize. A stale test label and two proofing lints were
corrected without changing the established comment-label or priority contract.

No GitHub Actions status was queried, awaited or rerun. Source checkpoints use
`[skip ci]` and are written incrementally to the remote implementation branch.

### Browser and memory qualification

JavaScript compilation and execution in Node do not close browser runtime gates.
The reader checkpoint could not start local Chromium, and the cloud browser
could not access its loopback harness;
[the exact limitation is recorded](../../validation/mail-reader-20261118/browser-limitations.md).
A new Chromium launch during M05 also failed before rendering because the
executor denied its process-singleton socket; the
[launch receipt](../../validation/mail-store-20261118/runtime/chromium-smoke.json)
records the failure. Reader rendering/no-fetch and browser-store acceptance both
remain open. Run those tests on a supported browser environment before enabling
host migration or claiming the corresponding browser capability.

A synthetic 16 MiB attachment (22,369,758 input bytes) was parsed by a native
executable in 493,958 microseconds on this Linux x64 host. Whole-process peak RSS,
including fixture construction, was 112,095,232 bytes. This measurement belongs
to the initial codec checkpoint `9ee120bd` and is a desktop baseline, not a
mobile/low-memory claim. Raw data is in `checks/mime-memory.json`.

### Charset and license decisions

The portable parser imports only the reviewed non-CJK enough_convert source
closure. GBK, Big5 and GB18030 aliases were removed from the registry because
the legacy mapping provenance was not established. Those charsets now report
unsupported and retain original source for a host fallback. UTF-8, ASCII,
Latin-1, supported ISO/Windows and KOI8 mappings remain available; malformed and
undefined character mappings are not silently displayed as exact text.

Original Quds files remain MIT. Modified enough_mail files retain MPL. The
selected enough_convert closure is MPL, with its matching notice/source record.
The complete enough_mail runtime dependency inventory is pinned and retained,
including component-specific notices. The store's
[dependency inventory](../../../packages/quds_mail_store/DEPENDENCIES.json) and
[retained notices](../../../packages/quds_mail_store/THIRD_PARTY_NOTICES.md)
record its independently resolved package closure and default SQLite artifacts.
Flutter, other host dependencies and
shipped assets still require the product-level LIC-02 review. This is
source-level evidence, not approval of an
Apple binary or the full existing CrispCloud host. That host's AGPL boundary
and LIC/CC release gates remain as documented in the original scope.

## Reproduce without hosted CI

Use the pinned Flutter 3.47.8 SDK, Node on PATH and the committed root lockfile.
Resolve the SDK's own flutter_tools dependencies normally if this is a fresh
SDK extraction. From the repository root, qualify the store and updated core:

```bash
python3 tools/mail/test_check_store.py
python3 tools/mail/check_store.py --flutter-sdk /path/to/flutter \
  --offline --direct-tests --command-timeout 300 --output /path/to/fresh-store-checks
```

The store runner records source hashes before/after execution, raw test events,
substantive cases, compilation and exact exit results. Its default output is
`build/mail-store-qualification`. It replaces any earlier PASS receipt with the
current run state before starting, and reports actual browser storage as NOT RUN.
The corrected launcher and its 42 regressions passed in the fresh baseline;
run them again with the final source when recording a new gate. Native
transaction-crash cases require an environment that can start and terminate child
processes. Transport/flags qualification has its own combined source-bound
record under [the Office integration report](../../validation/office-main-integration-20261119/README.md).

For the earlier reader qualification workflow:

```bash
python tools/mail/check_reader.py --flutter-sdk /path/to/flutter --web-build
```

On a machine where Chrome can run, include actual browser execution:

```bash
python tools/mail/check_reader.py --flutter-sdk /path/to/flutter \
  --web-build --chrome /path/to/chrome
```

The runner records command exits, raw output, before/after source hashes and
native/JavaScript projection equality. It reports browser execution as NOT RUN
unless requested. Its output defaults to `build/mail-qualification`, outside
the committed evidence; retain a new dated receipt when qualifying a release.

The web preview harness lives under `packages/quds_mail_ui/example`. A host can
embed `MailMessageView` using `MailReaderController.fromBytes` and
`const QudsMimeCodec()` without accounts or network setup. It is a reader
harness, not the standalone Office application.

## Next implementation order

1. Preserve the completed integrated qualification and its source/runtime
   identities. Rerun affected checks for subsequent source changes and retain
   their raw logs and remote checkpoints separately from earlier evidence.
2. Continue the remaining M06 work: scalable discovery beyond the configured
   simple-SEARCH count/byte budgets, host OAuth/refresh and lifecycle scheduling,
   other-OS TLS coverage and authorized disposable-account interoperability. Generic browser
   socket transport remains explicitly unsupported; no automatic retry is added
   without its own bounded policy and reconciliation checks.
3. Build the next M07 increment as a durable pre-submission undo delay and
   explicitly scheduled foreground send, with separate eligibility/intent,
   restart/time-change handling and cancel-before-attempt transactions. Keep
   M04W's repository-driven workspace and provider-specific Sent reconciliation
   as explicit subsequent boundaries; preserve unknown acceptance and the
   all-or-abort recipient policy.
4. Independently close reader/browser no-fetch and browser-store runtime gates,
   including quotas, reloads, tab contention and recovery. Qualify memory and
   rendering on the intended low-memory devices. Keep CrispCloud EML routing
   unchanged until CC parity tests pass in that repository.
5. Continue the Office attachment bridge, standalone full Office host and
   independent CrispCloud integration with the original dependency order and
   per-product release gates.
