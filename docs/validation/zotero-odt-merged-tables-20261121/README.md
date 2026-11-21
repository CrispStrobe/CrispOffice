# Native ODT merged tables and Zotero — 21 November 2026

**Status: subsequent local runtime qualification completed.** The Word style
integration checked the incoming reader/Zotero tests, existing ODT regressions
and editor loading tests with the genuine pinned SDK; see the
[completion record](../word-vba-styles-complete-20261121/README.md).

At the original checkpoint, shared executor disk exhaustion prevented SDK
installation and subsequent shell invocations. The original source-only
qualification report below is retained as historical evidence.

Starting main: `115f1c20131bf0157d047dfe2e9d704ddffb22a2`.
Checkpoint branch: `codex/zotero-parity-20261121-evening`.

## What changes

Native ODT input now accepts supported horizontal and vertical merged tables.
The reader validates the explicit logical coverage grid before reconstructing
rich content. Source paragraphs, formatting and Zotero fields stay in their
originating cell. Native `gridSpan` and vertical restart/continuation cells use
the existing Word table model; continuations have no duplicate citation text.
Merged widths sum the actual logical column widths, and nested tables retain
independent grids.

Supported table and row properties retain their earlier behavior. Cell
backgrounds resolve through named/default inheritance. A covered cell may have
no effective background declaration or one matching its origin. A distinct
effective background, including a transparent override, refuses rather than
being silently discarded.

The limits remain explicit:

| Resource | Bound |
| --- | --- |
| Logical columns / horizontal span | 32 |
| Actual rows / vertical span | 256 |
| Table count / nesting | 64 / 8 levels |
| Native cells | 4,096 across origins, continuations and nested tables |
| Paragraphs | The existing `maxParagraphs`, including generated empties |

Missing/orphan/overlapping coverage, out-of-range spans, repeated rows/cells,
unsupported covered styles and hidden covered content refuse atomically.
Decimal spans may include a plus sign and XML whitespace; hexadecimal
lookalikes, nonbreaking-space padding and invalid values refuse.

ODF permits stored content inside covered cells. This reader deliberately
refuses it, including empty child paragraphs, instead of discarding hidden
source data. The refusal defines Quds' supported subset, not universal ODF
invalidity. Original ODT bytes are not changed. Active imported citations save
as DOCX; ordinary ODT output retains its cached-result contract.

## Remote intake

The [initial intake](initial-intake.json) covers all 31 existing fork branches:
main and 30 topic branches. Each topic head is an actual ancestor of starting
main. An explicit open-PR query returned none.

The checkout subsequently fetched all 321 historical PR heads and all four
upstream branches. The [expanded intake](expanded-intake.json) records 356
captured refs: 342 actual ancestors, ten historical patch-equivalent heads,
two historical heads with no unmatched nonmerge patches, and two squash-merged
PRs whose merge commits are proven ancestors. No completed incoming change
needed another merge.

A later observation found independently advancing **WIP PR #322**, Word VBA
paragraph style assignment, at `61178b9149877ef38e18814ccc694b5ea38be1d8`.
Main was unchanged. That new WIP remains preserved on its own branch; it is not
silently treated as completed work by this increment.

## Source review and prepared tests

Independent review checked the reader against the actual native model APIs,
existing style inheritance and Zotero field reconstruction. It found no
additional source-level blocker after two corrections:

- Validate span syntax against XML whitespace before integer parsing, so
  Unicode `trim()` cannot admit nonbreaking-space padding.
- Keep the nested-note test's original citation paragraph distinct from the
  required empty paragraph generated after a nested table.

The focused reader suite adds horizontal and combined merge cases, repeated
column declarations, widths, inherited fills, row properties, DOCX persistence
and lexical refusals. The independent `odt_merged_table_zotero_test.dart`
prepares 40 cases after parameter expansion: identical-looking citation
ownership/order, staged citation/bibliography refresh, edit/unlink, authored
footnote/endnote nested tables, repeated DOCX saves, invalid topology, hidden
covered content, and actual paragraph/cell/row limits. The editor suite adds
three cases for asynchronous loading, field navigation/edit/unlink/undo,
DOCX reopen, failure atomicity and stale-result refusal.

