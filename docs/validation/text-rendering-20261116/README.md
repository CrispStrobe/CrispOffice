# Font and text rendering: implementation and local qualification

Work branch: [`codex/text-rendering-20261116`](https://github.com/CrispStrobe/quds_office_suite/tree/codex/text-rendering-20261116).
Integration baseline: `bfb24bf57d5efd52f00ab7079b4ac8968259a478`.

**Incremental qualification record.** The typography source at
`03a28d585869eec70b5d06eae4005a68151e9c34` passes the 437-test editor cohort,
static checks and rendered comparison. The affected engine cohort passes
225 tests, with one unrelated CLI timeout still under investigation. A remote
refresh found late incoming proofing/dialog and ODS writer changes; their
reconciliation and qualification follow this checkpoint. Every receipt
identifies its actual source snapshot.

## Incoming work

The work started from the consolidated incoming branch after fetching both the
fork and original upstream, including PR heads. All **132 observed incoming
heads** are ancestors of the chosen baseline: 62 branch heads and 70 PR heads.
The [incoming audit](incoming-work.md) and [exact ref inventory](incoming-refs.json)
record the cutoff, exclusions, source SHAs and ancestry checks. Source inclusion
does not imply PR approval, and later remote changes are outside that snapshot.

## What changed

Word pagination previously used isolated-character widths while the editor
painted complete shaped runs. Kerning, Arabic joining and grapheme behavior
could therefore change the width after a line had already been selected.

The editor now measures contextual runs using the same Flutter `TextPainter`
font, fallback, size, weight, style and direction policy used for painting.
The pure Dart engine accepts an optional typed `WordRunMeasure` callback with
complete, validated UTF-16 grapheme ranges. Existing scalar/font measurement
remains available to hosts without a contextual shaper. The callback does not
introduce Flutter or `dart:ui` into the engine.

Paragraph-context measurements are still only estimates for a final line:
trimming a space or removing neighboring letters can change shaping. The
breaker therefore remeasures the actual painted fragment, including a chosen
discretionary hyphen, and repairs overflow at earlier legal boundaries. The
same check applies to adaptive text bands around floating frames. Repair work
is bounded to 32 candidate measurements per overflowing interval; indivisible
oversized words or graphemes retain their existing overflow behavior.

Other changes keep lam–alef continuations in their source script font, retain
natural widths for left/center/right paragraphs, guard source grapheme break
boundaries, preserve styled combining-mark ownership and exact bidi embedding
levels, invalidate width caches after font registration, and release temporary
native text painters. Cached run metrics contain immutable Dart values and
have explicit entry and text-size bounds.

Two further reviewed edge cases now have regressions. A shortened line that a
host declines recovers its original scalar/font advances instead of retaining
metrics from the longer paragraph context. Long spans of omitted invisible
controls remain in paint text and preserve source caret offsets; genuinely
sparse visible text owned by another run remains excluded.

## Actual rendered comparison

![Real Flutter typography comparison](text-rendering-comparison.png)

The fixture uses bundled Liberation Serif at 32 points, text `AV AV`, and the
same 95.140625-point content box in both controllers.

| Path | Width used before wrapping | Lines |
| --- | ---: | ---: |
| Previous scalar measurements | 100.4375 pt | 2 |
| Contextual shaped measurements | 89.84375 pt | 1 |

The improved line remains 89.84375 points before and after paint fitting.
The [metrics](metrics.json) contain the full measured values. The image is an
actual Flutter test-engine Canvas/`TextPainter` diagnostic, not a screenshot
of the full application. The [rendering tool](../../../packages/quds_office_editor/tool/render_text_comparison.dart)
requires an explicit output directory and is reproducible locally.

The stricter 73.2-point table-cell regression exposed a separate boundary
problem: a paragraph-estimated 73.125-point fragment grew to 73.450195 points
after trimming. The actual-fragment check now chooses an earlier break. The
same regression is covered for a floating-frame band that widens from 73.2 to
173.2 points; its geometry tolerances were not relaxed.

## Qualification to date

All execution uses the real local Flutter 3.47.8 / Dart 3.13.7 runtime.
The [runtime record](runtime.json) pins framework/engine revisions and platform;
[resolved dependencies](resolved-dependencies.yaml) record the exact package
resolution. Production dependency manifests are unchanged. No GitHub Actions
jobs were polled, awaited or rerun.

| Local check | Result at this checkpoint |
| --- | --- |
| Broader editor cohort, 33 files, source `03a28d5` | 437 passed; zero failures or skips; two explicit image-golden exclusions |
| Initial broader editor cohort, 33 files, source `48123bf` | 432 passed; one inherited mode-test mismatch failed |
| Corrected focus/navigation test file | 5 passed |
| Run metrics / strict controller integration checks | 13 / 8 passed before the broad cohort; these overlap the cohort and are not additive totals |
| Actual Flutter comparison render on `03a28d5` | 1 passed; image and metrics byte-identical to the reviewed artifacts |
| Scoped analysis and formatting of 21 changed Dart files on `03a28d5` | Both pass; no analysis issues or formatting changes |
| Entire engine test directory, 185 files, source `48123bf` | 2,481 passed; seven outdated callback-count assertions failed; one CLI test timed out; one host-font-dependent PDF test skipped |
| Affected engine cohort, 18 files, source `03a28d5` | 225 passed; callback assertion cases and two-font PDF case resolved; one CLI timeout remains |

The initial editor cohort excluded only the two tests named `Word-like selection
golden`, whose platform-specific image baselines were not regenerated. Selection
geometry and pixel-difference assertions remained enabled. Its JSON receipts
count distinct visible test IDs, omit hidden loader/setup events, and preserve
the failure rather than hiding it. All 494 recorded inputs were unchanged
during that run. See [its summary](editor-broad-initial-summary.json) and
[baseline identity evidence](editor-incoming-test-mismatch.json).

The failed incoming test asked viewing mode to allow selection/navigation.
The existing public mode contract reserves viewing for scroll/zoom and uses
selecting for selection/copy without mutation. Both the original test and mode
policy were byte-identical to the integration baseline. The test now requests
selecting mode; the production interaction policy has not changed.

The [initial engine summary](engine-full-initial-summary.json) preserves all
2,490 distinct visible test outcomes and the full compressed event/log streams.
Its 740 recorded inputs were unchanged during execution. Seven new tests still
expected a single callback invocation even though actual-line remeasurement
intentionally calls the host again; their input/style/direction invariants now
allow repeat calls, with every geometry assertion unchanged. The CLI timeout
recurred with a two-minute execution budget and is being investigated
separately. The two-font PDF test now
prefers the audited bundled fonts so an incidental system face cannot cause
the distinct-resource assertion to skip. The focused final engine cohort also
includes six new declined-fragment regression cases.

## State of the art and licenses

The [strategy and license review](../../text-rendering-strategy.md) compares the
existing Flutter stack, HarfBuzz/ICU, FreeType's FTL license route, Skia, the
Parley/Fontique/HarfRust/Skrifa/ICU4X Rust stack, COSMIC Text/Swash and SheenBidi.
It links primary upstream documentation and licenses and distinguishes font
processing, shaping, paragraph layout and rasterization responsibilities.

This increment uses the existing Flutter shaping stack and introduces **no new
package or native dependency**. No GPL or LGPL component was added. FreeType's
FTL option is a possible BSD-style route for a future build; its alternative GPL
license is not the selected route. A future native/Wasm backend requires a
pinned, feature-specific dependency and notice audit before adoption.

The separate [font audit](font-license-audit.json) records all 14 bundled font
hashes and embedded metadata. Liberation Sans/Serif/Mono 2.1.5 (12 faces) and
Noto Naskh Arabic 2.004 (two faces) use SIL OFL 1.1. Full upstream license and
copyright notices replace the previous short labels. The older GPL-licensed
Liberation 1.x distribution is not bundled here. Font binaries are unchanged.

## Scope and limits

This work improves Word editor measurement, wrapping and source/caret handling;
it does not replace every Office rendering surface. Headless PDF retains its
pure Dart font/glyph pipeline, so editor success is not a claim of identical
OpenType shaping in PDF. A shared export backend would need exact font
identities, glyph IDs/offsets, cluster maps and line-boundary context.

Bounded overflow repair preserves the existing paragraph plan where it fits;
it is not a globally optimal reflow of every line after contextual changes.
The tests provide focused Latin, Arabic, supplementary, combining, bidi and
source-boundary coverage, not complete Unicode/font/platform conformance.
Cache limits and resource disposal are verified implementation properties;
no throughput or memory benchmark claim is made.
