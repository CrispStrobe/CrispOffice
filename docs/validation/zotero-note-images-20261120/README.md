# Zotero embedded note images — 20 November 2026

## In progress

This continuation starts from published main
`e06eb3a7e21b71c1d5d4b1d2cc9abde24774eb26`, which contains the previous
notes-and-attachments milestone `7501b604`. It first reconciles the captured
fork and upstream branches and pull-request heads with their original ancestry.
The retained remote checkpoint branch is `codex/zotero-parity-20261120`.
GitHub Actions, workflow runs, checks and commit-status endpoints are neither
queried nor awaited. Local results will retain their exact source identities.

## Selected parity increment

Zotero's native Add Note and Add Annotation commands already insert text,
supported formatting and active citations in Quds. The next increment accepts
bounded embedded PNG/JPEG pictures returned by Zotero through `Document.insertText`,
including image/ink annotations, as native inline Word pictures. It preserves
surrounding text, citation offsets, document preferences and the existing
atomic apply/undo contract. Unsupported or malformed content must refuse the
entire result before publication. No independent network download is needed.

The implementation is based on Zotero's actual note export and annotation
serialization, not inferred from screenshots. The completed report will state
the accepted image envelope, remaining rich-note limits, source references,
local qualification and any unexecuted live interoperability checks.

## Qualification plan

- Reconcile the new VBA, Mail recovery and system-font snapshots; review
  conflicts without replacing combined files wholesale.
- Restore the pinned official Flutter 3.47.8 / Dart 3.13.7 runtime and preserve
  the existing dependency lockfiles.
- Cover image parsing, malformed/oversized refusal, citation conversion and
  reading order, DOCX media round trips, controller undo/redo and stale results.
- Run the complete Zotero engine/editor selections plus meaningful incoming
  and shared image/Word regressions; retain raw local evidence.
- Review the final diff, refresh remote refs, save the final checkpoint and
  merge the qualified branch into remote main without waiting on hosted CI.

The initial incoming VBA and Mail snapshots do not yet carry a final combined
acceptance claim. Their existing development evidence remains attributed to
its original sources; this continuation will qualify the included behavior
locally before publishing main.
