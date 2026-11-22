# Quds Mail — coding plan and ordered TODO

**Scope authority:** [README.md](README.md). **Current implementation and evidence:** [status.md](status.md). Checked items below have a demonstrated implementation; a task acceptance gate can remain open even when its source checklist is checked.
**Target:** one reusable Dart/Flutter Mail implementation, a full standalone Office app, and a CrispCloud integration that preserves its saved-message workflows.
**License decision:** MIT for new independent Quds source; approved permissive dependencies plus MPL-2.0 are allowed. No GPL/AGPL/LGPL/NC imports into shared Quds or standalone source.

## 1. Start here

A fresh agent should use [status.md](status.md) to resume the remaining work without reopening product decisions. Read the current repository instructions first; this plan does not authorize changing existing license headers, deleting unrelated work, publishing a package, submitting an app or using real user mail as fixtures.

1. Work in CrispStrobe/quds_office_suite. Record current commit, working-tree changes and toolchain. The inspected planning baseline was 556c55c0ef312eda2cca11600021d293a81ab44b.
2. Read .cursorrules, CONTRIBUTING.md, docs/MISSION.md and relevant existing editor APIs. Follow the root workspace, not published upstream package examples.
3. Read this plan plus its three sibling specification files. No previous conversation is needed.
4. Implement the smallest end-to-end task slice with focused tests, then mark only its demonstrated acceptance items complete.
5. Keep original/shared code in Quds. CrispCloud changes are a later host integration with separate commits and evidence. Its AGPL implementation and tests are not source donors.
6. Do not block portable reader/core development on OAuth production approval, Apple credentials or CrispCloud's unresolved distribution status. These are later feature/release gates.

### Milestone order

- **Reader milestone:** M00 -> M01/M02 -> M03 -> M04. Produces a safe, portable, account-free EML reader.
- **Live mail milestone:** M02 -> M05 -> M06/M07 plus M04W; M07 requires M03 and M05. Produces the reusable mailbox workspace with recoverable native sync and sending.
- **Both-product milestone:** M08 + M09 + M10, using completed reader/client capabilities. Includes a full Office shell, not just a mail demo.
- **Productivity milestone:** M11 + M12.
- **Distribution milestone:** M13 + M14 and applicable LIC/CC gates. Both app products are assessed independently.

UI and storage work may proceed in parallel after the typed core contract is agreed. A task may have an interface dependency without requiring every later provider to exist. Unimplemented capabilities must report unavailable/unsupported explicitly; no successful empty results or TODO method bodies.

**Discovery continuation, 22 November 2026:** explicit
[saved-search folder sets](folder-saved-search.md) now preserve exact identities,
legacy definitions, bounded paging and missing-folder recovery. The next
ordered workspace task now includes one account's
[unified retained-folder navigation](retained-folder-navigation.md), with
repository-observed browse/sync catalogs and bounded local pages. The next
[durable single-message Move/Delete](durable-mutations.md) increment is also
implemented, with explicit capabilities, persisted dispatch markers and
uncertain-outcome handling. Provider-specific current-location recovery and
[authoritative IMAP/EWS identity transitions](identity-transitions.md), with
atomic retained-cache reconciliation and null-safe sync fences, are now
implemented. [Visible-selection Move/Delete](bulk-organization.md) now adds
confirmed destinations, frozen identities and per-message outcomes through that
same journal. [Explicit provider Archive](provider-archive.md) now adds Gmail
Inbox-label removal and reviewed exact folder moves through the same durable
pipeline. [Account navigation](account-navigation.md) and the
[connected-account continuation](connected-account-navigation.md) provide one
verified four-provider chooser, exact routes, draft-safe ownership transfer and
explicit sign-in with guarded foreground handoff. Remembered Archive destinations,
categories/rules, body/provider search, persistent conversations and provider
Drafts/Sent reconciliation remain organization and discovery boundaries.
Retained simultaneous account sessions and the shared unified workspace remain
open within M04W.
These increments do not close M04W or the complete desktop-client parity goal.

## 2. New package layout

~~~text
third_party/enough_mail/                  reviewed MPL fork, upstream name preserved
packages/quds_mail_core/
  lib/quds_mail_core.dart
  lib/src/model/
  lib/src/ports/
  lib/src/sync/
  test/
packages/quds_mail_mime/
  lib/quds_mail_mime.dart
  lib/src/codec/
  lib/src/policy/
  test/
packages/quds_mail_store/
  lib/quds_mail_store.dart
  lib/src/schema/
  lib/src/migrations/
  lib/src/native/
  lib/src/web/
  test/
packages/quds_mail_transport/
  lib/quds_mail_transport.dart            conditional native/unsupported entry
  lib/src/native/
  lib/src/unsupported/
  lib/src/providers/                     HTTP adapters as they land
  test/
packages/quds_mail_ui/
  lib/quds_mail_ui.dart
  lib/src/reader/
  lib/src/workspace/
  lib/src/compose/
  lib/src/calendar/
  lib/src/people/
  test/
packages/quds_mail_office/
  lib/quds_mail_office.dart
  lib/src/attachment_session/
  lib/src/office_commands/
  test/
apps/quds_office/
  lib/main.dart
  lib/app/
  lib/host/
  lib/features/documents/
  lib/features/mail/
  test/
  integration_test/
~~~

These paths and symbols are proposed. Do not create empty files/directories solely to match the tree. Add packages to the actual root workspace when each gets a working implementation. Keep publish_to: none initially and preserve existing package versions.

## 3. Core API contract

Define typed, immutable public models; no dynamic or untyped maps. Serialization accepts validated typed DTOs at the boundary. Public APIs do not expose enough_mail objects, platform File, CrispCloud database rows, Flutter BuildContext or credential strings.

