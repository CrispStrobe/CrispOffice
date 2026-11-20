# Word and PowerPoint VBA extension — 20 November 2026

## Scope and source

This increment extends the shared bounded source compiler with the
`vba-powerpoint` application adapter and additional `vba-word` formatting.
It preserves explicitly invoked native transactions, document admission,
host permissions, aggregate work limits, positioned diagnostics, and opaque
embedded VBA projects. See the exact [PowerPoint](../../VBA_POWERPOINT_MACROS.md)
and [Word](../../VBA_WORD_MACROS.md) contracts.

The retained checkpoint branch is `codex/word-powerpoint-vba-20261120`.
GitHub Actions are neither queried nor awaited. Every checkpoint uses a
non-forced expected-head update and its remote tree must equal the local tree.
Source commit identities are recorded separately from test results below.

## Incoming work and preserved ancestry

Initial remote main was `5e38de19ab5af8d6811d601c7317cba7f69d516b`.
All live fork branches were fetched, the latest 100 PRs were inspected, and a
later refresh fetched all 236 PR head refs. The first consolidation retained
the original parents of each substantive branch:

| Incoming head | Included work | Remote checkpoint |
| --- | --- | --- |
| `aa51b5700a4791db088a2d47b66ff521540b42e0` | Zotero continuation, initial Word/Variant compiler, rename, prior Android/PPTX work and main | `aa51b570` |
| `6fea99ed24d7cfeeefca67f139505091de36c1f6` | Mail workspace and presentation autofit | `c224a66a4c1913690aff5273ab584621487305d1` |
| `20573cabfd4dcae091e4c705fd58277cc6372075` | PDF radial/alpha changes | `54d07bc32fb35a7aa4445971b3cd3604b7c5cf7f` |
| `7ac3d3be4a62bf9d2e0ab8a67f0e122568691b22` | Optional Android replay workflow | `b9e4f1d4bc691714f68e3685dbf729b09ccb0449` |
| Shared compiler and CLI extension | PowerPoint object bindings, Word formatting, 91 new compiler cases | `1d3f9e64da6d7a9498e010c30e0e9d3f03c411bb` |

The integration resolved overlapping PDF paragraph layout while retaining
source/background ownership, installed font aliases, fixed leading and normal
autofit. A semantic merge conflict called PDF helpers that current main had
removed; its numeric text path now uses the existing shared measured/painted
line plan. Incoming alpha resources are connected to exported pages, and
picture opacity is scoped so it composes with image alpha without changing
later paint state. Focused checks passed 109 existing tests plus three new
alpha-resource tests at that integration source.

Older branches were not replayed over newer code. For every pair below, all
paths changed from the old branch's main merge-base matched the accepted
ancestor by Git mode/type/blob identity. Every accepted ancestor was reachable
from captured main; all comparisons were rerun locally with zero mismatches.

| Old head | Accepted ancestor | Matching changed paths |
| --- | --- | ---: |
| `c3494576` | `2c47165d` | 37 |
| `3abf8f43` | `4b2b4e78` | 221 |
| `58fdddfb` | `4eaca83b` | 1 |
| `69d14f84` | `52c73ae4` | 1 |
| `74ce9ffb` | `4584d5f3` | 7 |
| `0a53b8a7` | `b3f41eb4` | 8 |
| `68a0db23` | `d754bf15` | 4 |
| `005c708e` | `c84d5e16` | 7 |
| `7ef09f24` | `34dc6b68` | 7 |

## Runtime and evidence rules

Local engine checks use the official Linux x64 Dart **3.13.7** SDK, matching
the repository's prior qualified runtime. The archive SHA-256 is
`eb99aed266efbcb615c6ae21c12f52cfe935b9f208bccc5fea7f64c21e867229`.
A reduced workspace resolves the engine, legacy parser and engine example
from unchanged copied manifests and live source links. Every shared dependency
version matches the repository lock; no tracked manifest/lock change is made.
DevTools and unrelated SDK components were omitted to fit local disk limits.

