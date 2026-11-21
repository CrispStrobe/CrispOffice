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
| Initial existing and independent Mail header-search tests | 74 passed |
| Initial Mail core library and new tests, strict analysis | No issues |
| Exact initial default/Studio error-label bodies | 78 checks passed across 13 errors and English/German/Arabic |

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
`d052ef8c376fcf4bf9f02a9912521ea5219ee786f998010edf5eeeb682fa13b4`.
Identical text conformance receipt SHA-256:
`1f57b6bbaab9630ec83d05a64916ccb42c5d1563f15d38af2bef34952f96f433`.

The independent corpus contains 25 successful cases with 130 exact expected
native operations and 70 deliberate positioned diagnostics. Expectations were
authored from Microsoft documentation or the explicit dialect contract before
execution. No fixture is labeled as an observed Office-host result.

## Concurrent refresh

A subsequent fetch observed remote main
`f50c4f23392ccb0ac9f486541ffae6a65a691b99` and 24 branches, with no open PRs.
That head contains further Mail Boolean UI/tests/documentation and the Zotero
native ODT input contract. The Mail parser and engine compiler implementations
are unchanged by that refresh. The final integration record below will retain
the reconciled head, affected-source rechecks and publication outcome.

## Remaining compatibility boundary

These functions operate on source-known values. They do not add live Word
Range reads, document-dependent branching, embedded VBA execution, a macro
editor, COM automation, or general VBA project compatibility. Text/database
comparison, LCIDs, `Option Compare`, implicit coercions, Null propagation for
these String signatures, named intrinsic arguments and interior omissions
remain explicitly unsupported. Existing Word story/paragraph selectors and
whole-run policy boundaries continue to apply.
