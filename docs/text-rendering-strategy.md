# Text rendering strategy and license review

Reviewed: **16 November 2026**. Implementation baseline:
`bfb24bf57d5efd52f00ab7079b4ac8968259a478`.

## Decision

Use Flutter's existing text shaper consistently for editor measurement and
painting, while preserving the pure Dart document engine and its headless
fallback. The first improvement is to provide contextual run/cluster advances
to Word's line breaking. This addresses the current mismatch between widths
measured one code point at a time and text subsequently shaped as a whole run.
It requires no additional native rendering dependency.

The engineering choice follows the actual code paths:

- [`WordLayoutEngine`](../packages/quds_office_engine/lib/src/word/layout/word_layout.dart)
  accepts scalar `WordGlyphMeasure` widths and passes those into the engine's
  line-breaking/pagination machinery.
- [`LineBreaker`](../packages/quds_office_engine/lib/src/bidi/line_breaker.dart)
  preserves logical UTF-16 offsets through its bidi, Arabic and line-break
  processing.
- [`PaintRunText`](../packages/quds_office_editor/lib/src/editor_word/paint_run_text.dart)
  reconstructs logical source text, shapes it with Flutter `TextPainter`, then
  fits glyph boxes and caret positions to that shaped result.
- [`OfficeFontSet`](../packages/quds_office_engine/lib/src/fonts/office_font_set.dart)
  and [`OfficeHostFonts`](../packages/quds_office_editor/lib/src/embed/office_host_fonts.dart)
  already provide real face registration and explicit family fallback.

Kerning, ligatures, joining and combining sequences depend on neighboring
characters. Consequently, fitting text after pagination cannot by itself repair
a line break chosen from isolated-character widths. The inference from these
code paths is that sharing contextual advances is the most direct improvement
for this fork. Replacing the graphics backend would leave that contract
mismatch unresolved.

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
| Existing Flutter `TextPainter` / `dart:ui.Paragraph` | Contextual shaping, line metrics, selection and caret geometry, canvas text | Flutter BSD-3-Clause; retain the engine's third-party notices | **Use now in the editor.** Keep its font/style/direction inputs consistent with wrapping and painting. [API](https://api.flutter.dev/flutter/painting/TextPainter-class.html), [licensing](https://docs.flutter.dev/resources/faq) |
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

## First implementation contract

The intended increment adds an **optional, typed contextual measurement
callback** to the pure Dart layout layer and implements it using Flutter in
the editor. Keep the scalar callback/fallback working for existing clients
and headless export. The engine must not import `dart:ui` or Flutter.

1. Shape logical source text with the actual family/fallback, style, size and
   direction used for painting. Preserve fractional advances; avoid per-letter
   pixel rounding.
2. Return advances associated with source offsets/clusters. Combining marks,
   supplementary characters and joined emoji must not create arbitrary
   insertion or wrap positions inside a source grapheme.
3. Validate callback output before using it: correct source correspondence,
   finite nonnegative values and a complete usable result. Declining a run
   must fall back coherently rather than partly corrupting its geometry.
4. Preserve tabs, generated field/note labels, discretionary hyphens, bidi
   order, style boundaries and justified spacing. Display-only characters
   retain explicit source ownership.
5. Keep measurement and paint/caret policies aligned. A cached result must be
   invalidated when its text, style, font registration, direction or relevant
   layout context changes. Keep caches bounded and release ephemeral native
   paragraph resources.

Flutter documents explicit `TextPainter.dispose()` ownership and exposes
selection, caret, glyph and line metrics. These are the appropriate editor
primitives; introducing a separate text widget would violate the repository's
custom RenderBox document-surface architecture.
([TextPainter API](https://api.flutter.dev/flutter/painting/TextPainter-class.html),
[Paragraph API](https://api.flutter.dev/flutter/dart-ui/Paragraph-class.html))

This callback improves the editor's layout inputs. It does not by itself make
the headless PDF engine use Flutter shaping. A later shared glyph-run backend
would need to carry exact font identities, glyph IDs, advances/offsets,
cluster/source mappings and line-boundary context into both canvas and PDF
output. Font selection and PDF embedding capabilities remain explicit fidelity
boundaries.

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

Use local behavioral tests tied to the actual source revision: kerning and
ligature-sensitive wrapping, mixed fonts/styles, Arabic and mixed-direction
text, combining sequences/supplementary characters, tabs, hyphenation, caret
and selection ownership, malformed callback output and legacy fallback.
Compare independent Flutter measurements with layout results, and ensure a
regression fixture fails on the pre-change implementation where practical.
Test PDF/headless paths separately rather than inheriting editor results.

Use a fixed font corpus for visual comparisons and record font bytes, runtime,
platform and scale. Platform-specific raster differences are not evidence that
line-breaking or caret geometry is correct. Cache/performance claims require
their own measurements.

The [incoming baseline audit](validation/text-rendering-20261116/incoming-work.md)
accounts for all 132 fetched refs. This strategy document is a design/license
record, not a passing-test receipt. Subsequent validation records identify
implemented scope and results. Save incremental checkpoints to the remote work
branch, and proceed using local qualification without polling or waiting on
GitHub Actions.
