# Dynamic VBA arrays — implementation and validation record

19 November 2026. Local qualification for a bounded VBA language increment,
with reconciliation of the fork's current PPTX, Zotero and mail work.
No GitHub Actions result is used as an acceptance or merge gate.

## Delivered scope

The existing `vba-excel` compiler now supports one-dimensional dynamic local
arrays of `Long`, `Double`, `String`, `Boolean` and scalar `Variant`, including
`ReDim`, `ReDim Preserve`, `Erase` and module `Option Base 0/1`. This extends
the existing fixed-array indexing, `LBound`/`UBound` and `For Each` behavior.

The implementation checks unallocated arrays, typed initialization,
preserve/shrink/regrow behavior, lower-bound restrictions, once-only bound
evaluation, enumeration locks and shared resource budgets. `Erase` resets a
fixed array and unallocates a dynamic array. Multiple targets execute in source
order. Each target is charged to the compilation work budget, including an
already unallocated target.

The source compiler still generates an immutable native spreadsheet plan.
It does not read existing workbook values or execute embedded VBA projects.
Word and PowerPoint native operations remain distinct from future VBA object
model adapters. The [dialect contract](../../VBA_MACROS.md) states the exact
supported syntax and refusals; the [roadmap](../../VBA_PARITY_ROADMAP.md) records
the ordered remaining milestones.

## Repository reconciliation

Starting remote main was `2170791c9250d72c9df31a065408365f9b50abaa`.
The [initial reconciliation](initial-reconciliation.json) accounts for all
16 fork branches and the latest 100 PR heads at the initial observation.
There were no open PRs then. All four upstream branch heads were already
ancestors of main. Historical equivalents were checked using changed-path Git
mode/type/blob equality and the ancestry of their accepted replacements.

The unique initial incoming source was `integrate/recent-pptx` at
`5c3f9d7fd4531dfac7c0e49fba1827c39e17caf6`. It was included before the VBA work.
The later PPTX tab-stop correction at
`a5ae56c8e3e7f950c37ef491b17b5c32fcd0e13d` was included through the captured
Zotero ancestry.

Concurrent work was first captured at 21:12:09 UTC:

- Zotero `780422316b4e37989e01ac871dd2956fbd2c8908`.
- Mail `658095574de89cf3d6f3dfc874fab7e5c479b47e`.

The final refresh found two newly opened PRs. Their exact heads were also
integrated, with real parent relationships and focused local qualification:

