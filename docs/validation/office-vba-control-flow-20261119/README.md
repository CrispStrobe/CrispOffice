# VBA conditional control flow — local qualification

Date: 19 November 2026. GitHub Actions were not awaited or rerun.

Raw process logs are retained byte-for-byte for their recorded hashes. The
directory's Git attributes exempt those logs from whitespace cleanup; source
and documentation whitespace checks remain enabled.

This increment adds conditional loops and ordered `Select Case` selection to
the explicitly invoked `vba-excel` source compiler. Its output is still a finite,
inspectable native macro plan. Source evaluation has no access to workbook
values, and the existing runtime applies permissions and atomic publication.

## Implemented behavior

- `Do While` / `Do Until`, posttested `Loop While` / `Loop Until`, unconditional
  `Do` / `Loop`, and `While` / `Wend`.
- `Exit Do` leaves the nearest enclosing `Do` in the current procedure. Both
  `Exit Do` and `Exit For` pass through intervening block and loop kinds until
  reaching their owning loop. Procedure returns and exits restore `With` scopes.
- `Select Case` evaluates the selector once, checks clauses and comma-separated
  alternatives in order, and executes only the first matching body. It supports
  values, inclusive numeric/string ranges, all six relational comparisons with
  optional `Is`, and an optional final `Case Else`.
- Both endpoints of a reached range are evaluated. Later alternatives are
  skipped after a match. Scalar types remain strict; Boolean ranges are outside
  this dialect.
- All conditions, clauses and bodies are checked statically, including inactive
  paths and unused procedures. New constructs share existing work, statement,
  block, expression, call, operation and output-byte budgets.

The [dialect guide](../../VBA_MACROS.md) specifies the complete contract and
compatibility limits. The [control-flow report](../../../packages/quds_office_engine/example/macros/control_flow_report.bas)
uses six rows of synthetic source data, emits **35 native operations**, and
calculates **1,575** through a worksheet formula. It requires a `Summary` sheet.

## Qualified results

| Check | Result | Evidence |
| --- | --- | --- |
| Focused macro and existing command regressions | **427 distinct tests passed** | [Initial run](engine-initial/receipt.json), [final corrections and binding](engine-final/evidence-binding.json) |
| New control-flow coverage | **35 compiler tests, 42 independent boundary tests, 9 integration tests** | The three `office_vba_control_flow*` suites in the workflow |
| Whole engine analysis | `dart analyze --fatal-infos` passed | [Final analysis log](engine-final/analysis.stdout.log) |
| JavaScript portability | All **four** macro programs compiled and ran under Node | [Initial receipt](engine-initial/receipt.json), [corrected control-flow program](engine-final/receipt.json) |
| Incoming engine branding changes | **249 tests passed** across nine targeted suites | [Branding receipt](incoming-branding/receipt.json) |
| Incoming mail implementation and local quota fix | **469 VM tests passed**; strict analysis and formatting passed | [Mail receipt](incoming-mail/receipt.json) |
| Portable exact-byte mail manifest cases | **6 Node tests passed**, also counted within the VM suite | [Mail summary](incoming-mail/README.md) |
| Formatting and whitespace | Passed; 15 macro Dart files required no formatting changes | [Final receipt](engine-final/receipt.json) |
| Stable inputs | All **970** macro/configuration inputs and **84** mail inputs remained unchanged within their final runs | Receipts above |
| Published content binding | **1,048 distinct repository input hashes** match the published implementation checkpoint | [Binding](implementation-binding.json) |
| Incoming macOS build script | Linux `bash -n` syntax check passed | [Scope and script hash](macos-build-script-syntax.json) |

The initial frozen run passed all 427 macro tests and all four JavaScript
programs. Analysis and formatting then identified two style corrections: braces
around a smoke-program failure check and the layout of one integration-test
call. The final run repeated the nine affected integration tests, the changed
JavaScript program, whole-engine analysis, formatting and whitespace. The
[binding](engine-final/evidence-binding.json) verifies that the other **968**
inputs did not change, retaining the 418 other tests and three other JavaScript
programs. Repeat runs are not added to the distinct test totals. Production
compiler source was unchanged between these runs.

Tests exercised actual BAS CLI subprocesses, custom entry selection, saved native
JSON playback, MCP compile/validate/run, host read-only/allowlist/step policies,
and exact-byte rollback after a later selected case targeted a missing worksheet.
Existing input and output files remained intact on compilation and runtime
failure. Infinite empty loops stopped with structured budget diagnostics.

## Independent depth review and correction

Independent review exposed a fresh-process JavaScript stack overflow when valid
per-axis limits were combined. A lower-depth warmup could mask the failure.
The evaluator now uses explicit body, loop and `With` continuation frames
instead of recursively executing nested blocks. This retains the published
limits, `For` initialization/increment behavior, matching-loop exits, and scope
cleanup on returns and errors.

Both independent probes passed on Dart VM and fresh Node processes at **32
procedure frames × 32 mixed blocks × 50 or 63 unary operators**. The latter
reaches the existing 64-node expression-depth boundary. Each probe performs
174 checks; these are separate probes and are not added to the test-suite count.
The committed JavaScript smoke program runs the maximum-depth scenario before
warming up the evaluator.

