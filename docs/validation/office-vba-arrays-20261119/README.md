# VBA fixed arrays and For Each — local qualification

19 November 2026. GitHub Actions were not queried, awaited, or rerun.

This increment extends the explicitly invoked `vba-excel` compiler with bounded
source data tables and cell-range enumeration. Its result remains an immutable
native macro plan executed through the existing host permissions and atomic
publication path. Source expressions still have no live workbook-value access.

## Implemented behavior

- Fixed one-dimensional local arrays of `Long`, `Double`, `String`, `Boolean`,
  or scalar `Variant`. Explicit bounds are inclusive; omitted lower bounds are
  zero. Bounds may use previously declared constants and are checked in unused
  procedures as well as the selected entry.
- Strict indexed reads/writes and optional `Let`; typed element defaults and
  explicit rejection of uninitialized Variant element reads.
- `LBound` and `UBound`, with optional dimension 1 and structured
  `vba_subscript_out_of_range` diagnostics.
- `For Each` over local arrays with Variant controls, and explicit rectangular
  ranges with Range controls. Arrays read each slot at its iteration; changing
  the control variable does not write back. Ranges capture their source once
  and enumerate cells left-to-right, then top-to-bottom.
- Read-only `Range.Row` and `.Column` source coordinates. These expose explicit
  binding metadata without reading a workbook.
- Matching `Next`, mixed-loop `Exit For`/`Exit Do`, nested `With` restoration,
  procedure isolation, and full-module checking retained.

Arrays allow at most **4,096 elements each**, **16,384 slots across active
procedure frames**, and **1,048,576 UTF-16 code units of strings across active
array slots**. Each occupied slot contributes its string length even if another
slot references an equal string. Replacing a slot or returning from a procedure
releases its contribution. Allocation, bounds evaluation, indexing, and
iteration share the existing 100,000-visit work budget. All earlier operation,
source, expression, call, and encoded-plan limits remain in effect.

See the [complete dialect contract](../../VBA_MACROS.md) and the runnable
[array report](../../../packages/quds_office_engine/example/macros/array_report.bas).
The report creates four synthetic item rows in `Summary`, emits **24 native
operations**, and produces matching source and worksheet totals of **850**.

## Macro acceptance

The final combined implementation was accepted at
`61bb3ee42a385c5ffaffa44047693a6f378a8424` using Dart **3.13.7**. The repository
Flutter pin is **3.47.8**. The SDK archives and locked package setup are recorded
under [runtime](runtime/setup.json).

| Check | Result | Evidence |
| --- | --- | --- |
| Exact macro/command selection from the workflow | **614 distinct tests passed**, zero failures or skips | [Final receipt](engine-publication/receipt.json), [reporter summary](engine-publication/test-summary.json) |
| New macro coverage within that total | **32 core + 144 independent boundary + 11 integration tests** | The three `office_vba_arrays*` suites |
| Existing tests within that total | **427** | Final workflow selection and reporter summary |
| Whole-engine strict analysis | Passed | [Analysis](engine-publication/engine-analysis.json) |
| JavaScript portability | All **five** programs compiled at `-O1` and executed in fresh Node processes | Final receipt and `*-assertions.json` files |
| Formatting and scoped whitespace | Passed | Final receipt |
| Source stability during final acceptance | **All 856 repository inputs unchanged**; no dependency input changes | Final receipt and before/after manifests |

The JavaScript array smoke starts cold at **32 active procedure frames × 32
nested For Each blocks × 63 unary operators**, then exercises mixed block
nesting. The smoke verifies real assertion receipts; merely exiting a Node
process is not treated as execution evidence. The wrapper supplies
`globalThis.self = globalThis` before loading the compiled program.

The integration suite executes actual BAS CLI subprocesses, custom entry
selection, saved native plan playback, MCP compile/validate/run, policy
rejections, and late-failure rollback. Existing input, output, and saved-plan
files remain intact on the relevant failure paths.

Repeated development and confirmation runs are excluded from the 614 total.
The original 612-test run is retained under [engine](engine/receipt.json).
The first corrected 614-case run at `c3eaf57c` remains under `engine-final`;
`engine-publication` is the fresh complete 614-case run after the later PPTX
parser correction. All five JavaScript programs and whole-engine strict
analysis were rerun against that final source as well.

