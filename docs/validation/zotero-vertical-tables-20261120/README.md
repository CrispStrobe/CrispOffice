# Zotero vertical research-table continuation

## Scope

This continuation extends Add Note and Add Annotation with bounded vertical
table merges, including combined row and column spans. It preserves native
paragraph, list, picture and active-citation ownership, and qualifies body,
footnote and endnote destinations. Native table layout must retain merged-cell
decoration on every physical page containing the merge.

Implementation and acceptance are in progress. This record does not yet claim
final feature qualification or publication to main.

The row-height policy remains conservative: the originating cell's content
contributes to its first physical row. Compact Word-style distribution of that
content's height across several rows is a separate fidelity milestone. Nested
research tables, additional row groups and styling, broader replacement ranges,
active ODT citation transfer and installed-application release qualification
remain separate work.

## Source reconciliation

The frozen [initial inventory](intake-initial.json) captures 322 references:
38 fork branches, 276 fork PR heads, four upstream branches and four upstream
PR heads. The starting main is
`698209aaa6e7f1350b6541df5eb192b7b233443d`, the merged horizontal-table and
adjacent-citation milestone (PR #276).

The initial audit found 291 ancestor references, 23 references covered by
14 independently replayed historical replacement proofs, one rendering
equivalent, and seven uncovered references naming five distinct heads.
The [audit script](audit_intake.py) independently compares trees or changed
paths and requires each replacement to be an ancestor; its
[proof definitions](historical-equivalents.json) do not substitute a historical
claim for a fresh comparison.

The incoming histories include both Mail bulk-action continuations, the Word
unit-conversion continuation, bookmark performance documentation, and a retained
maintenance history for an already retired temporary workflow. Overlapping
Mail APIs and independent tests are reconciled together. Source-specific older
validation records retain their original attribution.

## Protocol and format references

- Zotero's [HTTP Citing Protocol](https://www.zotero.org/support/dev/client_coding/http_integration_protocol)
  defines rich HTML insertion and later conversion of citation placeholder
  links into active fields.
- Zotero's pinned [note-editor schema](https://github.com/zotero/note-editor/blob/bdf61e0c275e483c3068ce4fcb86b44691b22afc/src/core/schema/nodes.js)
  uses ProseMirror table nodes with block content in cells.
- The pinned [ProseMirror table schema](https://github.com/ProseMirror/prosemirror-tables/blob/a99f70855f2b3e2433bc77451fedd884305fda5b/src/schema.ts)
  encodes `rowspan`, `colspan` and logical column widths independently; a row
  may have no authored cells when preceding cells cover its grid positions.

## Validation policy

Local execution uses the genuine Flutter 3.47.8 / Dart 3.13.7 SDK and the
workspace's locked dependencies. The baseline table parser and Add Note
controller smokes passed 90 and 108 cases respectively. Those checks precede
this implementation and are not its final acceptance population.

Final evidence will retain commands, source hashes, successful and diagnostic
logs, explicit skips and process exit codes. Installed Zotero, Word,
LibreOffice/OpenOffice and platform-release interoperability are not inferred
from local protocol/model/controller/layout tests.

The user authorized incremental remote checkpoints and the final consistent
merge into main. GitHub Actions, workflow runs, checks and status endpoints are
neither queried nor awaited. Remote publication uses expected-head updates
and exact local/remote Git tree comparisons.
