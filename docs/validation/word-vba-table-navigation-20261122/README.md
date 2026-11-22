# Word table navigation continuation

## Intake

Work began from remote main `5d18df8dccaed89fd42720bb63dae09ae83d90ae`.
The [captured intake](intake.json) independently checked all 34 retained fork
branch heads and all four upstream branch heads as ancestors of that commit.
The explicit open-PR query returned no results; the 100 most recent PRs were
already merged. No intake merge was necessary. GitHub Actions are not a gate
for this continuation.

Remote main subsequently advanced to
`bbc4f82c7562e1004c59804b30a5baafcf53e4d1` through documentation-only PR #375.
The working branch preserved that history in merge checkpoint
`87171f31d8b9419d67d6b6c373ae9119db707ce0`. Its three incoming files are Mail
qualification records; no production or test input changed.

The [pre-publication intake](final-intake.json) verifies all original fork and
upstream heads remain contained and records a new concurrent branch,
`codex/zotero-workflow-parity-20261122` at
`e3f6b4e74241f805531156e0f1308041813c4f70`. That branch appeared after initial
intake and already includes Word checkpoint
`4eca268cfaab0a765816cd4f0bbadd7b414bfa30`. Its unique work changes two Zotero
engine files and adds engine/Flutter controller tests; it has an intake record
but no completed qualification receipt or ready PR at the observed head.
It remains preserved on its own remote branch for its concurrent workstream.
This Word publication includes all initial intake and current main, and does
not claim to qualify that newer Zotero implementation.

The open-PR query was empty. Remote checkpoints use non-forced expected-head
updates and retain ordinary Git ancestry. Publication uses an immediate merge,
without an Actions wait or changes to repository rules.

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
| Broad VBA and native macro regression suite, 149 selected files | **7,628 tests passed; zero failures** |
| New compiler and independent conformance suites | 185 tests passed |
| Independent DOCX/DOCM integration suite | 16 tests passed |
| Complete-example CLI and portable wrapper suite | 4 tests passed |
| Existing cell selector, alias-graph and suffix conformance regressions | 225 tests passed |
| Strict analysis of all seven changed/new Dart files | No issues |
| Formatting of those Dart files | No changes required |
| Independent 32-case corpus on VM and dart2js/Node | Passed; canonical results identical |
| Actual 10-operation BAS on VM and dart2js/Node | Passed; structured receipts identical |

Targeted counts overlap with the broad total; they are not a VBA compatibility
percentage. The [final qualification receipt](qualification.json) and
[complete broad-run command/results](evidence/macro-regression.json) record
the executed scope. The compiler hash is unchanged from the start of the
broad run, and all nine source/example/fixture/test input hashes still match
the source manifest after completion. Subsequent integration touched only
the recorded documentation files.

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

## Reproduce

In a normally provisioned and dependency-resolved repository workspace, the
focused tests are:

```sh
cd packages/quds_office_engine
dart test test/office_vba_word_table_navigation*_test.dart -r expanded
```

The receipts retain the exact commands used in this isolated runtime, including
the full 149-file test selection and the unchanged corpus/BAS bytes supplied
to both portable hosts. No GitHub Actions result is used as acceptance evidence.
