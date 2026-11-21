# Word VBA section PageSetup qualification — 2026-11-21

This increment adds section-scoped Word `PageSetup` setters to the bounded VBA
source compiler and the transactional `docx.pageSetup` operation. The final code
was qualified at **`72aa0ed9f447d1239763f0fbaa9ca9f7f78088c7`**. Subsequent
publication changes in this directory only retain evidence and reproduction
instructions. The historical working-branch/directory name mentions paragraph
pagination; the implemented increment is section page geometry.

## Delivered behavior

The source compiler accepts `ActiveDocument`, `ThisDocument`, or
`Application.ActiveDocument`, one-based `Sections(i)` / `Sections.Item(i)`, typed
`Section` and `PageSetup` locals and required `ByVal` helper arguments, named
helper arguments, and nested `With` blocks. It lowers these eight setters to
zero-based, policy-controlled native operations:

| VBA setter | Native property |
| --- | --- |
| `PageWidth` | `width` |
| `PageHeight` | `height` |
| `TopMargin` | `top` |
| `BottomMargin` | `bottom` |
| `LeftMargin` | `left` |
| `RightMargin` | `right` |
| `HeaderDistance` | `header` |
| `FooterDistance` | `footer` |

Measurements must lie exactly on the 0.05-point/twip grid. Dimensions are at
least one point, distances are nonnegative, and all values fit signed 32-bit
twips. Each step validates the resulting body and uniform-column text area.
Sparse native XML updates preserve unrelated geometry, extension namespaces,
and opaque package parts, including DOCM VBA payloads. Width/height assignment
clears the native printer paper code for custom paper. Failure rolls back the
entire detached run; recording, replay, allowlists and cancellation continue
through the existing engine paths.

Ambiguous or unsupported source geometry is rejected before publishing model
changes. This includes malformed or duplicate native attributes, negative or
universal native measurements, nonzero gutters, custom/unequal columns,
markup-compatibility section alternatives, `ProcessContent` sections/settings,
and enabled mirror-margin, top-gutter or book-fold settings. The source subset
does not include PageSetup reads, document-wide broadcasting, Orientation or
PaperSize setters, selection, or section creation. It does not execute embedded
VBA projects or establish full Microsoft Word/VBA parity.

See the [Word VBA contract](../../VBA_WORD_MACROS.md),
[macro operations](../../MACROS.md),
[parity roadmap](../../VBA_PARITY_ROADMAP.md), and
[executable BAS example](../../../packages/quds_office_engine/example/macros/word_page_setup.bas).

## Final local acceptance

| Gate | Result |
| --- | --- |
| Selected macro/VBA and Word fidelity regression | **3,996 passed; 0 failed; 0 skipped; 79 files** |
| Focused PageSetup, section and structure gate | **198 passed; 0 failed; 0 skipped** |
| New PageSetup cases within those gates | **147: 43 native, 89 source, 15 integration** |
| Engine library, macro tools and three new test files | Strict analysis with `--fatal-infos` passed |
| Actual committed BAS on Dart VM | Passed |
| Actual BAS compiled to JavaScript and run under Node | Passed; receipt byte-identical to VM |
| Actual root Mail presentation aliases | **2 passed** |
| Captured Mail increment | **498 passed**, including six compiled-JavaScript fallback cases; strict core/transport analysis passed |

The 198-case focused gate overlaps the 3,996-case regression; these counts must
not be added. The regression selection covers every current `office_macro*`
and `office_vba*` test plus the five listed Word/fidelity suites. It is not a
claim that every suite or Flutter application in the repository was run.

The regression took 238.618 seconds using Dart 3.14.1 and actual `package:test`
dependencies. [final-acceptance-summary.json](final-acceptance-summary.json)
records the exact commands, results, source checks and execution boundary.
[page-setup-portable-receipt.json](page-setup-portable-receipt.json) retains the
ten-operation example, repeated export/reopen behavior, unchanged third
section and opaque payloads, whole-run rollback, and recording/replay results.

The example's SHA-256 is
`92cc0edc359f2d31813c2266a8e55cb6153f27d8b630ed7d0f008221d62c6493`;
the identical VM/JavaScript output has SHA-256
`c79926eba214a4f1e9458e60a9ee147d618ec6232f6148e3a00d680e92cf0f23`.

## Source identity and retained evidence