| Proposed type/port | Required semantics |
| --- | --- |
| MailAccountId / MailProfileId | Stable local IDs; profiles are scoped to a host application. |
| MailCapabilities | Explicit mail/folder/label/search/move/draft/send/calendar/contact/shared-account capability flags; unsupported is distinct from empty. |
| MailMessage / MailEnvelope | Header projection, addresses, subject, date with parse diagnostics, local ID and provider references. The transport envelope is separately represented. |
| MailRemoteIdentity | Tagged provider identity; IMAP includes account, mailbox, UIDVALIDITY and UID; never use sequence numbers as persistent identity. |
| MailBody / MailAttachment | Decoded/normalized presentation plus immutable raw/blob references, media type, part path, declared/observed size and safe display name. |
| MailParseResult / MailDiagnostic | Complete, partial, rejected, unsupported or failed result; exact limit/unsupported-encoding reasons. |
| MailReadBudget | Raw, decoded-total, body, attachment, count, nesting, header and rendering budgets; enforced cumulatively. |
| MailCodec | Parse byte input to a bounded projection; build new canonical wire MIME from a draft; export-original returns retained octets. |
| MailProvider | Discover capabilities, list mailboxes, fetch headers/body/attachments, pull incremental changes and apply a typed operation. No UI or global state. |
| MailSubmissionProvider | Submit a prepared immutable wire message and explicit envelope; return accepted/rejected recipients and definite/uncertain outcome. |
| MailRepository | Transactional domain access, cursor advancement, drafts, pending operations and change streams. Native/web stores implement the same contract. |
| MailCredentialStore | Load/store/delete opaque credential records scoped to profile/account; secure implementation belongs to the host. |
| MailAttachmentHost | Pick/import, preview read-only, edit a working copy, export/share and attach a saved snapshot through bounded byte handles. |
| MailLifecycleHost / MailNotificationHost | Foreground/background opportunity and cancellation budget; optional notifications with explicit capability/permission state. |
| MailExternalResourcePolicy | Explicit link/remote-content decisions; no message-triggered background fetch without policy authorization. |

Use typed cancellation and progress throughout IO-heavy work. Disposal/account removal invalidates pending callbacks. Inject clock, IDs, provider and credential/store ports for deterministic recovery tests.

### Persistence and identity

Start with tables for profiles/accounts/identities, mailboxes, messages, memberships, body/blob records, attachments, drafts, outbox operations and provider cursors. Add contacts/events only when M12 is implemented.

- Store secret references rather than token/password values in ordinary account rows.
- Keep message content and mailbox/label membership separate.
- Account-less saved EML can remain ephemeral; importing it into a profile is explicit.
- Commit a sync page's records and its cursor together.
- Advance opaque provider cursors only after durable processing.
- Retain tombstones and local pending changes long enough for conflict reconciliation.
- Keep raw message/blob integrity hashes separate from message identity.
- Cache eviction must not delete unsent drafts, queued wire payloads or active editor snapshots.
- Migrations preserve user data; test upgrade from every released schema.
- Profile deletion removes that profile's credentials/cache/index/pending jobs. It must not delete provider mail.
- Record whether cached content is encrypted. OS sandbox protection is not described as database encryption.

### Outbox contract

Use explicit states such as queued, submitting, submitted, retryableFailure, permanentFailure, uncertain, cancelled and closedUncertain. The last is an explicit local stop with delivery still unknown. Persist attempt identity before network submission. Transport errors after possible server acceptance become uncertain; do not automatically resend those messages.

Prepare and freeze the draft revision, wire MIME hash and envelope before enqueueing. A later edit creates a new draft revision and cannot mutate the queued payload. Delay/undo-send operates before submission. A cancelled UI wait does not prove the provider did not accept a message.

Keep envelope acceptance separate from message submission and final delivery. The MVP follows enough_mail's current all-or-abort transaction: if any RCPT command fails, abort before DATA rather than submit to a subset. A successful RCPT response does not mean that recipient received a message. Expose attempted recipient responses through a reviewed adapter/fork change; when unavailable, report unknown rather than inventing a complete result map. Partial-recipient submission remains disabled until separately implemented and qualified. Sent-folder reconciliation is provider-specific and is not proof that exactly-once delivery is possible.

## 4. Implementation tasks

### M00 — baseline and workspace entry

**Depends on:** none.

- [x] Record current Quds commit and relevant source paths; preserve unrelated changes.
- [x] Inspect .fvmrc, root/package manifests and current commands; use Dart ^3.12.0 / Flutter >=3.44.0 or the repository's updated compatible pins.
- [x] Create a mail evidence directory containing a source/toolchain receipt, intended targets and initial dependency decisions.
- [x] Confirm no existing mail implementation has arrived since this planning snapshot before adding competing packages.

**Done when:** the agent can run the current workspace commands and identify new versus existing paths. Existing Office tests are recorded only if actually run.

### M01 — audited enough_mail fork and portable entry

**Depends on:** M00. **Files:** third_party/enough_mail; provenance and license inventory.

- [x] Retrieve reviewed upstream fc69f17e24e9d03ce813bbf613c07a2ce94e5e9a, whose manifest is 3.0.0; record source checksum and relationship to any chosen release archive.
- [x] Keep MPL LICENSE and notices; document local patches and source-release location. Do not relabel upstream files MIT.
- [x] Resolve exact dependencies and review the selected runtime source closure and notices; excluded CJK mapping modules remain unsupported. Product-specific LIC-02 artifact review is still open.
- [x] Add public lib/mime_core.dart with portable parser/model/codec exports. Do not export lib/mime.dart, lib/codecs.dart, native clients or File-based MessageBuilder through this entry.
- [x] Give quds_mail_mime a supported public import; do not import another package's lib/src.
- [x] Keep native APIs compiling. Split filesystem composition helpers into a native-only layer when shared composition is added.
- [x] Do not depend on enough_mail_flutter/html 2.x or force old wrappers through dependency_overrides.

**Acceptance:** actual native and JavaScript compilation of a tiny public-entry parser; original RFC fixture parsed in both runtimes; old native entry still analyzes. Static import review alone is not completion.

The inspected parser closure comprises these 19 local files; revalidate against the selected source:
mime_message.dart; codecs/date_codec.dart; codecs/mail_codec.dart; exception.dart;
imap/message_sequence.dart; mail_address.dart; mail_conventions.dart; media_type.dart;
message_flags.dart; mime_data.dart; private/imap/parser_helper.dart;
private/util/ascii_runes.dart; private/util/mail_address_parser.dart;
codecs/base64_mail_codec.dart; codecs/quoted_printable_mail_codec.dart;
imap/message_sequence.g.dart; mail_address.g.dart; private/util/byte_utils.dart;
private/util/word.dart. Paths are relative to upstream lib/src. External imports observed
in this closure are collection, json_annotation and enough_convert. This is a static
inspection receipt, not a complete dependency or runtime certification.

