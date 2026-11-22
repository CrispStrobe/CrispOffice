# Zotero hyperlink equivalence continuation

Date: 22 November 2026.
Working branch: `codex/zotero-continued-parity-20261122`.

## Intake

All 48 captured fork branch heads and upstream main were inspected before new
Zotero source changes. There were no open pull requests at intake; the 100 most
recent requests were merged. Main `ea7ae724` lacked only the last two commits
from `work/mail-connected-navigation-20261122`. The reconciliation preserves
that ancestry and all 38 missing historical evidence blobs while retaining the
newer main production source and Mail tests. Two documentation paths retain the
useful historical additions without reverting current Mail behavior.

The exact branch tips, retained test blobs and historical evidence blobs are
recorded in [intake.json](intake.json). Historical qualification remains bound
to its original source; no older result is credited as a fresh run.

## Planned bounded increment

Permit ordinary ODT hyperlinks whose different visited/unvisited style names
resolve to equivalent supported formatting and equivalent inheritance state.
Require equality for Western, complex-script and Asian settings, including
nullable fallback state, so a nested span cannot reveal a hidden difference.
True state-dependent styling remains unsupported. Keep the existing special
case for glyph-free linked images unchanged.

The broader directional research-list increment remains a future task: it
requires parser, native numbering/indentation, layout and editor qualification.
It is not included in this change.

## Validation status

Local Dart/Flutter setup could not start after the checkout exhausted workspace
capacity while querying repository object sizes. Subsequent shell startup and
file edits failed with `ENOSPC`; the fixed environment approval policy rejected
the cache cleanup escalation. No Dart test, formatter, analyzer, native
renderer, Zotero desktop or Word/LibreOffice plugin run is claimed here.

Implementation and regression cases will be reviewed against the exact remote
source. Any final release notes must retain this execution limitation. GitHub
Actions is neither queried nor awaited.