## Review corrections

### Preserve bare helper-call grammar

An isolated comparison with the exact pre-change compiler showed that
`Helper (1) = 2` is a bare call with a Boolean comparison argument. The initial
array parser mistook that token sequence for an indexed assignment. The parser
now applies that lookahead only to names declared as arrays in the current
procedure. Baseline and corrected implementations emit the same `False` value.
Two regression tests cover the prior helper grammar and nested parentheses in
array assignment subscripts.

The [comparison proof](independent-review/parser-compatibility/), original
failure, corrected result, reproducible probe, exact Git blob identities, and
two-file correction binding are retained. Only the compiler and core test file
changed between the original 612-case run and the first corrected 614-case
run; the other 854 recorded inputs were identical.

### Bound retained array strings

A slot-count limit alone allowed many long strings to remain in arrays. The
added aggregate UTF-16 occupancy limit is checked before replacement, spans
active calls, and releases storage accounting on overwrite and return.
Independent cases cover the exact boundary, one-unit overflow, surrogate pairs,
String and Variant slots, and nested procedure accounting.

### Independent boundary expectation

The independent suite initially expected an empty `For Each` body to skip an
uninitialized Variant element. Binding the control variable itself reads that
slot, so the existing unsupported-Empty diagnostic is correct. The fixture was
corrected, and a positive case verifies an early `Exit For` avoids later
uninitialized slots. No compiler change was made for that expectation. The
original failure and corrected 144-case result remain in
[independent-review](independent-review/README.md).

## Incoming work and reconciliation

The initial audit captured **14 fork branches**, fetched every advertised PR
head, and checked all four upstream branches. The upstream heads were already
ancestors of the handoff main `cf59efa9`. Seven historical divergent feature
heads match their accepted merged file blobs; two older docs heads are already
subsumed. No unique historical work was discarded. See
[the initial audit](remote-initial/audit.json).

The final source checkpoint is
`61bb3ee42a385c5ffaffa44047693a6f378a8424`. It retains mail restore PR **#209**,
merged on remote `main` at `caf378f40fd5bda50f504a6816404d01d8bbb8f8`, and
GUI PR **#211** through `8c6acd04637ef627959fe40f518254ed538ab087`.
The prior integration checkpoint `596430dc` explicitly parented the then-current
main and GUI heads. The final checkpoint has direct parents `f6b8638d`, GUI
`8c6acd04`, and the new mail-planning head `9d6cd050` from PR **#212**. That
last head adds only two planning/reconciliation documents; no durable-resume
runtime feature is claimed. All integrations were conflict-free.

The GUI work adds page-layout APIs, theme and document rendering improvements,
Studio page-layout and paragraph dialogs, File-menu document modes, slide and
sheet choices, dark slide rendering, readable themed tabs, and correct active
header/footer paragraph settings. The late mail changes after
`0c77b3488eb534868a7f98271ba2923d06759b8d` affect validation artifacts only.
See [the remote refresh](pre-acceptance-frontier.json),
[the initial incoming review](final-review/latest-frontier/), and
[the final source audit](final-review/publication-source/README.md).

| Incoming qualification | Result | Evidence |
| --- | --- | --- |
| Mail store full VM selection | **508 distinct tests passed** | [Mail receipt](incoming-mail/receipt.json) |
| Mail core/store strict analysis | Passed | [Mail review](incoming-mail/README.md) |
| Initial mail Studio restore, native MIME, and layout checks | **18 distinct tests passed** | [Studio receipt](incoming-studio/receipt.json) |
| First expanded page-layout/theme attempt | **212/213 editor**, **115/115 Studio GUI**, **18/18 repeated mail**; strict editor analysis passed; one Studio lint | [Retained expanded attempt](incoming-layout-theme-final/receipt.json) |
| Corrected combined GUI acceptance | **213 editor + 116 Studio GUI + 18 repeated mail passed**, zero failures or skips; both strict analyses passed | [Accepted receipt](incoming-layout-theme-accepted/receipt.json) |

The accepted combined GUI run recorded **2,495 unchanged inputs**, and all **20**
copied workspace manifests matched the repository. The selected final editor
cohort contains ten suites; Studio GUI contains eleven suites, plus the three
repeated mail UI suites.

