# Editable Zotero ODT output — 21 November 2026

Status: implementation and local qualification in progress.

Starting main: `3dbaa8429b14ac43721e165b4d50d3f6d2845309`.
Checkpoint branch: `codex/zotero-editable-odt-20261121`.

## Scope

First execute and repair the native ODT merged-table increment already merged
in PR #323. Then add an explicit editable Zotero ODT export path, preserving
supported native field ownership and document preferences. Ordinary ODT export
keeps its existing visible-cache contract. The opt-in path must refuse a
document if it cannot preserve the active Zotero fields it claims to export.

Engine serialization, editor export and actual installed Zotero/LibreOffice
interoperability are separate acceptance boundaries. Installed-plugin acceptance remains separate from local runtime verification.

## Initial intake

All advertised fork branches and all 323 pull-request heads were fetched, along
with all four upstream branch heads. At the initial snapshot, 31 fork topic
heads and all four upstream heads were already ancestors of starting main.

At intake, two additional fork heads were preserved as unfinished independent work:

- `codex/word-vba-extensions-20261121` at
  `870e0ff97c9c6290bfe14bb6a137d46c54f2e697`: draft PR #322 compiles a new
  paragraph-style operation whose native implementation is still absent.
- `work/mail-compose-tools-20261121` at
  `32a6dcd4e56584b5af34625b44a845eb15ba44bd`: account signatures and Quick Text
  remain under implementation and qualification; no completed PR was present.

The [fresh intake](initial-intake.json) accounts for all 361 fetched refs:
344 actual ancestors, ten reverified patch equivalents, two empty nonmerge
patch histories, two API-confirmed squash integrations and three refs for the
two unfinished heads. No ref was unaccounted.

During this continuation, Mail PRs #324 and #325 landed on main at
`1078372da9213c1ef4cdd362ca2285db9acb8d7b`. Their source and original ancestry
are now included by remote checkpoint
`2cf5055db72e229b10bf27735ba92e72e996ff84`. That intake preserves the Mail
work record's own explicit outstanding qualification; it does not borrow Zotero
test results. The Word style continuation remains independently advancing.
Remote refs will be refreshed again before publication.

## Executed baseline qualification

The [baseline receipt](baseline/receipt.json) and [work record](baseline/README.md)
record 219 passing engine cases and 93 passing editor cases, with no failures
or skips. All four pending #323 files pass formatting and fatal-info analysis.
Only formatting and five automatic test-string interpolation fixes were needed;
reader behavior is unchanged. The original failures, successful logs and source
snapshots are retained in [the execution archive](baseline/execution.tar.gz).
Concurrent new export work is explicitly identified in that receipt; the final
combined export source will be qualified separately.

## Validation plan

Use the genuine repository-pinned Flutter 3.47.8 / Dart 3.13.7 runtime and
locked dependencies. Execute the pending merged-table reader/editor cases,
focused new ODT export interoperability and refusal tests, and affected Zotero
and ODT regressions. Record actual commands and outcomes here before delivery.

Push each meaningful checkpoint to the remote topic branch. The user explicitly
authorized final integration into remote main without waiting for the starved
GitHub Actions queue. Checkpoint and merge messages use `[skip ci]`; Actions
will not be queried, rerun, or awaited, and repository protection is unchanged.