**Open qualification:** actual browser execution is blocked in this executor; see [status.md](status.md). Native/Node checks do not close that gate. M03 additionally requires the intended low-memory-device measurement.

### M02 — portable domain and host contracts

**Depends on:** M00. **Files:** quds_mail_core.

- [x] Implement the minimal typed models and ports from section 3, with explicit parse/provider error variants.
- [x] Define raw-message ownership, immutable attachment references, profile/account scoping and cancellation.
- [x] Define portable capability negotiation and typed unsupported results. The initial native/web transport dispatch is implemented under M06; its integrated local qualification is recorded in [status.md](status.md).
- [x] Add provider-independent state-machine tests for account disposal, stale operations and recipient-level outcomes.
- [x] Keep mail, calendar and contact capabilities separate; do not imply IMAP implements all three.

**Acceptance:** pure-Dart analysis and JS compilation; no Flutter/dart:ui/dart:io import in core; fixture provider demonstrates real state transitions without successful stub implementations.

### M03 — bounded MIME codec and original-byte preservation

**Depends on:** M01, M02. **Files:** quds_mail_mime.

- [x] Parse immutable bytes through the portable upstream surface and project into Quds DTOs.
- [x] Preserve original raw bytes/hash for source view and export; display decoding never overwrites originals.
- [x] Implement defaults: full input 32 MiB; preview input 20 MiB; cumulative decoded payload 32 MiB; body 8 MiB; attachment 16 MiB; 128 attachments; 512 parts; nesting 20; header block 256 KiB; logical header field 64 KiB.
- [x] Enforce budgets before unbounded allocation and during traversal/decode. Where the upstream whole-message parser cannot enforce a limit early, add a bounded pre-scan and/or a reviewed fork fix. An after-the-fact output-size check is insufficient.
- [x] Implement deterministic plain/HTML alternative selection, CID mapping, encoded headers/filenames, truncated/malformed diagnostics and supported charset tests.
- [x] Unsupported charset or syntax produces a diagnostic and source fallback, not silent replacement presented as exact text.
- [x] Add strict validation or reviewed decoder hooks for unknown charsets, malformed bytes and undecodable encoded words before lossy fallback. Replace uncontrolled upstream parser/codec print output with structured content-redacted diagnostics. Merely wrapping a permissive decoded string does not establish this contract.
- [x] Define bounded HTML/image work and limit handling, including cancellation on browser workers/native isolates where used.

**Tests to add:** test/eml_bytes_test.dart, mime_limits_test.dart, mime_encodings_test.dart, mime_parts_test.dart, portable_import_test.dart; independently authored fixtures under test/fixtures.

**Acceptance:** non-UTF-8/line-ending/signed-message original export has identical hash; malformed nesting/count/decode cases stop within limits; unknown header/body charsets, malformed UTF-8 and invalid encoded words produce explicit diagnostics without leaking source headers/body to console or logs; equivalent native/browser projection for supported fixtures; measured low-memory-target peak usage is retained. No streaming-parser claim.

**Open qualification:** actual browser execution is blocked in this executor; see [status.md](status.md). Native/Node checks do not close that gate. M03 additionally requires the intended low-memory-device measurement.

### M04 — shared account-free message reader

**Depends on:** M02, M03. **Files:** quds_mail_ui reader plus fixture harness.

- [x] Implement MailMessageView and an explicit decoded-message selection/search/copy interface usable in full and compact host views.
- [x] Headers, plain text, supported static HTML, attachment list, CID resources and diagnostic states.
- [x] Sanitize before rendering; block script/forms/active URLs, remote images, CSS url/import/background/srcset/font and equivalent resource routes.
- [x] Link/remote-content actions go through host policy. Use no WebView by default.
- [x] Keep Raw Source/Hex and attachment-open callbacks available to host routing.
- [x] Render RTL/mixed-direction addresses safely; preserve accessible labels and keyboard traversal.
- [x] Provide an in-memory preview harness that needs no account, credentials, database or network.
- [x] Host the same full/compact reader in CrispOffice for saved `.eml` messages. This account-free, read-only dialog does not complete the account-aware mailbox workspace, composer or SMTP submission. Its later integration evidence belongs to the [host report](../../validation/office-main-integration-20261119/host-final/README.md).

**Acceptance:** the injected resource/network port observes zero requests, and native/browser harnesses also monitor or deny outbound traffic at the runtime boundary after app bootstrap. Exercise ordinary remote images, CSS resources, srcset, protocol-relative/encoded URLs and redirects. Test explicit user-approved loading separately. Exact attachment bytes reach the read-only callback; no writable source path is fabricated; full/preview modes use their proper budgets. This enables CC-01 through CC-04, but migration waits for host parity tests.

**Open qualification:** actual browser execution is blocked in this executor; see [status.md](status.md). Native/Node checks do not close that gate. M03 additionally requires the intended low-memory-device measurement.

### M04W — reusable account-aware mailbox workspace

**Depends on:** M04 and M05; connected acceptance also requires M06/M07. **Files:** quds_mail_ui/workspace.

- [x] Extend connected and cached lists with bounded structured loaded-header
  search, visible To/Cc and local-calendar date predicates, observed flag
  filters, stable local sorting and localized help/errors. Preserve scope,
  IME input and stale-activation guards; never issue provider work from search.
  See [header-search.md](header-search.md). Full account search remains below.
- [x] Add [foreground bulk read/flag](bulk-flags.md) with frozen visible
  selections, exact account/provider/mailbox identities, sequential explicit
  assignments and confirmed/failed/uncertain/unattempted outcomes. Stop after
  the current request, require refresh after uncertainty, reject stale scopes
  and preserve unknown independent flags. Show localized progress and frozen
  per-message receipts. The durable continuation is recorded next.
- [x] Journal native single/bulk read and flag commands before dispatch; retain
  typed outcomes, interrupted uncertainty and definitely unattempted tails across
  restart. Atomically patch exact cached flags, preserve owner/revision guards
  and expose paginated connected/offline history with bounded safe cleanup.
  See [command-journal.md](command-journal.md). No automatic replay is enabled.
- [x] Reconcile historical uncertainty against explicit fresh provider
  observations, retaining evidence and detecting UIDVALIDITY, identity and
  concurrent-change conflicts before closing unresolved receipts.
  See [flag-recovery.md](flag-recovery.md). Later observations remain separate
  from the original uncertain outcome; no command is replayed.

