# Office continuation — 17 November 2026

This continuation integrates incoming fork/upstream work and repairs PDF logical
text, replacement-text reading, font-map validation, and spreadsheet conditional
rule persistence. Work continues on `codex/text-rendering-20261116`, draft PR #72,
from `51cc65f1dc7ec860c0ff7324b73adda9d70a86ef`.

**Final local qualification: 877 passing tests across 57 test files**, with no
reported failures, errors or skips. Strict scoped analysis and formatting pass
in all three cohorts. All **195 references** in the final incoming snapshot are
included by ancestry. Checkpoints were saved incrementally with `[skip ci]`.
**No GitHub Actions jobs, checks or statuses were queried or awaited.**

## Incoming work and preservation

The first [inventory](incoming-inventory.json) pins 189 references / 128 distinct
commits at **2026-11-16 23:10:27 UTC**. All were integrated before new source work;
the [initial ancestry receipt](integrated-ancestry.json) records that result.

A bounded [final refresh](final-remote-refresh/comparison.json) found additional
work at **2026-11-16 23:28:30 UTC**, or **17 November, 00:28:30 Europe/Berlin**:

| Final snapshot | Named references |
| --- | ---: |
| Fork branches | 98 |
| Fork PR heads | 89 |
| Upstream branches | 4 |
| Upstream PR heads | 4 |
| Total | **195** |

These represent **132 distinct head commits**. The union of both observations
contains **200 reference/revision pairs and 135 distinct commits**, including
superseded tips. Every pinned commit remains in the ancestry. The cutoff is
explicit; later arrivals are outside this qualification.

The additional merges include main `50b3694e`, conditional-format documentation
and DXF styles from PRs #88/#89, protected-text and German proofing improvements
from `6cd04528`, and Zotero recovery/English notice work from `5adf034d`. Equivalent
vendor and original PR-head histories are also retained. Main's squash commits
alone would not preserve those exact PR heads.

The [final ancestry receipt](integrated-final-ancestry.json) records integration
head `b2dd1991` and equivalent vendor blobs. The only new production conflict was
in the conditional-rule constructor: the combined version retains our
priority/stopping metadata and the incoming fill/font/DXF fields. A native-style
regression verifies that combination through two saves. Initial rendering-evidence
conflicts are preserved byte-for-byte in [the incoming archive](incoming-rendering-conflicts/ARCHIVE.md);
their historical qualification does not become a new result for this source.

## Repairs and resulting behavior

### Authored text survives shaped PDF export

Word, worksheet and presentation export now write logical source text in
`ActualText` when it differs from the painted presentation. Tests cover Arabic
joining and lam-alef, bidi punctuation and controls, supplementary aliases,
wrapped source separators, small caps, manual hyphens, generated labels, and
headers/footers/tables/notes. Word reconstructs explicit source ownership without
borrowing visible text from sparse gaps. Drawing still uses the selected fonts
and existing shaped positions.

The 17 logical-export tests validate Quds extraction/search and unchanged painted
operations. The corrected comparison helper additionally serializes and reopens
valid control PDFs with indirect content streams, exact stripped content,
matching page geometry and nonempty drawing operations.

### PDF replacement scopes and selection bounds are consistent

Nested marked-content frames share the owning replacement span. A replacement
is consumed once, including an explicitly empty replacement, and its selectable
box covers all visible text showings in the scope. Hidden optional content does
not consume or enlarge it. The reader handles indirect property dictionaries,
UTF-16 literal strings and operators ending at EOF.

Generic rotated drawing uses the actual content-stream glyphs. The explicit
`PdfCanvas.showMarkedLine` helper retains its existing watermark reconstruction
policy through a separate `QudsLogicalLine` hint. Sixteen new reader tests cover
these contracts.

### Font character maps are validated before use

The SFNT parser checks table/subtable bounds, duplicate records, declared
lengths, segment/group ordering, Unicode ranges and glyph limits. Malformed
inputs fail with `SfntException`. Format 12 stores compact groups and uses binary
search rather than allocating a map entry for every code point while parsing.