These are **test sources and intended assertions**, not successful executions.
Source review does not establish their runtime correctness, rendered table
geometry, actual Zotero behavior or Word/LibreOffice acceptance.

## Execution failure and source provenance

The official Flutter **3.47.8** archive (Dart **3.13.7**) downloaded successfully
and matched SHA-256
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
The shared executor filled during extraction. The incomplete SDK was stopped
and was never used as qualification evidence. No dependency resolution,
formatter, analyzer, compiler or Dart/Flutter test ran.

Subsequent normal shell and file-edit calls failed during sandbox startup:
`bwrap: Can't create file .../.git: No space left on device`.
A narrowly scoped elevated attempt to delete our reproducible SDK archive was
automatically rejected because sandbox approvals are disabled. The alternative
desktop runtime was unavailable. No user files were removed.

To preserve the work, exact remote baseline files and logged edits were used
to reconstruct the implementation/focused tests through the GitHub API.
The independent and editor tests were preserved from their prepared source.
The independent test is equivalent to, not asserted byte-identical with, the
unreadable local draft. Published blob identities in
[source-review.json](source-review.json) identify the reviewed sources.
No unavailable local logs or passing results were reconstructed.

## Reproduction once a usable executor is available

Use the pinned Flutter SDK and the repository lock, with writable temporary
and package-cache directories. First verify `flutter --version` reports
Flutter 3.47.8 / Dart 3.13.7, then run `flutter pub get --enforce-lockfile`
without changing the checked-in dependency graph.

From the repository root:

```bash
dart format --output=none --set-exit-if-changed \
  packages/quds_office_engine/lib/src/word/serial/odt_document_reader.dart \
  packages/quds_office_engine/test/odt_document_reader_test.dart \
  packages/quds_office_engine/test/odt_merged_table_zotero_test.dart \
  packages/quds_office_editor/test/word_odt_merged_table_load_test.dart

dart analyze --fatal-infos \
  packages/quds_office_engine/lib/src/word/serial/odt_document_reader.dart \
  packages/quds_office_engine/test/odt_document_reader_test.dart \
  packages/quds_office_engine/test/odt_merged_table_zotero_test.dart \
  packages/quds_office_editor/test/word_odt_merged_table_load_test.dart
```

From `packages/quds_office_engine`:

```bash
dart test \
  test/odt_document_reader_test.dart \
  test/odt_merged_table_zotero_test.dart \
  test/odt_libreoffice_fixture_test.dart \
  test/odf_zotero_ownership_test.dart \
  test/odf_zotero_resource_test.dart \
  test/word_table_vertical_merge_layout_test.dart \
  test/word_zotero_note_tables_integration_test.dart \
  test/word_zotero_nested_tables_integration_test.dart
```

From `packages/quds_office_editor`:

```bash
flutter test \
  test/word_odt_load_test.dart \
  test/word_odt_merged_table_load_test.dart \
  test/word_zotero_vertical_table_controller_test.dart \
  test/word_zotero_citing_controller_test.dart
```

Record actual failures and correct them before calling the increment
runtime-qualified. Existing broader tests may then be selected to resolve
specific regressions; earlier test totals must not be reused.

## Checkpoints and remaining parity work

- `65f71ba2942f53d38ecb899594698d6794c2fe3e`: initial intake and bounded scope.
- `56841e8bc4c00a05f443cf448a82ecbff0542f6c`: initial implementation, focused
  engine/editor regressions and explicit execution-blocked status.
- A subsequent checkpoint retains source-review corrections, the independent
  suite, updated contracts and this report.

Checkpoints and the requested merge use `[skip ci]`; GitHub Actions are not
queried, rerun or awaited. The user explicitly requested incremental remote
preservation and final main integration. Runtime qualification remains pending
and is not inferred from that integration.

Native editable ODT output, broader ODT formatting/images, installed
Word/LibreOffice/Zotero sessions and separately identified legacy Apache
OpenOffice acceptance remain open. Real LibreOffice merged-table fixtures are
needed before claiming broad shading or rendering compatibility.

## Primary format reference

[OASIS ODF 1.3 Part 3](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html),
sections 9.1.5, 19.680 and 19.682, defines covered-cell order and row/column spans.