- [x] Deliver the bounded foreground-list foundation: shared virtualized loaded-message list, stable identities, local subject/sender search, conjunctive unread/flagged filters, keyboard activation, compact reader/Back state and explicit 50-message pagination across native Studio hosts. Native IMAP browsing has its own scoped descending-UID cursor and a 1,000-loaded-message host ceiling; confirmed flag actions preserve nullable observations. See the [contract](mailbox-workspace.md) and [local evidence](../../validation/mail-workspace-20261120/README.md). This is a prerequisite slice and does not close the broader items below.
- [x] Qualify the native [remembered IMAP/SMTP account chooser](remembered-accounts.md) with deterministic storage/provider fixtures: bounded selected-backend catalog, verified legacy migration, explicit selection/connection, selected-only Forget and unchanged per-account draft recovery. See the [local qualification and source-bound evidence](../../validation/mail-accounts-20261120/README.md). The four-provider connected continuation is recorded below.
- [x] Persist dated ordered views of visited folders and explicitly opened body/attachment snapshots for credential-free cached reading across native IMAP, EWS, Gmail and Microsoft 365. Preserve stable identities, exclusive draft/cache ownership, transactional revision/lease checks and separate sync cursors. See [cached-mailboxes.md](cached-mailboxes.md). Loaded windows do not imply complete or currently synchronized folders.
- [x] Observe bounded saved folder/catalog streams in native connected and
  cached sessions. Preserve selected readers on metadata changes, display
  saved-view unread/unknown counts, retain original provider action identities,
  reject stale account/folder and queued events, and drain subscriptions before
  owner close. See [repository-sessions.md](repository-sessions.md).
- [x] Connect native provider sync to the owned repository through explicit
  bounded resumable folder runs. Persist checkpoint state with each atomic page,
  preserve stable account/cache IDs across reconnects, distinguish partial from
  completed observations, and expose local paginated headers/cached bodies in
  connected and credential-free offline dialogs. See [durable-sync.md](durable-sync.md).
- [x] Add explicit single-message/current-page body and attachment downloads to
  synchronized native folders. Bound each request and cumulative retained
  content, skip complete exact-identity snapshots across restarts, preserve
  draft/Outbox/cursor state, and drain cancelled work before releasing the
  owner. See [offline-downloads.md](offline-downloads.md). Automatic retention
  policy and background scheduling remain separate work.
- [ ] Implement QudsMailWorkspace with account/folder or label navigation, paginated/virtualized message and conversation lists, stable selection and coordinated reader/composer sessions.
- [x] Search retained browse/synchronization headers across folders and native
  account profiles using the existing Boolean query. Preserve account/folder
  provenance, explicit cache coverage, bounded continuation, stale-query and
  owner guards, and local-only result opening. See
  [unified-cached-search.md](unified-cached-search.md). This separate chooser
  workflow does not complete the shared workspace, body or server search.
- [ ] Extend repository-observed browsing to authoritative synchronized lists,
  unread counts and full account search in the shared workspace; keep loading,
  empty, offline, synchronizing, failed credentials and unsupported capabilities
  distinct. The separate foreground sync dialog does not complete this requirement.
- [x] Extend the existing durable command journal to foreground single-message
  Move/Delete with exact destinations, provider capabilities, confirmation,
  restart uncertainty and dated-cache boundaries. Preserve read/flag observations
  while retiring membership subscriptions. See [durable-mutations.md](durable-mutations.md).
- [x] Add confirmed visible-selection Move/Delete with exact destination previews,
  frozen identities, per-message outcomes, stop-after-current and durable restart
  evidence. See [bulk-organization.md](bulk-organization.md) for provider limits
  and the local validation record.
- [x] Add reviewed single-message and checked-selection Archive through the
  durable journal. Gmail removes only Inbox membership; IMAP and Microsoft 365
  resolve authoritative ordinary Archive destinations, and unavailable discovery
  or EWS requires an explicit same-account folder. Preserve frozen identities,
  exact Move receipts, uncertainty and restart recovery. See
  [provider-archive.md](provider-archive.md).
- [x] Add a bounded remembered-account chooser for IMAP/SMTP, EWS, Gmail and
  Microsoft 365 in Studio. Preserve exact non-secret routes, explicit sign-in,
  account-owned drafts/uncertainty and one foreground connection. Drain cached
  observers, journal writes and owners before handoff; fence late acquisitions
  and retired callbacks. Retain failed observer/owner release for explicit close
  recovery; a failed release never authorizes another account. Refresh selected
  native directory records atomically
  against the expected record; custom directories without conditional refresh
  retain their existing metadata. See
  [connected-account-navigation.md](connected-account-navigation.md) and its
  source-bound qualification record. This does not complete the shared workspace.
- [ ] Broaden provider-specific membership reconciliation and special-folder
  discovery, remember custom Archive destinations, and add tags/categories with
  preview and recovery.
- [x] Implement visible checked ranges in the shared list with Shift navigation,
  Shift+click, preserved independent checks and generation/scope guards, plus
  EN/DE/AR help. Correct synchronized header search to include visible names
  and addresses. Fresh local qualification passes 272 shared UI and 176 Studio
  cases, with strict analysis and formatting. See
  [keyboard-triage.md](keyboard-triage.md).
- [ ] Provide responsive single-pane mobile and multi-pane desktop layouts, keyboard actions and accessible focus movement. Lists/navigation are host chrome, not replacement document editors.
- [ ] Extend the delivered Studio foreground handoff into the shared workspace
  and both hosts, with simultaneous account/profile lifecycle ownership,
  background scheduling and unified live folders. Preserve the existing
  selection/attachment/credential/callback fences and account-owned draft recovery.
- [ ] Accept host navigation/attachment/composer services by injection; do not instantiate CrispCloud or standalone global services.

**Acceptance:** the same workspace package runs in both hosts; account switching, pagination, search, action recovery and compose/read coordination pass with deterministic provider fixtures and the qualified native adapter. Reader-only and composer-only demos do not satisfy this task.

### M05 — local store, search and recovery journal

**Depends on:** M02. **Files:** quds_mail_store.

