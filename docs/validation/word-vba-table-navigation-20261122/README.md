# Word table navigation continuation

## Intake

Work began from remote main `5d18df8dccaed89fd42720bb63dae09ae83d90ae`.
The [captured intake](intake.json) independently checked all 34 retained fork
branch heads and all four upstream branch heads as ancestors of that commit.
The explicit open-PR query returned no results; the 100 most recent PRs were
already merged. No intake merge was necessary. GitHub Actions are not a gate
for this continuation.

## Implemented scope

The bounded Word source adapter now supports typed `Rows`, `Row`, `Columns`,
`Column` and `Cells` selectors. An explicitly selected row or column supplies
its cells, which lower to the existing guarded table-cell operations. Required
named `Index` arguments and `Table.Cell(Row:=, Column:=)` support conventional
Word VBA template code without document reads during compilation.

Whole-table `Cells`, collection enumeration/counts, whole-row/column ranges,
merged-cell geometry and live property reads remain separate capabilities.

## Local qualification

The initial implementation was saved remotely as
`d1935ba19caa6b0aaead23198170ed3acefa58ea`. The
[source manifest](evidence/source-manifest.json) identifies the compiler,
example, corpus and tests used for the complete authored increment, including
the subsequent CLI/portable additions and final corpus provenance.

Executed targeted checks:

| Check | Result |
| --- | --- |
| New compiler and independent conformance suites | 185 tests passed |
| Independent DOCX/DOCM integration suite | 16 tests passed |
| Complete-example CLI and portable wrapper suite | 4 tests passed |
| Existing cell selector, alias-graph and suffix conformance regressions | 225 tests passed |
| Strict analysis of all seven changed/new Dart files | No issues |
| Formatting of those Dart files | No changes required |
| Independent 32-case corpus on VM and dart2js/Node | Passed; canonical results identical |
| Actual 10-operation BAS on VM and dart2js/Node | Passed; structured receipts identical |

Counts overlap with the broader macro regression suite; they are not a VBA
compatibility percentage. The broader source suite and final integration
receipt are recorded separately when complete.

The native tests cover exact row/column routing, retained selectors, helper
rebinding, nested `With`, independent body/header/cell targets, validation
without mutation, DOCX/DOCM save/reopen, opaque VBA and untouched package
preservation, policy enforcement, recording/replay and whole-run rollback.
CLI tests run the checked-in BAS and preserve prior output/plan files after
late native failures or malformed named selectors. The portable smoke also
exercises actual MCP compile, validate and run calls.

The runtime is official Dart 3.14.1 with its published archive checksum
verified, plus Node v24.22.3. An isolated pure-engine dependency workspace uses
56 package entries exactly matching the repository lock and maps package
resolution to the real checkout sources. Tracked manifests and lock files
were unchanged. See [runtime provenance](evidence/runtime-provenance.json),
[SDK provenance](evidence/sdk-provenance.json),
[CLI/portable results](evidence/table-navigation-verification.json),
[portable commands](evidence/table-navigation-portable-commands.json),
[corpus commands/results](evidence/navigation-conformance-verification.json)
and the [compressed log manifest](evidence/log-manifest.json).

This qualifies the engine/compiler and its portable native transaction. The
canonical pinned Flutter 3.47.8 workspace, Flutter editor UI and an installed
Microsoft Word host were not executed. Microsoft API-derived expectations and
the explicit Quds dialect limits remain distinct in the corpus. No embedded
VBA execution, document reads, collection enumeration or merged-cell expansion
is claimed.
