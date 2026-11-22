# Zotero automatic note-numbering parity — 22 November 2026

## Scope

This continuation closes a native interchange gap: editable Zotero ODT export
rejects Word's default lower-Roman endnotes. The intended increment preserves
continuous automatic decimal and lower/upper Roman numbering, independently for footnotes and endnotes, through editable ODT
export/import and subsequent DOCX save/reopen.

The implementation must use explicit note configuration and ordinal ownership,
not infer numbering from displayed labels. It must include uncited notes in
the sequence and preserve active citation fields, Zotero preferences, surrounding
prose and the source document. Custom marks, incompatible section settings,
page/section restarts and unsupported active configurations remain guarded.
Alphabetic numbering is deferred: independent official-source review and a
real LibreOffice probe found incompatible `num-letter-sync` semantics between
the ODF prose and the application. Roman ordinals stay within the native
formatter's supported range of 1–3,999.

Implementation and local qualification are in progress. This initial record
is a scope and intake checkpoint, not a claim that tests or application
acceptance have passed.

## Intake and remote preservation

The initial main was `b13a170cdb5fd42b9a0f2c77d97c996caf5d0d7f`, including
Zotero PR #364, Mail PR #363 and Word PR #362. The intake fetched all 29
advertised fork branch tips, all 364 PR heads and all four upstream branch
tips. The fork had no open pull requests at that snapshot.

Two newer branch tips were not ancestors of main: Mail's membership-recovery
planning checkpoint `13405f728a5a172951a71f078beab6aebc62f6ee` and Word's
reconciliation checkpoint `ee3ba4f6a7d5f2a9d73926d95d41e16580bf97c0`.
Both histories and the incoming Mail planning files are preserved in remote
checkpoint `be2908c7261e73859282cf759d825f563436897c`. The complete existing
Zotero recovery report is retained when reconciling its terminal documentation
conflict. Product source is unchanged from the qualified initial main.

The [intake receipt](intake.json) records captured refs and ancestry. Historical
PR heads outside the recent range are retained as fetched refs, not blindly
reapplied over newer accepted implementations.

Work is saved incrementally on `codex/zotero-native-parity-20261122`. GitHub
Actions are neither awaited nor used as an acceptance gate. Repository
protections are unchanged; publication uses ordinary forward-only updates
with an observed expected branch head.

## Planned qualification

- Engine format/ordinal mapping, ODT configurations and cached-label validation.
- Default Roman endnotes, independent foot/endnote formats, Roman and
  supported-range boundaries, and uncited/cited sequence accounting.
- Active citation order and ownership after ODT import and DOCX reopening.
- Editor/Studio import/export, source-bound save, unchanged dirty/undo state,
  cancellation and invalid-numbering refusal.
- Real LibreOffice file conversion where a verified runtime is available;
  distinguish this from installed Zotero plugin interaction.

The final record will contain exact local commands, results, source/dependency
hashes, runtime identity, preserved fixtures and remaining acceptance limits.

## Primary workflow references

- [Zotero LibreOffice plugin usage](https://www.zotero.org/support/libreoffice_writer_plugin_usage)
- [Moving Zotero documents between word processors](https://www.zotero.org/support/kb/moving_documents_between_word_processors)
- [Existing parity roadmap](../../roadmaps/zotero/word-processor-parity.md)

Zotero controls citation formatting and note placement preferences; the host
word processor controls the numbering and presentation of the notes. Native
editable ODT and the documented temporary transfer format retain separate
contracts. This increment does not claim complete Word/LibreOffice parity.
