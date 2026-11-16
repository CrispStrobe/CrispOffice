# Text rendering strategy and license review

Reviewed and implemented: **16 November 2026**. Integration baseline:
`bfb24bf57d5efd52f00ab7079b4ac8968259a478`.

## Decision

The Word editor now uses Flutter's existing text shaper for contextual run
measurement before wrapping and for measurement of the actual trimmed line
fragments before they are accepted. Painting uses the same font/style/direction
policy. The document engine remains pure Dart, and existing scalar measurement
and headless fallback paths remain available. This implementation adds no native
rendering dependency.

The change addresses two distinct errors: choosing line breaks from isolated
character widths, and assuming that a fragment cut from a shaped paragraph keeps
the same width when its neighbors are removed. The latter matters even for
Latin kerning at a trimmed space. An overflowing candidate is now remeasured
and repaired before painting. This is a bounded refinement of the existing
line-break plan, not a new globally optimal paragraph shaper.

The engineering choice follows the actual code paths:

- [`WordLayoutEngine`](../packages/quds_office_engine/lib/src/word/layout/word_layout.dart)
  accepts an optional `WordRunMeasure` callback alongside `WordGlyphMeasure`.
  The [typed source-range contract](../packages/quds_office_engine/lib/src/word/layout/word_run_measure.dart)
  contains no Flutter or `dart:ui` types.
- [`WordRunMetrics`](../packages/quds_office_editor/lib/src/editor_word/word_run_metrics.dart)
  implements that contract with Flutter `TextPainter`; the default
  [`WordEditorController`](../packages/quds_office_editor/lib/src/embed/office_controller.dart)
  supplies both contextual measurement and scalar fallback.
- [`LineBreaker`](../packages/quds_office_engine/lib/src/bidi/line_breaker.dart)
  measures accepted slices through an optional `measureLine` callback, repairs
  overflow at legal source boundaries, and uses the same path for ordinary
  paragraphs and adaptive frame wrapping.
- [`PaintRunText`](../packages/quds_office_editor/lib/src/editor_word/paint_run_text.dart)
  reconstructs logical source text, shapes it with Flutter `TextPainter`, then
  fits glyph boxes and caret positions to that shaped result.
- [`OfficeFontSet`](../packages/quds_office_engine/lib/src/fonts/office_font_set.dart)
  and [`OfficeHostFonts`](../packages/quds_office_editor/lib/src/embed/office_host_fonts.dart)
  already provide real face registration and explicit family fallback.

Kerning, ligatures, joining and combining sequences depend on neighboring
characters. Consequently, fitting text after pagination cannot by itself repair
a line break chosen from isolated-character widths. The implementation changes
the measurement contract and its use in line breaking while keeping the existing
graphics backend. The [validation report](validation/text-rendering-20261116/README.md)
records the final tested revision, commands and results.

## State of the art: components with different responsibilities