- [x] Implement Drift/SQLite schema and transactional repository streams using independently resolved approved dependencies.
- [x] Native app-container store and separately configured browser store; explicit quota/storage-unavailable results. The browser opener compiles; actual browser persistence remains unqualified.
- [x] Durable drafts and immutable outbox/blob references, atomic page+cursor commits with expected-cursor comparison, tombstones and transactional migration versioning.
- [x] Reconcile authoritative closed IMAP UID ranges within the same transaction: remove absent stored memberships, preserve mailbox/UIDVALIDITY isolation and pending-edit evidence, and create no tombstones for numeric gaps.
- [x] Add nullable durable standard flag snapshots and additive schema v3 migration from v1/v2. Omitted observations preserve known flags; observed empty snapshots clear them. Flags/migration tests passed in the integrated local qualification linked below.
- [x] FTS indexing of supported plain text and metadata; cap indexing work, avoid remote fetch as a side effect of local search. HTML-only bodies are not interpreted by search.
- [x] Account deletion, cache eviction, logout and pending-operation policies, including durable host-vault cleanup and retired local identities.
- [x] Simulate crash/restart at transaction boundaries and preserve unsent work. Native process-kill and file-backed migration/recovery evidence is retained separately from injected rollback cases.

**Acceptance:** reopen offline and recover drafts/queue; half-applied sync page cannot advance cursor; cache eviction does not lose outgoing attachments; account/profile isolation; browser quota failure is explicit. No secrets or body data in diagnostics.

**Implementation/evidence:** [quds_mail_store](../../../packages/quds_mail_store/README.md)
and the [19 November continuation](../../validation/mail-m06-resume-20261119/README.md).
The fresh baseline at `479e1e038af0467b7f07b35d80bac9e4cc60a198` passed its
complete Mail gate: 186 test executions across core/store VM and Node cohorts,
42 Python launcher regressions, strict analysis, formatting and compilation
checks. Its 72-suite Office/reader gate also passed with 1,230 cases. The earlier
[failed store attempt](../../validation/mail-store-20261118/README.md) remains
historical evidence; its runner/formatting blockage is resolved for the fresh
baseline. Those results predate schema v3 and native transport. The
[preserved pre-Arabic integration report](../../validation/office-main-integration-20261119/pre-arabic-report.md)
records the earlier 632-execution / 562-distinct-case qualification at
`ac1e4c8c`, including a fresh 199-execution core/store gate. The
[retained completion report](../../validation/office-main-completion-20261119/README.md)
records its separate full 199-execution core/store gate at `5569c055`,
within its 836 application executions and 78 separate Python controls.

The discovered-UID source at `29dd23a6edd0a0fbb916b3d9f73861a8aa4f435e` has a
fresh **250-execution / 162-distinct-scenario** core/store gate. It belongs to
the **608-execution / 508-distinct-scenario / 33-suite** Mail subset in the
[qualified UID checkpoint](../../validation/office-main-integration-20261119/latest-final/README.md).
Exact Mail source/dependency continuity supports retaining that result during
the subsequent host integration; execution remains attributed to `29dd23a6`.
The [later host report](../../validation/office-main-integration-20261119/host-final/README.md)
records its separate selection and source. None of these runs is added to an
older source-qualified total.

Browser entry/worker compilation and Node error-policy tests do not close actual
browser storage, Web Locks, reload or quota acceptance. Chromium previously
failed before startup under this executor's socket restriction. Database contents
are not encrypted; container protection and credential-vault separation are
distinct from encryption. M06 is partially implemented; M07 and M04W remain open.

### M06 — native accounts, authentication and IMAP synchronization

**Depends on:** M01, M02, M05. **Files:** quds_mail_transport native adapter and core sync.

- [x] Manual IMAP endpoint/account configuration with validated host/port, required STARTTLS or implicit TLS, and no cleartext fallback or certificate bypass. SMTP configuration and bounded discovery are not included.
- [x] Qualify real Linux loopback TLS success, trust/hostname refusal, cancellation/deadlines and write lifecycle on the default owned connector, preserving certificate validation.
- [ ] Add SMTP configuration and optional bounded account discovery after validation; qualify external-provider and other-OS TLS interoperability.
- [x] Load current host-owned password/token bytes for each operation using account/profile/host-scoped vault references. Negotiate XOAUTH2/OAUTHBEARER protocol capability and keep credential material out of ordinary account rows and public diagnostics.
- [ ] Implement native system-browser OAuth/PKCE, registered redirect handling, token refresh and platform credential-vault hosts. No embedded confidential secret.
- [x] Discover selectable folders, fetch bounded header/flag pages over discovered UIDs, retrieve exact full-message literals on demand, and apply observed UID flag changes and capability-gated MOVE. Delete marks only `\Deleted`, without mailbox-wide EXPUNGE or CLOSE.
- [x] Page by strictly discovered existing UIDs across sparse/high numeric UID spaces; reconcile actual stored absences through typed closed UID ranges and preserve v1/v2 cursor continuation and advance a monotonic per-page revision. Qualification is tracked in the [discovery continuation](../../validation/mail-uid-pagination-20261119/README.md).
- [ ] Add discovery beyond bounded simple SEARCH, archive/destination workflows and individual body-part retrieval beyond the initial full-message fetch boundary.
- [x] Use stable account/mailbox/UIDVALIDITY/UID identities and scoped transactional cursors. Request mailbox reset when UIDVALIDITY changes; never persist sequence-number identities.
- [x] Implement an explicitly bounded full-sweep fallback that revisits old flags and expunges. Advertise no IDLE/CONDSTORE/QRESYNC behavior that is not implemented.
- [ ] Add IDLE/CONDSTORE/QRESYNC only with genuine adapter/server support and independent qualification; retain a correct fallback.
- [x] Enforce finite operation timeouts, account-lease cancellation and typed credential-revocation/ambiguous-mutation outcomes. Do not automatically retry operations.
- [x] Add explicit native foreground folder synchronization and user-requested
  continuation across restart/reconnect, with bounded pages, cancellation,
  cursor-loop detection and persistent partial/completed observations.
- [ ] Add automatic foreground/resume scheduling and bounded provider rate/backoff policy with recovery controls.
- [x] Provide a conditional browser entry returning typed unsupported for generic socket transport without accessing the vault/codec or importing the native socket implementation. The unsupported entry passed three Node cases in the integrated gate; this does not qualify browser socket transport.

