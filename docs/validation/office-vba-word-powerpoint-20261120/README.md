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

## Final qualification

Final source, command receipts and publication reconciliation will be recorded
here after the native formatting and transaction checks complete. No full
Flutter/native application build, Microsoft Office execution, hosted CI result,
or editor macro ribbon/undo integration is implied by the engine checks.
