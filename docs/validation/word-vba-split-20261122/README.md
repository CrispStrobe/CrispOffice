# Word VBA delimited report authoring — 22 November 2026

## Result and source boundary

This increment adds bounded `Split` assignment to local dynamic String arrays
in the shared Word, Excel and PowerPoint source compiler. Word macros can parse
source-local delimited records, iterate their fields and fill supported native
tables. The complete example is
[`word_split_report.bas`](../../../packages/quds_office_engine/example/macros/word_split_report.bas).

The final combined production and test source is checkpoint
[`8bbe17bc`](https://github.com/CrispStrobe/quds_office_suite/commit/8bbe17bc7d82964b67385aa796b7f43248c65149),
which retains remote main
[`4cc60481`](https://github.com/CrispStrobe/quds_office_suite/commit/4cc604810fb2f41ac7ba04cbed65cb76300bff59)
and the captured recent branch histories. Later commits in this increment add
qualification records and documentation. The publication is tracked in
[PR #383](https://github.com/CrispStrobe/quds_office_suite/pull/383).
GitHub Actions were neither queried nor awaited; acceptance uses the local
executions recorded here.

## Capability and example

```vb
Dim records() As String, fields() As String
records = Split("Item|Status;Quarterly report|Ready", ";")
fields = Split(records(1), "|", 2, vbBinaryCompare)
```

The included complete BAS fills an existing supported 2×2 table with `Item`,
`Status`, `Quarterly report` and `Ready`, makes both header cells bold and colors
`Ready` green. It compiles to seven existing native operations. The tests execute
the actual BAS through native DOCX and DOCM handling, detached validation,
recording/replay, CLI and MCP paths. Opaque VBA/signature/custom parts and
untouched stories are checked for preservation; failure and cancellation paths
are checked for atomic behavior.

`Split(expression[, delimiter[, limit[, compare]]])` has these explicit limits:

- The destination is a local dynamic `String()` array. Fixed arrays, scalar
  Variant array storage, array copying and general array-valued expressions are
  outside this increment.
- Results are zero-based even with `Option Base 1`. Empty input or limit zero
  produces an allocated empty array with bounds `0..-1`; this differs from an
  erased, unallocated array. These empty-array bounds are a documented Quds
  contract rather than a new installed-Office observation.
- Matching is binary, case-sensitive and based on UTF-16 code units. Delimiters
  may contain multiple units, empty pieces are retained, and a positive limit
  leaves the remaining suffix in the last element. Named arguments, omitted
  comma slots and locale/text comparison are unsupported.
- Arguments run once in written order, may read the previous array, and undergo
  validation even for empty results. Replacing an array locked by `For Each`
  fails before argument evaluation. Frame ownership and resource accounting
  remain enforced.
- Existing limits remain 4,096 elements per array, 16,384 active array slots,
  32,767 UTF-16 units per String, 1,048,576 stored UTF-16 units and 100,000 shared
  work units. Allocation, retirement and copies are charged before new storage
  is constructed.

See the [full language contract](../../vba-macros-details.md#splitting-source-string-arrays)
and [Word authoring guide](../../VBA_WORD_MACROS.md). This remains the documented
source-to-plan VBA subset; live document reads, arbitrary array values and
embedded VBA execution are outside its supported surface.

## Local qualification

| Execution | Suites | Passing cases | Source/runtime boundary |
| --- | ---: | ---: | --- |
| Broad Word/VBA, native operations and selected ODT regression gate | 179 | 9,310 | Original integrated source `373b7fe9`; official Dart 3.14.1; all 3,068 captured inputs unchanged |
| New Split compiler, native Word and CLI suites on the repository pin | 3 | 373 | Same Split implementation; Flutter 3.47.8 / Dart 3.13.7; 473 captured inputs unchanged |
| Final combined engine, Zotero, Word native and revision/fidelity gate | 61 | 1,798 | Final source `8bbe17bc`; pinned Dart 3.13.7; complete captured engine/local closure verified |
| Final Mail navigation | 6 | 220 | Final source `8bbe17bc`; pinned Flutter 3.47.8; all new main regressions retained |
| Final Zotero editor integration | 12 | 296 | Final source `8bbe17bc`; pinned Flutter 3.47.8 |
| Native SQLite account store | 2 | 47 | Previously passed execution retained; 6,381 relevant inputs rechecked unchanged through final integration |

Every accepted execution has zero failed or skipped cases and no error events.
These rows are separate qualifications with overlapping cases; they must not be
added together as a unique-test total. The broad count is 9,310 registered test
cases from one execution. Some parameterized cases share display names; the raw
reporter IDs and source variants are retained.

The 58-case Split corpus contains 22 specification-derived and 36 explicit
dialect-contract cases. Its 174 outcomes across the three adapters are
byte-identical on the Dart VM and optimized JavaScript. The complete Word BAS
also runs on both runtimes: its DOCX/DOCM receipts are equal after JSON parsing.
Those native receipts are not byte-identical because integral doubles have
spellings such as `4.0` versus `4`; the retained comparison records the distinction.
Node was version 24.22.3.

Strict analysis and formatting pass for the nine original feature/intake files,
the fourteen final affected engine files, and the final Mail/editor targets.
The final engine run includes the revision-validation, revision-story,
revision-scaling, extended-revision, macro revision-guard and ODT complex-field
suites added for the newly merged revision-preservation changes.

### Evidence scope and reporting recovery

The original broad test subprocess exited zero and emitted one successful
terminal event. Its Python reporter then encountered an intentionally isolated
UTF-16 surrogate in a test name while writing UTF-8 JSON. The reporting fix uses
JSON escaping. `--resume-tests-report` checks the original stream digests, input
hashes, suite selection and successful test exit before reconstructing the
ledger and running analysis/portability checks. No test was reexecuted or credited
twice. The original reporter exception, original runner, continuation invocation
and complete raw stream are retained.

The pinned three-suite manifest captured 473 files but omitted one imported
Word table smoke fixture. Independent review found that fixture unchanged from
the tested commit; this is explicitly recorded as a post-run comparison. The
broader engine manifests capture that helper directly. Neither manifest is
represented as installed Microsoft Office differential testing or a complete
Flutter application/platform qualification.

## Reconciled incoming work

The initial audit inspected 45 fork branches, the 100 most recently updated PR
heads and four canonical upstream heads. All inspected PR and upstream heads
were actual ancestors of starting main `659b8146`; no open PR was observed at
that initial boundary. Word selector work subsequently reached main through
PR #381 (`a9bfc961`) and is retained.

Before and during this increment, the branch also preserved Mail and Zotero work
at `550abcef`, `77f8ede7`, `0cb4057a`, `f4516c13`, `2d19bb8d`, `d53f30f1`,
`08c48772` and `8f2e943b`. The later captured snapshot contains 47 fork heads;
every captured head is an ancestor of checkpoint `0e0994d7`. Main then advanced
through Zotero PR #382 to `4cc60481`; the final source checkpoint includes that
main with ordinary merge ancestry. No existing remote branch was rewritten or
deleted. Exact records are in `initial-intake.json`, `concurrent-intake.json`,
`late-main-intake.json` and the retained snapshots.

The overlapping Mail changes retain explicit owner-release recovery, observer
and pending-write draining, late-acquisition fencing, per-await identity/host
checks and the final guarded atomic selected-account refresh. The final refresh
placement avoids both duplicate writes and rejection of the connection's own
revision update. All eleven additional main regressions pass. The merge reasoning
and test-policy reconciliation are documented in `mail-merge-resolution.md` and
`late-main-resolution.md`.

Independent review found one additional incoming Word defect: empty instruction
runs could supply visible color, weight and size when refreshing an empty Zotero
result. The correction excludes those non-visible runs while retaining existing
cached-result and neighboring-text formatting. Nine focused regressions cover
citation, bibliography, unlink and adjacent empty fields, including native
save/reopen behavior.

The incoming revision/XML preservation fixes from PR #382 are retained. Full
post-refresh converter snapshots still check the original golden layout,
colors, preferences, story ownership and item metadata, allowing only explicit
requested citation-text/property changes. Original golden files are unchanged.

## Evidence and reproduction

`evidence/artifact-index.json` lists the retained artifacts, sizes and SHA-256
values. The compressed archives contain raw successes and earlier failed
attempts, per-case ledgers, exact commands, source/dependency snapshots, runtime
provenance, independent verification and reproduction scripts. Historical
failures remain labeled as historical and receive no accepted-case credit.
Generated JavaScript/maps, SDK binaries and downloaded specification copies are
excluded from the archives.

With the repository's pinned Flutter/Dart environment and resolved exact
lockfile, run the portable broad gate from the repository root:

```sh
python3 docs/validation/word-vba-split-20261122/run_checks.py \
  --output /tmp/quds-word-split-checks
```

The output directory must be new. The recorded isolated-runtime wrapper and
SDK/dependency receipts explain the original Dart 3.14.1 execution. The final
engine and Flutter intake archives contain their pinned-runtime runners and
exact suite selections. Their before/after hashes bind each result to the source
it actually exercised.
