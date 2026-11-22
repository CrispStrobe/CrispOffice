# Quds Mail and standalone Office — implementation scope

**Status:** accepted product scope; the core, MIME codec, account-free reader and
durable Mail store now have an initial implementation. See [status.md](status.md) for demonstrated
checks and open gates. The wider product scope remains unchanged.
The [archive and search guide](archive-search.md) tracks the independent durable
archive, Studio workflows and remaining MailStore parity work.
**Decision date:** 2026-11-18 (Europe/Berlin); on-premises EWS prioritized 2026-11-19.
**Canonical repository:** CrispStrobe/quds_office_suite, branch main.
**Entry point for a fresh coding agent:** read this file, then [implementation-plan.md](implementation-plan.md). The [CrispCloud contract](crispcloud-integration.md) and [licensing/App Store requirements](licensing-and-app-store.md) are part of the same specification. No prior chat is required.

## Desktop mail parity: ordered increments

The [account-navigation workflow](account-navigation.md) and
[connected-account continuation](connected-account-navigation.md) provide one
verified remembered-account chooser across IMAP/SMTP, Exchange EWS, Gmail and
Microsoft 365. Exact non-secret routes lead to explicit sign-in. Switching saves
the retained draft and uncertain-submission state, drains observers, journal
writes and owners, and fences stale routes and late acquisitions. Atomic
selected-record refresh cannot recreate a forgotten shortcut. One account stays
connected at a time; retained simultaneous sessions and an account-aware unified
workspace remain open. The linked work records identify actual qualification.

The [explicit Archive continuation](provider-archive.md) adds reviewed single and
checked-selection Archive to connected mail. Gmail removes only Inbox membership;
IMAP and Microsoft 365 resolve an authoritative ordinary Archive destination,
while EWS and unsupported discovery require explicit folder selection. All paths
reuse durable command outcomes and restart recovery. Account navigation is
continued above. Remembered custom Archive destinations, tags/categories and
ordered rules remain organization boundaries; retained multi-account sessions
and a unified workspace remain part of M04W.

The [durable bulk organization continuation](bulk-organization.md) adds
capability-scoped Move/Delete to checked visible selections. Confirmations show
the count, account, source and exact destination; every selected identity is
frozen before prompts and revalidated before dispatch. The existing journal
preserves per-message outcomes, stop-after-current behavior and restart evidence
across IMAP, EWS, Gmail and Microsoft 365. Explicit Archive and connected account
navigation are continued above; ordered rules remain subsequent work.

The [authoritative move continuation](identity-transitions.md) preserves IMAP
COPYUID and EWS replacement identities through the durable journal. Exact
retained folder entries reconcile atomically when local evidence is current;
stale state or cache limits keep the acknowledgement and require refresh.
Null-safe synchronization snapshots prevent older pages from restoring moved
messages. Studio translates stable account/cache identities and shows saved
acknowledgement status in EN/DE/AR. Visible-selection Move/Delete is continued above.

The [membership recovery continuation](membership-recovery.md) adds explicit
current-location checks for uncertain Move/Delete in connected Mail activity.
IMAP UID generations/deletion markers, Gmail labels and Graph/EWS parent folders
have separate exact-identity semantics. Latest observations persist with check
times while original uncertainty, cleanup protection and dated cache views stay
intact. IMAP/EWS identity transitions and guarded cache reconciliation are
continued above, followed by visible-selection Move/Delete and connected
account navigation.

The [durable Move/Delete continuation](durable-mutations.md) journals connected
single-message organization with exact destinations, pre-dispatch persistence,
restart evidence and explicit provider capabilities. IMAP gains Move and Mark
deleted controls; EWS/cloud retain their distinct trash semantics. Membership
uncertainty cannot use flag-only status checks and never replays. Current-location
checks, guarded cache reconciliation and visible-selection Move/Delete are
continued above, followed by the connected account-navigation increment.

The [folder-set continuation](folder-saved-search.md) adds explicit saved-search
folders across verified accounts, stable identity-based persistence, filtered
paging/provenance and per-folder coverage. Missing folders remain visible and
require explicit repair; they never broaden the search. Legacy all-folder
definitions remain compatible. Unified retained-folder navigation is now
implemented; durable single-message Move/Delete is continued above.

