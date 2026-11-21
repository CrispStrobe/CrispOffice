# Word VBA section controls: local acceptance

**Passed: 5,286 tests across 127 files, zero failures and zero skips.**
The final integrated engine passed strict analysis and both actual BAS examples
produced byte-identical Dart VM and compiled JavaScript receipts. All 3,032
captured source/configuration/font inputs match committed Git blobs and remained
unchanged during execution. No GitHub Actions runs or queues were queried or
awaited.

Qualified code checkpoint: `47660815c429e15aa280005dc6d76bb36c53eca4`

Qualified tree: `82d40c175d7aafb588dcb0f241c876fe5233dd73`

Subsequent publication commits add only evidence and documentation. The exact
command list, JSON test events, stdout/stderr, dependency identities and before/after
source hashes are retained in [the evidence archive](local-qualification-evidence.tar.gz).
[acceptance-summary.json](acceptance-summary.json),
[qualification.json](qualification.json) and
[source-applicability.json](source-applicability.json) give machine-readable
results and source binding.

## Delivered behavior

The existing explicit section selectors and typed `PageSetup` aliases now accept:

| VBA member | Supported values or form | Native operation |
| --- | --- | --- |
| `Orientation` | `wdOrientPortrait` (0), `wdOrientLandscape` (1) | `docx.pageOrientation` |
| `TogglePortrait` | Zero arguments; bare, parenthesized or `Call` form | `docx.pageOrientation` |
| `SectionStart` | Continuous (0), new page (2), even page (3), odd page (4) | `docx.sectionStart` |

These operations participate in existing typed helpers, named arguments, nested
`With` blocks, source-order accounting, policy allowlists, recording and atomic
publication. Section selectors are explicit; no fallback section or
collection-wide broadcast is introduced.

Orientation is resolved at native integer-twip precision (0.05 pt). A change
swaps canonical width/height while retaining named margins, header/footer
distances, uniform columns and printer paper code. Square pages preserve an
explicit orientation through repeated saves/reopens. Existing opaque native
metadata and DOCM VBA payloads remain intact. Unsupported or inconsistent source
orientation, ambiguous pending near-square geometry, and invalid rounded body or
column widths are refused before publication.

Section starts change only the selected section's native break attribute and
its snapshot, preserving unrelated geometry and metadata. Headless pagination
checks place the second section on pages 1/2/2/3 for continuous/new/even/odd
starts respectively. The compiler recognizes `wdSectionNewColumn` (1) but
refuses it because the native model does not implement that mode.

