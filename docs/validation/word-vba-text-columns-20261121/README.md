# Word VBA text columns — 21 November 2026

## Result and scope

The final stable local gate passed **5,258 tests across 107 files**, with zero
failures or skips and clean whole-engine analysis. All 948 source inputs were
unchanged during validation and match the final implementation checkpoint
`1995fb753cebffb818ba3123f23719e6149f9314`. The later reconciliation with remote
main retained the exact same Git tree; remaining publication changes only add
this qualification record and its evidence.

This increment adds explicit `Section.PageSetup.TextColumns` selectors, typed
`TextColumns` aliases and required `ByVal` helpers, `SetCount NumColumns:=n`,
`Spacing` and `LineBetween`. The guarded `docx.textColumns` operation changes one
existing uniform section, preserves unrelated native XML and validates resulting
geometry before publication. The complete BAS example is
[`word_text_columns.bas`](../../../packages/quds_office_engine/example/macros/word_text_columns.bas).

The [contract](../../VBA_WORD_MACROS.md#uniform-section-text-columns) records
numeric bounds, method forms, property ownership and unsupported scope. Count
accepts integers 1–45; spacing accepts nonnegative exact 0.05-point increments;
separator writes require Boolean values. Native geometry must retain at least
12 points of usable width per column. Unequal/custom columns and unmodeled layout
settings are rejected atomically. No live document reads, unequal-column
conversion, full VBA runtime or installed Microsoft Word differential acceptance
is claimed.

## Recent-work intake and remote checkpoints

The initial remote main was `08fe271f945dfc915dc817febb756ca111baed73`.
All 33 advertised branches were inspected; 29 non-main tips were already
ancestors. All pull-request head refs were fetched. The outstanding Mail test
branch merged as PR #317 during intake, advancing main to
`f3a0a64a8ea2995221e262d65950283a6049dfb4`.

The first integration checkpoint retained that main and both outstanding branch
histories:

- `fix/goldens-about-20261121` at
  `90736bdcf07feb64b8e1c2a76c8a80d9decf0ccb`: running app version/build in About,
  deterministic About tests and dependency/platform lock updates; additionally,
  preserve an unchanged authored PPTX transition when no duration was authored.
- `ci/golden-attrib-20261121` at
  `3bae324bbc56d7fa49089100eace3dd3c4798153`: retain ancestry while omitting
  `.github/workflows/tmp-golden-attribution.yml`, whose own header requires
  removal before merge. The original diagnostic is recoverable from retained
  commit history.

A final remote refresh found PR #318 merged as
`d4a1f2274e3e0147628f4daa1d937faac5ff81ce`, containing the same About/oracle work
already qualified here. Merging that latest main into the feature branch made
**no file changes**: both trees are
`9a90057f77c8a636a8c6e74aee978d038f2ad457`. The publication snapshot advertised
31 branches and no open PRs before opening this work's PR; every captured branch
tip is retained in the reconciled ancestry.

Incremental remote saves on `codex/word-vba-next-20261121`:

| Checkpoint | Commit |
| --- | --- |
| Recent branch integration | `db364268d5034fa4a66d482534c6912ce2f559d9` |
| Typed VBA source support and BAS example | `e33a81c68bd4271d71270d5ebc0de73bb28e4fe3` |
| Guarded native operation, tests and contract | `ad7f295740a747bde77f88b2bce01de8848d171a` |
| Integration, portable coverage and namespace repair | `d8157d58a9d623fb118ed83cbee48195ee82c252` |
| Final namespace projection repair and regression gate | `1995fb753cebffb818ba3123f23719e6149f9314` |
| Latest main PR #318 reconciled with identical tree | `5224454a71f7ada7c82c5be15ed303402dcd77cc` |

See [initial and refreshed intake](intake.json), its
[ancestry checks](intake-ancestry.json), and the
[publication reconciliation](publication-intake.json). GitHub Actions were not
an acceptance gate and were not awaited, as requested. Checkpoint commit
messages include `[skip ci]`.

## Local qualification

The official Flutter 3.47.8 archive was restored and SHA-256 verified
(`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`);
its Dart SDK is 3.13.7. The workspace and Flutter-tool dependencies resolve
offline with the checked-in lockfiles enforced. No dependency manifests were
changed for runtime setup.

| Check | Final result | Evidence |
| --- | --- | --- |
| Whole-engine `dart analyze --fatal-infos` | Exit 0; no issues | [Analysis receipt](evidence/final-engine-analysis.json) |
| Macro/VBA/XML/native-fidelity regression cohort | **5,258 passed; 0 failed; 0 skipped; 107 files** | [Final summary](evidence/final-summary.json), [target list](evidence/final-targets.json), [compressed JSON event log](evidence/final-macro-xml-tests.stdout.gz) |
| New TextColumns source/native/end-to-end suites | 81 / 83 / 12 passed; included in the cohort above | [Cohort receipt](evidence/final-macro-xml-tests.json) |
| Final XML capture and Word compatibility focus | 27 passed | [XML receipt](evidence/xml-projection-summary.json) |
| Native Flutter Word page layout | 10 passed | [Receipt](evidence/xml-projection-summary.json), [compressed log](evidence/word-page-layout-final.jsonl.gz) |
| Complete BAS on Dart VM and optimized JavaScript under Node | Both passed with identical result JSON; all 10 input hashes unchanged | [Portable receipt](evidence/text-columns-final-portable-receipt.json) |
| Incoming Studio About tests and scoped analysis | 11 passed; no analysis issues | [About receipt](evidence/studio-about-summary.json) |
| Real native PPTX/XLSX generation and exact fidelity oracle | 6 generation tests passed; all 15 exported files accepted over three save/reopen cycles; 4 deliberate corruptions rejected | [Oracle qualification](evidence/native-oracle-qualification.json) |

The stable broad run took 23.035 seconds for analysis and 145.894 seconds for
tests. Its [compressed source manifest](evidence/final-sources-before.json.gz)
records all 948 inputs; `sourceChangesDuringValidation` is empty. Later
reconciliation and evidence preparation did not alter any of those inputs.
The portable receipt spans a checkpoint SHA alignment, so `headBefore` and
`headAfter` differ; the ten source hashes are identical and match the qualified
implementation. XML and native-oracle receipts likewise carry exact source
hashes matching the final implementation.

Integration and portable checks exercise the committed BAS, repeated saves and
reopens, section isolation, preservation of opaque DOCM payload bytes,
alias/helper rebinding, setter order, geometry, late failure rollback, recorder
and revision behavior, allowlists, budgets, replay, MCP and CLI paths. Byte
preservation of opaque macro payloads does not establish that an Office digital
signature remains valid after editing a signed package.

The incoming oracle was checked against actual generated exports, superseding
the earlier 14 subtree probes. Authored `fade`/`spd=slow` transitions without
`p14:dur` remain unchanged; edited `wipe` transitions have positive duration
`900`. The exact oracle rejects changed authored speed, changed authored kind,
an unexpected authored attribute and zero edited duration.

## Defects found and corrected during qualification

Independent source review found a missing static scalar-Variant/object guard.
The final source suite covers invalid `TextColumns` assignment and helper
arguments even in unused helpers and dead branches.

Native integration exposed a pre-existing XML capture defect: a descendant's
local namespace shadow could corrupt the captured root. The fix retains reader
scope per visible node and materializes missing or changed declarations locally.
A further independent review reproduced namespace loss when Word markup
compatibility hides a `Choice` or `Fallback` wrapper. The final repair also
preserves declarations from those projected wrappers, sibling scope restoration,
default namespace unbindings and QName-valued attribute context. The
[before/after receipt](evidence/xml-projection-summary.json) records the defect
and the corrected round trip.

An existing tab-stop test had expected a valid namespace-shadowed section to
fail because of the old capture defect. It now checks successful editing,
foreign metadata preservation and atomic rollback; a separate genuinely foreign
paragraph-property snapshot still exercises the rejection boundary.

An intermediate broad run is retained for audit, **not used as acceptance**:
[summary](evidence/intermediate-summary.json). It reported 5,253 passes and four
failures: the stale tab-stop expectation and three newly added XML projection
cases running against a previously loaded implementation. Its manifest detected
source changes during the run. After completing the fixes and freezing the
source, the fresh final run passed all 5,258 cases with no source changes.

## Reproduce and review

With Flutter 3.47.8 / Dart 3.13.7 on `PATH` and the locked workspace dependencies
resolved, run from the repository root:

```sh
python docs/validation/word-vba-text-columns-20261121/run_local.py ../word-text-columns-results
```

The runner writes source hashes, complete command arguments, analysis and test
logs, compressed logs and a machine-readable summary. It exits unsuccessfully
if a command fails or source inputs change during the run. The portable and
native-oracle receipts contain their commands and input hashes; the complete BAS
SHA-256 is
`0abed44bdc0f5d71eac1fee6d4ec9b868a4860c27944d386f6942658a247b7b9`.

[The evidence manifest](evidence-manifest.json) lists retained receipts and
compressed logs with SHA-256 values. Native macOS/iOS builds and installed
Microsoft Office were not executed. The local results qualify this bounded
implementation and its exercised integration paths, not full VBA parity.
