# Zotero native ODT round-trip continuation

## Combined-source completion

The [round-trip completion record](../zotero-roundtrip-complete-20261121/README.md)
reconciles this branch, the inline-image continuation, scheduled Mail and the
latest accepted main. It retains the earlier converter failure and separately
qualifies newly exported explicit note-marker styles, semantic uppercase text,
native reference metadata, repeated file saves and current editor workflows.
Its source, fresh local results, exact remote intake and installed-plugin
boundaries are recorded independently. The historical checkpoint status below
describes the original work and is not a substitute for that combined gate.

## Goal

Continue the Word/LibreOffice Zotero parity roadmap by reopening actual
LibreOffice-saved editable Zotero ODT documents through the native Quds reader,
preserving citation identities, bibliography ownership, document preferences,
rich cached text and authored notes through further saves and native edits.

This work starts at remote main `4970f71f983535d045ce263e86835b499db4fda9`.
The initial fetch includes 39 fork branch tips, 332 PR heads and four upstream
branch tips. Every current branch tip is already an ancestor of main. Fourteen
historical PR heads need equivalence review; the other 361 captured refs are
ancestors. The attached intake records the exact refs. There are no open PRs.

## Work plan and progress

1. Complete historical-ref accounting before implementation.
2. Reproduce native-reader failures using the unchanged LibreOffice artifacts
   retained by the editable ODT export work.
3. Implement bounded, semantics-preserving fixes with targeted regressions.
4. Run the pinned local Dart/Flutter checks and actual LibreOffice file-save
   cycles, keeping installed Zotero-plugin acceptance separate.
5. Refresh remote main, review affected integration checks, and merge the
   qualified branch. Keep every remote checkpoint.

The available converter is LibreOfficeDev 26.8.0.0.alpha0, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. A converter check does not establish
supported stable-release or installed Zotero-plugin acceptance. GitHub Actions
are not queried or awaited for this task, per the user's instruction.

## Intake completed

Independent Git-object comparisons account for all 375 captured refs:
361 ancestors and 14 verified historical equivalents, with zero uncovered
work. Thirteen original/replacement trees are identical; PR #140's 37 changed
paths are identical in mode, type and blob to its main-ancestor replacement.
See `intake-equivalence.json` and `intake-equivalence.md`. No historical work
needed replay and no current branch or upstream work was omitted.

## Development findings and checkpoints

A frozen copy of all 436 relevant baseline source files was checked against
main's Git blobs. The baseline generator and actual LibreOffice save both
passed the native metadata inventory checks, but neither returned file could
reopen through Quds' reader. The bibliography failed on its new section style.
The table/notes document failed on table defaults; its table also expanded to
page width because `table:align="margins"` overrode the supplied absolute width.

The first implementation checkpoint qualifies an inert, inherited bibliography
section style, validates unused sequence declarations, recognizes a narrowly
identified LibreOffice zero-offset note convention with exact cached ordinals,
and fixes editable ODT absolute table alignment. The retained actual bibliography
fixture now reopens; targeted development tests pass for its repeated native
updates/saves and for the note-offset cases. Final combined validation and
external repeat-cycle checks remain pending at this checkpoint.

An active footnote separator remains unsupported by the native reader. The
observed LibreOffice separator has geometry and styling that the Quds note
layout cannot represent. Table-only and endnote-only converter fixtures will
be qualified separately; no guard will be removed by silently dropping that
footnote formatting.
