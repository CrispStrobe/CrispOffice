# Text rendering follow-up — 16 November 2026

This continues the [first rendering increment](../text-rendering-20261116/README.md)
on `codex/text-rendering-20261116` / draft PR #72. It fixes embedded-font identity
and Unicode transport in the current PDF path without adding a rendering
dependency. The original Flutter contextual-measurement work remains in place.

## Incoming work first

The refreshed inventory contains **148 refs: 72 branch heads and 76 PR heads**
across the fork and original upstream. All are ancestors of integration
checkpoint `b3b5006c44dd8e0de96fe05b563f3fcfa1b107c0`.
[reconciliation.json](reconciliation.json) records every ref and exact SHA.

The new proofing continuation `95185d2` adds German-rule refinements, review
dialog recovery, and invisible line-control semantics. The merge preserves
contextual line measurement and existing ODS picture support. Five incoming
ODS feature/vendor commits have the same stable patch IDs as their already
integrated main counterparts; the feature image and documentation snapshots
also have identical complete trees. Their histories are retained explicitly.
ODS production source and tests are unchanged by this reconciliation.

The remote checkpoints use `[skip ci]`. **No GitHub Actions jobs, checks or
statuses were queried, awaited, polled or rerun.** Shell-based pushing has no
credentials here; the connected GitHub plugin saves Git blobs, trees and
commits, then advances the branch with a checked expected parent. Retrieved
trees are compared with the local staged tree before continuing.

## Unicode export fix

The prior font subsetter only emitted a BMP format 4 cmap, even when the subset
contained supplementary glyphs. Its subtable length was also two bytes too
large. The PDF ToUnicode writer emitted Unicode scalar numbers directly,
instead of UTF-16BE surrogate pairs.

The implementation now:

- Writes exact format 4 lengths and keeps the mandatory U+FFFF sentinel.
- Adds a full format 12 mapping for supplementary values and real U+FFFF
  mappings; this table includes all BMP mappings as well.
- Uses format 12 when a sparse mapping cannot fit the format 4 16-bit length,
  preserving the complete mapping instead of wrapping or truncating it.
- Filters invalid scalar requests and invalid ToUnicode aliases.
- Emits proper UTF-16BE PDF destinations for supplementary characters.

The new `font_subset_unicode_test.dart` tests use required bundled Liberation
Sans outlines with explicit synthetic cmap aliases. They test encoding,
mapping, outlines, advances, extraction and search; they do **not** claim that
Liberation Sans contains emoji or CJK glyph designs.

All **seven regressions failed** against the integrated prior production code
and **all seven passed** after the initial fix. For example, the prior PDF
reopened `A😀𠀀Z` as `Aὠ Z`; the fixed export preserves the authored text.
[unicode-regression-receipt.json](unicode-regression-receipt.json) records exact
source hashes and the before/after commands. Compressed raw test events are
preserved beside it. Loader events are excluded from the test counts.

## Local checks recorded so far

| Check | Result | Evidence |
| --- | --- | --- |
| Unicode/subset regression baseline | 7 expected failures | `unicode-before.events.jsonl.gz` |
| Unicode/subset initial fix | 7 passed; no skips | `unicode-after-initial.events.jsonl.gz` |
| Integrated controls/contextual wrapping | 72 passed; no skips | `controls-contextual-summary.json` |
| Changed engine files, strict analysis | Clean | Initial local analysis; final receipt follows |

These are separate scoped checks, not a claim that the whole repository has
been retested. Subsequent rendering/cache checks and the final source-bound
qualification receipt will be added with the next checkpoints.

## Runtime and license boundary

The official Flutter 3.47.8 / Dart 3.13.7 runtime and pinned package archives
were SHA-256 verified. Offline enforced dependency resolution preserves the
earlier lock hash. [runtime.json](runtime.json) records provenance. The runtime
setup's smoke checks are not counted as implementation qualification.

No production dependency manifest or bundled font binary has changed. The
existing bundled-font OFL notices and audit remain in force. This increment
does not add a GPL/LGPL component or claim exact editor/headless shaping
parity. See the [strategy and license review](../../text-rendering-strategy.md).