**Implemented foundation and limits:**
[quds_mail_transport](../../../packages/quds_mail_transport/README.md) is present,
but M06 is not complete. `maxDiscoveredUids` defaults to **10,000** and has an
upper limit of **100,000**; it bounds existing UIDs in each complete
remaining-range SEARCH response. Protocol byte budgets can bind sooner. Exceeding
either budget fails with `quotaExceeded` before FETCH or commit. Numeric gaps
consume neither the page limit nor tombstone storage. An optional explicitly
supplied legacy `maxUidScan` retains its old numeric ceiling and `unsupported`
outcome; no numeric ceiling applies by default. Repeated simple SEARCH remains
a bounded fallback, with ESEARCH/PARTIAL optimizations outside this increment.
Direct on-demand retrieval of a specified high UID remains available.
Cursors freeze each sweep ceiling, and arrivals beyond it enter the
next sweep; the fallback is not a server snapshot protocol. MOVE confirms source
absence but does not expose COPYUID destination identities. Controlled parser,
SQLite/coordinator, lifecycle and conditional-entry tests passed in the
[32-suite earlier qualification](../../validation/office-main-integration-20261119/pre-tls-report.md)
at `7d279e084bae438d383630726ad7b0514da77d35`, with 389 focused cases. The
[retained qualification](../../validation/office-main-completion-20261119/README.md)
at `5569c055a021c893e941fc54d40499ad9d96a5db` adds broader protocol coverage and
real Linux TLS tests within its separate 836 application executions. The
[earlier combined qualification](../../validation/office-main-integration-20261119/pre-arabic-report.md)
at `ac1e4c8c788ea608402c2260488235c0189efcba` passed 433 focused cases across
35 suites, including 26 TLS/ownership cases and the rejected-upgrade cleanup,
plus the fresh 199-execution core/store gate. External-provider, other-OS and
disposable-account interoperability remain open.
The applicable discovered-UID Mail result is the separately recorded **608
executions / 508 distinct scenarios / 33 suites** at `29dd23a6`, including the
fresh 250-execution store/core gate, 346 focused Mail cases and 12 repeated Node
configuration cases. The later CrispOffice saved-message dialog has its own host qualification
report and does not complete M04W or M07.
The 186-execution Mail and 1,230-case Office passes above retain their separate
baseline `479e1e03` identity.

**Acceptance:** controlled IMAP transcripts/local test server cover UIDVALIDITY reset, missing extensions, expunge/move, dropped connections, stale credentials and bounded fetch. Real interoperability uses explicit disposable test accounts and retains no private mail/credentials in fixtures.

### M07 — composer, MIME generation and SMTP submission

**Depends on:** M03, M04, M05; native send also M06.

**Foreground increment:** [recipient groups and Reply all](recipients-and-reply-all.md)
now provide bounded To/Cc/Bcc composition, explicit-envelope Bcc separation,
visible-participant replies and retained uncertain drafts in the Studio host.
The later [outgoing attachment increment](attachments.md) adds immutable local
file snapshots, atomic/cancellable selection, ten-file/10 MiB limits, exact
base64 parts and ASCII-safe RFC 2231 filenames to that shared foreground path.
The pure draft model is independent of the widget surface. Current locked-graph
qualification is recorded with the attachment increment, separately from the
earlier recipient subset. The [draft recovery continuation](draft-recovery.md)
adds one durable local draft per connected account, debounced autosave and
interrupted-send recovery to SMTP, EWS, Gmail and Graph. The later
[Outbox continuation](outbox.md) atomically transfers a saved draft into a frozen
queue and exposes explicit send/retry/cancel with restart recovery. The
[reply/forward continuation](reply-forward.md) adds complete supported attachment
forwarding. The [multiple-draft continuation](multiple-drafts.md) adds independent
local drafts and offline entry for remembered explicit-server/preset IMAP
accounts. The [verified-account continuation](offline-accounts.md) extends local
draft entry to autodiscovered IMAP, EWS, Gmail and Microsoft 365 after successful
connection. [Cached mailbox views](cached-mailboxes.md) now retain visited
folder windows and explicitly opened content. Richer bodies, full offline
synchronization, server draft synchronization,
Sent reconciliation and live-provider gates remain open; this does not complete
M07 or the document-snapshot work in M08.

- [x] Add bounded outgoing file attachments to the shared Studio foreground
  composer and retain their immutable bytes across rejected/uncertain attempts.
- [x] Typed draft model, identity/To/Cc/Bcc, subject, attachments and reply/reply-all/forward, with independently retained local drafts per native account. Preserve incomplete recipient text separately from validated transport addresses.
- [x] Debounce saves, flush close/send, expose pending/saved/failure states, compare revisions, retain immutable attachment blobs and restore after reconnect. Explicit confirmed unsaved exit remains available during storage failure.
- [x] Persist a possible-submission marker before provider invocation. Recover interrupted sends with explicit delivery-check acknowledgement; clear accepted/discarded drafts durably. Only a matching definite rejection can retire the current attempt's marker, preserving any earlier uncertainty.
- [x] Reuse the Word custom RenderBox surface for the plain-text body, including IME, selection, undo, bidi and accessibility. Rich mail formatting remains below.
- [x] Add a bounded local draft list with independent IDs/revisions, new/resume/delete actions, per-draft uncertainty and exact Outbox handoff. Preserve the legacy draft and reject stale selection callbacks. See [multiple-drafts.md](multiple-drafts.md).
- [x] Add save-only offline draft entry for remembered IMAP accounts with explicit servers or a provider preset, without constructing a provider or discovering settings.
- [x] Persist bounded non-secret verified connection identities for autodiscovered IMAP, EWS, Gmail and Microsoft 365; reopen their original local draft catalogs without credentials, discovery or provider construction. Preserve exact account fingerprints and compare shortcut removal revisions. See [offline-accounts.md](offline-accounts.md).
- [x] Bind cached mailbox reads to stable account identities and durable visited-folder views, without credentials or provider construction. Preserve local drafts/Outbox and expose missing bodies explicitly.
- [x] Persist foreground read/flag commands and their recovery evidence separately from drafts and outgoing-message submission. See [command-journal.md](command-journal.md).
- [ ] Add general durable synchronization commands and repository-driven foreground account/folder sessions, then provider-side Drafts synchronization with explicit conflicts. Cached browse windows and the flag journal do not complete this boundary.
- [x] Implement account-scoped plain-text signatures, independent new/reply defaults
  and literal Quick Text with additive schema 10 persistence, revision guards
  and connected/offline composer integration. See [compose-tools.md](compose-tools.md).