The [keyboard triage increment](keyboard-triage.md) adds visible checked ranges
with Shift navigation/click, preserves independent selections and resets anchors
on projection/host changes. Synchronized loaded-header search now includes
From/To/Cc names and addresses consistently. EN/DE/AR selection help and focused
regressions are included. Fresh native qualification passed 272 shared Mail UI
and 176 Studio cases, including the 48 new regressions; changed Dart paths also
pass strict analysis and formatting. The original outage and interrupted test
attempt remain in the work record. Its planned saved-search folder-set increment
is now implemented in the continuation above.

The [saved-search refresh increment](live-saved-search.md) adds an explicit
replacement scan and opt-in 30-second foreground updates over retained headers.
It preserves an opened reader when its result survives, reports incomplete
coverage and pauses on failure or app suspension. Repository-event-driven
shared views and a continuously synchronized unified inbox remain open.

The [scheduled-send increment](scheduled-send.md) adds saved UTC deadlines and
a ten-second pre-submission Undo window to native Outbox. Scheduling and Resume
explicitly arm one foreground attempt; reopening and refreshing never send.
Lifecycle, clock changes and stale schedule revisions retain guarded recovery.

The [writing-tools increment](compose-tools.md) adds account signatures and
literal Quick Text to connected and offline composition. Its model, storage,
composer and management tests have subsequently passed with the pinned runtime;
the original setup failure remains in its historical qualification record.

The [loaded-conversation continuation](conversations.md) adds opt-in
account-scoped grouping, expand/collapse and observed unread/flag counts for
explicitly linked, already loaded mailbox headers. It preserves individual
visible-message actions. [Saved searches](saved-searches.md) persist named
queries and fixed account scopes, reopening against current retained headers.
Full threaded inboxes, event-driven shared search views, background synchronization
and cross-folder conversation indexing remain open.

Outlook, Thunderbird and eM Client are comparison targets for complete workflows,
reliability and usability. The workflow areas below organize the existing
M00–M14 scope. The immediate delivery sequence appears after the table.

| Area | Workflow | Current position | Next acceptance boundary |
| --- | --- | --- | --- |
| 1 | Recoverable composition | Multiple account-scoped local drafts, independent reply/forward drafts, attachment/reply recovery and interrupted-send warnings; offline draft entry for verified IMAP (including discovery), EWS, Gmail and Microsoft 365 accounts | Provider-side Drafts synchronization with explicit conflicts and repository-backed offline sessions |
| 2 | Everyday mailbox workspace (M04W/M06) | Verified four-provider remembered-account chooser with exact routing, draft-safe explicit sign-in and guarded foreground handoff; repository-observed loaded/cached sessions, durable single/bulk flags, Move/Delete and Archive, membership recovery, resumable header sync and bounded offline downloads | Retained multi-account sessions, complete shared synchronized workspace and unified live Inbox, durable retention/background scheduling, broader provider membership reconciliation and remembered custom Archive destinations |
| 3 | Sending and outbox (M07) | Native durable Outbox, atomic draft transfer/edit-copy, frozen MIME/envelopes, review/export, restart recovery, explicit send/retry/cancel, saved UTC schedules and a ten-second Undo window with explicit foreground resume across SMTP/EWS/Gmail/Microsoft 365 | Account-owned background execution, provider-specific Sent reconciliation and installed/live-provider qualification |
| 4 | Efficient discovery and organization | Independent archive FTS, saved archive searches, Boolean header queries, bounded saved-header discovery, persistent named searches with exact account/folder scopes, missing-folder recovery and optional foreground refresh, expandable loaded conversations and observed counts, stable local sorting and journaled visible-selection read/flag/Move/Delete and provider Archive commands | Repository-event-driven shared saved views, indexed body/server search, persistent cross-folder conversations, tags/categories, remembered custom Archive destinations and ordered rule execution with preview/recovery |
| 5 | Rich authoring and Office workflows (M07/M08) | Word-based plain text, To/Cc/Bcc, reply all, inert text quotes, attachments, locally qualified account signatures and reusable Quick Text | Identity routing/full-message templates, HTML alternatives, inline images, attach current document/PDF and edit a copy of a received attachment |
| 6 | Integrated productivity and release (M09–M13) | Provider adapters and shared foundations available | Calendar/People, invitation workflows, provider-specific shared mailboxes, encryption/signatures where supported, installed-platform and live-provider qualification |

Each increment needs an actual user path, typed failure/recovery behavior,
focused local tests and a remote source checkpoint before the next. Reconcile
current main/branches/PRs before final publication. GitHub Actions queue time is
not an acceptance dependency; record the actual local commands and scope.