All **3,019 captured source/fixture inputs** were checked against their actual
Git blobs at the qualified commit. There were no mismatches and no source
changes during the final run. The capture was made while the final namespace
fixes were still uncommitted; its original local-head label therefore differs
from the qualified commit. The per-file hashes, final committed-blob comparison
and [source-applicability.json](source-applicability.json) bind the results to
the actual final source, not that earlier label.

The engine and legacy parser were copied to an isolated Dart workspace. Only
three copied `resolution: workspace` manifest directives were removed. Original
sources, tests, the root dependency lock, analysis options and both editor font
fixture directories were retained. This permitted genuine CLI/MCP, native Dart
and compiled-JavaScript engine checks without replacing Flutter with stubs.

[local-qualification-evidence.tar.gz](local-qualification-evidence.tar.gz)
contains the full JSON test-event logs, complete 79-file list, per-source
SHA-256 capture, strict-analysis output, portable outputs, actual execution
scripts, Mail source-integrity receipts and all Mail phase logs. The
[evidence manifest](evidence-manifest.json) records the archive digest and the
uncompressed size and SHA-256 of every member. Generated JavaScript build
products and the SDK are reproducible and are not included.

The final run is separate from earlier unsuccessful development attempts.
Those attempts identified missing font fixtures and a repeated namespace
declaration regression; the fixtures and implementation were corrected before
the passing run above. [review.json](review.json) records the independent review
findings, their verified resolutions, and the review's limits.

No installed Microsoft Word host, Flutter widget/application runtime or live
Mail provider account was exercised. Mail provider tests use the original
in-process protocol and HTTP fixtures. Preserving opaque VBA project payloads
does not imply executing them. These results do not establish Office `Single`
rounding parity.

## Reproduce the engine acceptance

Use Dart 3.14.1 and Node, then run from a checkout of the qualified code or a
later commit with the same engine/parser/fixture sources:

```sh
python3 docs/validation/word-vba-paragraph-pagination-20261121/reproduce.py \
  --dart /path/to/dart \
  --node /path/to/node \
  --work-dir /absolute/path/to/empty-validation-directory
```

The work directory must be empty and outside the checkout. The script copies
the actual packages and font fixtures, resolves dependencies from the captured
lock, runs strict analysis and the same 79-file selection with concurrency 4,
executes the actual BAS on the VM and compiled JavaScript, compares receipts,
and writes commands, raw logs, source hashes and `qualification.json`. It does
not modify the source checkout or invoke GitHub Actions. The separate focused
and Mail commands and their original results are retained in the archive.

## Reconciled remote work and checkpoints

[intake.md](intake.md), [intake-inventory.json](intake-inventory.json),
[intake-verification.json](intake-verification.json) and
[overlap-resolution.json](overlap-resolution.json) record the initial complete
capture of 328 fork/upstream branch and PR heads: 303 ancestors of initial main,
24 freshly verified historical equivalents, and one incoming merge. There were
no open PRs at capture. The incoming crisscross history was reconciled while
retaining newer main behavior and exact historical evidence blobs.

[late-intake.md](late-intake.md) and [late-intake.json](late-intake.json) record
the subsequent captured Zotero intake and Mail observation increment. Their
heads were merged with real ancestry. The final Mail core, transport and UI
subtrees exactly equal the validated Mail source at
`71a9d73f86a30380d7fe3563f1a0048f1f7eb860`.
[late-mail-validation.json](late-mail-validation.json) records its 498 cases.
Later pushes to concurrently active work branches are outside these fixed
source snapshots; remote main is refreshed before final publication.

| Remote checkpoint | Saved increment |
| --- | --- |
| `aefcb7663e63130487054723ed7f1530ad5f9f60` | Initial remote reconciliation |
| `d71d378325e4f61996320b0415779f45cea60ce2` | Word PageSetup source/native implementation |
| `c093f6387fcae69f04c63f4344476e4785906a54` | Namespace/source guards and contract |
| `1e49a2afa2be0cb3b095f311d1d396ff0d669d9e` | Captured Zotero intake merge |
| `770c7dc8afddf62f1d831af95e9070bd890df4f4` | Captured Mail increment merge and validation |
| `72aa0ed9f447d1239763f0fbaa9ca9f7f78088c7` | Repeated-edit namespace stability; final qualified code |

The checkpoints are retained on
`codex/word-vba-paragraph-pagination-20261121`. GitHub Actions, workflow queues,
check runs and statuses were neither queried nor awaited. No workflow or
repository policy was changed.