- [x] Execute and qualify the writing-tools model, migration, adapter and widget
  regressions on the pinned toolchain. Subsequent Word integration and the
  scheduled-send continuation retain the successful local results separately
  from the original executor failure.
- [ ] Add multiple sender identities/alias routing and full-message templates;
  saved writing tools do not change transport identities or recipient fields.
- [ ] Initial canonical body supports paragraphs, line breaks, emphasis, lists and links; add tables/inline images only with serializer/round-trip tests.
- [ ] Generate multipart plain/HTML with deterministic boundaries and transfer encodings; preserve quoted original content as data.
- [ ] Generate ASCII-safe wire MIME for the current text-oriented enough_mail SMTP API. Encode display names/subjects/filenames and payloads correctly. Handle non-ASCII mailbox local parts through negotiated SMTPUTF8 or explicit unsupported feedback.
- [ ] Keep Bcc recipients in the SMTP envelope and out of transmitted headers, including folded/case-varied header cases.
- [ ] Use the DATA submission path initially. Preserve the current all-or-abort RCPT policy and add typed recipient-attempt outcomes in the adapter/fork where the library exposes only an aggregate error. A failed RCPT followed by RSET must leave every recipient marked not submitted, never delivered. BDAT or partial-recipient delivery requires separate qualification before enabling it.
- [x] Freeze the saved draft revision, MIME and complete envelope together; atomically clear the source draft; expose native account-scoped queued/submitting/accepted/failed/uncertain/cancelled states, restart recovery, explicit send/retry/cancel and guarded terminal cleanup. No automatic uncertain retry or reconnect sending.
- [x] Add bounded Outbox review, exact EML/private-envelope export, atomic edit into a new draft and explicit local closure of uncertain records without resending or fabricating delivery. See [outbox-management.md](outbox-management.md).
- [x] Add durable undo-send delay and explicit foreground scheduling on the frozen-entry foundation, with persistent UTC eligibility, clock/restart handling, explicit resume and cancellation before provider invocation. See [scheduled-send.md](scheduled-send.md); server/OS background execution remains separate.
- [ ] Complete partial-recipient results, live SMTP transcript qualification and provider-specific Sent-folder reconciliation. Background execution requires its own ownership/lifecycle acceptance.
- [ ] Do not send imported arbitrary raw MIME through a text path and call it byte-exact. Byte-stream SMTP is a separate extension.

**Acceptance:** raw SMTP transcript proves envelope/header separation, DATA dot handling, MIME bytes and final-response semantics; mixed 250/550 RCPT replies cause RSET and no DATA; injected CR/LF is rejected; connection loss after potential acceptance yields uncertain, not automatic resend; reopen preserves draft and queue. Submitted means accepted by the submission server, not final delivery. Large-file behavior respects declared limits without claiming BDAT means streaming memory.

### M08 — Office attachment and document-to-mail workflows

**Depends on:** M04, M07. **Files:** quds_mail_office.

- [ ] Preview DOCX/XLSX/PPTX/PDF and supported report documents through existing public Quds APIs.
- [ ] Read-only received attachment -> separate editable working copy -> explicit exported file or new draft attachment.
- [ ] Document command: attach current saved/snapshotted document, or export and attach a PDF.
- [ ] Commit pending edits before snapshot, capture controller identity/revision, handle disposal/stale results, and distinguish attaching a copy from saving the original.
- [ ] Preserve source format/type and current STANDARDS limits; do not silently flatten unsupported structures to claim edit support.

**Acceptance:** test attachment hash/immutability, cancelled edits, concurrent document changes during async save, failed persistence, two open documents and reply with edited copy. Existing editor undo/save tests relevant to touched behavior pass.

### M09 — full standalone Office host

**Depends on:** M02/M04 for initial shell, M04W and M05–M08 for functional Office+Mail.

- [ ] Create apps/quds_office; adapt approved MIT Studio shell code selectively and record provenance. No CrispCloud app/shell imports.
- [ ] Provide document home, open/new/save/save-as/export, tabs/windows, recent documents and unsaved-close behavior.
- [ ] Host Word, spreadsheet, slide, PDF and report surfaces; route Mail and later Calendar/People without resetting document sessions.
- [ ] Wire scoped file access, vault, store, lifecycle and notification ports. Local documents/EML work without cloud signup.
- [ ] Remove runtime dependence on sample galleries, development daemons or external executable helpers.
- [ ] Add platform targets and build configuration without changing the existing Report Studio app or Office example's behavior.

**Acceptance:** create/edit/save/reopen each supported document kind; receive/preview/edit/reply workflow; offline start with documents and cached mail; distinct app profile; document/Mail navigation preserves state. A mail-only sample does not close this task.

### M10 — CrispCloud integration and regression preservation

**Depends on:** M04 for the initial saved-EML reader; M08 for editable Office working copies; M04W and M05–M07 for the full client. The reader migration does not wait for composition or SMTP.

- [ ] Execute CC-01 through CC-10 in [crispcloud-integration.md](crispcloud-integration.md).
- [ ] Vendor/pin the same canonical packages and approved MPL fork; extend source/hash inventory.
- [ ] Keep EML reader migration and live Mail workspace enablement independently gated.
- [ ] Preserve MSG/MBOX routes, F3/preview behavior, raw F4 source editing, attachment bytes and read-only targets.
- [ ] Implement host adapter without importing AGPL implementation into Quds; run the existing host regression tests in CrispCloud.
- [ ] Record combined-host AGPL/distribution status honestly; do not use shared-package licensing as proof about the complete app.

**Acceptance:** same shared reader/version exercised by both products, documented host parity, no document/viewer regressions, explicit account/profile isolation.

### M11 — provider adapters beyond generic mail

**Depends on:** M05–M07; common contracts remain provider-neutral.

