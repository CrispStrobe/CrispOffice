# Word VBA proofing and kerning continuation

## Intake and integration

Captured remote main: `4090feb56f308cd3657c5edd1d045ff1197ff79b`.
The intake inspected all 49 fork branch heads and the latest 100 PRs, with no
open PRs. Of the branch heads, 37 were ancestors of main and ten were historical
equivalents. All ten existing tree/path equivalence proofs were independently
replayed, including replacement ancestry, against the captured Git objects.
The exact snapshots and proofs are in `intake-snapshot.json` and
`intake-audit.json` beside this record.

The two remaining recent branch heads were merged with their genuine ancestry:

- `fix/app-store-screenshot-polish-20261121` at
  `e6a38e2bd7b0bc8a267f4fbd416c7f6bcd96cf2b` contributes localization,
  Mail date/reader labels, plural counts and screenshot scenes.
- `perf/wrap-chrome-20261121` at
  `5332c5ff4d3e72dffcd6fa78444dca22787be88e` contributes unchanged-paragraph
  translation, typing notification reduction and benchmark statistics.

Integration checkpoints were saved on
`codex/word-vba-paragraph-flow-20261121` as `88c337bb` and `7c2d609f`, with
verified tree equality against the local merges. Connected GitHub Git-data
operations preserve the two merge parents; no forced branch updates are used.

Review found and corrected two incoming defects. Mail date labels now compare
local calendar dates across daylight-saving changes and normalize a supplied
UTC `now`. Incremental line translation now declines paragraphs containing
inline page/column breaks, because a previously ignored page break can become
active after typing. The new regression reproduced two page-break failures
before the fix; its four cases plus the existing incremental layout tests pass
after the fix (13 tests). The broader scratch reproduction independently
observed 12 failing cases out of 24 before correction.

## Compatibility increment

The bounded `vba-word` compiler adds `Range.NoProofing`,
`ParagraphFormat.Hyphenation`, and `Font.Kerning`. The first two require actual
Booleans. Kerning requires an exact half-point threshold in `0..1638`, with
zero disabling kerning. These setters use the existing explicit paragraph
selectors, typed aliases, helpers and independent header/footer paragraphs.

Native writes preserve other formatting and foreign XML metadata, including
same-value assignments and explicit false/zero overrides of inheritance.
Document reads, embedded project execution, paragraph-mark insertion formats,
and full Word automation remain outside this increment. Automatic hyphenation
still depends on the document setting and existing language support; the
paragraph setter only controls inclusion. The exact public contract is in
[`VBA_WORD_MACROS.md`](../../VBA_WORD_MACROS.md#proofing-and-kerning-controls).

## Validation status

Qualified implementation checkpoint: `75b429e30a80181c34205d49391fb21e9928b490`,
tree `2282addcb35747cf5c63049468d06b4970618ed6`. The final evidence commit adds
the new nested-table test and this qualification record without changing the
qualified runtime implementation. `source-manifest.json` records SHA-256 values
for the changed implementation, examples, tests and related contract files.

| Local check | Result | Evidence |
| --- | --- | --- |
| Word/VBA/native/runtime/MCP/proofing/layout regressions, 17 files | 463 passed | `engine-tests.log` |
| Nested Zotero tables and adjacent table/list/research behavior, 5 files | 234 passed | `zotero-tests.log` |
| Entire engine `lib`, `dart analyze --fatal-infos lib` | No issues found | `engine-analysis.log` |
| Actual committed BAS on Dart VM and compiled JavaScript | Identical results: nine operations, one publication, nine recorded native calls, two additional reopens and preserved opaque DOCM project bytes | `portable-result.json`, `portable-vm.json`, `portable-js.json`, `portable-compile.log` |
| Changed calendar-label function, exact extracted production source and ten existing test bodies, `TZ=Europe/Berlin` | 10 passed; actual 23/25-hour days verified | `calendar-tests.log`, `calendar-derivation.json` |

The 697 completed engine tests include the new source and native proofing tests;
the earlier 52-test source/integration and 94-test native batches are subsets
and are not counted again. Native tests cover explicit inheritance overrides,
namespace aliases, foreign/native `val` ordering, duplicate and
markup-compatibility refusal, citation-expanded ranges, rollback, actual glyph
kerning eligibility and hyphenation layout. Source integration executes the
real CLI and MCP paths. Playback is deliberately not recorded; the portable
example records its equivalent successful native tool calls and replays them.

The captured Zotero continuation originally had no positive nested-table test.
This integration adds `word_zotero_nested_note_tables_test.dart` with eleven
cases for cell ownership, paragraph/list/citation index remapping, inner/outer
spans, repeated save/reopen, body/footnote/endnote staging, and shared depth and
table-count limits.

Runtime: Dart 3.13.7, the Dart version in the pinned Flutter 3.47.8 release.
The pure Dart validation workspace links the checkout's live source and tests;
the resolved full project lock matched the committed lock byte-for-byte.
JavaScript was compiled with `dart compile js -O1` using the complete BAS passed
as `WORD_PROOFING_BAS_BASE64`. Node received `globalThis.self = globalThis` as
the browser-global bootstrap before loading the compiled program. An initial
Node launch without that bootstrap emitted no result and was rejected by the
qualification driver; it is not counted as a successful portable check.

Earlier broad and final regression attempts were interrupted by disk
exhaustion. They do not qualify as completed gates. The completed 463-test
repeat above ran after disposable SDK/cache cleanup. Full Flutter editor/widget
and screenshot execution could not be completed in this environment. The
calendar harness preserves the production helper bodies and original test
bodies exactly, with source hashes and import adaptation recorded; it qualifies
date math only. No installed Microsoft Word host execution is claimed.

GitHub Actions were neither awaited nor used as a gate. All task commits use
`[skip ci]`; branch updates are expected-head, non-forced writes.

## Concurrent refresh

The immutable refresh captured main
`97cfb09b277e0808f9228a4fb638a55748c6268f`, 51 branch heads and zero open PRs.
Its full snapshot and independently replayed equivalence checks are retained in
`intake-refresh-snapshot.json` and `intake-refresh-audit.json`.

The integration preserves incoming PRs #294 and #295, the captured Mail
continuation `f0c2599bf685a599e5bb0aa00f9f1e898e42bf43` (which only joins main
and the already integrated performance work), and Zotero continuation
`2914fd3bd3e799e08ebe280102cc835d122ec95d`. Remote checkpoints `c0698bb7`,
`a243eaf8`, and `75b429e3` retain their genuine ancestry. The Mail date and inline
page-break corrections survive the refresh. A final fetch before evidence
publication still found remote main at `97cfb09b`, already contained by the
qualified checkpoint.