See the [review explanation](independent-review/README.md),
[final hashes and commands](independent-review/fixed-review.json), and retained
pre-fix evidence in that directory.

## Incoming mail correction

The integrated export implementation rejected a valid 348-byte manifest when
its configured byte limit was exactly 348. Conservative header/item estimates
could fail before the exact final check. The correction counts the actual UTF-8
JSON envelope, origins, items and separators incrementally, while retaining
pre-allocation bounds and rejection of actual overflow.

Seven regressions cover empty/single/multiple originals, Unicode and escaped
text, exact limits, one-byte-under limits, and the database `planExport` path.
The incoming decoder preflight and this encoding correction were retained
together. Export ordering was also corrected for strict analysis. The later
mail branch independently published the same ordering correction.

## Source and remote reconciliation

The initial fetch retrieved all **23** fork branches and every PR head. All
four advertised upstream branch heads were already ancestors of initial main
`304d4bff45da24f22cee420ec464882d7c7ce516`. Older divergent ODS/ODT branches were
checked against their merged equivalents; they were not blindly reapplied.
The macro branch makes the final recorded fork branch count **24**.

| Incoming work | Incorporated head | Treatment |
| --- | --- | --- |
| Existing VBA procedures, PR #204 | `304d4bff45da24f22cee420ec464882d7c7ce516` | Starting main |
| macOS bundle script and explicit native gate | `d5abf0e09d9fef6a29821f412f791c1284d62be8` | History and implementation retained |
| Mail portability, PR #205 | `9bdef4895922ae74f6275e421af5665552d18b4e` | Source, Studio wiring and bounded decoder retained; mail store independently qualified |
| Studio GUI, PR #206 | `6c10cc30e61f4fd1333b0a385989cf6b3cdf1788` | Ribbon/menu/branding and later lifecycle/PDF-save-state checkpoint retained |

The final GUI tip changes 19 editor paths and no engine or mail source. It also
contains an earlier macro checkpoint through ancestry; merging it retained the
newer stack-safe evaluator and final tests. GUI and mail PRs were still drafts
in the [recorded frontier](final-frontier.json); this task did not manually
close them or claim completion of their authors' continuing work.

The initial and subsequent audit JSON files in this directory preserve exact
branch/PR heads, comparison results, prior merge equivalents and snapshot times.

## Incremental remote checkpoints

Branch: `codex/vba-control-flow-20261119`.

| Commit | Saved state |
| --- | --- |
| `4df40458` | Initial current-main, macOS and mail reconciliation |
| `7aa6ebbc` | Compiler extension, 85 initial new tests, example and mail quota correction |
| `176530fa` | Refreshed GUI/mail snapshots, guide and workflow integration |
| `6fd1f976` | Stack-safe evaluator and cold maximum-depth regression |
| `ab253c35` | Final smoke lint, integration formatting and changelog |
| `8005b04b` | Latest GUI lifecycle/PDF checkpoint, preserving accepted engine/mail content |

`implementation-binding.json` binds the published code to the accepted source
hashes, including publication after acceptance started from a staged checkpoint.
Validation evidence is saved in subsequent commits on the same branch.

## Environment and reproduction

The official Dart **3.13.7** archive matches SHA-256
`eb99aed266efbcb615c6ae21c12f52cfe935b9f208bccc5fea7f64c21e867229`, matching the
repository's Flutter **3.47.8** pin. Engine and mail checks used reduced,
source-linked workspaces without editing tracked dependency manifests or
lockfiles. Environment and resolved dependency records accompany the receipts.
The mail suite used the unchanged sqlite3 3.9.1 default native hook.

With repository dependencies resolved using the pinned SDK:

```bash
cd packages/quds_office_engine
dart test test/office_vba_control_flow_test.dart \
  test/office_vba_control_flow_boundaries_test.dart \
  test/office_vba_control_flow_integration_test.dart
dart analyze --fatal-infos
mkdir -p build/macros
dart compile js -O1 tool/macros/web_vba_control_flow_smoke.dart \
  -o build/macros/web_vba_control_flow_smoke.js
node -e 'globalThis.self = globalThis; require("./build/macros/web_vba_control_flow_smoke.js")'
```

The full macro selection and four JavaScript programs are in
`.github/workflows/office-macros.yml`. No queued Actions run was used as a gate.

## Qualification limits

These receipts qualify the engine macro path, targeted incoming engine changes,
Linux mail storage/export behavior, and portable JavaScript paths. A separate
targeted Flutter qualification of the final GUI snapshot is in progress at this
checkpoint and will be recorded before merge. Native macOS bundle building,
AppKit execution, the full repository suite, and native Microsoft Office
interoperability are outside these checks. The existing explicit macOS gate is
preserved for execution on a macOS host.

Live workbook reads, `ByRef`, optional/named arguments, arrays, recursion,
cross-module calls, COM/events, and full VBA compatibility remain unsupported.
Embedded VBA projects remain inert and preserved.
