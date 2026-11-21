# Native ODT rich import continuation

Status: implementation in progress; no runtime or installed-host acceptance is
claimed by this initial checkpoint.

Baseline: `2f90a0c8f21499d5a1113943971cb7379183885c`.
Remote checkpoint branch: `codex/zotero-parity-2026-11-21`.

The initial intake in `initial-intake.json` checks all 25 advertised fork
branches, the latest 100 PR heads and all four upstream branch/PR heads.
Every captured head is already an ancestor of the baseline. No incoming work
needs replay, cherry-picking or a conflict resolution at that cutoff. Refresh
the remote frontier before publication to account for concurrent work.

## Implementation objective

Advance the next milestone in `docs/roadmaps/zotero/native-odt-input.md`:
construct an editable Word model from a bounded native ODT document, using
the existing inventory's exact native field ownership. Retain rich formatting,
paragraph and story order, citation metadata, bibliography paragraphs and
document preferences. Reject unsupported structures explicitly before returning
an editable document. Do not turn a text-extraction result into an active
document or weaken ordinary Word/HTTP preference validation.

The first content envelope and its executable evidence will be recorded here
once implemented. Save checkpoints using the connected GitHub Git Data API,
with expected-head ref updates, because the local GitHub CLI has no credentials.
All existing commit ancestry remains intact. No GitHub Actions polling is part
of acceptance; local executed checks and installed-application limits remain
separate.

## Acceptance to complete

- Deterministic namespace-aware rich import and exact UTF-16 field boundaries.
- Native citation and bibliography reconstruction, including equal visible
  strings and adjacent fields, without metadata loss.
- Explicit import-only preference conversion from ReferenceMark to Field.
- DOCX save/reopen, subsequent native Zotero operations and repeated saves.
- A real loader route that publishes only after complete import and layout.
- Resource limits and full refusal for ambiguous or unsupported content.
- Targeted regressions against ODF inventory/extraction and Word Zotero fields,
  notes, document preferences, transfer and the existing DOCX loader.

Actual Zotero/Word/LibreOffice interoperability is a separate acceptance gate.
Historical Apache OpenOffice compatibility requires named legacy versions.
