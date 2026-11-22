# Zotero selected-field context — 22 November 2026

## Baseline and scope

This continuation starts from remote main
`2eecf9aec2c7d1f979064448b911b516d3f56c73`. The [intake](intake.md)
and [machine-readable inventory](intake.json) account for all current fork and
upstream branches and recent pull requests. All captured tips are already
included in that baseline; no incoming source merge is required.

Incremental checkpoints are saved to `codex/zotero-field-context-20261122`.
Remote updates use an expected branch head and preserve existing history.
GitHub Actions are not a wait path for this work.

## Implementation target

Zotero's `Field.select` currently changes the detached session's selected field
without showing that field in the native host. During manual-edit and repair
prompts this leaves the user without the citation or bibliography being discussed.

This increment will expose validated original-document field ranges, display a
temporary highlight and readable source context in the native prompt, and retain
the user's writing caret, selection, Notes target and undo history. Pending
insertions and imported transfer clones must never be presented as live document
ranges. Completion, cancellation, errors and stale host state must clear the
presentation without publishing staged document changes.

Safe structural recovery of malformed fields and installed Word/LibreOffice/
Zotero interoperability remain separate acceptance work. The current Zotero
comparison target is Word and LibreOffice; legacy Apache OpenOffice requires
identified application and plugin versions.

## Validation

Implementation and local validation are in progress. Historical checks in
earlier work records are not fresh results for this continuation. This record
will be updated with the exact final source, commands, outcomes and limits
before merging.
