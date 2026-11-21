# LibreOffice ODT styles and Zotero continuation

Status: implementation checkpoint; combined local qualification and independent
review are in progress. This checkpoint is not a release acceptance result.

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

## Implementation checkpoint

- Resolve independent complex-script and Asian font, size, weight, italic and
  language settings across named/default/automatic style inheritance. Resolve
  percentage sizes against the corresponding inherited script size.
- Materialize the current source text into ordinary native runs when scalar
  settings differ. Keep supplementary Unicode, combining marks, hyperlinks and
  original UTF-16 positions. A shared 100,000-run limit also bounds alternating
  script input.
- Preserve native complex/Asian slots in DOCX. Private ignorable provenance
  limits synchronization of subsequent scalar edits to importer-owned runs;
  ordinary DOCX sparse properties keep their existing independent ownership.
- Evaluate effective automatic color, opacity and hyphenation after inheritance.
  Accept supported disabled/default paragraph and page values without dropping
  unknown or foreign settings. Content-sensitive guards reject active Asian
  typography, uncertain break locales, nonstandard default tab grids used by
  actual tabs, active page grids, and a custom separator with actual footnotes.
- Retain the exact original ODT and source DOCX under the engine's fixture
  directory. A synthetic extension injects canonical Zotero fields and
  preferences while leaving the production style envelope unchanged.

The first development cohort opened the untouched ODT and passed its synthetic
Zotero edit/refresh case. A new combined hyperlink/citation test exposed a
field-ownership mismatch that is still being reviewed. Final counts, commands,
source identities and complete passing results will replace this provisional
execution note before merging.

The [typography source review](lo-typography-research.md) records the pinned
LibreOffice implementation behind the content/language guards. Its conclusion
is an inference from source and the fixture, not a new rendered LibreOffice
session. Conversion preserves the supported current content; it does not retain
all dormant ODF style behavior for future typing or future Zotero replacements.
