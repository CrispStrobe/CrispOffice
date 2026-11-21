# LibreOffice ODT styles and Zotero continuation

Status: implementation in progress; fresh local qualification is pending.

Baseline: `01517de8886ef7bd24947894be5dc823d0328869` (merged PR #310).
Working branch: `codex/zotero-libreoffice-styles-20261121`.

## Goal and acceptance

Broaden the bounded native ODT importer from the previous milestone's retained,
untouched LibreOfficeDev fixture. The original `native-prose.odt` has SHA-256
`9fd4e0d23bf9cd2be0248bd5e9cfb496dfe512ec1226c456f324f2171705e1bd`
and is retained in the preceding rich-ODT validation archive. It contains Latin
and Arabic prose, supplementary Unicode, bold and italic text. Its actual
complex-script font size differs from its Latin size.

Acceptance requires opening those exact bytes, preserving supported effective
formatting through DOCX save/reopen, and qualifying a separately identified
synthetic native-Zotero fixture using the same production style envelope.
Unsupported active settings must remain explicit failures; default-value
acceptance must not silently discard active formatting or layout behavior.

The change will resolve effective inherited text formatting, represent active
script-specific text as native runs, and qualify supported or inactive
paragraph/page defaults. Existing field ownership, resource limits, atomic
publication, and first-save routing remain part of the regression scope.

This milestone does not establish installed Word/LibreOffice/Zotero plugin
interoperability. Native editable ODT output and historical Apache OpenOffice
compatibility retain their separate contracts and acceptance requirements.

## Initial intake

`initial-intake.json` captures the first 27 fork branch heads, 100 most recently
updated PRs, and four upstream branch heads. `expanded-intake.json` records all
29 subsequently fetched fork branches, all 310 fork PR heads, all four upstream
branches, and all four upstream PR heads. Every captured head is already
included in the baseline by ancestry or an explicit historical equivalence
proof. The two new concurrent Mail/VBA branches had no additional commits at
that cutoff. There was no pending feature delta to merge before implementation.

## Validation and remote saves

Use repository-pinned Flutter 3.47.8 / Dart 3.13.7 with locked dependencies.
Record local tests and exact source/runtime identities. Save working increments
remotely, reconcile newer incoming changes, and merge to current remote main.
GitHub Actions and status checks are not queried or awaited.
