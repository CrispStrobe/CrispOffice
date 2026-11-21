# Native ODT merged tables and Zotero — 21 November 2026

## Scope and starting point

This increment extends native ODT import to supported horizontal and vertical
table merges while preserving Zotero field ownership. The existing Word table
model, active citation operations and DOCX persistence provide the destination
representation. Ordinary ODT export retains its cached-result contract.

Starting main: `115f1c20131bf0157d047dfe2e9d704ddffb22a2`.
Checkpoint branch: `codex/zotero-parity-20261121-evening`.

The [initial intake](initial-intake.json) checks all 31 existing fork branches:
main and 30 topic branches. Every topic head is an actual ancestor of main,
with no unique commit to reconcile. An explicit open-PR query returned none.
The checkout also fetches historical PR heads and upstream branches; any
additional findings belong to a separate expanded intake receipt.

## Implementation contract

- Accept rectangular ODT tables with explicitly described covered cells and
  bounded row/column spans. Infer logical columns only when no column
  declarations exist, as the existing reader does for ordinary tables.
- Keep source paragraphs and Zotero fields in their originating cell. Emit
  native vertical continuation cells without duplicating source text or fields.
- Preserve supported inherited cell shading and sum the actual logical column
  widths for a merged cell. Nested tables use independent coverage grids.
- Reject missing/orphan covered cells, overlaps, out-of-range spans and hidden
  covered-cell content. Repeated rows/cells and unsupported styles retain their
  explicit refusal; no input is silently flattened or repaired.
- Count generated continuation cells and paragraphs against the complete
  document's existing resource budgets.

## Qualification plan

Exercise combined spans, citations in body/note/nested-table owners, full
document refresh, editing/unlinking and repeated DOCX saves. Verify layout and
selection ownership, asynchronous editor loading and failure atomicity. Keep
ordinary ODT and Zotero regression coverage around the changed reader.

Use the repository-pinned Flutter 3.47.8 / Dart 3.13.7 with the checked-in
dependency lock. Checkpoints use `[skip ci]`; GitHub Actions are not a wait path.
Executed results, exact source identity and remaining acceptance boundaries
will be recorded here before the completed increment is merged.

The planned checks use synthetic ODT and controlled Zotero callbacks. They do
not establish an installed Zotero/Word/LibreOffice plugin session or legacy
Apache OpenOffice compatibility. Native editable ODT output remains separate
work; imported active citations save as DOCX.

## Development checkpoint: execution environment blocked

The merged-table reader and its focused engine/editor regression sources have
been preserved in a remote development checkpoint. They are not yet qualified.
The reader validates explicit ODF coverage before reconstructing rich content,
retains origin ownership, and generates bounded native vertical continuations.

SDK setup downloaded the official Flutter 3.47.8 archive and verified SHA-256
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
The shared executor ran out of disk during extraction, before a usable runtime
or dependency graph was available. New shell and file-edit tool processes then
failed during sandbox startup with `No space left on device`. No Dart formatter,
analyzer, engine test or Flutter test result is claimed for this increment.

The implementation checkpoint was reconstructed from exact remote baseline
files and logged edits because a fresh filesystem read was unavailable. The
covered-cell XML-whitespace check is a further reviewed source edit; the editor
test source was preserved directly from its prepared content. Their published
blob identities, rather than an unavailable local-state assertion, identify
the checkpoint. Runtime validation and final integration remain pending.

ODF 1.3 permits stored content in covered cells. This reader deliberately
refuses such content instead of discarding it; that refusal describes Quds'
supported subset, not a claim that the source is invalid ODF. See OASIS Part 3
sections 9.1.5, 19.680 and 19.682:
https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html