An authoritative supported Unicode cmap takes precedence over legacy encodings.
The fallback policy for legacy tables is deterministic: Windows Symbol,
Macintosh, then other supported encodings. Unicode scalar restrictions are not
incorrectly applied to legacy byte-pair codes. Fifty-five new tests cover valid,
malformed, competing and very large range cases.

### Spreadsheet edits retain conditional-rule meaning and styling

Snapshots and rename operations include both formulas, rank, priority and
`stopIfTrue`. Rank/upper-bound/metadata edits now invalidate cached native rule
XML, and both formulas follow sheet-name rewrites. XML boolean word and numeric
spellings are accepted. Native expression predicates survive XLSX and ODS
interchange using the existing OpenFormula translator.

Regenerated rules preserve valid authored priorities, including precedence that
differs from XML order. Missing, duplicate or invalid values receive unused
positive Int32 priorities across the whole worksheet. Serialization does not
mutate the model's priority fields. Native stopping flags and differential styles
survive edits. The integrated DXF work restores decoded fill/font colors and
creates styles for fresh conditional-only workbooks.

Rename undo keeps later page-layout edits while still rejecting stale formula or
conditional metadata changes. Forty-four focused tests include a native DXF with
fill/font plus unmodeled bold/border properties; rank editing and two save/reopen
cycles preserve its original `styles.xml` exactly.

Expression predicates are preserved for interchange; the compact renderer does
not evaluate them. Native rule priority/stopping preservation does not claim a
new conditional-expression evaluation engine.

## Final local qualification

| Final cohort | Passing tests | Test files | Unchanged recorded inputs |
| --- | ---: | ---: | ---: |
| [Engine](engine/receipt.json): fonts/PDF, layout, spreadsheets/ODS, English/German proofing | **654** | **37** | **528** |
| [Actual Flutter editor](editor/receipt.json): fonts/PDF, wrapping/hyphenation and proofing UI | **196** | **17** | **584** |
| [Harper](harper/receipt.json): adapter and source/protected-span contracts | **27** | **3** | **496** |
| Total | **877** | **57** | — |

These are disjoint final cohorts, not a complete repository test run. Earlier
overlapping runs are excluded from the total. The engine receipt uses source
checkpoint `ea9f1b2f`; editor and Harper use `ac295d4b`. The intervening change is
the engine test-only PDF control repair plus its independent comparison script;
all recorded editor/Harper inputs remain identical to the final committed files.

Each receipt includes exact commands, resolved genuine runtime launchers and
binary hashes, before/after input hashes, optional input presence, timeout/result
records, and compressed logs. Static analysis covers changed Dart files, including
incoming native-test and web-smoke sources even where those runtimes are not run.
Selected tests, relative source dependencies, fixtures, package configuration,
manifests and analysis configuration are bound separately from runtime binaries.
Some inherited tests return early when optional host files are absent; those
absences are explicitly recorded and are not broader coverage claims.

The [runtime record](runtime/runtime-receipt.json) identifies genuine **Flutter
3.47.8 / Dart 3.13.7**, framework `737ba8f8`, engine `cf636b1d`, verified official
components and an unchanged enforced dependency lock. Restoration verified
529 selected Dart SDK archive members, four common archives, the native engine
archive and 162 pinned pub archives. It does not claim a fresh download of the
entire Flutter SDK archive. SDK tracked sources are unmodified.

[The independent verifier](verify_final.py) recomputes event counts, log hashes,
source/configuration closure, current and committed input bindings, runtime
identity, both pinned reference inventories and exact advertised remote-head
correspondence. Its [qualification receipt](source-qualification.json) records
the evidence checkpoint it audited; evidence-only publication can be audited
again against the final branch head without rerunning tests.

Harper's 27 fresh tests use injected transport. Native/Wasm acceptance and other
incoming intermediate journals retain their own earlier source attribution.

## Independent rendering results and their limits

The [Poppler receipt](engine/logical-render/poppler-receipt.json) compares the
final emitted PDFs with valid controls that omit replacement-text wrappers:

| Logical-text fixture | Raster dimensions at 120 dpi | Nonwhite pixels in each image | Differing pixels |
| --- | --- | ---: | ---: |
| Word | 993 × 1404 | 1,126 | **0** |
| Worksheet | 993 × 1404 | 5,323 | **0** |
| Rotated slide | 1200 × 675 | 222,854 | **0** |

