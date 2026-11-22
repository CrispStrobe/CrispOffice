# Zotero converter interoperability — 22 November 2026

## Goal

Continue Word/LibreOffice Zotero parity using the original converter failures
retained by the research-note formatting increment. Qualify benign DOCX field
boundary formatting and the exact inert outline structure produced by
LibreOffice, preserving active metadata, content, ownership and editing.
Numbered/positioned outlines, unknown field semantics and installed application
acceptance remain separate unless explicitly demonstrated by this work.

## Intake and remote preservation

The initial remote main is `659b81462224a40f50975cfbfca39f636538b836`.
The intake fetched all 380 PR heads and checked all 43 existing fork branches,
four canonical upstream branches, and the 100 most recently updated PR heads
and merge commits. No recent PR was open. Two fork tips were ahead of main:

- `5949a298444cec06632a28858c75670541a914a9`: Word Variant substring and named
  selector implementation, tests and documentation.
- `622d9fda2a6564638af153de887adea922bc26f8`: guarded connected Mail account
  navigation, tests and documentation.

Both histories were merged without conflicts before Zotero implementation.
`initial-intake.json` retains the captured refs and starting ancestry results.
Incoming behavior will be covered by focused local regression cohorts before
publication. Work is saved incrementally on
`codex/zotero-converter-parity-20261122`, with an ordinary final merge into main.

## Acceptance plan

1. Preserve the original DOCX and ODT converter outputs and source provenance.
2. Implement bounded acceptance with negative controls for unsupported content.
3. Reopen the original files, perform native citation edits and controlled
   Zotero protocol operations, and save/reopen with exact metadata and ownership
   checks. Test outline behavior through native ODT/DOCX cycles.
4. Run focused engine/editor/Studio and incoming Word/Mail regressions with the
   pinned Flutter 3.47.8 / Dart 3.13.7 runtime and the unchanged lockfile.
5. Refresh the remote intake, preserve concurrent work, and verify the final
   GitHub main commit and retained checkpoint branch after merging.

GitHub Actions will not be awaited or used as a local-validation substitute.
No repository workflow or protection changes are part of this task.
Live installed Zotero, Microsoft Word and supported-release LibreOffice plugin
acceptance must be reported separately from controlled protocol and converter
fixture checks.
