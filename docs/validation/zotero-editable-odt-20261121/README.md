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
interoperability are separate acceptance boundaries. No passing runtime result
or installed-plugin result is claimed by this initial checkpoint.

## Initial intake

All advertised fork branches and all 323 pull-request heads were fetched, along
with all four upstream branch heads. At the initial snapshot, 31 fork topic
heads and all four upstream heads were already ancestors of starting main.

Two additional fork heads are preserved as unfinished independent work:

- `codex/word-vba-extensions-20261121` at
  `870e0ff97c9c6290bfe14bb6a137d46c54f2e697`: draft PR #322 compiles a new
  paragraph-style operation whose native implementation is still absent.
- `work/mail-compose-tools-20261121` at
  `32a6dcd4e56584b5af34625b44a845eb15ba44bd`: account signatures and Quick Text
  remain under implementation and qualification; no completed PR was present.

Neither is silently merged as completed work. Both remain on their remote
branches and their fetched local refs. Historical nonancestor PR heads are
being rechecked against current main. Remote refs will be refreshed before
publication to account for concurrent work.

## Validation plan

Use the genuine repository-pinned Flutter 3.47.8 / Dart 3.13.7 runtime and
locked dependencies. Execute the pending merged-table reader/editor cases,
focused new ODT export interoperability and refusal tests, and affected Zotero
and ODT regressions. Record actual commands and outcomes here before delivery.

Push each meaningful checkpoint to the remote topic branch. The user explicitly
authorized final integration into remote main without waiting for the starved
GitHub Actions queue. Checkpoint and merge messages use `[skip ci]`; Actions
will not be queried, rerun, or awaited, and repository protection is unchanged.