An early development run used Dart 3.12.2 and exposed the incoming PDF compile
conflict. It is not final evidence. A broad in-progress run was stopped after
507 passing tests because concurrent compiler edits caused transient compile
failures and test-kernel caching exhausted disk. A later two-file PowerPoint
run passed seven integration tests but could not create the CLI temporary
directory. These incomplete runs are not qualification. Final tests run in
small batches against a frozen source, with exit codes and receipts retained.

## Compatibility decisions

- All three application adapters share the source compiler. No live document
  reads are introduced; unsupported object paths are checked in unused code.
- Word paragraph marks remain structural. This increment adds underline,
  strike, indentation and pagination, without approximating `Range.Text` or
  `InsertAfter` as plain paragraph text edits.
- PowerPoint selectors request a strict native top-level collection check.
  Grouped/empty-group/unmodeled collections are refused before a shape edit.
- PowerPoint formatting preserves rich text source XML, fields, hyperlinks
  and paragraph/body settings. Explicit false and same-value assignments are
  applied, including to mixed runs and empty text shapes.
- New conformance expectations are authored from Microsoft documentation and
  explicit dialect restrictions. No Microsoft Office host was executed, and
  test counts are not a percentage of VBA compatibility.

## Final source and captured-ref coverage

The final product source is `a6068b4d46421e8a0c5921ba0b5cc24b4873ca12`. The engine gate began at
`fb09a29b70e469c2858bde48c8977590791b6ba7` and finished at `55e52def` before the
latest-main reconciliation. Both the proofing/UI and latest-main merges left
the entire engine tree unchanged: `aabb48ef7ab6a79904a889c50dc3756eab116e7c`.
All **1,041** source, test, tool, fixture and manifest inputs were
hashed before and after qualification and checked again while bundling evidence.
The final evidence commit changes only this validation directory.

