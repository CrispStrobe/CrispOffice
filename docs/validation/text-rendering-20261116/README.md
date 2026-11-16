# Font and text rendering: implementation and local qualification

Work branch: [`codex/text-rendering-20261116`](https://github.com/CrispStrobe/quds_office_suite/tree/codex/text-rendering-20261116).
Initial integration baseline: `bfb24bf57d5efd52f00ab7079b4ac8968259a478`.
**Qualified integrated source: `4c1d71adea066bd5ee4d510a8b60b79b64f96a49`.**

The rendering improvements and late incoming work are implemented and locally
qualified. On the integrated source, **138 editor tests, 245 engine tests, the
isolated CLI regression, and the rendering diagnostic pass**. Analysis and
formatting pass for all 36 changed Dart files. Final evidence/documentation
commits do not change the qualified production or test sources.

## Incoming work and incremental preservation

Both the fork and original upstream were fetched, including branch and PR
heads. The initial [audit](incoming-work.md) and [inventory](incoming-refs.json)
account for 132 heads already included in the chosen baseline.

A subsequent refresh found work arriving during this pass. The pinned
[late inventory](late-incoming-refs.json), observed at **15:23:50 UTC on
16 November 2026**, contains **138 incoming refs**: 66 branch heads and 72 PR
heads across the two repositories. Every one is now an ancestor of the
integrated work; see the [138/138 ancestry verification](integrated-ancestry.json).
The work branch and symbolic HEAD are excluded. The inventory defines the
cutoff; it does not claim that other branches stopped changing afterward.

The substantive merges bring in main `a042466` (including ODS writer PRs #67–68),
proofing `6b5c114`, and dialog/rendering `5376008`. Equivalent feature/vendor ODS
histories are also retained as merge parents. Their patch IDs and identical
writer/tree evidence are recorded in the [reconciliation plan](late-incoming-plan.md);
the newer writer implementation was preserved. Ref ancestry establishes source
inclusion, not PR approval.

Source, font notices, research, render evidence, test receipts and each reviewed
integration were saved incrementally to the remote branch. New checkpoints use
`[skip ci]`. No GitHub Actions jobs, checks or statuses were polled, awaited or
rerun for this work.

## What changed

Word pagination previously used isolated-character widths while the editor
painted complete shaped runs. Kerning, Arabic joining and grapheme behavior
could therefore change the width after a line had already been selected.

The default editor now measures contextual runs using the same Flutter
`TextPainter` font, fallback, size, weight, style and direction policy used for
painting. The pure Dart engine accepts an optional typed `WordRunMeasure`
callback with complete, validated UTF-16 grapheme ranges. Existing scalar/font
measurement remains available to hosts without a contextual shaper. The
engine gains no Flutter or `dart:ui` dependency.

Paragraph-context measurements remain estimates for a final line: trimming a
space or removing neighboring letters can change shaping. The breaker
remeasures the actual painted fragment, including the chosen discretionary
hyphen, and repairs overflow at earlier legal boundaries. Adaptive text bands
around floating frames use the same check. Repair work is bounded to 32
candidate measurements per overflowing interval; indivisible oversized words
or graphemes retain their existing overflow behavior.

A shortened fragment that the host declines recovers its original scalar/font
advances instead of retaining widths from the longer context. This preserves
font glyph identities, generated-label scales, and zero-width lam–alef
continuations. Ordinary spaces stay with the preceding soft-wrapped interval,
including the new measured-line emergency path.

Other changes retain natural widths for left/center/right paragraphs, guard
source grapheme boundaries, preserve styled combining-mark ownership and exact
bidi embedding levels, invalidate width caches after font registration, and
release temporary native text painters. Run caches contain immutable values
and have explicit entry/text-size bounds. Omitted invisible controls remain in
paint text across long gaps, preserving authored UTF-16 caret/hit offsets;
visible text owned by another sparse run remains excluded.

Reconciliation also preserves the latest proportional underline ink clearance,
with painter disposal and canvas restoration in `finally` blocks, together with
modal input ownership, direction-chord handling, proofing navigation cleanup,
and route-driven IME reattachment. Underline behavior is covered at normal and
Retina scales. Incoming ODS writer functionality is included and tested.

## Actual rendered comparison

![Real Flutter typography comparison](text-rendering-comparison.png)

The fixture uses bundled Liberation Serif at 32 points, text `AV AV`, and the
same 95.140625-point content box in both controllers.

| Measurement path | Width before wrapping | Lines |
| --- | ---: | ---: |
| Previous scalar path | 100.4375 pt | 2 |
| Contextual shaped path | 89.84375 pt | 1 |

The improved line remains 89.84375 points before and after paint fitting.
The [metrics](metrics.json) contain the measured values. This is an actual
Flutter test-engine Canvas/`TextPainter` typography diagnostic. The
[rendering tool](../../../packages/quds_office_editor/tool/render_text_comparison.dart)
requires an explicit output directory; its final integrated replay produced
[byte-identical image and metrics](integrated-render.json).

The strict 73.2-point table-cell regression exposed a separate boundary
problem: a paragraph-estimated 73.125-point fragment grew to 73.450195 points
after trimming. The actual-fragment check chooses an earlier break. Coverage
also includes a floating-frame band that widens from 73.2 to 173.2 points.
Geometry tolerances were not relaxed to hide the original overflow.

## Final local qualification

All rows below use source **`4c1d71adea066bd5ee4d510a8b60b79b64f96a49`**,
real Flutter **3.47.8** / Dart **3.13.7**, and the actual package manifests.
The [runtime record](runtime.json) pins framework/engine revisions and platform;
[resolved dependencies](resolved-dependencies.yaml) record the exact package
resolution. Production dependency manifests and font binaries are unchanged.

| Check | Result | Evidence |
| --- | --- | --- |
| Integrated editor cohort | **138 passed / 16 files**, no failures, skips or exclusions | [Summary](editor-integrated-summary.json) |
| Integrated engine cohort | **245 passed / 19 files**, no failures or skips | [Summary](engine-integrated-summary.json) |
| Original CLI rejection/preservation regression | **1 passed**, unchanged test, isolated two-minute execution budget | [Summary](engine-cli-isolated-summary.json) |
| Actual Flutter comparison render | **1 passed**, PNG and metrics byte-identical | [Receipt](integrated-render.json) |
| Analysis and formatting | **36 changed Dart files**, no issues or formatting changes | [Receipt](integrated-static-checks.json) |
| Incoming source inclusion | **138/138** pinned refs are ancestors | [Receipt](integrated-ancestry.json) |

The editor, engine and isolated CLI runs retained **595, 764 and 309** input
hashes respectively, with no changes during execution. Tracked inputs were
checked against the published source where supported by the runner. The
untracked generated lock was separately verified against the committed
resolved-dependency receipt and hashed before/after. Bundled fonts are covered
by the stable manifests; the engine's additional system-font record is
explicitly a post-run observation.

Exact file lists, commands, unique visible test-ID counts, hidden-failure checks,
source/runtime manifests and raw or losslessly compressed event streams are
preserved beside these summaries. The editor's Flutter subprocess exited zero;
its original Python wrapper then failed in metadata assembly. A separate
finalizer corrected only that bookkeeping from the original events, without
rerunning tests or overwriting original evidence. The
[wrapper-exit record](editor-integrated-wrapper-exits.json) distinguishes these
outcomes, and the archive checksums were independently recounted.

### Earlier broader sweeps and resolved findings

The earlier 33-file editor cohort passed **437 tests** at `03a28d5`, before the
late integration; its [receipt](editor-broad-final-summary.json) remains separate.
It excluded two named platform-specific `Word-like selection golden` image
comparisons while retaining selection geometry/pixel assertions. No golden
exclusions apply to the final 16-file integrated cohort.

The [full initial engine sweep](engine-full-initial-summary.json), at
`48123bf`, exercised 185 files and 2,490 visible tests: 2,481 passed, seven
callback-invocation assertions failed, one CLI test timed out, and one
host-font-dependent PDF case skipped. The seven assertions had incorrectly
assumed a single host call before actual-line remeasurement was added; their
text/style/direction invariants now allow repeat calls, with geometry checks
unchanged. The two-font PDF test now uses the audited bundled faces and passes
without skipping. New fragment-fallback and ordinary-space regressions pass.

The CLI test also timed out in the first affected cohort. Direct diagnostics
verified the rejection and preserved output, and the original test subsequently
passed in isolation on the final integrated source without code or assertion
changes. Its body took 48.715 seconds. The [startup diagnostic](engine-cli-startup-diagnostic.json)
records substantial startup cost but does not establish the exact cause of the
earlier two-minute timeout under concurrent work.

The initial editor failure was a pre-existing test that asked viewing mode to
allow selection. It now requests selecting mode, matching the existing public
contract; production interaction policy is unchanged. The incoming proofing
branch independently contained the same correction plus stronger IME tests.

Earlier counts overlap the final cohorts and must not be added together. The
entire engine directory and all editor files were not rerun after the last
integration; the final source was qualified with the explicit affected cohorts.

## State of the art and licenses

The [strategy and license review](../../text-rendering-strategy.md) compares the
existing Flutter stack, HarfBuzz/ICU, FreeType's FTL license route, Skia, the
Parley/Fontique/HarfRust/Skrifa/ICU4X Rust stack, COSMIC Text/Swash and SheenBidi.
It links primary upstream documentation/licenses and separates font processing,
shaping, paragraph layout and rasterization responsibilities.

This increment uses the existing Flutter shaping stack and introduces **no new
package or native dependency**. No GPL or LGPL component was added. FreeType's
FTL option is a possible BSD-style route for a future build; its alternative GPL
license is not the selected route. A future native/Wasm backend needs a pinned,
feature-specific dependency and notice audit before adoption.

The separate [font audit](font-license-audit.json) records all 14 bundled font
hashes and embedded metadata. Liberation Sans/Serif/Mono 2.1.5 (12 faces) and
Noto Naskh Arabic 2.004 (two faces) use SIL OFL 1.1. Full upstream license and
copyright notices replace the previous short labels. The older GPL-licensed
Liberation 1.x distribution is not bundled here. Font binaries are unchanged.

## Scope and limits

This work improves Word editor measurement, wrapping and source/caret handling;
it does not replace every Office rendering surface. Headless PDF retains its
pure Dart font/glyph pipeline, so editor success does not establish identical
OpenType shaping in PDF. A shared export backend would need exact font
identities, glyph IDs/offsets, cluster maps and line-boundary context.

Bounded overflow repair preserves the existing paragraph plan where it fits;
it is not globally optimal reflow of every line after contextual changes.
Unsupported host decompositions retain validated scalar/font fallback. The
tests provide specific Latin, Arabic, supplementary, combining, bidi and
source-boundary coverage, not complete Unicode/font/platform conformance.
Cache bounds and resource cleanup are implementation properties; no throughput
or memory benchmark claim is made.