A modern stack separates Unicode segmentation/bidi, font matching, OpenType
shaping, paragraph layout and glyph rasterization. HarfBuzz explicitly leaves
bidi, line breaking, hyphenation and justification to its caller; it shapes
runs with consistent font/script/language/direction properties.
([HarfBuzz responsibilities](https://harfbuzz.github.io/what-harfbuzz-doesnt-do.html))

The candidates below have licenses compatible in principle with the requested
MIT/BSD/Apache/MPL-or-similar policy. A proposed future dependency still needs
its exact version, enabled features, build outputs and notices checked; a
top-level license does not describe every optional dependency or test font.

| Component/stack | Role | Upstream license route | Fit for Quds |
| --- | --- | --- | --- |
| Existing Flutter `TextPainter` / `dart:ui.Paragraph` | Contextual shaping, line metrics, selection and caret geometry, canvas text | Flutter BSD-3-Clause; retain the engine's third-party notices | **Used by this implementation.** Font/style/direction inputs are shared across measurement and painting. [API](https://api.flutter.dev/flutter/painting/TextPainter-class.html), [licensing](https://docs.flutter.dev/resources/faq) |
| HarfBuzz + ICU | Mature native OpenType shaping plus Unicode services | HarfBuzz Old MIT; ICU Unicode-3.0 and bundled notices | Strong optional native/headless shaping path. Needs FFI/Wasm packaging and a source-cluster contract; it is not a complete office pagination engine. [HarfBuzz license](https://github.com/harfbuzz/harfbuzz/blob/main/COPYING), [ICU license](https://github.com/unicode-org/icu/blob/main/LICENSE) |
| FreeType | Font loading, metrics, hinted outlines and rasterization | Explicitly select **FTL**, its BSD-style license with credit clause, rather than the alternative GPL license | Eligible under the similar-permissive route when FTL obligations and enabled dependencies are honored. Adding it does not solve shaping by itself. [License choices](https://freetype.org/license) |
| Skia | 2D graphics and text drawing infrastructure | BSD-3-Clause for Skia; separate notices for dependencies | An established renderer, but a second Skia integration adds substantial packaging work to an existing Flutter application. [License](https://skia.googlesource.com/skia/+/main/LICENSE) |
| Parley / Fontique + HarfRust + Skrifa + ICU4X | Modern Rust layout, font discovery, shaping, font processing and Unicode data | Parley/Fontique MIT OR Apache-2.0; HarfRust MIT; Fontations MIT OR Apache-2.0; ICU4X Unicode-3.0 | Promising future shared native/Wasm backend. Assess the whole dependency graph, maturity and fidelity before adoption. [Parley](https://github.com/linebender/parley), [HarfRust](https://github.com/harfbuzz/harfrust), [Fontations](https://github.com/googlefonts/fontations), [ICU4X](https://github.com/unicode-org/icu4x) |
| COSMIC Text + Swash | Rust text layout/editing primitives and font scaling | MIT OR Apache-2.0 for both projects | Another permissive Rust option; compare script coverage, font fallback and editor integration against the same corpus. [COSMIC Text](https://github.com/pop-os/cosmic-text), [Swash](https://github.com/dfrg/swash) |
| SheenBidi | Standalone Unicode bidirectional algorithm | Apache-2.0 | A focused candidate if replacing the custom bidi component independently of shaping. [Project and license](https://github.com/Tehreer/SheenBidi) |

The Rust option has production evidence beyond a new-library claim: Chrome's
official April 2026 update reports Fontations use for Linux/Android system
fonts and removal of FreeType from Blink in Chrome 145. Skrifa supplies font
processing and outlines; this does not mean it supplies office layout or
replaces every shaping/rasterization responsibility.
([Chrome's migration report](https://developer.chrome.com/blog/memory-safety-fonts))

DirectWrite and CoreText can be host/platform adapters, but their APIs and
system components do not constitute a portable MIT/BSD library that Quds can
redistribute identically on every target. They are not required for this
increment. LGPL stacks such as [FriBidi](https://github.com/fribidi/fribidi)
must not be treated as automatically equivalent to the requested
permissive/MPL set. No GPL implementation is proposed.

## Implemented measurement and line-fitting contract

### Optional contextual measurement in the pure Dart engine

`WordRunMeasure` receives original logical text, the already-scaled point size,
run properties and the exact bidi embedding level. It returns
`WordMeasuredCluster` values containing UTF-16 `start`/`end` offsets and a
fractional advance. The engine validates the complete result before replacing
fallback advances: it must cover the input consecutively, contain exactly one
extended source grapheme per range, and contain finite nonnegative widths.
Soft hyphens must have zero source advance; an invisible source range without
a glyph cannot own a nonzero advance. A null or invalid result retains the
existing measurement path for that run.

The editor implementation shapes each complete logical run with the same
family resolution, fallback list, bold/italic style, size and direction policy
as `PaintRunText`. Per-grapheme widths come from Flutter's selection/caret
geometry. It checks their total against the complete shaped run width and
declines a decomposition that cannot be reconciled; it does not proportionally
scale independent character widths to make the total look correct.

Run grouping follows paint-relevant style and exact bidi level. Equal parity
alone no longer merges nested embeddings into one paint run. For a lam-alef
continuation with a zero shaped code point, the engine recovers the original
source code point for font-family selection, keeping the ligature in its
complex-script family. Tabs, hard breaks, inline pictures and discretionary
hyphens retain their dedicated handling. Generated labels and small-cap
presentations keep their explicit source ownership. Child engines used for
notes and tall table rows receive the same optional measurement callback.

### Actual trimmed-line measurement and bounded overflow repair

Contextual paragraph advances produce the initial line-break plan. They are
not treated as final evidence that each fragment fits: trimming spaces or
changing a line boundary can change kerning and joining. The new `measureLine`
hook measures the actual painted slice, including the chosen discretionary
hyphen representation, before final bidi reordering and width calculation.
The Word adapter reuses its run measurer for this slice and leaves dedicated
hyphen handling separate, matching painting. A line callback may change only
advances; changing source offsets, glyph identity, bidi state or other glyph
metadata invalidates its result.

An accepted line uses that measured width and glyph list. If a planned
fragment overflows, the breaker tries earlier legal boundaries while retaining
the rest of the original plan. Natural word/hyphen boundaries have priority.
Fixed-width cells and textboxes may use their existing emergency grapheme
break policy. Each repair tries at most 32 candidates: up to 32 natural
boundaries, or up to 16 natural and 16 emergency boundaries when emergency
breaking is enabled. The earliest candidate is included in that bounded
search. Ordinary paragraphs can still contain an indivisible oversized word;
an individual grapheme wider than its box remains whole.

Both ordinary paragraph layout and the prepared breaker used by adaptive
frame wrapping share this measurement/refinement path. Legal natural breaks
are checked against source grapheme boundaries, including a space carrying a
combining mark. Candidate and emitted measurements share a cache scoped to the
paragraph/chunk, bounded to 128 entries and 32,768 glyph records.

Nonjustified paragraphs now keep their natural measured line widths. Word
enables the breaker's justification behavior only for `justify` or
`distributed` paragraphs. This removes the former inflation of left-aligned
non-final lines to the available width and keeps alignment geometry consistent
with the subsequent paint fit.

### Font changes, resource ownership and source slicing

`OfficeHostFonts.registrationRevision` advances after a font or alias has
successfully loaded. Both the scalar advance cache and shaped-run cache observe
that generation. The shaped-run LRU stores immutable Dart values, with limits
of 256 entries and 65,536 UTF-16 units across retained text and family/theme
names. Family names longer than 256 units are measured without retaining a
cache entry. Cache identity also includes text, requested and resolved family,
theme, size, bold/italic style and bidi level.

Temporary `TextPainter` objects are released after measurement, including
declined results. The affected Word paint, fit, caret and hit-test paths now
dispose their temporary painters as well; native paragraph objects are not
retained in the new run cache.

The integration baseline already reconstructed logical source text for
Flutter painting and included surrogate-aware run extraction. Those inherited
fixes are retained. This increment makes the general `logicalSlice` helper
expand to complete extended graphemes and prevents `runText` from borrowing a
following Arabic mark owned by a differently styled run. A source-selection
slice and a styled paint run consequently have distinct boundary policies.

Flutter documents explicit `TextPainter.dispose()` ownership and exposes
selection, caret, glyph and line metrics. These are the appropriate editor
primitives; introducing a separate text widget would violate the repository's
custom RenderBox document-surface architecture.
([TextPainter API](https://api.flutter.dev/flutter/painting/TextPainter-class.html),
[Paragraph API](https://api.flutter.dev/flutter/dart-ui/Paragraph-class.html))

## Explicit limits

This implementation improves the Flutter Word editor's measurement and
wrapping. It does **not** establish exact headless PDF/canvas parity. The
optional callback supplies advances, not exportable font glyph IDs, outlines
or a complete cross-surface glyph-run representation. Headless clients that do
not provide it continue to use the engine's existing font/scalar paths. A
shared export backend would need exact font identities, glyph IDs,
advances/offsets, source mappings and embedding support on both paths.

The bounded repair validates and shortens overflowing planned intervals; it
does **not** re-optimize the whole paragraph using every possible fully shaped
line. It does not claim globally optimal reflow, maximum packing of newly
underfilled lines, or removal of the existing oversized-word/grapheme policy.
Hosts unable to supply valid individual grapheme advances for a multi-grapheme
ligature must decline that run. This increment also does not replace the
engine's custom bidi/shaping implementation or certify complete Unicode and
complex-script conformance.

The tests establish specific geometry and source-ownership behaviors with the
bundled fonts. Emoji/Indic source-boundary cases do not prove that the bundled
font set contains every corresponding glyph. Cache bounds and disposal are
implemented resource controls; no general throughput or memory benchmark claim
is made.

## Font and distribution policy

The existing bundled fonts were inspected separately from code dependencies:

| Bundled assets | Version in the font name table | License and evidence |
| --- | --- | --- |
| Liberation Sans, Serif and Mono, four styles each | 2.1.5 | SIL Open Font License 1.1, verified in all twelve binaries and the [2.1.5 upstream notice](https://github.com/liberationfonts/liberation-fonts/blob/4b0192046158094654e865245832c66d2104219e/LICENSE). The [older Liberation 1.x branch](https://github.com/liberationfonts/liberation-1.7-fonts) has different GPL terms; those binaries are not bundled here. |
| Noto Naskh Arabic, Regular and Bold | 2.004 | SIL Open Font License 1.1. Both font blob IDs match the [recorded upstream revision](https://github.com/notofonts/noto-fonts/tree/bbdcaa392e1a67b5a81c8fe9e961f8325352a141/hinted/ttf/NotoNaskhArabic); the [upstream license](https://github.com/notofonts/noto-fonts/blob/bbdcaa392e1a67b5a81c8fe9e961f8325352a141/LICENSE) and embedded copyright notices are retained. |

The bundled one-line license labels have been replaced with the full OFL
notices, including the applicable copyrights and Reserved Font Names. The
[font audit](validation/text-rendering-20261116/font-license-audit.json)
records every asset's SHA-256, version and license metadata, plus the exact
notice sources and verification limits. Font binaries are unchanged.

OFL is a separate, non-GPL font license suitable for bundling and embedding
under its conditions. Keep the copyright and full license with the assets,
honor Reserved Font Names for modifications, and do not sell the fonts alone.
Font derivatives retain OFL; documents created with them do not inherit it.
([Official OFL 1.1 terms](https://openfontlicense.org/open-font-license-official-text/))

Engine code, Unicode data, font files and dictionary data have separate
licenses. A permissive shaper does not authorize bundling a commercial font.
Retain font provenance and license notices, honor embedding restrictions, and
register the same real font bytes for each surface when reproducibility is
required. Keep the authored family name in the document and report actual
substitutions rather than silently claiming the missing face's metrics.

For any future native/Rust addition, record a pinned source revision and
enabled features alongside the license inventory. Choose a permitted branch
of a dual license explicitly, preserve required notices, and include MPL
source obligations if MPL components are introduced. FTL's GPL compatibility
does not make an FTL-licensed build GPL-licensed.

## Acceptance and evidence

The new [run-metric tests](../packages/quds_office_editor/test/word_run_metrics_test.dart)
compare source-cluster advances with independent Flutter measurements for
kerning, ligatures, Arabic joining and marks, combining sequences, supplementary
characters and trailing spaces. They also exercise style/size changes,
registration-generation invalidation, immutable cache values, bounded retention
and declined inputs. The [controller integration tests](../packages/quds_office_editor/test/word_shaped_wrap_test.dart)
exercise wrapping before paint fitting, strict before/after width agreement,
narrow table cells and adaptive frame wrapping. In the 73.2-point cell/frame
regression, trimming the planned fragment changes its shaped width enough to
overflow; the actual-fragment measurement now selects an earlier safe break.

The [reproducible Flutter diagnostic](../packages/quds_office_editor/tool/render_text_comparison.dart)
draws the same bundled Liberation Serif text through actual controller layout
and `TextPainter`/Canvas painting for the scalar-only and shaped paths. For
`AV AV` at 32 points in a 95.140625-point box, scalar measurement totals
100.4375 points and creates two lines. Contextual measurement totals 89.84375
points and creates one line, with the same width before and after paint fitting.
The scalar-only controller is an executable negative control: fitting its paint
metrics cannot undo its earlier line-break decision.

The generated [comparison image](validation/text-rendering-20261116/text-rendering-comparison.png)
and [metrics](validation/text-rendering-20261116/metrics.json) record this fixture,
runtime and scale. The image is a deterministic typography diagnostic, not a
full application screenshot. Source-boundary tests, numerical geometry checks
and the visual artifact support different claims; the image alone does not
prove caret correctness, export fidelity or complete font coverage.

The [incoming baseline audit](validation/text-rendering-20261116/incoming-work.md)
accounts for all 132 initially fetched refs. This strategy document records the
implemented design and license decisions. The [validation report](validation/text-rendering-20261116/README.md)
is the source of truth for the final tested revision, exact local commands,
broader regression results and remote checkpoints. Local qualification proceeds
without waiting for GitHub Actions. PDF/headless behavior and performance need
their own evidence and do not inherit the editor geometry results.