- [ ] Microsoft Graph cloud mail: delegated auth, folder delta state, stable/immutable ID strategy, send/draft operations and rate/consent states.
- [ ] Gmail: labels/threads/history, cursor-expiry full recovery, send/drafts and explicit OAuth verification status.
- [ ] JMAP mail where supported: session/capability discovery, state tokens, bounded fetch, changes and submission.
- [x] Keep Microsoft cloud support on Graph. The separately prioritized
  [on-premises EWS provider and Studio entry](exchange-ews.md) now provide native
  mail read/sync/mutations/submission. Its live-server and wider productivity
  acceptance boundaries are tracked separately.
- [ ] Native/web support is verified per endpoint/redirect/CORS combination; no generic web success claim.

**Acceptance:** fixture/API-contract tests and disposable-account interoperability for each enabled adapter; feature matrix distinguishes implemented, unsupported and unqualified capabilities. Google production access is a release gate, not something tests can certify.

### M12 — Calendar, People and mail-linked tasks

**Depends on:** M02/M05/M11 where provider-specific data is required.

- [ ] Separate calendar/contact provider interfaces and typed models; local data supports a usable initial UI.
- [ ] Invitations and replies using iCalendar/iTIP semantics: event UID, sequence, recurrence ID, organizer/attendees, status, updates/cancellation and deduplication.
- [ ] Preserve wall-clock time, timezone identity, all-day/floating-time semantics, recurrence rules/exceptions and provider version/ETag.
- [ ] Day/week/month views, contacts/address completion and mail-to-task links; do not send a meeting response solely by opening an invitation.
- [ ] Graph calendars/contacts; Google Calendar/People; CalDAV/CardDAV when configured.
- [ ] Audit recurrence/timezone libraries. Current Dart rrule limitations require adaptation/conformance tests; no claim of complete recurrence from its license or package description.

**Acceptance:** DST transition, moved/cancelled single occurrence, series update, all-day cross-zone display, stale invite, duplicate response, conflicting contact edits and unsupported provider capabilities. Personal OS Calendar/Contacts integration is optional and distinct from provider access.

### M13 — Apple packaging and source distribution

**Depends on:** relevant functional milestones; start dependency/entitlement review early.

- [ ] Execute LIC-01 through LIC-12 in [licensing-and-app-store.md](licensing-and-app-store.md).
- [ ] Qualify iOS/iPadOS and macOS standalone builds separately, and separately assess any CrispCloud build.
- [ ] Inspect signed archives, entitlements, privacy manifests, source links, secure storage, OAuth redirects, file grants, encryption declaration and background behavior.
- [ ] Include build-specific source/notices and open-source information within the product.
- [ ] Optional default-mail entitlement is a later capability, not a blocker to ordinary mail development.

**Acceptance:** retained evidence for the exact archive/commit. A simulator build, TestFlight availability or development run alone is not App Store acceptance. Do not submit a release as part of routine implementation.

### M14 — compatibility, performance and handoff

**Depends on:** the milestone being released, not necessarily all future enterprise features.

- [ ] Test agreed mailbox-size/attachment-size profiles and record device, memory, latency and cancellation behavior.
- [ ] Pin native/browser supported encoding and MIME corpus coverage; identify unsupported cases.
- [ ] Retain both-host integration results and dependency/source inventories.
- [ ] Update this checklist, README status and root roadmap with actual delivered behavior and limitations.
- [ ] Record remaining provider, platform and distribution gates so another agent can resume without inferring success.

**Acceptance:** each release claim maps to a test/source/build record; no placeholders, inherited unrelated test totals or unverified App Store claims.

## 5. Suggested verification commands

These commands are for the implementing agent after the named packages/tests exist.
Use the repository's pinned Flutter/FVM invocation; do not assume dependencies are installed.
Run commands from the indicated directory rather than hiding failures in a long shell chain.

~~~bash
# Repository root, after registering implemented workspace members:
flutter --version
dart --version
flutter pub get

# From packages/quds_mail_core:
dart analyze --fatal-infos
dart test

# From packages/quds_mail_mime:
dart analyze --fatal-infos
dart test
dart test --platform chrome
mkdir -p build
dart compile js test/compile/portable_import.dart -o build/portable_import.js

# From each implemented Flutter package:
flutter analyze --fatal-infos
flutter test

# From apps/quds_office:
flutter test
flutter build web
flutter build macos --release
flutter build ios --release --no-codesign
~~~

The Apple build commands require macOS/Xcode; final signed archive verification is separate.
Create the portable-import harness in M03; it must use only the public portable entry.
For real browser tests use an available supported browser and record the environment.
Run focused existing Quds editor tests for behavior touched by M08/M09 and the explicit CrispCloud
tests named in its integration document. Broaden testing to resolve a specific risk or satisfy a
release gate; do not wait on unrelated hosted jobs.

## 6. Source references for implementation decisions

- [Scope and inspected source map](README.md#2-inspected-baseline-and-repository-map).
- [Reviewed enough_mail source](https://github.com/Enough-Software/enough_mail/tree/fc69f17e24e9d03ce813bbf613c07a2ce94e5e9a), especially lib/src/mime_message.dart, lib/src/mime_data.dart, lib/src/smtp/smtp_client.dart and private SMTP commands.
- [SMTP](https://www.rfc-editor.org/rfc/rfc5321.html), [message format](https://www.rfc-editor.org/rfc/rfc5322.html), [MIME](https://www.rfc-editor.org/rfc/rfc2045.html), [internationalized mail](https://www.rfc-editor.org/rfc/rfc6531.html).
- [IMAP rev2](https://www.rfc-editor.org/rfc/rfc9051.html), [CONDSTORE/QRESYNC](https://www.rfc-editor.org/rfc/rfc7162.html), [JMAP mail](https://www.rfc-editor.org/rfc/rfc8621.html).
- [iCalendar](https://www.rfc-editor.org/rfc/rfc5545.html), [iTIP](https://www.rfc-editor.org/rfc/rfc5546.html), [CalDAV](https://www.rfc-editor.org/rfc/rfc4791.html), [CardDAV](https://www.rfc-editor.org/rfc/rfc6352.html).
- [Graph message delta](https://learn.microsoft.com/en-us/graph/delta-query-messages), [immutable IDs](https://learn.microsoft.com/en-us/graph/outlook-immutable-id), [Gmail sync](https://developers.google.com/workspace/gmail/api/guides/sync), [Google Calendar sync](https://developers.google.com/workspace/calendar/api/guides/sync), [People API](https://developers.google.com/people/v1/contacts).

