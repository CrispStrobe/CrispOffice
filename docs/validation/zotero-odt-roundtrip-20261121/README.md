# Zotero native ODT round-trip continuation

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

This initial checkpoint contains the intake and plan only. Implementation and
validation results will be recorded as they complete; no new test pass or
interoperability result is claimed yet.
