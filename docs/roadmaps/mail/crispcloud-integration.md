# CrispCloud integration for shared Quds Mail

**Status:** proposed integration, not implemented or verified. **Evidence date:** 2026-11-18. CrispCloud was inspected at [`05e10a6e5afd951844b45fd4f2aac11de15d0e6b`](https://github.com/CrispStrobe/CrispCloud/tree/05e10a6e5afd951844b45fd4f2aac11de15d0e6b); canonical Quds at [`556c55c0ef312eda2cca11600021d293a81ab44b`](https://github.com/CrispStrobe/quds_office_suite/tree/556c55c0ef312eda2cca11600021d293a81ab44b). Quds has no mail implementation at that baseline. See the [scope](./README.md), [implementation plan](./implementation-plan.md), and [licensing and App Store plan](./licensing-and-app-store.md).

## 1. Ownership and reuse boundary

CrispCloud's [root license](https://github.com/CrispStrobe/CrispCloud/blob/05e10a6e5afd951844b45fd4f2aac11de15d0e6b/LICENSE.txt) is AGPL-3.0. Its [distribution cleanup](https://github.com/CrispStrobe/CrispCloud/blob/05e10a6e5afd951844b45fd4f2aac11de15d0e6b/docs/distribution-license-cleanup-20261115.md) expressly retains the application license. No separate permissive grant was established for its email parser, viewer, or MBOX implementation. Treat those as AGPL host code. The independently licensed Quds engine/editor remain separate components; their presence does not relicense the host.

The source-sharing direction is **canonical Quds → CrispCloud**. Write the shared mail packages and standalone shell independently, retaining licenses on approved third-party adaptations, including permitted MPL-2.0 components. Do not transplant CrispCloud implementation, fixtures, tests, assets, or wrapper classes into Quds. The documented behavior below is an interoperability and regression contract, not an extracted implementation.

CrispCloud can consume the shared packages through a host adapter, subject to its own distribution obligations. This does not make the complete host meet the requested no-GPL-family policy. The separate `apps/quds_office` application supplies the clean Office-and-Mail shell; the existing report-oriented application is not that product. Host licensing and App Store clearance remain separately tracked in the licensing plan.

## 2. Preserve the existing saved-message viewer

CrispCloud's [viewer specification](https://github.com/CrispStrobe/CrispCloud/blob/05e10a6e5afd951844b45fd4f2aac11de15d0e6b/docs/file-format-viewers.md) describes saved-file viewing, not account synchronization or a mailbox client.

| Format or operation | Observed documented contract |
| --- | --- |
| EML | Decode MIME multipart, Base64/quoted-printable content, encoded headers, and extended attachment names. Show headers, plain text or restricted HTML, and ordinary attachments. F4 edits raw MIME; it is not structured composition or automatic boundary/signature repair. Preserve original bytes and source newline metadata through the existing source path. |
| MSG | Read the message's own headers, body, and ordinary attachments from CFB. Prefer plain/HTML bodies, with compressed RTF fallback. Embedded Outlook messages remain a limitation. No structured MSG writer. |
| MBOX | Build a bounded index, select one message, and support previous/next navigation. Decode only the selection; search/copy scope is that message. A malformed selected MIME message must not block navigation. Reject ambiguous boundaries or exceeded index limits. No MBOX writer. |
| HTML | Retain basic formatting while removing active content, links, remote images, source CSS, and resource attributes. Fetch no remote resources. Offer plain text. |
| Search | Search decoded headers, body, and attachment names. Build the representation only for a nonempty query. Closing search restores formatted viewing. Exceeding the search budget leaves the formatted view available with an explanation. |
| Attachments and source | Open exact attachment bytes in the existing nested viewer without a writable original-file target. Keep original message/container bytes available through Source/Hex. |

Preserve these existing limits during viewer replacement:

| Resource | Existing limit |
| --- | --- |
| Full F3 single message / compact preview | 32 MiB / 20 MiB |
| Decoded body / individual attachment | 8 MiB / 16 MiB |
| Attachment count / MIME parts / nesting depth | 128 / 512 / 20 |
| MSG recipients | 512 |
| MBOX input / indexed messages | 64 MiB / 1,000; selected message still limited to 32 MiB |
| Search representation | 200,000 lines and 8 MiB decoded UTF-8, checked before allocating the index |

Keep explicit warnings for approximated character encodings and failures for invalid Base64 or unsupported transfer encodings. Mailbox synchronization may later need streaming and explicit download policies; it does not justify silently raising saved-viewer budgets.

## 3. Shared packages and host seams

All package names below are **new proposals**, not present implementations or discovered CrispCloud API signatures.

| Package | Responsibility and boundary |
| --- | --- |
| `quds_mail_core` | Pure Dart DTOs, ports, account/message identities, and synchronization contracts; no Flutter or host imports. |
| `quds_mail_mime` | Byte-only codec interface over an audited MPL MIME surface; preserve covered-source notices. Prove platform-neutral imports independently. |
| `quds_mail_store` | Drift-backed message, draft, and operation storage, partitioned by product and account. |
| `quds_mail_transport` | Native `enough_mail` adapter through conditional exports; browser transports use separately implemented HTTPS/provider ports or report unsupported capability. |
| `quds_mail_ui` | Independently embeddable reader, mailbox workspace, and composer. Saved-file viewing requires no account or network setup. |
| `quds_mail_office` | Bridge to the licensed Quds engine/editor for document snapshots and attachment working copies. No dependency on CrispCloud's Office wrappers. |

The existing routing locations are `lib/services/internal_viewer_service.dart`, `lib/widgets/internal_viewer_dialog.dart`, `lib/widgets/internal_viewer_views.dart`, and `lib/widgets/preview_pane.dart`. Existing format components are `lib/services/email_message_service.dart`, `lib/widgets/email_message_view.dart`, `lib/services/mbox_message_service.dart`, and `lib/widgets/mbox_message_view.dart`. Office host integration lives in `lib/services/office_document_service.dart` and `lib/widgets/office_editor_dialog.dart`. These are adapter investigation points, not instructions to move their source.

Propose small host ports for attachment preview, explicit export/save-copy, attachment picking, external navigation policy, credentials, notifications, and window lifecycle. Exchange bytes or bounded streams plus opaque identifiers and display metadata. Keep filesystem paths, cloud-provider objects, global registries, and host widgets outside the shared contracts. Unsupported host capabilities must be visible and testable.

## 4. Attachments and editable working copies

An incoming message and its attachment payloads are immutable source objects. Preview grants read access only. Editing creates a separately identified working copy with its own save destination and revision. Saving or attaching that copy must never overwrite the received message, silently upload to cloud storage, or mutate the original attachment.

The current Quds [`OfficeController`](https://github.com/CrispStrobe/quds_office_suite/blob/556c55c0ef312eda2cca11600021d293a81ab44b/packages/quds_office_editor/lib/src/embed/office_controller.dart), publicly exported through `quds_office_editor.dart`, exposes `commitPendingEdits()`, `contentRevision`, `isDirty`, `isDisposed`, `saveBytesAsync()`, and `markClean()`. Build the new bridge against these APIs: commit pending edits, capture document identity/revision, await serialization, retain an immutable byte snapshot, then recheck identity, disposal, and revision. If editing changed the document during serialization, retry or explicitly present the captured version; do not silently label it current.

Call `markClean()` only after successful persistence of the unchanged working-copy revision. Attaching a serialized snapshot to a draft is not evidence that the document was saved. “Attach edited copy” creates or explicitly replaces a draft attachment using new bytes and metadata. Cancellation, serialization failure, permission loss, and reopening must preserve the original and the recoverable draft.

Editable Office surfaces continue to follow Quds' `RenderBox`/`LeafRenderObjectWidget` constraint. Material controls are appropriate for host forms, account settings, navigation, and surrounding chrome; they do not replace the document editing architecture.

## 5. Incremental migration and acceptance tasks

Each row is a separate gate. Proposed feature flags start disabled; retain the existing viewer as default until the corresponding parity gate passes independently.

| Task | Change and required acceptance evidence |
| --- | --- |
| **CC-01** | Record baseline licenses, upstream revisions, interface ownership, and supported host capabilities. No prohibited host source enters shared packages. |
| **CC-02** | Create independently authored message fixtures and specification-derived tests for decoding, malformed input, limits, sanitization, and exact bytes. Keep existing AGPL tests in CrispCloud. |
| **CC-03** | Embed the shared reader without accounts. Native and browser builds pass; opening a saved file performs no network requests or login. Browser MIME has no transitive `dart:io` dependency. |
| **CC-04** | Introduce proposed `mailSharedEmlReader`. Verify full viewer and compact preview, raw Source/Hex, search restoration, hostile HTML, all bounds, and read-only nested attachments. Switch EML only after parity. |
| **CC-05** | Add the Office attachment bridge. Verify received-source immutability, working-copy save/cancel, concurrent edits, failed serialization, lost document access, and attachment snapshot revision. |
| **CC-06** | Evaluate proposed `mailSharedMsgReader` and `mailSharedMboxReader` independently. Preserve existing routes until format-specific limits, failure behavior, navigation, and source retention pass. EML success does not authorize either switch. |
| **CC-07** | Add proposed `mailWorkspace` separately from viewer flags. Account setup, synchronization, composition, outbox recovery, and send-state handling follow the implementation plan; opening a file never enables them implicitly. |
| **CC-08** | Verify product/account storage and credentials are isolated; disconnecting one account affects only its documented local data and never deletes another account or remote mailbox. |
| **CC-09** | Pin and hash every vendored mail component. Verify clean canonical-to-host synchronization and a repeatable rollback without losing drafts or queued operations. |
| **CC-10** | Run host lifecycle and platform qualification: close/reopen, suspend/resume, offline use, notifications denied, browser capability limits, and signed sandbox attachment round trips. Track each host's release evidence separately. |

Existing host regression targets include `test/email_message_service_test.dart`, `test/widget/email_message_view_test.dart`, `test/mbox_message_service_test.dart`, `test/widget/mbox_message_view_test.dart`, `test/widget/extended_format_viewer_test.dart`, `test/widget/document_preview_integration_test.dart`, and `test/internal_viewer_test.dart`. Their paths and documented purposes were inspected; these tests were **not run** for this plan. Use them inside CrispCloud alongside fresh integration tests, without copying their code or uncleared fixtures into Quds. Historical test reports are not a new parity result.

## 6. Platform, persistence, and vendoring controls

Conditional exports must actually exclude socket implementations from browser builds. An umbrella import of a native library is not a portable MIME boundary. Keep native credential stores, authorization callbacks, background scheduling, and document access behind host ports. A browser host needs an implemented HTTPS path or explicit capability limitation; it cannot directly reuse native IMAP/SMTP sockets.

Use separate database locations, cache namespaces, keychain/secure-storage identifiers, and temporary directories for CrispCloud and standalone Office, with account IDs inside each. Mail authorization is separate from an existing CrispCloud cloud-storage login. Shared packages do not imply shared credentials. Cross-product account transfer would require a later explicit user-facing design.

Extend the existing [Quds vendoring approach](https://github.com/CrispStrobe/CrispCloud/blob/05e10a6e5afd951844b45fd4f2aac11de15d0e6b/packages/QUDS_FORKS.md): commit an immutable canonical revision, managed-file hashes, dependency locks, provenance, notices, and matching MPL source references. `tool/office_fidelity_manifest.json` already tracks Office provenance; extend it deliberately or add a mail-specific companion manifest. Historical pins in the document are not the current canonical Quds baseline.

Fix shared behavior in canonical Quds, review it there, then vendor the exact reviewed revision into CrispCloud. Keep host adapters host-owned. Retain old viewer routes until each gate passes, and version mailbox schemas so flag rollback preserves data. None of these planning tasks claims completed licensing clearance, working software, or App Store approval.