The captured snapshot contains **24 live branch heads**. The final inclusion
audit accounts for all of them: **15 true ancestors and 9 historical equivalents**.
All three captured open PR heads (#227, #234 and #236) are true ancestors.
Of all 236 fetched PR head refs, 222 are ancestors and 14 older refs have proven
accepted equivalents; those 14 are not described as ancestor commits.
Thirteen of those historical PR equivalents have identical full trees, and the
remaining ODT PR has identical mode/type/blob entries on all 37 changed paths.
See [the complete inclusion receipt](integration/inclusion-receipt.json).

The final captured additions include Zotero `708f2821`, window focus `b8f4a7be`,
Mail `44abcfa1`, presentation controls `1eddb914`, rename/workflow `228d13d9`,
Android `67a4917b`, Variants/Word `1ceae221`, and proofing `604e5f1a`.
Original branch parents are retained by merge commits. Incremental remote
checkpoints and local-to-remote commit mappings are recorded in
[checkpoints.json](integration/checkpoints.json); each published tree was
verified against its local tree before a non-forced expected-head update.
The exact snapshot cutoff is recorded in
[captured-refs.json](integration/captured-refs.json).

Remote main subsequently advanced to `33190e50cae486be362eedb5fa687dd9c82b0c51`. Its exact head
was integrated at `a6068b4d46421e8a0c5921ba0b5cc24b4873ca12`, retaining the new installed-font
fixes and evidence. All 1,041 qualified inputs were checked again and remain
identical. The original captured-ref audit remains applicable by ancestry.
[The latest-main receipt](integration/latest-main-reconciliation.json) records
all seven incoming commits, their merge-resolution inspection, the seven net
changed paths, and the retained Mail regression assertions. No additional
engine test execution was needed because its entire source tree is unchanged.

See [integration-reconciliation.md](integration-reconciliation.md) for the
PDF/autofit/radial merge decisions. Final review additionally repaired explicit
same-value PowerPoint text replacement, preventing old fields/mixed runs from
being resurrected, and kept existing native-menu callers compatible with the
incoming optional View groups.

## Final local qualification

**Strict analysis of the whole engine passed with `--fatal-infos`.**
The frozen macro selection passed **1,221 test cases
across 32 files**, with zero failures and zero skips. Test IDs, exact command
arguments, exit codes, source hashes, durations and local resource limits are
retained in the [summary](macro-gate/summary.json) and
[full raw receipt](macro-gate/receipt.json.gz).

There are 1,221 distinct runner execution IDs and 1,220 display labels because
the empty-group and populated-group guard fixtures share an existing test title.
[Case identifiers](macro-gate/case-identifiers.json.gz) distinguish those inputs.

| Local test batch | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| operations-runtime | 63 | 0 | 0 |
| format-and-word-guards | 56 | 0 | 0 |
| word-structure-and-sheet | 90 | 0 | 0 |
| word-powerpoint-transactions | 75 | 0 | 0 |
| slide-fidelity-and-variant | 257 | 0 | 0 |
| conformance-and-word-format | 215 | 0 | 0 |
| compiler-host-boundaries | 438 | 0 | 0 |
| mcp-cli-bridge | 15 | 0 | 0 |
| native-macro-cli | 5 | 0 | 0 |
| word-vba-cli | 5 | 0 | 0 |
| powerpoint-vba-cli | 2 | 0 | 0 |

The selection includes all 93 new compiler cases, actual DOCX/PPTX operations,
validation without publication, permissions and work budgets, strict shape
selection, late-failure rollback, exact XML units, explicit false/same-value
formatting, imported fields/hyperlinks, empty/authored rich text, repeated saves,
opaque macro-project preservation, MCP and real CLI subprocesses.

The separate PDF/import reconciliation gate passed **213 tests in 10 files**
across three bounded processes (39 + 119 + 55). Its tested source hashes match
the frozen engine commit. It covers finite/zero autofit, shared paragraph layout,
shape geometry and anchors, scoped picture opacity, alpha resources, radial
guards and ring colors, backgrounds and import preservation.
See [its receipt](pdf-gate/final-pdf-results.json). These selections overlap;
their counts are not added into a claimed unique grand total.

### Portability and runnable example

- The 20-case independently authored PowerPoint conformance corpus passed on
  both Dart VM and compiled JavaScript, with byte-identical canonical receipts
  and unchanged inputs.
- The native PowerPoint transaction smoke passed on both runtimes with
  byte-identical receipts, including real save/readback, MCP, strict selectors,
  read-only refusal, validation without publication and rollback.
- The committed `example/macros/powerpoint_report.bas` compiled through the
  public default `Main` entrypoint into exactly 18 independently specified
  operations. Native PPTX readback verified both formatted shapes, an unchanged
  third shape, and the computed body text `Source records: 3; total units: 14`.

Portable source/command receipts are retained in
[conformance](macro-gate/portable-conformance-receipt.json) and
[native smoke](macro-gate/portable-smoke-receipt.json). Raw VM/JS outputs are in
`portable/`; the runnable example receipt is in the macro summary.

### Reproduction and evidence boundaries

Use the repository's pinned environment and the exact test-file selections and
arguments in `macro-gate/summary.json` and `pdf-gate/final-pdf-results.json`.
All final test commands use `--concurrency=1 --timeout=4x`; CLI-containing suites
run alone. The executed local drivers and runtime receipt are preserved under
`runtime/`. Their absolute workspace paths describe the original run and must
be adjusted when reproducing elsewhere. Raw logs and large JSON manifests use
gzip compression; `evidence-manifest.json` records their SHA-256 hashes.

Earlier source-only shared compiler and Word/Variant regression logs are kept
under `development/` for traceability and are not added to the final-source
execution count. The same-value text regressions were observed failing before
their fix and passing afterward. Earlier disk-exhausted or default-timeout CLI
attempts were development failures, not qualification; the final isolated CLI
batches above supersede them.

No GitHub Actions run, check, status, or queued job was used as an acceptance
gate. No Flutter UI/native application build or Microsoft Office host execution
was performed. The inherited editor/proofing integration received source and
call-site review; its Flutter runtime behavior is not qualified by these engine
tests. No full VBA runtime, COM, live object-property reads, embedded-project
execution, or editor macro ribbon/undo integration is implied.
