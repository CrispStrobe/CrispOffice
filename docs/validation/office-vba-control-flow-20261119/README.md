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
| Later default-comment initials change | **67 existing tests repeated and passed**; whole-engine analysis passed | [Late engine receipt](late-incoming-engine/receipt.json), [exact one-line binding](late-incoming-engine/evidence-binding.json) |
| Incoming mail implementation and local quota fix | **469 VM tests passed**; strict analysis and formatting passed | [Mail receipt](incoming-mail/receipt.json) |
| Portable exact-byte mail manifest cases | **6 Node tests passed**, also counted within the VM suite | [Mail summary](incoming-mail/README.md) |
| Incoming Studio, PDF and directory-import behavior | **148 distinct tests passed**; one opt-in screenshot generator skipped | [GUI receipt](incoming-gui/README.md), [final publication binding](incoming-gui/publication-followup/source-binding.json) |
| Formatting and whitespace | Passed; 15 macro Dart files required no formatting changes | [Final receipt](engine-final/receipt.json) |
| Stable inputs | All **970** macro/configuration inputs and **84** mail inputs remained unchanged within their final runs | Receipts above |
| Published content binding | **5,192 distinct repository inputs** match the final published code tree, including the 1,048 engine/mail inputs | [Final publication binding](publication-binding.json), [engine/mail binding](implementation-binding.json) |
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

The final incoming GUI snapshot also changes the engine's default new-comment
initials from `QO` to `CO`. The late engine qualification repeated the 67 affected
existing tests and whole-engine analysis. Its binding verifies that this is the
only change among the 970 recorded inputs; the other 969, including the compiler
and all JavaScript smoke sources, are identical. These repeated tests do not
increase the 427 distinct macro/command total.

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

The subsequent mail publication from source `9bdef489` to `82b20dc8` adds only
151 documentation, changelog and evidence paths. Its retained author evidence
was independently audited: all 130 artifact hashes and lengths, 4,418 source
hashes, and ten raw test-reporter cohorts agree with the recorded results.
The author's **1,750 passing tests**, including 405 shared/Studio Mail UI tests,
are supporting evidence at that accepted source. They are not tests executed
again by this task and are not added to our local totals. The audit does not
claim access to the author's original runtime or dependency installations.
Current shared Mail UI and `studio_mail*` product files are unchanged; the
current Studio shell is covered by the separate Flutter qualification.
The [audit](mail-publication-audit.json) and its
[reproducible checker](mail-publication-audit.py) are retained.

## Incoming Flutter qualification

The incoming Studio and PDF changes are exercised with the pinned Flutter
3.47.8 SDK in an isolated copy of the repository packages. Dependency resolution
does not edit the tracked repository manifests or lockfiles.

The combined Studio selection passed 114 tests across 12 suites, and the PDF
save-state suite passed four tests. The final runs preserved all 5,188 recorded
source-input hashes. Product and test copies match the repository; the isolated
root lockfile is explicitly recorded as dependency-resolution metadata.

The author's final publication retains these product sources and adds an
earlier window-show assertion, settles the worksheet-test timing, isolates its
unused proofreader, and canonicalizes the directory-import fixture's system
temporary path. Strict analysis of the three changed tests passed. The final
targeted follow-up passed 12 repeated GUI cases and **30 additional unique
directory-import cases**, with no failures or skips. Their source hashes and
isolated copies remained identical. Thus the distinct local UI total is **148**;
the 12 repeated cases are not added again.

The first widget runs exposed incomplete or stale test fixtures. The macOS
window-manager mock returned `null` for `isMinimized`, where the plugin requires
a Boolean, so it failed before reaching the deliberately delayed `show` call.
The corrected mock returns `false`; the delayed show/focus and modal-action
assertions remain. The localized Mail switcher and compact File commands now
use their tooltips. The worksheet reset cases explicitly confirm the new
unsaved-changes dialog, assert that the old workbook survives until discard,
and retain the original reset assertions. These corrections change tests only.

The optional screenshot generator is skipped when `QUDS_SHOTS_DIR` is unset;
it is not a skipped behavioral check. Native macOS/AppKit execution remains
outside a Linux widget run, even when `TargetPlatform.macOS` is simulated.

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
| Mail portability, PR #205 | `82b20dc8b52d0b95efeff590c6023ed84704fa7a` | Accepted source `9bdef489`, final publication and author evidence retained; our mail store qualification and quota correction remain |
| Updated remote main after PR #205 | `0c29b5d8a0a92148dcd95f3282b4d43c462be20d` | Merged into this branch before final publication |
| Studio GUI, PR #206 | `f489cefe48e6fd4b0dcbada8fc4025682733a118` | Ribbon/menu/branding, lifecycle, PDF save state, keyboard/outside-click behavior and default comment initials retained |
| Final GUI publication, PR #206 | `bba11ff1b23b2e8c0cdc0d872ce31394ada83bf2` | Author's final evidence and equivalent or stronger test fixtures retained; no additional product source changes |
| MacBook import-fixture integration, PR #208 | `de9d21f9014060c14263ce17fe323d5fdb063d11` | Canonical system temporary path retained and directory-import suite qualified |
| Final refreshed main after PRs #208 and #206 | `0d87cebea232c3edf55c4f4a22f63684dbe5a3f5` | Same complete tree as our qualified `dde14aa6` checkpoint; ancestry incorporated before final evidence publication |

The first GUI refresh at `6c10cc30` changed 19 editor paths. The later genuine
changes are `92941ac1` (keyboard/outside-click handling, native dialog and window
guards, preference flushing, tests and previews) and `f489cefe` (default comment
initials). Its intervening merge commits also absorb earlier macro checkpoints;
our integration retained the newer stack-safe evaluator and final tests.

The earlier [frontier](final-frontier.json) is retained as a historical snapshot.
At the later publication audit, PR #205 was merged and PR #206 remained a draft
at the frozen `f489cefe` product head. Its subsequent ready publication added
tests, documentation and acceptance evidence only. That publication was also
incorporated, keeping the qualified product sources unchanged. The main merge
required a changelog conflict resolution preserving both the GUI and mail entries;
the final publication required a test-timing conflict resolution retaining the
author's strengthened worksheet assertions. No product source conflict was
discarded. This task did not manually close the GUI PR.

The final refresh found PR #208 merged at `bcb061e1` and PR #206 merged at
`0d87cebe`. That main tree is **exactly identical** to the qualified `dde14aa6`
tree. Its merge ancestry was incorporated without changing product or test
inputs. The [final binding](publication-binding.json) verifies all 5,192 distinct
accepted repository files against both their SHA-256 receipts and the published
Git blobs, and records every incorporated head. It also verifies 59 referenced
evidence-file hashes. No further test rerun is needed for an identical tree.

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
| `ca536ee0` | Macro, mail, branding and independent review receipts, logs and hashes |
| `bba77ddc` | Updated main with merged mail publication and final frozen GUI snapshot |
| `bc32a144` | Native-window mock, compact command locators and explicit discard/reset fixture corrections |
| `dde14aa6` | Final GUI author publication and accepted fixtures, with no product source changes |

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
Linux mail storage/export behavior, portable JavaScript paths, and targeted
Studio/PDF/directory-import behavior through Flutter widget tests. Native macOS
bundle building, AppKit execution, the full repository suite, and native
Microsoft Office interoperability are outside these checks. The existing
explicit macOS gate is preserved for execution on a macOS host.

Live workbook reads, `ByRef`, optional/named arguments, arrays, recursion,
cross-module calls, COM/events, and full VBA compatibility remain unsupported.
Embedded VBA projects remain inert and preserved.