The initial mail qualification recorded 168 stable inputs. Its 85 unchanged
runtime/test package inputs remain bound; the subsequent README and CHANGELOG
changes are explicitly documentation-only. No mail-author test claim is added
to these executed counts.

The initial Studio run used a byte-verified frozen engine library while the
macro parser correction was proceeding. The later GUI acceptance repeats those
same 18 tests on the combined current source, so they are counted only once.
The first broader editor sweep reproduced eight missing-Overlay fixture
failures. Two representative cases also fail against the pre-GUI source with
the identical historical test file. Their baseline evidence is retained under
[incoming-layout-theme/baseline](incoming-layout-theme/baseline/).

The correction supplies a standard `MaterialApp` host to eight historical
fixtures and explicitly unmounts and disposes seven externally owned Word
controllers after their assertions. The host owns the eighth controller. All
510 `expect`/`expectLater` expressions remain byte-identical and in the same
order, and default review/proofing behavior remains enabled. The focused eight
cases pass. Original failures, intermediate probes, and the assertion-preservation
proof remain in [the retained diagnostic record](incoming-layout-theme/README.md).
The first expanded GUI qualification is recorded separately in
`incoming-layout-theme-final/`; all 2,495 recorded inputs were stable. It found
one new raster assertion failure and one strict-analysis info. The table's
13-point black text on white was rendered correctly and identically with color
adaptation enabled or disabled, but antialiasing left only three pixels within
three RGB units of fully opaque black. The retained diagnostic records the
pixel distribution and a wrong-color control. The other issue was an incoming
multiline `if` without braces in the Studio measurement-unit callback. Its
correction preserves the guard and assignment. The accepted rerun is recorded
separately under `incoming-layout-theme-accepted/`.

Once the pixel gate was corrected, the unchanged export assertion exposed a
DrawingML parser defect: a table run's pending text color was assigned to its
enclosing shape. The narrow correction assigns the active cell's first
representative text color, preserving cell fills and ordinary shape behavior.
Two new engine regressions cover RGB/theme/automatic colors, later runs,
neighboring shape isolation, and three consecutive save/reopen cycles. They
both fail against the exact old parser and pass with the fix; all **33** cases
across the selected slide, import-fidelity, and text-fidelity suites pass.
See [the source-bound before/after proof](independent-review/slide-table-color/README.md)
and [the independent six-case GUI follow-up](final-review/dark-slide-corrected/README.md).

The parser and its regression test are the only two changed inputs relative
to the earlier `engine-final` macro receipt. The complete `engine-publication`
rerun binds all 856 inputs at the final source checkpoint.

## Publication verification

The [publication binding](publication-binding.md) independently reparses the raw
reporters, checks artifact hashes against published Git blobs, verifies source
and dependency stability, compares each accepted repository input with its Git
blob, and deduplicates cases by repository test file and full test name. It
confirms **1,502 distinct selected cases passed**, with zero failures or skips,
**287 published artifact files** across eight manifests, and **2,792 distinct
accepted repository inputs** matching working bytes and published Git blobs.
Historical failures remain retained and are excluded from the accepted total.

The final source audit confirms the observed GUI and mail-planning paths are
preserved, remote main is an ancestor, no tracked dependencies changed, and no
files were deleted. Subsequent top-level README and engine CHANGELOG updates
are documentation-only and outside the qualified source-input sets. The
[checkpoint record](final-source-checkpoint.json) identifies the exact accepted
source; later evidence commits retain that runtime/test source unchanged.

## Reproduction and limits

[run-local-validation.py](run-local-validation.py) derives its 24 test files
and five JavaScript programs from the committed workflow, records exact
commands and raw logs, and rejects source/dependency drift. Each incoming
qualification also includes its runner. The copied dependency workspaces do
not modify the tracked repository manifests or lockfile. GitHub Actions are
not an acceptance dependency.

This is bounded source-to-plan compilation, not general VBA execution. Dynamic
or multidimensional arrays, whole-array passing or returns, ByRef, recursion,
COM/ActiveX, embedded VBA execution, and live workbook-value reads remain
unsupported. Embedded VBA projects remain opaque and preserved.

These checks qualify the selected Dart VM, Node, Linux Flutter widget/render,
and native SQLite paths. They do not represent a full repository test run,
native macOS/AppKit execution, or native Microsoft Office interoperability.
