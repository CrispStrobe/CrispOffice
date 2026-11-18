# Quds Mail and standalone Office — implementation scope

**Status:** accepted product scope; implementation has not started in this plan.
**Decision date:** 2026-11-18 (Europe/Berlin).
**Canonical repository:** CrispStrobe/quds_office_suite, branch main.
**Entry point for a fresh coding agent:** read this file, then [implementation-plan.md](implementation-plan.md). The [CrispCloud contract](crispcloud-integration.md) and [licensing/App Store requirements](licensing-and-app-store.md) are part of the same specification. No prior chat is required.

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

All paths below are **proposed new implementation paths**.

| Package / app | Responsibility and dependency boundary |
| --- | --- |
| packages/quds_mail_core | Pure-Dart typed domain models, capabilities, operation state machine, provider/storage/host ports and sync coordination. No Flutter, dart:ui, platform paths or sockets. |
| packages/quds_mail_mime | Byte-oriented parse/compose facade and resource budgets; normalized Quds DTOs. Must compile for native Dart and browser JS. |
| third_party/enough_mail | Audited MPL fork retaining upstream package name and notices; one parser implementation, portable public MIME surface, native protocol APIs. |
| packages/quds_mail_transport | Native IMAP/SMTP adapter around the reviewed enough_mail fork; conditional export provides explicit unsupported capability on web. No socket library in the browser import closure. |
| packages/quds_mail_store | Drift/SQLite persistence, migrations, full-text search, cursor transactions and durable outbox. Native and web storage implementations share a typed interface. |
| packages/quds_mail_ui | Account-free reader plus account-aware workspace, composer, navigation and status. No CrispCloud imports, global navigation or hard-coded storage. |
| packages/quds_mail_office | Attachment preview/edit/export integration with Quds controllers, safe working-copy handling and Office-to-mail commands. |
| apps/quds_office | Clean standalone host: document home/tabs and editor commands, Mail/Calendar/People modules, lifecycle, credential/file services and store packaging. |

Future provider implementations live under the provider boundary, with separate source modules for Graph, Google, JMAP and DAV. Split these into packages only when dependency or platform boundaries justify it; do not create empty provider packages.

Dependency direction is host -> UI/Office integration -> core/MIME/store/provider adapters. The document engine and editor do not depend on mail or either host. Do not put mail models into quds_office_engine.

The local store drives connected-mail UI. Commands persist their intent before remote execution. Background workers update the same store. The saved-message reader can also operate entirely in memory with no mailbox account or database.

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

R0/R1 are useful increments, not completion of the whole requested Office+Mail scope. Full Outlook compatibility is not claimed. PST/OST import, public folders, on-premises Exchange, full delegation, protected mail, S/MIME/OpenPGP and add-in compatibility are separately prioritized projects. MSG/MBOX authoring is not part of the first shared reader.

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
- Microsoft cloud uses Graph; EWS is not the new cloud foundation. On-premises Exchange is separately scoped.
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

