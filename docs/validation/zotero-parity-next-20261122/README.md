# Zotero parity continuation — 22 November 2026

## Baseline and scope

This continuation starts from main
`b2bba1638924237435460e4238d4bd98c407fc3a`, after PRs #364–368.
The initial intake fetches every advertised fork branch, all 368 pull-request
heads and all four upstream branches. All 30 fork branch tips, all four
upstream tips and every PR head #153–368 are already ancestors of this main.
Fourteen older PR heads remain recorded as superseded, consistent with the
previous reconciliation record; replaying them would restore older work over
accepted implementations. No fork PR is open at this intake.

The exact snapshot is in [intake.json](intake.json). Work is saved incrementally
on `codex/zotero-parity-next-20261122` and will be integrated into current main
with ordinary forward-only updates after local checks. GitHub Actions are not
an acceptance gate for this continuation.

## Implementation plan

1. Extend document-wide citation unlinking to structurally complete fields with
   damaged metadata, matching the established individual-field conversion.
   Confirm the damaged-field count, preserve visible rich text and notes, apply
   one undo transaction, and retain atomic refusal for unsafe ownership or
   incomplete/locked/nested/opaque packets.
2. Preserve continuous decimal and Roman note numbering that starts above one
   through the bounded editable ODT path. Separate displayed note numbers from
   Zotero's physical note indexes, require explicit producer conventions and
   exact cached labels, and qualify representative files through actual
   LibreOffice saves before enabling exchange.
3. Exercise engine, editor and Studio lifecycle tests, including cancellation,
   stale state, undo/redo, source preservation and DOCX reopening. Run targeted
   strict analysis/formatting and record the tested source and actual results.
4. Refresh remote branch/PR/main intake, preserve incoming accepted work, publish
   reviewable qualification, and merge the completed increment to remote main.

This is an implementation checkpoint, not a completed validation claim. The
final record will replace this plan with observed behavior and results.

## Parity boundaries

The native integration already delegates citation dialogs, style/locale
preferences, bibliography processing and refresh to Zotero through its HTTP
Citing Protocol. The existing [parity roadmap](../../roadmaps/zotero/word-processor-parity.md)
retains the wider feature and acceptance matrix. Installed Zotero workflows in
identified Word and stable LibreOffice releases remain separate from controlled
protocol tests and headless file conversion. Alphabetic numbering, page/section
restarts and broader ODF structures remain separately bounded work.

## Primary references

- [Zotero Word plugin](https://www.zotero.org/support/word_processor_plugin_usage)
- [Zotero LibreOffice plugin](https://www.zotero.org/support/libreoffice_writer_plugin_usage)
- [HTTP Citing Protocol](https://www.zotero.org/support/dev/client_coding/http_integration_protocol)
- [ODF 1.3 schema](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html)