The next delivery sequence is remembered Archive destinations, categories/tags
and ordered rules, indexed body/provider search, persistent conversations and
provider Drafts/Sent reconciliation, then fuller background multi-account work.
The [account-navigation guide](connected-account-navigation.md) defines these
boundaries and maps them to official Outlook, Thunderbird and eM Client workflows.

The [loaded-header search guide](header-search.md) describes the shared query
language, sorting, loaded-only scope and ordered next steps for discovery and
bulk triage. It covers connected and cached mail without extra provider work.
The [Boolean continuation](boolean-search.md) adds AND/OR/NOT and grouping with
unknown-observation safety. Its original static-only record remains historical;
fresh core/UI execution is recorded in the
[unified cached-search qualification](../../validation/mail-unified-cache-20261121/README.md).
The [cached-search continuation](unified-cached-search.md) reuses the same query
across retained folder memberships and native account profiles, with bounded
continuation, account/folder provenance, partial coverage and explicit offline
body opening. [Persistent saved searches](saved-searches.md) now reuse that
workflow with revision-guarded name/query/scope management. These features do
not claim server-wide or body-content search.

The [foreground bulk contract](bulk-flags.md) describes checked visible selections,
explicit read/unread/flag/unflag commands, outcome counts, stop-after-current
behavior and required refresh after uncertainty. Connected hosts share that
contract and one execution engine; cached mail stays read-only. The
[command-journal continuation](command-journal.md) persists native single/bulk
intent and outcomes, updates exact cached target flags transactionally and adds
offline activity history. The [uncertain-action recovery](flag-recovery.md)
adds explicit fresh provider observations while preserving the original receipt.
The [repository session continuation](repository-sessions.md) now observes
saved folder/catalog streams, preserves selected readers and fences account
and folder changes. The [durable synchronization continuation](durable-sync.md)
adds explicit resumable folder runs, atomic checkpoint state and offline
synchronized-header browsing. The [offline-download continuation](offline-downloads.md)
adds explicit single-message/current-page body and attachment retention with
restart skipping, bounded progress and guarded close. Unified cached-header
discovery is now a separate local workflow. The next boundaries include saved
continuously refreshed shared views, the complete shared synchronized workspace
and persistent cross-folder conversations.

The [cached mailbox guide](cached-mailboxes.md) describes durable ordered views
of visited folders, explicit body/attachment retention and credential-free
reading through the verified-account chooser. It separates limited cached
windows from authoritative synchronization and a unified inbox. Its
[local work record](../../validation/mail-cached-workspace-20261120/README.md)
tracks source checkpoints, intake and qualification.

The [multiple-draft guide](multiple-drafts.md) describes the bounded draft list,
independent selection/deletion and offline editing boundary. Its
[local evidence](../../validation/mail-multiple-drafts-20261120/README.md)
records intake, remote checkpoints and actual qualification.

The [Outbox management guide](outbox-management.md) describes message review,
exact EML/private-envelope export, atomic editing into a new draft and explicit
local closure with delivery still unknown. Its [combined-source evidence](../../validation/mail-outbox-management-20261120/README.md)
also qualifies the newly integrated multiple-draft and account boundaries.

The [durable Outbox guide](outbox.md) describes the sending continuation, atomic
draft handoff, sticky uncertainty and native account boundaries. Its
[local evidence](../../validation/mail-outbox-20261120/README.md) records source,
intake and actual qualification separately from previous increments.

The [reply and forwarding guide](reply-forward.md) describes the preceding
composition-fidelity increment: HTML-only text quotations, complete attachment
forwarding, preserved draft recovery and explicit refusal boundaries. Its
[validation record](../../validation/mail-reply-forward-20261120/README.md)
separates source checkpoints and actual local qualification.

The [offline account guide](offline-accounts.md) describes verified, credential-free
local draft access for all four native providers, including autodiscovered IMAP.
Its [qualification record](../../validation/mail-offline-accounts-20261120/README.md)
separates this completed composition entry from the future offline inbox.

The [remembered-account guide](remembered-accounts.md) describes the native
IMAP/SMTP account-management increment and its exact scope. Its
[local work record](../../validation/mail-accounts-20261120/README.md) tracks
implementation and qualification separately from earlier results.

