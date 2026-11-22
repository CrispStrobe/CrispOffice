# Word VBA cell text controls and Join qualification

## Delivered behavior

The bounded Word adapter now accepts direct `Cell.Range.HighlightColorIndex`,
`NoProofing`, `LanguageID` and `LanguageIDOther` assignments. These use the
existing guarded `docx.runFormat` table-cell selector, retaining cell identity
through aliases, `With` and named `ByVal` helpers. They affect current nonempty
ordinary text, preserve paragraph/cell marks and unrelated language slots, and
retain the existing grid/content/protection and atomic-publication boundaries.
No native serializer or runtime mutation implementation was changed.

Shared `Join(parts[, delimiter])` assembles a scalar String from an allocated
local String array. Fixed and dynamic arrays, arbitrary supported lower bounds,
default/explicit separators, empty entries and Unicode are covered. String
size and traversal/copy work are checked before output allocation. Numeric,
Boolean and Variant arrays, whole-array values/parameters, multidimensional
arrays and live document reads remain outside the contract.

See the [Join contract](../../vba-macros-details.md#joining-source-string-arrays),
[cell-control contract](../../vba-word-macros-details.md#cell-highlighting-and-proofing-controls),
[combined report](../../../packages/quds_office_engine/example/macros/word_join_report.bas)
and [cell-control report](../../../packages/quds_office_engine/example/macros/word_table_text_controls.bas).

## Source and remote intake

Initial remote main was `2eecf9aec2c7d1f979064448b911b516d3f56c73`.
All 20 other fork branch tips, all four upstream tips and the latest 30 PR heads
(#329–358) were already ancestors of it; no PRs were open. No initial merge was
needed. Exact observations are in [intake.json](intake.json) and
[intake.md](intake.md).

The qualified implementation, examples, tests and contracts are saved at
`d16649e94bc0106c000a9f2a00e70447e4a5ffa2`. Earlier remote checkpoints are
`3fd8197508ded7fb4de82ecf7264ab6b307e0cb9` and
`4b6eeacfc72902efd628e6f0ff5b943554344726`, on
`codex/word-vba-cell-text-20261122`. Saved Git trees were verified against the
local commit trees, and remote ref updates were non-forced with expected-head
checks. No GitHub Actions run was queried, awaited or used as an acceptance gate.
Commit messages use `[skip ci]`; no workflow or branch-protection settings changed.

Two independent Mail/Zotero branches appeared after the initial intake. The
[concurrent snapshot](concurrent-intake.json) records their heads and explicit
in-progress implementation/validation status. Those checkpoints remain on their
own branches. The [publication refresh](publication-refresh.json) confirms main
was unchanged and already an ancestor of the qualified Word head; no additional
main-source reconciliation was needed. Both later branches' qualification
READMEs still identified work in progress at their refreshed heads.

## Local qualification

The official Dart 3.14.1 Linux x64 archive was verified against its published
SHA-256. The temporary pure-Dart workspace retains unchanged engine, legacy DOC
parser and engine-example package manifests, plus the tracked editor fonts
needed by native Word tests. Only its temporary root workspace list excludes
unrelated Flutter packages. All 56 retained dependency entries match the
repository lockfile, including versions and checksums. See
[runtime-provenance.json](runtime-provenance.json).

| Gate | Executed result |
| --- | --- |
| Initial-main baseline | 225 cases across six relevant suites passed |
| Corrected focused continuation gate | 299 cases passed |
| Final shared macro/VBA coverage | 6,630 cases across 129 files passed |
| Additional native Word atomicity, vocabulary, structure and table-grid coverage | 123 cases across five files passed |
| **Single combined final test command** | **6,753 cases across 134 files; zero failures/skips; exit 0** |
| Strict analysis with `--fatal-infos` | All 10 changed/new Dart files clean |
| Versioned Join corpus on VM and compiled JavaScript/Node | All 25 cases passed; canonical outputs byte-identical |
| Actual table text-controls BAS on VM and compiled JavaScript/Node | 17 native operations, 17 recorded/replayed steps and two further reopen cycles; outputs byte-identical |
| Combined Join/table report through native, CLI and MCP paths | All five integration tests passed within the final command |

The five added test files contribute 146 registrations. Existing negative
matrices lose seven obsolete refusal cases because those members are now
supported, giving a net suite increase of 139. Neither the baseline, focused
checks nor repeated runs are added to the final 6,753-case total. Hidden
loading/setup events are excluded. Per-file totals are in
[test-summary.json](test-summary.json).

The actual examples verify DOCX/DOCM execution, preview without publication,
repeat persistence, native recording/replay, sparse formatting overrides,
preserved opaque VBA and unrelated package parts, shared-property isolation,
policy/cancellation/refusal paths, and rollback after a late missing cell. CLI
failures leave input and an existing output unchanged. The Join corpus checks
complete plans and positioned diagnostics; its expectations identify Microsoft
specification inputs separately from Quds type/resource restrictions.

The final source manifest covers 3,198 files. Every recorded file still matched
after the tests. The prior Join VM/JavaScript result remains applicable because
all 438 checked production/support/corpus dependencies matched the final source.
The cell report comparison is also type-aware, distinguishing Booleans from
numbers even though its raw VM/JavaScript output was identical.

## Corrections retained in the evidence

The first focused run had three authored-test issues: an expected diagnostic
code and two styles-part fixtures that omitted an XML declaration added by an
ordinary save. The fixtures now perform a no-macro control save before baseline
capture and retain the complete styles-byte assertion. The first Join corpus
run corrected diagnostic-code spelling and moved a declaration before executable
statements, as required by the existing language. A preliminary analyzer pass
found one missing-braces lint in a new test. These corrections preceded the
successful final gate; no production fix was needed for those failures.

Initial failed receipts/logs remain alongside successful results. They are not
reported as passes or substituted for the final command. No installed Microsoft
Word differential execution or Flutter UI validation was performed; this record
qualifies the bounded headless engine and its VM/JavaScript portability.

## Reproduction and evidence

In a normally resolved workspace, from `packages/quds_office_engine`:

```bash
dart test --concurrency=4 --reporter=expanded \
  test/office_macro*_test.dart test/office_vba*_test.dart \
  test/word_step_atomicity_test.dart test/word_steps_vocabulary_test.dart \
  test/word_structure_steps_test.dart test/table_grid_steps_test.dart \
  test/word_table_grid_addressing_test.dart

dart run tool/macros/office_macro.dart compile-word-vba \
  example/macros/word_join_report.bas joined-report.qudsmacro.json
```

The exact executed commands, test selection, exit codes, source identities and
artifact hashes are indexed by [validation.json](validation.json). Compressed
logs include the final visible case list, full test JSON stream, source
manifests, runtime-comparison outputs and the exact temporary validation
scripts. Those scripts retain their original environment paths as execution
evidence. [files.json](files.json) maps their original names to saved artifacts;
`SHA256SUMS` covers the saved qualification files.

Portable entry points use the actual committed inputs: `VBA_CONFORMANCE_BASE64`
for `tool/macros/web_vba_join_conformance.dart`, and
`WORD_CELL_TEXT_BAS_BASE64` for
`tool/macros/web_vba_word_cell_text_controls_smoke.dart`.
