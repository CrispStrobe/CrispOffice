# Text rendering strategy and license review

Reviewed and implemented: **16–17 November 2026**. Original integration baseline:
`bfb24bf57d5efd52f00ab7079b4ac8968259a478`.
The backend/license review below was refreshed against pinned upstream sources
on the same date; it does not add or enable a native backend.

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
records the first increment's tested revisions, commands and results.

### Follow-up: embedded font identity and Unicode export

The [second increment](validation/text-rendering-followup-20261116/README.md)
extends the existing stack with concrete PDF fixes. Embedded viewer fonts now
use full-content hashing plus exact byte equality and owned snapshots, so two
files with identical length and a few matching sampled bytes cannot select
the same face accidentally. All waiting viewers are notified, and retained
layers repaint after reattachment. Retained Dart deduplication snapshots are
bounded; this does not bound Flutter's native font registry.

The pure-Dart font subsetter now retains supplementary Unicode through a
format 12 cmap, corrects the format 4 length, and avoids its 16-bit length
overflow. PDF ToUnicode destinations use UTF-16BE surrogate pairs. Real
Flutter tests load fonts reopened from exported PDFs and verify Unicode,
source outlines, advances and the raster output of identical Unicode subsets.
These changes add no production dependency or font binary.

The encoding choices follow the
[OpenType cmap specification](https://learn.microsoft.com/en-us/typography/opentype/spec/cmap)
and [Adobe's ToUnicode tutorial](https://pdfa.org/norm-refs/5411.ToUnicode.pdf).
Format 12 carries a superset of BMP mappings when both subtables are present;
large sparse sets use format 12 alone instead of emitting a corrupt format 4.
Older readers restricted to format 4 do not gain support for that overflow case.

### Continuation: TrueType structure and independent PDF character codes

The [continuation report](validation/text-rendering-continuation-20261116/README.md)
records the next implementation and its local qualification. Office PDF exports
now allocate a distinct CID for each mapped Unicode scalar, even when several
scalars share one font glyph. A real `CIDToGIDMap` stream maps these character
codes to the embedded subset's glyph IDs; widths and ToUnicode use the same
encoding. Word, worksheet and presentation exports therefore preserve authored
aliases for extraction and search. Font resources are immutable once emitted,
limited to 65,535 mapped characters, and split/reused for larger repertoires.
Low-level writer callers can retain their existing identity encoding.

The subsetter aligns glyph records before writing `loca`, retains and remaps
composite dependencies without recursively expanding their outlines, and rejects
cycles, dangling references and truncated records with typed errors. It preserves
font-wide OS/2 metrics and embedding metadata while recomputing Unicode coverage
for the subset, and retains post style metrics in a version 3 table. The numeric
OS/2 interval transcription carries the upstream FontTools MIT notice; no
FontTools runtime or new native dependency is introduced.

The independent PDF fixture compares explicit CID mapping with an identity-mapped
reference containing the same embedded font and positioned glyphs. It checks
actual PDF raster output and Unicode extraction separately. Synthetic emoji/CJK
code points deliberately alias a Latin outline in this fixture; they test mapping
and transport, not emoji/CJK font coverage or a new shaping backend.

A separate cmap-only diagnostic found that changing font character coverage can
change autohint output in Matplotlib 3.10.8's bundled FreeType 2.6.1 even when
all glyph outlines, IDs and metrics remain identical. Its native-hinting and
unhinted controls stayed identical. That result establishes a mechanism in that
runtime; it does not identify Flutter 3.47.8's exact cause or establish general
full-font/subset raster equality. Shared positioned-glyph shaping and exact
editor/headless parity remain separate future work.

### 17 November continuation: logical PDF text and bounded font maps

The [office continuation report](validation/office-continuation-20261117/README.md)
records the next integration and local qualification. PDF drawing still uses
the existing selected font, shaped code points and positioned glyphs. When
those differ from the authored text, a separate `ActualText` span now carries
the logical source. Word spans compose explicit glyph-owned source ranges,
synthetic presentations and generated labels without borrowing visible text
from sparse gaps. Worksheet and slide spans use the breaker's logical source
ranges; omitted wrap separators remain available for copy and search.

The reader shares one replacement owner through nested marked content and
accumulates its selectable box across the covered text showings. Generic
replacement metadata no longer changes rotated painting. The explicit
`PdfCanvas.showMarkedLine` watermark helper retains its existing Quds logical
painting policy through a separate `QudsLogicalLine` hint. Other readers keep
using the same content-stream glyphs and may apply their own extraction order
and whitespace conventions.

The cmap parser now checks declared subtable boundaries, group/segment order,
Unicode ranges and glyph limits before accepting a mapping. Format 12 remains
compact instead of allocating one map entry per scalar during parsing.
Supported Unicode tables take precedence over legacy mappings; among legacy
tables the deterministic fallback order is Windows Symbol, Macintosh, then
other supported encodings. This fallback order is an application policy.
Malformed tables fail with `SfntException`; no native dependency is added.

These changes preserve logical text within the tested source spans and wrapped
single-paragraph paths. They do not establish a shared shaping pipeline,
universal paragraph/newline reconstruction, or complete PDF marked-content
conformance. Selection boxes cover whole replacement spans, not independently
positioned source characters. At that checkpoint, Type3/image-only replacement content and full
PDFDocEncoding remained separate reader work. The report distinguishes exact
Quds extraction from external text-extractor behavior and records independent
PDF raster comparisons.

### Further 17 November continuation: text decoding and worksheet colors

The [office fidelity continuation](validation/office-fidelity-20261117/README.md)
adds one shared PDF text-string decoder for COS metadata and inline or named
`ActualText`. It handles PDFDocEncoding accents/typography and BOM-marked
UTF-16BE/PDF 2.0 UTF-8 consistently, with documented malformed-input recovery.
Font character codes still use the separate font decoder; this change does not
alter painted glyphs or replacement-span selection bounds. See the
[text-string policy](pdf-text-string-decoding.md) for exact compatibility choices.

Worksheet grid and PDF output now share the
[conditional color resolver](conditional-format-rendering.md). It respects
authored precedence, independent fill/font contributions and stopping rules;
supported expressions use a read-only bounded formula context. Sparse rank,
percentage, average and duplicate rules scan stored cells. Numeric guards reject
unrepresentable calculations and extreme rounding precision before they can
control loops or become misleading Boolean matches. The resolver uses existing
formula caches and evaluates uncached formulas; it is not a new full-workbook
recalculation engine.

Native conditional color edits create or reuse differential-style copies while
preserving unrelated original properties. Saving a derived conditional-state
checkpoint no longer invalidates worksheet rename undo; authored model edits and
native reference/metadata edits still have stale-operation checks. Native
bold/border and other unmodeled differential properties are preserved, without
claiming new rendering support for them.

The incoming ODT/ODP writers also use a shared explicit-whitespace encoder, and
ODF extraction/search now decode those elements with bounded expansion. The ODT
path keeps visible cached field results, suppresses hidden field instructions,
and emits valid inline fallback and indentation structure. These are bounded
new-document writers, not lossless native ODF editors.

These changes add no dependency manifests, font binaries or native shaping
backend. Exact editor/headless font identity, selected glyph positions and
source-cluster parity still require the shared shaping pipeline described below.

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
| Raqm + HarfBuzz + SheenBidi + FreeType | Native bidi/script itemization and positioned glyph output | Raqm MIT; HarfBuzz Old MIT; SheenBidi Apache-2.0; FreeType **FTL** | An eligible configuration when SheenBidi is selected explicitly and the resulting dependencies are audited. The default FriBidi build does not meet this review's no-GPL-family policy. [Pinned Raqm license](https://github.com/HOST-Oman/libraqm/blob/08ee1537e63f93bf926498e12b12ed15ee383216/COPYING), [SheenBidi license](https://github.com/Tehreer/SheenBidi), [glyph API](https://host-oman.github.io/libraqm/raqm-Raqm.html#raqm-glyph-t) |
| COSMIC Text + Swash | Rust text layout/editing primitives and font scaling | MIT OR Apache-2.0 for both projects | Another permissive Rust option; compare script coverage, font fallback and editor integration against the same corpus. [COSMIC Text](https://github.com/pop-os/cosmic-text), [Swash](https://github.com/dfrg/swash) |
| SheenBidi | Standalone Unicode bidirectional algorithm | Apache-2.0 | A focused candidate if replacing the custom bidi component independently of shaping. [Project and license](https://github.com/Tehreer/SheenBidi) |

The Rust option has production evidence beyond a new-library claim: Chrome's
official **24 April 2026** update reports Fontations use for Linux/Android
system fonts from Chrome 136 and removal of FreeType from Blink in Chrome 145.
This supports the maturity of Skrifa's font processing and outline work;
Parley's layout and HarfRust's shaping need their own qualification. Chrome's
adoption does not establish Quds editor/PDF parity or a performance result.
([Chrome's migration report](https://developer.chrome.com/blog/memory-safety-fonts))

DirectWrite and CoreText can be host/platform adapters, but their APIs and
system components do not constitute a portable MIT/BSD library that Quds can
redistribute identically on every target. They are not required for this
increment. [Pango](https://gnome.pages.gitlab.gnome.org/gtk/Pango/) and
[FriBidi](https://github.com/fribidi/fribidi) identify LGPL-2.1-or-later licenses;
this review excludes them under the conservative no-GPL-family policy. No GPL
implementation is proposed.

### Verified Raqm configuration

The Raqm source fetched for this review is **0.11.0**, commit
[`08ee1537e63f93bf926498e12b12ed15ee383216`](https://github.com/HOST-Oman/libraqm/commit/08ee1537e63f93bf926498e12b12ed15ee383216).
Its [Meson options](https://github.com/HOST-Oman/libraqm/blob/08ee1537e63f93bf926498e12b12ed15ee383216/meson_options.txt)
define `sheenbidi` with a default of `false`. Its
[build logic](https://github.com/HOST-Oman/libraqm/blob/08ee1537e63f93bf926498e12b12ed15ee383216/meson.build)
selects SheenBidi with `-Dsheenbidi=true`; the other branch selects FriBidi.
The same file requests HarfBuzz without GLib/GObject/Cairo when building its
fallback dependency. Those fallback defaults do not certify an externally
installed HarfBuzz or FreeType library: inspect the actual linked dependency
closure and preserve the selected FTL and other notices.

This is source verification of an available configuration, not a completed
Quds build or deployment. Raqm's output supplies font glyph IDs, positions and
source clusters. It still needs Quds font fallback, line breaking, PDF mapping
and target-specific packaging; it is not an office pagination engine.

### Rechecked backend decision

The follow-up review retains **HarfBuzz plus ICU as the conservative native
shaping candidate**, and **Parley/Fontique, HarfRust and Skrifa/Fontations as
the Rust candidate to evaluate**. Parley's current documented stack includes
Fontique, HarfRust, Skrifa and ICU4X. Its repository also identifies differently
licensed test/benchmark assets. These facts support a qualified evaluation
before replacing the current editor.
([Parley README](https://github.com/linebender/parley),
[ICU4X Unicode-3.0 license](https://github.com/unicode-org/icu4x/blob/main/LICENSE))

HarfRust needs a more precise assessment than its unversioned README alone.
At the inspected commit
[`26f5a7682d5c846a99e702c8b883a8d0113085b3`](https://github.com/harfbuzz/harfrust/commit/26f5a7682d5c846a99e702c8b883a8d0113085b3),
the [workspace manifest](https://github.com/harfbuzz/harfrust/blob/26f5a7682d5c846a99e702c8b883a8d0113085b3/Cargo.toml)
reports version 0.16.0 and includes an MIT
[`harfrust_capi`](https://github.com/harfbuzz/harfrust/blob/26f5a7682d5c846a99e702c8b883a8d0113085b3/harfrust_capi/README.md)
that builds static/shared C libraries. It exposes positioned shaping output,
font scale/variation settings, and optional Skrifa drawing/painting and Skera
subsetting. This is a possible Dart FFI entry point, without writing a Rust
bridge from scratch. It has documented API gaps and behavioral differences:
custom Unicode callbacks are unavailable, allocation failure aborts, and
font/table callbacks must be thread safe. Its optional outline API does not
expose hinting. None of these features has been built or qualified for Quds.

The pinned
[`HARFBUZZ.md`](https://github.com/harfbuzz/harfrust/blob/26f5a7682d5c846a99e702c8b883a8d0113085b3/HARFBUZZ.md)
still records nine Arabic fallback failures from **24 August 2026**, but the
same revision's
[`arabic.rs`](https://github.com/harfbuzz/harfrust/blob/26f5a7682d5c846a99e702c8b883a8d0113085b3/harfrust/src/ot/shaper/arabic.rs)
now constructs and applies an Arabic fallback plan. The historical count is
not evidence of nine current failures, and source inspection is not proof of
full conformance. The
[pinned README](https://github.com/harfbuzz/harfrust/blob/26f5a7682d5c846a99e702c8b883a8d0113085b3/README.md)
still documents Graphite and experimental feature gaps. Run the actual selected
release against the office corpus,
including malformed fonts and Arabic fonts without OpenType substitutions.
This review makes no comparative throughput or memory claim.

Flutter's documented `GlyphInfo` exposes grapheme ranges, layout bounds and
direction; it does not expose the exact font identity and positioned glyph
IDs required by the current PDF embedder. Consequently, a `TextPainter`
measurement result alone cannot be promoted to an exact, selectable PDF glyph
run. This is an inference from the public API surface.
([GlyphInfo](https://api.flutter.dev/flutter/dart-ui/GlyphInfo-class.html),
[Paragraph](https://api.flutter.dev/flutter/dart-ui/Paragraph-class.html))

A shared backend must connect the whole path: exact font bytes/face index,
variation coordinates, glyph IDs, advances and offsets, source clusters,
feature/language settings, line-boundary context, subsetting and final PDF
emission. Preserve the original logical text and its UTF-16 indexing separately
from visual glyph order. A shaping cluster
may span multiple editing graphemes or produce multiple glyphs. The current
PDF emission path still resolves glyphs by code point, so an unused result
type or a measurement-only FFI adapter would not close that gap.
([HarfBuzz cluster contract](https://harfbuzz.github.io/working-with-harfbuzz-clusters.html),
[Quds PDF emission](../packages/quds_office_engine/lib/src/pdf/office_pdf_export.dart))

HarfBuzz's `UNSAFE_TO_BREAK` output identifies boundaries that require
reshaping. A complete export path must subset the glyphs actually selected
by shaping, including glyphs with no direct character mapping, and preserve
logical extraction for ligatures and multi-glyph clusters. Better advances
alone do not implement these behaviors.
([Shaping output and break safety](https://harfbuzz.github.io/getting-started.html))

The next adoption should pin concrete versions and enabled features, audit
their complete code/data/font dependency and notice set, and qualify fixed-font
Latin kerning, ligatures, Arabic joining/marks, bidi text, fallback clusters,
discretionary hyphens and PDF extraction locally. The existing permissive
project licenses are an eligibility check, not a completed audit of a future
build. No native/Rust backend is enabled by the present changes.

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

The engine records original scalar/font advances before the first host
measurement. An actual shortened fragment restores those values before asking
the host again, so a declined fragment cannot silently retain widths from the
longer context. This also preserves zero-width lam-alef continuations and
generated-label scales; selected hyphens keep their independent metrics.

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
Paint extraction also replaces the inherited gap-length heuristic with source
ownership checks. Omitted invisible controls and unselected soft hyphens stay
in the logical text even across long gaps, preserving UTF-16 hit/caret offsets;
omitted visible text belonging to another sparse run is excluded even when its
gap is short.

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
honor Reserved Font Names for redistributed font modifications, and do not sell
the fonts alone. The official FAQ permits full or subset embedding in documents;
its document-embedding rules differ from distributing a modified font for reuse.
Font derivatives retain OFL; documents created with them do not inherit it.
([Official OFL 1.1 terms](https://openfontlicense.org/open-font-license-official-text/),
[OFL FAQ, embedding and subsetting](https://openfontlicense.org/ofl-faq/))

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
accounts for all 132 initially fetched refs. A later refresh reconciled all
138 refs pinned at 2026-11-16 15:23:50 UTC; the
[ancestry receipt](validation/text-rendering-20261116/integrated-ancestry.json)
verifies that each is included in qualified source revision
`4c1d71adea066bd5ee4d510a8b60b79b64f96a49`.
This strategy document records the implemented design and license decisions.
The [validation report](validation/text-rendering-20261116/README.md)
is the source of truth for the final tested revision, exact local commands,
broader regression results and remote checkpoints. Local qualification proceeds
without waiting for GitHub Actions. PDF/headless behavior and performance need
their own evidence and do not inherit the editor geometry results.