The comparison rejects PDF-tool diagnostics, unequal image dimensions and empty
rasters before comparing pixels. All six PDFs have one page. Raw `pdftotext`
output is retained: **none of these three external extractions equals the exact
Quds logical sequence**. Poppler applies bidi controls/order and whitespace choices.
Exact Quds extraction assertions and external raster equality are separate
results; universal extractor parity is not claimed.

The three actual Flutter font-rendering tests also pass. [Unicode subset
metrics](editor/render/metrics.json) and [shared-glyph metrics](editor/render/shared-glyph-aliases.json)
show zero pixel differences between PDF-reopened fonts and directly generated
identical subsets. The distinct authored alias sequence remains exact. These
are synthetic supplementary aliases of Latin outlines, not real emoji/CJK font
coverage. The separate cross-cmap Latin reference still differs by **559 pixels**.

During qualification, the independent gate caught malformed control PDFs from
the first logical-export helper. Its preliminary zero-pixel comparison was
invalid: unequal images could be compared only over a 1×1 overlap. The helper
was repaired without production changes, and the engine cohort plus full-size
comparison were rerun. The [superseded run and correction record](attempts/pre-control-fixture-repair-engine/README.md)
are retained and excluded from final totals and parity claims.

## Negative controls, licenses and remaining architecture

The [negative-control archive](negative-controls/README.md) preserves three
separately attributed historical probes on the unmodified integration source:

| Baseline cohort | Real test cases | Assertion failures | Passes |
| --- | ---: | ---: | ---: |
| PDF reader and logical export | 33 | 30 | 3 |
| Safe cmap validation probes | 45 | 41 | 4 |
| Original conditional-rule probes | 28 | 17 | 11 |

They are not added to the final passing count and do not claim to run every final
test. Exact baseline test versions, parser/source bindings and compressed logs
are retained; the PDF baseline predates the later test-helper repair. The giant
cmap-range probe was deliberately not executed against the old eager parser.

This continuation changes no dependency manifests or font binaries and adds no
native shaping backend. Earlier reviewed MIT FontTools attribution, British
English MIT patterns and the identified American English Kuiken permissive grant
remain in place. The incoming Zotero branch adds exact pinned original US/GB
notice preambles and generation checks; the read-only generator check passed with
eight inputs unchanged, as recorded in [its receipt](negative-controls/english-generator/receipt.json).
The restricted underlying Oxford word list is not shipped. Poppler is an external
validation tool, not a linked or shipped engine dependency. See the [earlier scoped
license audit](../text-rendering-continuation-20261116/license-audit.md) and the
checked-in English notices under the engine's `third_party/hyphenation/`.

The [rendering strategy](../../text-rendering-strategy.md) retains Flutter for
the current editor. A shared font/glyph/position/source-cluster contract is still
needed for exact editor/headless shaping parity. This increment does not establish
universal paragraph/newline reconstruction, complete PDF marked-content support,
Type3/image-only replacement handling, full PDFDocEncoding, or per-character
selection inside a whole replacement span.

## Reproduction

Activate the recorded compatible Dart/Flutter runtime and enforced dependency
lock, then run from the repository root:

```sh
python docs/validation/office-continuation-20261117/validate.py --cohort engine --output docs/validation/office-continuation-20261117/engine
python docs/validation/office-continuation-20261117/validate.py --cohort editor --output docs/validation/office-continuation-20261117/editor
python docs/validation/office-continuation-20261117/validate.py --cohort harper --output docs/validation/office-continuation-20261117/harper
python docs/validation/office-continuation-20261117/verify_pdf_visuals.py --directory docs/validation/office-continuation-20261117/engine/logical-render
python docs/validation/office-continuation-20261117/verify_final.py --head FULL_PUBLISHED_COMMIT_SHA --branch codex/text-rendering-20261116 --output /absolute/scratch/final-office-audit.json
```

The verifier reads the advertised branch ref and Git objects. None of these
commands queries or waits for GitHub Actions.
