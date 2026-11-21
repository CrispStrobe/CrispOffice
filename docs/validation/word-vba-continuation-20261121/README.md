# Word VBA source text continuation

## Implemented behavior

This continuation adds binary `InStr`, `InStrRev`, `Replace`, and the
`Trim` / `LTrim` / `RTrim` families, including the Trim-family `$` forms, to
the shared VBA compiler. Word, Excel and PowerPoint use the same checked
implementation. The exact positional forms, strict types, UTF-16 units and
deliberate refusals are documented in
[`VBA_MACROS.md`](../../VBA_MACROS.md#binary-search-replacement-and-trimming).

The matcher meters pattern storage, code-unit comparisons and retained matches
against the existing compilation budget. Replacement checks its complete
result size and output work before construction. The implementation retains
the 32,767-unit String limit and shared 100,000-work limit.

The committed `word_text_report.bas` prepares a report title and filename from
source values, then inserts/formats text in two body paragraphs and an
independent primary header. It emits six native operations. Runtime validation
remains detached, execution publishes only a successful complete plan, and
opaque embedded VBA project bytes remain inert and preserved.

## Initial reconciliation and remote checkpoints

Initial remote main was `1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0`.
`intake.json` captures 55 fork branches, zero open PRs, the recent merged PRs,
and all 15 independently replayed historical equivalence proofs. Upstream main
had no commits absent from the fork.

The continuation preserved genuine ancestry for the recent CLI/typing branch,
the compile-package-path correction, Zotero ODT intake, and Mail Boolean
header search. The bounded per-file CLI compiler was retained; the URI-to-file
path fix was applied without reviving the previously rejected shared cache.
Mail's new error enum cases received complete localized UI handling and
independent Boolean grammar/truth-table tests.

These checkpoints were saved remotely on
`codex/word-vba-text-intrinsics-20261121`:

| Remote commit | Contents |
| --- | --- |
| `7f12e0c5a39302cba96f96ba99592619fb4cf73b` | Reconciled CLI runner and typing benchmark |
| `ee9e0cd55c3979f8a0888abb47c519782721a2a0` | Compile package-path fix with both merge parents |
| `49b4ff856a6a76d387e2d5c80a8b9df05ce12a30` | Zotero ODT intake ancestry |
| `b35a9c47d33c583cc2023f247844e939cffb8511` | Mail Boolean core ancestry |
| `0995c533408cd34b0d90c342330599656e586950` | Complete Mail enum handling and intake evidence |
| `801ad67ba8bf98083af79bcf4acb79757cf0f351` | Bounded text intrinsics, 156 compiler cases and independent Mail tests |
| `2714483aafe059065b00dac23032023f9ddf7aac` | Word BAS, transaction/portable tests, independent corpus and public contract |
| `7e33854158243c47e95c43fbb890cce23da4e0ce` | Latest main reconciliation; both Mail test suites preserved |

GitHub Git-data writes use expected-head, non-forced ref updates. Every remote
tree was compared with its local committed tree, then fetched back into the
checkout. GitHub Actions were not awaited or used as a gate; task commits use
`[skip ci]`.

## Local qualification

Runtime: standalone Dart 3.13.7. The pure Dart validation workspace links the
actual checkout sources and tests, and resolves 56 dependency entries with
versions and source descriptions matching the committed lockfile. Tracked
manifests and lockfiles remain unchanged. This is headless engine and Mail
core qualification; full Flutter widgets and installed Microsoft Office were
not executed.

| Completed check | Result |
| --- | --- |
| VBA and native macro regression cohort, 85 files | 4,543 unique tests passed |
| New text compiler unit cases | 156 passed; included in the 4,543 above |
| Independent versioned text corpus test | 96 passed: 95 fixtures and one provenance check |
| Word text transaction/CLI/MCP integration | 11 passed |
| Entire engine library plus new text compiler test, strict analysis | No issues |
| Same 95 text fixtures on VM and compiled JavaScript | Byte-identical successful receipts |
| Complete committed Word BAS on VM and compiled JavaScript | Byte-identical receipts; six operations, one publication, six recorded/replayed calls, two additional reopens |
| Final existing, incoming and preserved Mail header-search tests | 100 passed: 27 existing, 26 incoming and 47 preserved regressions |
| Final Mail core library and all three header-search test files, strict analysis | No issues |
| Exact final default/Studio error-label bodies, help text and direction expressions | 78 label, 56 direction and 31 parser/example checks passed; all 12 localized example lines parse and select LTR |

The engine total is **4,650 unique test registrations** across the regression
cohort, independent conformance file and Word integration file. VM/JavaScript
fixture executions and repeated verification are separate evidence, not extra
unique tests. No VBA parity percentage is inferred from these counts.

The broad regression initially reported four missing-font errors in the
isolated workspace. Linking the exact sibling editor font and rerunning that
96-test file produced 96 passes without source changes. The aggregate replaces
that file's initial 92 successes/four errors with its complete passing retry;
the original environmental failure remains in the raw record. An earlier
baseline command contained one nonexistent test filename and was corrected.
The first Word example harness used a nonexistent `fontAscii` property; it was
corrected to the model's `asciiFont` before all passing integration and portable
checks. Those unsuccessful setup attempts do not qualify as passing gates.

Qualified compiler SHA-256:
`4f969f9de6259dd6362440f939a931be7e647be5001ce002525af188f8242b94`.
Qualified CLI helper SHA-256:
`a99c9fa6df165eb5fe864104a92d971af3ebc1595bde8504e04b704524078c3a`.
Independent fixture SHA-256:
`73b05587b1e1e4c517aa059f44de4f2d26cec8b8294da41e1c59f8b5deec2511`.
Identical text conformance receipt SHA-256:
`8dfa6bef86ad43c377491cfb64226ecb0ed705b4f93680c1c8dff4f4decfb166`.

The independent corpus contains 25 successful cases with 130 exact expected
native operations and 70 deliberate positioned diagnostics. Expectations were
authored from Microsoft documentation or the explicit dialect contract before
execution. Three combined empty/start/count cases were subsequently labeled
as explicit dialect contracts because the primary return tables do not fully
order all combined edge conditions. Their expected operations and diagnostics
are unchanged; the final VM and JavaScript runs use the corrected provenance.
No fixture is labeled as an observed Office-host result.

## Concurrent refresh

A subsequent fetch observed remote main
`f50c4f23392ccb0ac9f486541ffae6a65a691b99` and 24 branches, with no open PRs.
That head contains further Mail Boolean UI/tests/documentation and the Zotero
native ODT input contract. The Mail parser and engine compiler implementations
are unchanged by that refresh. All 23 other surviving remote branch heads are
contained in refreshed main; only this continuation is ahead. The 32 remotely
removed initial branch names remain represented in the frozen intake record.

The refreshed main is merged with genuine ancestry at remote checkpoint
`7e33854158243c47e95c43fbb890cce23da4e0ce`, tree
`59f6577c131f67406833e66dff632b98476ab504`. Its equivalent local merge
`0afbc2d90be94418eba1d8bad69c224f7359fae5` appears in the final Mail receipt;
the remote and local trees were verified identical. Incoming Mail UI and
localized strings supersede the initial companion wording while retaining all
error cases and adding grouped/NOT/minus example routing for RTL. Both
independently authored Boolean suites remain: the incoming file keeps its
name and the earlier 47 cases live in
`header_search_boolean_regression_test.dart`.

The compiler and CLI-helper hashes above survive this merge unchanged. The
affected Mail suites and extracted production helpers were requalified as
listed above. Word's 11 integration tests were repeated successfully after
adding the library-level timeout that covers shared CLI compilation. Its
portable runner and integration file also pass strict analysis.

Final publication is tracked by
[PR #301](https://github.com/CrispStrobe/quds_office_suite/pull/301), using a
merge commit so earlier branch ancestry and checkpoints remain reachable.
The PR's merge metadata identifies the resulting remote-main commit.

## Preserved evidence

- `evidence/engine/` retains the 85-file aggregate, exact commands, original
  event stream, 96-case retry, strict analysis and runtime/dependency receipt.
- `evidence/text-conformance/` retains the corrected final 95-case VM/JS
  receipts, 96-test event stream, compiler output and complete source hashes.
- `evidence/word-text/` retains the final 11-case integration log, strict
  analysis, actual BAS portable receipts and source hashes.
- `evidence/mail/` retains final 100-case events, analysis, exact helper
  derivation and all label/direction/example checks.
- `source-manifest.json` binds the final relevant changed source, tests,
  example and public contract files to their SHA-256 values.
- `refresh.json` records the surviving branch heads and their containment.

Large raw `.jsonl` event streams are stored as `.jsonl.gz`; receipt filenames
refer to their decompressed bytes. Portable generated JavaScript is
reproducible from the recorded commands and is not duplicated in this report.
Extracted Mail helper execution does not establish actual Flutter widget
rendering or full Studio compilation.

## Remaining compatibility boundary

These functions operate on source-known values. They do not add live Word
Range reads, document-dependent branching, embedded VBA execution, a macro
editor, COM automation, or general VBA project compatibility. Text/database
comparison, LCIDs, `Option Compare`, implicit coercions, Null propagation for
these String signatures, named intrinsic arguments and interior omissions
remain explicitly unsupported. Existing Word story/paragraph selectors and
whole-run policy boundaries continue to apply.