See [the precise contract](../../VBA_WORD_MACROS.md#section-orientation-and-start-controls),
[the BAS example](../../../packages/quds_office_engine/example/macros/word_sections.bas),
and [the portability harness](../../../packages/quds_office_engine/tool/macros/web_vba_word_sections_smoke.dart).

## Executed final gate

| Gate on the final integrated engine inputs | Result |
| --- | --- |
| Strict analysis: engine `lib`, macro tools and six changed Word test files | No issues |
| Macro/VBA, native Word/fidelity/layout and all selected Word/Zotero suites | **5,286 passed; 0 failed; 0 skipped; 127 files** |
| Actual `word_sections.bas`: Dart VM and compiled JavaScript + Node | Passed; complete stdout byte-identical |
| Existing `word_page_setup.bas`: same two runtimes | Passed; complete stdout byte-identical |
| Root hosted dependency identities | 54/54 matched |
| Auto-generated example-lock hosted identities | 8/8 matched |
| Original inputs, copied inputs and resolved engine lock | Unchanged |

The standalone harness also exercises detached validation, whole-run rollback,
policy denials, successful-only recording/replay, DOCM opaque payload retention,
repeated reopen, authored A4 rounding, fractional-square normalization and
near-square orientation. It runs the checked-in BAS files, rather than a manually
reconstructed equivalent. The section example emits seven native operations.

Executed runtimes: official Dart 3.14.1 and Node v24.22.3.
The native regression command completed in 261.493 seconds.
These are correctness checks; that duration is not a performance benchmark.

| Portable receipt | Output SHA-256 |
| --- | --- |
| Section controls | `40c10fc01520a6337a9e684e1df4ac4c08b12be3a4d13a0602d1c5f19d06709c` |
| Existing page setup | `c79926eba214a4f1e9458e60a9ee147d618ec6232f6148e3a00d680e92cf0f23` |

## Incoming changes and scoped Flutter evidence

The [initial intake](intake.md) accounts for all 335 captured fork/upstream
branch and PR heads. The [publication intake](publication-intake.md) records the
later completed Mail, performance-tooling and Zotero snapshots retained in
ancestry, plus the later active draft/WIP successors outside this accepted
snapshot. The earlier [late intake](late-intake.md) remains a historical record;
its incomplete Zotero checkpoint was superseded by the completed `3da241d5`
implementation integrated here.

| Additional recorded gate | Result and applicability |
| --- | --- |
| Exact incoming Zotero native source | 798 passed, 0 failed, 0 skipped across 28 files |
| Zotero helper after 21 brace-only lint fixes | Strict analysis clean; 30 transfer cases passed; all 5,977 non-brace tokens identical |
| Zotero editor/controller/dialog suites | 97 passed, 0 failed, 0 skipped; focused analysis clean; exact merged controller matches tested identity |
| Mail session/store/provider-identity suites | 58 passed, 0 failed, 0 skipped; focused analysis clean; all eight captured inputs match |
| Earlier replacement-layout and enabled typing suites | 53 passed, 0 failed, 8 expected image-only fixture skips; scoped execution before the later Zotero controller additions |
| Performance reporter | Synthetic complete/B-E event, per-thread pairing, idle and handler-overlap assertions passed |

Flutter executions used genuine Flutter 3.47.8 / bundled Dart 3.13.7 with pinned
dependencies. The Zotero Flutter run used the original helper; the later
brace-only correction is separately bound by native analysis/tests and the
final integrated gate. The earlier layout/typing run was not literally repeated
after the Zotero merge; read-only comparison shows its lazy-layout/listener
logic remains intact and the controller differences are isolated Zotero hunks.
Optional validation-directory DOCX fixtures were not materialized in that
sparse checkout, so its counts do not claim the larger earlier author's corpus.

See [incoming editor evidence](incoming-editor-validation.json),
[late Flutter evidence](late-incoming-flutter-validation.json),
[incoming Zotero review](incoming-zotero-engine-review.json), and the
[transcribed parser smoke receipt](perf-reporter-smoke.json). The parser's
frame/phase output was exercised without numeric assertions. The Flutter
profile harness received source review only and was not executed.

## Reproduction and evidence integrity

From a checkout containing both editor font fixture directories:

```sh
python3 docs/validation/word-vba-sections-20261121/reproduce.py \
  --dart /path/to/dart --node node \
  --work-dir /empty/path/outside/checkout
```

The recipe creates an isolated engine/parser workspace, removes only copied
workspace-resolution declarations, enforces hosted identities against the root
lock, and captures source invariance and full commands. It requires the locked
packages to be cached or accessible. Original manifests and locks are not
rewritten. The output archive excludes SDKs, caches, copied checkouts and compiled
JavaScript. [archive-manifest.json](archive-manifest.json) binds all retained
archives by size and SHA-256; [local-evidence-manifest.json](local-evidence-manifest.json)
binds the final archive's individual evidence members.

The earlier [preintegration run](preintegration-qualification.json) is retained
with its original overall **failed** recipe status: all 4,278 cases and portable
checks passed, but its source-invariance gate classified a newly generated
example lock as an input change. That lock's eight hosted identities matched
the root lock and no existing input changed. The recipe was corrected to verify
that exact generated output explicitly, then the entire expanded final gate
above was rerun and passed. The old failure was not relabeled as a success.

## Boundaries

This remains a bounded source-to-plan Word VBA adapter. Source property reads,
new-column section starts, collection-wide page setup, `PaperSize`, and live
document-dependent VBA branching are outside this increment. Embedded VBA
projects are preserved as opaque payloads and are not executed. Installed
Microsoft Word, LibreOffice, Zotero and printer-dependent interoperability was
not exercised. Mail/Zotero tests used in-process fixtures, not live accounts.