- [PR #218](https://github.com/CrispStrobe/quds_office_suite/pull/218), Zotero
  `400fffd04fcceee78959e4c38b4d1dbe89767c2b`. Its continuation adds validation
  and documentation; the accepted Zotero feature source is unchanged.
- [PR #217](https://github.com/CrispStrobe/quds_office_suite/pull/217), mail
  `a0f27b2f61d332ff834d4bda59dadccdad020021`. Its continuation extracts the
  immutable draft model, adds host/session/composer regressions and improves
  master-background resolution. These source changes receive fresh checks.

See [the final inventory](final-remote-inventory.json) and
[the checkpoint ledger](checkpoint-ledger.json). This is a finite source
snapshot; branch names are not used as a substitute for the recorded SHAs.
The final main update is conditional on its observed head and preserves all
accepted history without force-pushing.

## Concurrent main reconciliation

Before publication, main advanced to
`88513f04cfbdec210340f2d70a674cf3f23e31c0` through the Zotero merge. That
history is preserved in checkpoint
`6a7e0afaec7b597abf3a6ad5d43a8295fcce855a`, whose parents are the qualified
`435bc212` source and the new main head.

All 5,647 tracked entries outside `docs/` and the two package changelogs retain
identical Git modes, types and blob IDs from the tested source. All 24 new main
documentation/evidence files retain their exact incoming blobs; both changelog
entries are combined. The three incoming Dart diffs were independently parsed
and shown to have identical canonical syntax trees, so preserving the tested
formatting does not discard a behavior change. No product test rerun is
represented as necessary or performed for this documentation/history union.

See [the main reconciliation proof](main-reconciliation.json). The commit
containing this final record adds documentation and evidence only after that
reconciliation; the qualified executable and test source remains unchanged.

## Local qualification

Source checkpoint used for the final tests:
`435bc212401db13efa56483ac852e4bc25bcc5d2`, tree
`0a916bed8acace7078e031b76a690991ff323a0e`.

| Gate | Result | Actual source boundary |
| --- | --- | --- |
| Macro/command selection, 26 files | 675 distinct cases accepted; zero remaining failures or skips | `9dbba0f7`; original run and two exact isolated retries |
| Portable macro programs | 6 of 6 compiled at `-O1` and executed under Node; dynamic arrays completed 27 assertions | Same unchanged `9dbba0f7` input snapshot |
| Captured PPTX union | 105 cases passed: 68 engine and 37 editor | Inputs bound to `8356fb0a` |
| Captured mail union | 235 cases passed: 230 Studio and 5 provider boundary cases | Inputs bound to `8356fb0a` |
| Zotero | 341 cases passed: 127 engine and 214 editor; no retries | Inputs bound to `8356fb0a`; final Zotero source/tests unchanged |
| Final PR slide integration | 107 cases passed | Final product-source snapshot |
| Final PR mail integration | 254 cases passed | Final product-source snapshot |
| Final macro/native boundaries | 135 cases passed | Final product-source snapshot; affected native operations, runtime, MCP, steps, dynamic-array and Word/presentation CLI paths |
| Final portable boundary checks | Native spreadsheet and dynamic-array web programs passed; dynamic-array VM/JavaScript receipts agree on all 27 checks | Final product-source snapshot |
| Static checks | Whole-engine and affected editor/Studio strict analysis, formatting and whitespace checks passed | Recorded source hashes in each receipt |

These rows deliberately overlap. They are not summed into a repository-wide
unique test count, and the earlier 675-case run is not represented as a fresh
675-case run on the final union.

The final native-boundary selection covers the concrete serialization and
publication risks introduced by the incoming PML changes. All 34 automation
and sheet library files remain byte-identical to `9dbba0f7`. The complete
earlier language selection therefore retains its original source attribution;
the affected final boundaries receive their own fresh execution evidence.

### Runtime and commands

Qualification uses repository-pinned Flutter 3.47.8 (Dart 3.13.7), with Node
24.22.3 as the observed JavaScript runtime. The official Flutter archive SHA256 is
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a7f06a6e9cefe386fec8075865be93adfa`.
The runtime receipt records the framework revision, archive size, package
integrity checks and dependency restoration. No dependency versions were
upgraded for this task.

The committed workflow includes the new unit/integration suites and web
program. It is a reproducible selection, not evidence of an Actions run.
The archives below contain every actual command, working directory, exit
status and raw reporter log. Local Dart gates used the installed test runner
directly with an explicit package configuration; Flutter gates used `--no-pub`.

The new feature can be exercised from `packages/quds_office_engine` after
dependency resolution:

```bash
dart test test/office_vba_dynamic_arrays_test.dart \
  test/office_vba_dynamic_arrays_integration_test.dart \
  --concurrency 1 --timeout 4x
dart run tool/macros/office_macro.dart compile-vba \
  example/macros/dynamic_array_report.bas dynamic-array.qudsmacro.json
```

The committed example produces 24 native operations. Both the source total
and the worksheet formula total are 850; the value after `Erase` and
reallocation is zero. It uses synthetic source data and does not read existing
worksheet values.

### Attempts and corrections retained

The original 26-file macro run completed 673 cases successfully and timed out
in two actual CLI-process cases at their explicit two-minute limits. Both
exact cases passed isolated retries with concurrency one and timeout factor
`4x`. All 582 source/configuration inputs stayed unchanged through the original
run, retries and web programs. Timeout teardown cascades are retained in the
logs; this is not described as an uninterrupted clean run.

The earlier baseline also retained its original timeout attempts and isolated
retries. No unsupported network or package-resolution diagnosis is inferred
from an interrupted run that emitted no reporter events.

An initial post-union helper accidentally retained the original checkout as a
Python default working directory. Reporter URLs exposed that mismatch. The
attempt was interrupted and contributes zero qualifying cases. Its logs and
explicit exclusion record are preserved. The corrected final runner uses
explicit working directories and absolute test paths, checks package-root
resolution and verifies reporter source URLs before accepting results.

## Incoming-source review decisions

The initial incoming PPTX work exposed regressions in the original exact-color
dark-slide tests. Corrections restored native font/background defaults and
preserved rich-text scalar formatting edits without weakening those original
assertions. Engine and widget tests cover imported paragraph defaults, text
replacement, contrasting text on explicit slide backgrounds and saved XML.

The reconciled master-background model preserves explicit slide ownership,
master inheritance and direct background edits. Paint, hit testing and PDF
text layout retain the shared origin/tab-stop behavior. Detailed resolutions,
exact input hashes and the original-test identity proof are retained in the
slide review archives.

Mail checks exercise To/Cc/Bcc deduplication, visible MIME groups, separate
recipient envelopes, reply-all threading and uncertain-send recovery through
controlled native, EWS, Gmail, Microsoft365 and session handlers. No real mail
was sent. Zotero tests use fake transports and the Flutter test environment;
they do not represent a live Zotero account or desktop integration run.

## Evidence and limits

[qualification.json](qualification.json) is the machine-readable gate summary.
[evidence-index.json](evidence-index.json) records SHA256 and size for each
archive and every contained file. Source manifests, Git bindings, exact commands,
raw successes/failures, retries and reviewer conclusions are retained together.
Generated JavaScript build outputs are represented by their hashes and
reproducible compile commands; runtime archives and build caches are not vendored.

| Archive | Contents |
| --- | --- |
| [Runtime](evidence/runtime.tar.gz) | Pinned toolchain, package integrity, setup commands and compiler review |
| [Baseline](evidence/baseline.tar.gz) | Existing macro baseline and timeout retries |
| [Initial PPTX](evidence/incoming-pptx.tar.gz) | Incoming regression discovery, corrections and original-test checks |
| [Macro milestone](evidence/macro-9dbba0f7.tar.gz) | 675-case acceptance, six web programs, exact source guards and raw attempts |
| [Captured Zotero](evidence/captured-zotero.tar.gz) | 341-case selection, analysis, review and source binding |
| [Captured mail](evidence/captured-mail.tar.gz) | 235-case selection, host regressions and recipient-boundary review |
| [Captured slides](evidence/captured-slides.tar.gz) | 105-case union, static checks and conflict-resolution review |
| [Final mail](evidence/final-mail.tar.gz) | Fresh checks for the final PR head |
| [Final slides](evidence/final-slides.tar.gz) | Final master-background reconciliation and checks |
| [Final macro boundaries](evidence/final-macros.tar.gz) | Corrected final runner, source guards, native spreadsheet execution and VM/web agreement |
| [Main reconciliation](evidence/main-reconciliation.tar.gz) | Exact new-main ancestry, formatting equivalence and unchanged-product proof |
| [Excluded attempt](evidence/excluded-attempt.tar.gz) | Interrupted wrong-directory verification, explicitly excluded |

This is bounded dialect qualification. No installed Microsoft Word, Excel or
PowerPoint process was used for differential execution. Native document
round trips and local assertions do not establish full Microsoft Office VBA
compatibility. The remaining language, live document execution, object models,
projects, events and authoring work is tracked in the roadmap.
