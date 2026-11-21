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

This record is completed with source-specific local test, analyzer and portable
VM/JavaScript results before final publication. GitHub Actions are not used as
a gate. No installed Microsoft Word host execution is claimed.
