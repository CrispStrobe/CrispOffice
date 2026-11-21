# Word VBA table-cell authoring: local qualification

The feature source is checkpoint
`e65ce54c5301839c1c012092c13f1997afec127e`. The completed intake at
`9d6fc334c6df86262cc5086caa253765b1b5fe86` retains every captured current fork
branch head, including the published Mail and ODT work and the latest Zotero
table-layout branch. Its product source, tests, tools and dependency inputs
are identical to the qualified feature checkpoint. The later qualification
commit adds this record and the bounded local runner.

## Delivered behavior

The `vba-word` compiler supports explicit `Tables`, `Table`, `Cell` and cell
`Range` selectors, aliases, `With`, required `ByVal` object helpers and named
module-helper calls. `Table.Cell(row, column).Range.Text = value` emits one
`docx.tableCellRangeText` operation. Source selectors are one-based exact Long
values; native selectors are zero-based. Selectors use positional arguments.

The guarded native operation fills ordinary single-paragraph cells in
unmerged rectangular main-story tables. It preserves structural ownership,
table/cell/paragraph formatting and the first effective run formatting. Its
conservative collection and source-packet checks refuse unsupported neighboring
table structures as well as ambiguous target content. The previous native
`docx.tableCellText` contract is unchanged.

The [actual report module](../../../packages/quds_office_engine/example/macros/word_table_report.bas)
fills five cells across two tables using local data, computed text and a typed
helper. It runs through compilation, native JSON, validation, execution,
recording/replay, CLI and MCP. DOCM tests retain the inert VBA project bytes,
relationships and unrelated custom XML. Failed late selectors and denied
policies leave the published bytes and revision unchanged.

An associated DOCX import correction retains explicitly represented empty
ordinary runs, preserving insertion formatting through clear/save/reopen/refill.
Bare runs remain discarded, and structural field/note/comment/drawing/break
markers do not gain phantom ordinary runs.

The [exact Word contract](../../VBA_WORD_MACROS.md#filling-existing-table-cells)
documents admitted structure and unsupported reads, enumeration, merged/nested
tables, arbitrary ranges and embedded VBA execution. No full Word or VBA parity
is claimed.

## Successful final qualification

| Scope | Suites | Passing cases | Failed / skipped |
| --- | ---: | ---: | ---: |
| Macro/VBA, operation and parser regressions | 124 | 6,289 | 0 / 0 |
| Incoming ODT/table-layout engine regressions | 17 | 376 | 0 / 0 |
| Final-source Studio shortcuts and focus | 4 | 35 | 0 / 0 |
| Final-source editor focus and review | 2 | 21 | 0 / 0 |
| Final-source editor ruler and shaping | 2 | 17 | 0 / 0 |

The engine scopes are disjoint: **6,665 cases across 141 suites**. Final-source
editor/Studio scopes add **73 cases**. The initial 97-case integration cohort
is retained as earlier evidence and is not added to these final-source totals.

The new feature contributes **231 regression cases** within the engine total:
107 compiler, 84 native, 16 corpus/provenance, seven end-to-end integration and
17 empty-run import cases. The versioned corpus has 15 independently authored
table-cell expectations; its provenance distinguishes specification-derived
expectations from installed-Office observations.

Strict scoped analysis, pinned-language formatting and whitespace checks pass.
Every successful engine command records unchanged hashes for **1,154 source,
fixture, font and dependency inputs** before and after execution. The same
inputs were checked again after the final ancestry-only reconciliation.
Successful final-source UI receipts also record unchanged captured input hashes.

The actual table report produces byte-identical JSON receipts on Dart VM and
compiled JavaScript/Node. It verifies five operations, idempotent replacement,
two additional DOCX reopens, preservation, recording/replay, late rollback and
three policy refusals. Three canonical conformance corpora also match on VM and
JavaScript: table cells (15 cases), existing Word paragraphs (44), and numeric
intrinsics (58). These **117 portable corpus cases** overlap the engine checks
and are not added to the test totals.

## Runtime and reproduction

Validation used Flutter **3.47.8** and Dart **3.13.7**. The official Flutter
framework is `737ba8f885dc774b53b442759999a312c9461e4e`, engine
`cf636b1dfb818dd6a3ff16e390e93b1a036969c8`. The full Flutter workspace resolved
146 locked packages with `flutter pub get --enforce-lockfile`; all 21 compared
workspace manifests/lockfiles remained byte-identical. The pure Dart engine
harness uses source symlinks and the unchanged 56-package subset of those
locked dependencies. Exact runtime and harness receipts are in the archive.

With the repository's pinned SDK installed and dependency resolution complete,
run each finite phase from the repository root:

```sh
python3 docs/validation/word-vba-table-cells-20261121/run_local.py regressions \
  --repo "$PWD" --engine "$PWD/packages/quds_office_engine" \
  --dart /path/to/pinned/dart --out /path/to/qualification
```

Repeat with `incoming`, `static` and `portable` in place of `regressions`.
`TMPDIR` and `PUB_CACHE` must point to usable locations. The runner accepts a
resolved source-symlink engine workdir for environments without a complete
Flutter workspace. The recorded UI runners use the full enforced Flutter
workspace. No tracked manifest or dependency lock was modified for testing.

The regression runner executes all selected files in batches of at most ten,
because Dart retains a separate compiled test kernel per suite. The exact
124-file scope and every command are retained, including output, case outcomes,
elapsed times and input hashes. Generated JavaScript is reproducible; its hashes
are retained alongside the VM/Node receipts instead of archiving compiled code.

## Preserved failed attempts

The first unbatched macro attempt encountered missing sparse fidelity fixtures
and harness font links, then exhausted scratch space with retained test kernels.
It is excluded from successful qualification. The final bounded batches include
every originally selected suite, with the required fixtures/fonts available.

The initial incoming engine attempt passed 375 cases and failed one because a
Zotero fixture was absent. The complete 376-case rerun passes. An initial editor
follow-up failed to create its temporary directory during the disk exhaustion,
before executing cases; the same selected files subsequently pass using a
dedicated temporary directory. Raw failed-attempt logs and explicit receipts
remain in the archive. Only reproducible generated test/build files were
reclaimed; source and evidence were retained.

## Intake and evidence

[intake.json](intake.json) records exact branch heads and ancestor checks. The
initial audit also found every captured upstream branch head already integrated
and no open upstream PRs. Concurrent Mail/Zotero publication changes were merged
before completion; the last two conflicts concerned only a README heading and
retaining the new changelog entry. No force push or branch deletion was used.

[qualification.json](qualification.json) contains the results, runtime identity
and archive digest. [source-inputs.json](source-inputs.json) binds the qualified
inputs. [execution.tar.xz](execution.tar.xz) contains successful and failed raw
events, exact commands, case outcomes, snapshots and reproducible runners;
[execution-index.json](execution-index.json) records every member's size and
SHA-256 digest.

GitHub Actions were not queried or awaited. Installed Microsoft Word
differential tests, fresh external LibreOffice/Zotero converter runs and the
entire Flutter application suite were not executed. Earlier incoming converter
evidence retains its original source/runtime identities and receives no new
qualification credit here.