The [foreground mailbox guide](mailbox-workspace.md) describes the delivered
first workspace slice, including the 50-message pages, 1,000-loaded-message
ceiling and loaded-only search boundary. Repository-observed sessions and the
connected account chooser now extend that foundation. M04W remains open for the
complete shared synchronized workspace and simultaneous multi-account lifecycle.
The [local qualification](../../validation/mail-workspace-20261120/README.md)
records the exact accepted source and incoming-work dispositions.

Comparison references checked 20 November 2026: Thunderbird's
[quick filters](https://support.mozilla.org/en-US/kb/quick-filter-toolbar),
[eM Client email capabilities](https://www.emclient.com/features-email), and
[Outlook rules](https://support.microsoft.com/en-gb/outlook/mail/manage-email-messages-by-using-rules-in-outlook).
Feature availability depends on the provider and product version; the matrix
does not claim identical behavior across every comparator edition.

## 1. Product decisions

Build one reusable Mail implementation with two consumers:

1. **Embedded consumer:** CrispCloud can use the shared saved-message reader and, separately, the full Mail workspace alongside its existing Quds editors.
2. **Standalone consumer:** a new app at **apps/quds_office** provides Word, spreadsheets, presentations, PDF, reports and Mail in one local-first Office suite, followed by integrated Calendar and People. It must function without a CrispCloud installation, account, server or database.

The component boundary is a compiled Dart/Flutter package API, not a separate process or a downloaded executable plug-in. Shared source does not imply shared credentials, profiles, caches or windows between the two apps.

### License policy accepted for this work

- Original Quds code remains MIT under the existing repository policy.
- MIT, BSD, Apache-2.0, ISC and explicitly reviewed similar permissive components are acceptable.
- **MPL-2.0 is explicitly allowed.** Preserve the license of copied/modified MPL files and publish the corresponding covered source for shipped builds.
- GPL, AGPL, LGPL, noncommercial and other unapproved restrictive code/data are excluded from the new shared packages and standalone product.
- Distribution of our source is intended. Source availability does not remove other licenses' obligations or certify App Store eligibility.
- Do not alter existing project license declarations merely to make a scanner pass.

### Critical existing-host boundary

CrispCloud currently declares **AGPL-3.0**. Its existing mail-viewer implementation and tests are not established permissive donors. Implement the shared Mail source independently in Quds using approved sources; let CrispCloud consume it through a fresh host adapter. Do not import CrispCloud implementation or tests into Quds.

This direction preserves the reusable packages' provenance. It does **not** make the combined CrispCloud executable a no-GPL product or establish that it can be distributed through Apple's stores. Resolving that host's complete distribution rights is a separate release gate. Continue independent Mail and standalone implementation while that gate is open.

## 2. Inspected baseline and repository map

The following are observed facts, not claims about future commits:

| Repository | Inspected main commit | Relevant observations |
| --- | --- | --- |
| Quds fork | 556c55c0ef312eda2cca11600021d293a81ab44b | MIT root; Dart workspace; engine and editor packages; existing Office Studio example and report-only standalone app; no shared Mail packages or full standalone Office app at the proposed paths. |
| CrispCloud | 05e10a6e5afd951844b45fd4f2aac11de15d0e6b | AGPL host; existing saved EML/MSG/MBOX viewers; vendored MIT Quds packages; existing host database, credential and document-routing infrastructure. |

Before coding, read the current repository instructions and compare against these snapshots. Do not assume a historical test receipt validates new mail code.

Existing Quds integration anchors:

| Path | Why it matters |
| --- | --- |
| .cursorrules; CONTRIBUTING.md; docs/MISSION.md | Pure-Dart engine, typed APIs, custom RenderBox editing surfaces and host-chrome distinction. |
| pubspec.yaml | Workspace registration; current Dart constraint is ^3.12.0. |
| packages/quds_office_editor/pubspec.yaml | Current Flutter minimum is 3.44.0; use the repository's actual pinned toolchain. |
| packages/quds_office_editor/lib/quds_office_editor.dart | Public editor entry point. |
| packages/quds_office_editor/lib/src/embed/office_controller.dart | Existing controller lifecycle, revisions, byte save and PDF export. |
| packages/quds_office_editor/example/lib/main.dart; suite_workspace.dart | MIT Office Studio example; a source for selective shell adaptation, not an already qualified standalone product. |
| apps/quds_report_studio | Existing report-only app; retain it. |
| docs/STANDARDS.md | Existing document-format limits continue to apply. |

Relevant controller APIs observed in the baseline: OfficeController.commitPendingEdits(), contentRevision, isDirty, isDisposed, saveBytesAsync(), markClean(); WordEditorController.fromBytes()/loadBytesAsync(); QudsWordEditor; corresponding sheet, slide, PDF and report surfaces. Use public imports rather than reaching through another package's src directory.

## 3. Architecture and package ownership

Core, MIME, the MPL fork, durable store and the saved-reader portion of UI now exist. Other
paths below remain planned implementation paths; consult [status.md](status.md).

| Package / app | Responsibility and dependency boundary |
| --- | --- |
| packages/quds_mail_core | Pure-Dart typed domain models, capabilities, operation state machine, provider/storage/host ports and sync coordination. No Flutter, dart:ui, platform paths or sockets. |
| packages/quds_mail_mime | Byte-oriented parse/compose facade and resource budgets; normalized Quds DTOs. Must compile for native Dart and browser JS. |
| third_party/enough_mail | Audited MPL fork retaining upstream package name and notices; one parser implementation, portable public MIME surface, native protocol APIs. |
| packages/quds_mail_transport | Native IMAP adapter around the reviewed enough_mail fork and direct on-premises Exchange EWS mail/submission adapter; conditional exports provide explicit unsupported capability on web. No socket library in the browser import closure. |
| packages/quds_mail_store | Drift/SQLite persistence, migrations, full-text search, cursor transactions and durable outbox. Native and web storage implementations share a typed interface. |
| packages/quds_mail_ui | Account-free reader plus account-aware workspace, composer, navigation and status. No CrispCloud imports, global navigation or hard-coded storage. |
| packages/quds_mail_office | Attachment preview/edit/export integration with Quds controllers, safe working-copy handling and Office-to-mail commands. |
| apps/quds_office | Clean standalone host: document home/tabs and editor commands, Mail/Calendar/People modules, lifecycle, credential/file services and store packaging. |

Future provider implementations live under the provider boundary, with separate source modules for Graph, Google, JMAP and DAV. Split these into packages only when dependency or platform boundaries justify it; do not create empty provider packages.

Dependency direction is host -> UI/Office integration -> core/MIME/store/provider adapters. The document engine and editor do not depend on mail or either host. Do not put mail models into quds_office_engine.

The target connected-mail architecture is driven by the local store, with commands persisted before remote execution and background workers updating the same repository. Native Studio journals foreground read/flag commands, explicitly checks uncertain receipts against fresh provider observations, and observes the successfully saved browsing window through repository streams. Explicit foreground folder synchronization now commits authoritative memberships and durable checkpoints into that repository. Background scheduling and the complete shared workspace remain the next M04W boundaries. The saved-message reader can also operate entirely in memory with no mailbox account or database.

### Existing editor rules remain binding

Mail/document body editing must use a custom RenderBox/LeafRenderObjectWidget surface with IME, selection, accessibility and undo behavior. Do not install Flutter Quill or a WebView editor as an undocumented exception. Reuse or factor approved MIT Quds input/command primitives without introducing cycles. Recipient/address/subject controls, toolbars, lists and dialogs are host chrome; CONTRIBUTING.md explicitly permits ordinary host UI there.

## 4. Protocol foundation: Dart first, MPL allowed

Use **enough_mail 3.0.0 as the initial evaluated baseline**, not a mandatory Rust dependency. The reviewed upstream main snapshot is **fc69f17e24e9d03ce813bbf613c07a2ce94e5e9a**, whose manifest declares 3.0.0. Its identity with the pub.dev archive has not been established. Resolve the exact source archive/commit, record hashes and audit dependencies in M01 before vendoring.

Reasons and limits:

- The 3.0.0 changelog records security corrections relevant to mail transport and Bcc handling; do not select an older major merely to satisfy an old widget dependency.
- Current enough_mail_flutter/enough_mail_html releases inspected during planning still constrain enough_mail 2.x. They are not baseline dependencies and must not be forced in with an untested override.
- Current lib/mime.dart exports MessageBuilder; MessageBuilder imports dart:io and exposes File. lib/codecs.dart also reaches that export. Neither public entry is established browser-safe.
- Static inspection found a parser/model import closure without dart:io. Add a supported public **lib/mime_core.dart** in the reviewed MPL fork, exporting that closure directly, without exporting the existing native MIME/codecs barrels.
- Keep composition bytes-based. Separate filesystem helpers into native-only code. Verify the actual import closure by compiling and running browser tests; a manifest platform label or static inspection is insufficient.
- Enough_mail's current public sendMessageData path takes MIME data through text serialization; its BDAT path is not established as a byte-preserving streaming transport. MVP submission uses generated ASCII-safe MIME, encoded headers and transfer encodings, plus a separate SMTP envelope.
- The initial SMTP policy aborts before DATA if any recipient is rejected. Envelope acceptance is distinct from submission and delivery; implement typed adapter outcomes rather than inventing a complete recipient result map from an aggregate library error.
- Retain imported EML octets exactly for source view/export. Do not promise arbitrary signed or raw 8-bit EML can be reserialized and submitted byte-for-byte. Add such a transport only with its own implementation and interoperability evidence.
- Quds owns synchronization, resource limits, retries, account state and provider semantics. Library reconnection behavior does not replace that work.

A Rust core remains an optional future alternative behind the same interfaces if measured requirements justify it. It is not part of this baseline.

## 5. Deliverable scope and completion levels

| Level | Required result |
| --- | --- |
| R0 — shared reader | Account-free EML parsing/reader and exact source export on desktop, mobile and web; safe attachment handoff; no implicit network traffic. CrispCloud retains working MSG/MBOX routes. |
| R1 — functional mail | Multi-account IMAP/SMTP, credentials, folders, message read/search, draft/reply/forward, attachments, durable sending, offline recovery and explicit capabilities. One desktop target qualifies first, while Apple/web compilation remains a design gate. |
| R2 — both consumers | Standalone full Office+Mail app and independently verified CrispCloud host integration use the same shared packages. Existing document and saved-message workflows remain intact. |
| R3 — productivity integration | Graph; Gmail plus Calendar/People; standards DAV where available; calendar invitations, recurrence/exceptions, contacts, identities and capability-aware shared workflows. |
| R4 — distribution qualification | Separate signed Apple build records, source/notice bundles, privacy declarations, sandbox/auth/background results and store review readiness for each eligible host. |

R0/R1 are useful increments, not completion of the whole requested Office+Mail scope. Full Outlook compatibility is not claimed. [On-premises Exchange EWS](exchange-ews.md) is now a prioritized native mail provider and Studio entry. PST/OST import, public folders, full delegation, protected mail, S/MIME/OpenPGP and add-in compatibility remain separate projects. MSG/MBOX authoring is not part of the first shared reader.

## 6. Host-neutral behavior contracts

### Saved message

The reader accepts raw RFC message bytes or a parsed immutable Quds message, a render-budget policy, theme/localization and attachment/link actions. It does not require accounts, credentials, a sync worker, a network resolver or a writable original-file target.

Display a structured parse status: success, partial-with-diagnostics, rejected-by-limit, unsupported or failed. Never display a truncated success after a parser limit was exceeded. Raw source/hex fallbacks belong to the host and remain available when safe.

### Connected mailbox

An account has stable local identity, provider kind, server configuration and capability flags. Credentials are references to a host-owned vault, never serialized into ordinary account rows, diagnostics or telemetry.

A message has a stable local ID and separate provider identity. IMAP identity includes account/mailbox/UIDVALIDITY/UID. Memberships are separate records so folders and labels are not conflated. Message-ID headers help threading but are not the local primary key.

Persist outgoing operations with stable IDs, immutable payload/revision references, retry policy and explicit reconciliation state. Events and push notifications request a synchronization pass; they do not directly establish mailbox truth.

### Attachments and Office

Incoming source bytes are immutable. Preview receives a read-only attachment handle. Editing creates a working copy. Attaching an edited document snapshots its bytes into the draft; it does not keep a mutable file-path reference.

Before an asynchronous Office save/export: commit pending edits, capture controller identity and contentRevision, then serialize. Reject stale/disposed callbacks. Mark an editor clean only after its actual intended persistence succeeds and the relevant revision still matches. Adding a copy to an email alone does not mark the original document saved.

Host services own file picking/export/sharing, external-link policy, secure storage, notification/background integration, local profile location and navigation. Separate host instances get separate credentials and databases by default.

### Rendering and resource limits

Baseline shared-reader defaults preserve the documented CrispCloud envelope: 32 MiB full-open raw message; 20 MiB preview; 8 MiB decoded body; 16 MiB per attachment; 128 attachments; 512 MIME parts; depth 20. Additionally enforce a cumulative decoded-payload budget and bounded header/HTML/image work; M02 defines exact accounting before parsing begins.

No script, forms, arbitrary SVG, executable attachments or remote resources are enabled by default. Normalize URLs after HTML/CSS decoding before policy checks. CID images use bounded local resources. Block CSS URL/import loads, srcset/background resources, external font loads and equivalent routes. An HTML renderer alone is not a sanitizer.

Connected mail fetches headers first and bodies/attachments on demand. A server's advertised SIZE is a hint, not an allocation authorization.

## 7. Provider and platform policy

- Generic IMAP/SMTP is the first live-account target. Calendars and contacts are independent providers.
- Microsoft cloud uses Graph. On-premises Exchange uses the [EWS provider](exchange-ews.md), with explicit HTTPS and NTLMv2 as the default, plus host-supplied bearer tokens or explicitly selected Basic over TLS.
- Google uses Gmail/Calendar/People APIs when those adapters land. Restricted-scope verification and any server-side assessment are launch dependencies, not an excuse to embed an application secret.
- Native OAuth uses system-browser authorization and PKCE. Mailbox login is separate from a host's primary account.
- Web reader and pure-Dart model/codec support are required. Generic browser IMAP/SMTP is explicitly unsupported without a separately designed user-controlled gateway; do not advertise native socket support on web.
- Native/mobile mail supports foreground/resume sync. Background and notification capabilities are platform-specific; suspended iOS execution and perpetual IMAP IDLE are not guaranteed.
- No mandatory Quds relay or hosted mail service is required for the initial desktop product.
- App Store targets are iOS/iPadOS and macOS. Sharing source across those targets is not release evidence.

## 8. Source and acceptance evidence

Every task starts unchecked. Save focused evidence with source identity and commands; do not carry over unrelated Office test totals.

Required evidence includes parser limits and malicious input; JS/browser portability; no-fetch reader checks; sender/recipient/header injection and Bcc handling; UIDVALIDITY/cursor expiry; draft and outbox crash recovery; partial recipients and ambiguous SMTP outcomes; attachment edit/export across both hosts; existing document behavior; Apple archive/privacy/sandbox checks.

Use original fixtures, approved permissive/MPL corpora or explicitly authorized sanitized messages. Do not import AGPL CrispCloud tests or real private messages into this repository. Existing CrispCloud tests are run in that host after integration.

See [implementation-plan.md](implementation-plan.md) for ordered tasks, contracts and commands, [crispcloud-integration.md](crispcloud-integration.md) for the host migration checklist, and [licensing-and-app-store.md](licensing-and-app-store.md) for per-product release evidence.

## 9. Primary references

Source references were checked during planning on 2026-11-18. Recheck the applicable version before implementation/release.

- [Quds baseline](https://github.com/CrispStrobe/quds_office_suite/tree/556c55c0ef312eda2cca11600021d293a81ab44b).
- [CrispCloud saved-message behavior](https://github.com/CrispStrobe/CrispCloud/blob/05e10a6e5afd951844b45fd4f2aac11de15d0e6b/docs/file-format-viewers.md).
- [CrispCloud license](https://github.com/CrispStrobe/CrispCloud/blob/05e10a6e5afd951844b45fd4f2aac11de15d0e6b/LICENSE.txt).
- [enough_mail reviewed manifest](https://github.com/Enough-Software/enough_mail/blob/fc69f17e24e9d03ce813bbf613c07a2ce94e5e9a/pubspec.yaml), [MIME exports](https://github.com/Enough-Software/enough_mail/blob/fc69f17e24e9d03ce813bbf613c07a2ce94e5e9a/lib/mime.dart), [builder](https://github.com/Enough-Software/enough_mail/blob/fc69f17e24e9d03ce813bbf613c07a2ce94e5e9a/lib/src/message_builder.dart), [changelog](https://pub.dev/packages/enough_mail/changelog).
- [MPL 2.0](https://www.mozilla.org/en-US/MPL/2.0/), [Mozilla FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/).
- [IMAP identity specification](https://www.rfc-editor.org/rfc/rfc9051.html), [JMAP mail](https://www.rfc-editor.org/rfc/rfc8621.html), [iCalendar](https://www.rfc-editor.org/rfc/rfc5545.html).
- [Graph incremental message sync](https://learn.microsoft.com/en-us/graph/delta-query-messages), [Gmail sync](https://developers.google.com/workspace/gmail/api/guides/sync), [Google restricted-scope requirements](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification).

