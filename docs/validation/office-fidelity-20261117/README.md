# Office fidelity continuation — 17 November 2026

This continuation integrates the recorded incoming histories, makes conditional
colors visible in the worksheet editor and PDF output, repairs native conditional
style edits, completes PDF text-string decoding, and preserves text and structure
in the incoming ODT/ODP writers. Work continues from
`74b6b39e7941ab351133023b4165cbd6101d2877` on
`codex/text-rendering-20261116`, with draft PR #72.

**The final local qualification passed 1,815 tests in 108 files.** All three
cohorts ran from the same published source checkpoint,
`a9516dd1b30e78b3b8d774b600ed54937f07773f`, using genuine Flutter 3.47.8 /
Dart 3.13.7. Strict scoped analysis and formatting passed, with no failures,
errors or reported skips in these final runs. The exact selected suites and
recorded inputs define this claim; it is not a complete repository run.

**No GitHub Actions jobs, checks or statuses were queried, polled or awaited.**
Incremental remote checkpoints use `[skip ci]`. No dependency manifest or font
binary changed from the starting checkpoint, and no native shaping backend was
added.

## Incoming work and preservation

The initial API inventory was captured on 17 November at 06:11:38–06:11:56 UTC
(07:11 Europe/Berlin). All branch and pull-request collections, including closed
PRs, were paginated through a terminal empty page. Its **204 references / 137
distinct heads** were included by ancestry in remote checkpoint
`b9dd6bab52d42f2e0e1e8b0c1bb8f7b5be8d3cea` before new implementation began.

A bounded second observation captured upstream at 06:26:01 UTC and the fork at
**06:26:03 UTC / 07:26:03 Europe/Berlin**:

| Source | Initial references | Refreshed references |
| --- | ---: | ---: |
| Fork branches | 103 | 104 |
| Fork PR heads | 93 | 94 |
| Upstream branches | 4 | 4 |
| Upstream PR heads | 4 | 4 |
| **Total** | **204** | **206** |
| **Distinct head commits** | **137** | **138** |

The two observations together preserve **213 reference/revision pairs covering
142 distinct commits**, including superseded tips. Every captured head is an
ancestor of the final source checkpoint. Later arrivals fall outside this
recorded cutoff. The initial compressed API responses retain both original
payload hashes and stored-file hashes; the refreshed inventory retains exact
`git ls-remote` observations.

Incoming integration includes main `6860985f`, ODT/ODP export PRs #92/#93, ODP
documentation PR #94 (`8221b008`), proofing `aadae32d`, and Zotero/ODT cached-field
work `bacce8e1`. The new German morphology, grammar, suggestions, locale handling
and source-context UI are covered by the selected fresh engine/editor suites.
Original PR heads and equivalent vendor histories are retained by ancestry.

Merge decisions retained the corrected PNG fixture, all conditional priority /
stopping / differential-style fields, the absence of an unauthored yellow fill,
and the shared ODF whitespace encoder. Incoming hidden-field suppression and
cached-result tests were combined with the inline-fallback and indent repairs.
See [initial inventory](incoming/README.md),
[initial integration](initial-integration.json),
[refreshed inventory](final-refresh/inventory.json), and
[conflict resolution](final-refresh/resolution.json).

The branch was published repeatedly with an expected parent and exact Git tree
verification. Milestones include initial integration `b9dd6bab`, test/runtime
evidence `b85b0569`, PDF and conditional core `deb18002`, ODF repairs `8ff124c6`,
editor/PDF conditional painting `6b350c3b`, refreshed integration and native DXF
edits `fa0f9c20`, archived qualification evidence `6d0bb0ab`, and final numeric /
rename repairs `a9516dd1`.

## Behavior changes

### Conditional colors reach the actual worksheet and PDF

The grid and worksheet PDF now use the same conditional resolver. It applies
authored precedence, resolves fill and font color independently, and honors a
matching `stopIfTrue` even when that rule supplies no visible style. Valid
priorities remain authoritative; invalid or duplicate priorities use the same
normalization as serialization. Font-only native rules no longer acquire an
invented yellow fill.

Supported expression rules evaluate relative, mixed and absolute references
from the applies-to anchor. The editor passes workbook scope for qualified
references and supported names; `ROW()` and `COLUMN()` use the evaluated cell.
Lookups do not create missing cells or mutate formula caches. Existing scalar
caches remain authoritative unless the value is null or still equals the formula
text; those uncached formulas can be evaluated without writing the result back.
This is not a new whole-workbook recalculation engine.

Sparse rank, percentage, average and duplicate checks scan stored cells and
cache per painting/export pass. The paths cover blank cells in the painted or
printed area, merged anchors and frozen panes. The public predicate-only
`matches` behavior remains separate from range-aware resolution.

Expression work is bounded to 8,192 UTF-16 source units, 1,024 tokens, 64 nested
parentheses / active cell recursion levels, 4,096 cells per range, and 8,192
reference reads per evaluation. Only the documented function set is eligible;
dynamic, volatile and array-generating functions decline evaluation. Numeric
operations reject nonfinite literals, caches and results with typed `#NUM!`
errors before they can become comparisons or Boolean matches. Standard bounded
math operations replace input-controlled power/logarithm loops, and rounding
rejects unsupported precision before integer conversion. Boolean functions
propagate typed errors and flatten range values with explicit scalar semantics.

See the [conditional-format guide](../../conditional-format-rendering.md) for
supported rules, cache semantics, limits and examples. Only solid fill and font
color are newly painted; preserved native borders, bold and other differential
properties are not newly rendered.

### Native conditional edits survive repeated saves

Changing an imported conditional color now copies or reuses an appropriate
differential style rather than mutating a shared original. Unedited rules retain
their styles. Unrelated bold, borders, number formats, theme-based properties
and foreign XML survive the color edit. An explicitly edited color becomes an
RGB override, while the original shared differential-style entry remains intact.
Removing an override preserves unrelated properties.
Metadata-only rule edits retain exact original `styles.xml` bytes.

New rules, including rules on newly added sheets in a native workbook, receive
valid differential-style IDs. Equivalent styles are reused on repeated saves.
The native conditional-state checkpoint advances after saving, so reverting a
previously saved color or formula does not incorrectly reuse stale source XML.

That checkpoint exposed a real rename/save/undo interaction during qualification.
Rename staleness now excludes the derived serialization checkpoint while still
checking actual conditional rules, source references and native metadata.
Saving therefore preserves valid rename undo/redo, while subsequent authored
formula or conditional edits still reject a stale prepared rename.

### PDF metadata and replacement strings share one decoder

COS text strings and inline/named `ActualText` use a shared decoder for complete
PDFDocEncoding mappings, BOM-marked UTF-16BE and PDF 2.0 UTF-8. Accent positions,
typography and the euro character no longer fall through a Latin-1 approximation.
Malformed surrogate sequences, odd UTF-16 tails, malformed UTF-8 and undefined
PDFDocEncoding slots recover predictably as U+FFFD. Existing C0 compatibility
behavior is retained.

PDF font character codes still use their own decoder. The text-string repair
does not change painted glyphs or the established replacement-span bounds.
UTF-16LE, guessed BOM-less UTF-8, language escape processing, Type3/image-only
replacement handling and complete marked-content conformance remain outside
this change. The exact policy and primary specification references are in
[PDF text-string decoding](../../pdf-text-string-decoding.md).

### ODT/ODP preserve whitespace and valid inline structure

The incoming writers share an explicit ODF whitespace encoder. Leading,
trailing, repeated and cross-run spaces, tabs and line breaks survive export;
CRLF and CR normalize to line breaks. Extraction and search decode explicit
whitespace while applying literal-whitespace collapse across the paragraph.
Empty and whitespace-only paragraphs, namespace aliases, CDATA, nonbreaking
spaces and Unicode are covered, with bounded expansion of explicit space counts.

Generic extraction limits decoded paragraph/cell content to 16 MiB; subsequent
presentation wrappers are outside that content cap. Search respects its exact
caller-supplied UTF-8 output budget, including separators.

ODT emits one valid `text-indent` value: hanging indentation takes precedence
over first-line indentation, and signed lengths remain valid. Image-less inline
visual fallbacks remain inline instead of nesting a paragraph inside a
paragraph. Incoming Zotero field handling suppresses hidden field instructions
and keeps visible cached results. These are bounded new-document writers, not
lossless native ODF editors.

## Final local qualification

| Cohort | Passing tests | Test files | Unchanged recorded inputs |
| --- | ---: | ---: | ---: |
| Engine: fonts/PDF, layout, spreadsheets/formulas/ODS, ODT/ODP, proofing and fields | **1,416** | **71** | **568** |
| Actual Flutter editor: rendering, worksheet/history, wrapping and proofing UI | **370** | **34** | **607** |
| Harper adapter and source/protected-span contracts | **29** | **3** | **500** |
| **Total** | **1,815** | **108** | — |

All runs started at 06:42:52 UTC and completed by 06:45:04 UTC on 17 November
(07:42–07:45 Europe/Berlin). Tests, `dart analyze --fatal-infos`, and
`dart format --output=none --set-exit-if-changed` succeeded in each cohort.
Analysis/format cover changed Dart files in the selected packages; the test
suite is broader. Source inputs, local dependency configuration, enforced lock,
runtime binaries and launchers were recorded before and after execution.
The documentation edit made during execution is outside those source inputs.

The six new regression files contain **192 cases**: 59 PDF text-string cases,
83 engine conditional-rendering cases, 20 native DXF/rename cases, 23 ODF text /
structure cases, and 7 real Flutter conditional-rendering cases. The seven
Flutter cases include six whole-image comparisons against independently styled
ordinary cells, with nonempty raster and exact-color checks, plus a real editor
workbook-scope check. These counts are included in the table, not added to it.

The [engine](engine/receipt.json), [editor](editor/receipt.json), and
[Harper](harper/receipt.json) receipts retain exact commands, selected files,
source and runtime hashes, compressed JSON event logs, analysis and format logs.
Some inherited tests return early when optional host fixtures are unavailable;
the receipts record those absences. No reported skips does not establish that
every optional host-dependent path ran. Harper's fresh cohort exercises injected
transport contracts; native/Wasm acceptance remains separately attributed to
the incoming historical evidence.

### Runtime identity

Flutter framework `737ba8f885dc774b53b442759999a312c9461e4e` and engine
`cf636b1dfb818dd6a3ff16e390e93b1a036969c8` identify the genuine runtime. Tracked
SDK sources are unchanged. The enforced dependency lock SHA-256 is
`344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.
The workspace activates 108 packages with 162 pinned external archives.

[Runtime evidence](runtime/runtime-receipt.json) distinguishes selected SDK
members, the native test engine, common artifacts, transparent launchers and
workspace activation. It does not assert that every member of a full Flutter
distribution was installed or checked. The independent review checks the
recorded SDK/common members and notes the harmless shared license-file variant
overwritten by another original SDK archive.

### Superseded attempts and defect controls

The [first combined qualification](attempts/pre-numeric-and-save-undo-repair/README.md)
at `fa0f9c20` is retained with its original source and logs: engine 1,380 passes,
Harper 29 passes, and editor 367 passes plus three rename/save/undo runtime
errors. Review also found an input-controlled numeric loop risk. The derived
checkpoint fingerprint and numeric operations were repaired, focused checks
passed, and all three cohorts were rerun from `a9516dd1`. Only those replacement
runs count toward the final 1,815 total.

[Historical defect controls](negative-controls/README.md) preserve exact test
versions and source snapshots: PDF text decoding produced 41 assertion failures
with 18 controls passing; conditional rendering 4 failures; ODF 21 failures with
1 passing control; native DXF editing 15 failures; and rename/save/undo 3 runtime
errors with 2 stale-edit controls passing. Two preliminary ODF fixture compile
attempts are retained and excluded. The numeric archive records source review
and 200 repaired-source focused tests; unsafe old numeric loops were not executed
as a negative probe. Historical and focused counts are never added to the final
cohorts.

## Independent artifact evidence

Fresh Poppler comparisons at 120 dpi compare each logical-text PDF with a valid
paint control after checking clean diagnostics, equal dimensions and nonempty
rasters:

| Fixture | Dimensions | Nonwhite pixels in each image | Differing pixels |
| --- | ---: | ---: | ---: |
| Word | 993 × 1404 | 1,126 | **0** |
| Worksheet | 993 × 1404 | 5,323 | **0** |
| Rotated slide | 1200 × 675 | 222,854 | **0** |

[The comparison receipt](engine/logical-render/poppler-receipt.json) retains
PDFs, PNGs, authored text and raw external extraction. Exact Quds logical-text
assertions and external raster equality are distinct results: `pdftotext`
applies its own bidi and spacing conventions, and its outputs do not exactly
equal the authored logical sequences.

The [conditional PDF check](engine/conditional-render/poppler-receipt.json)
independently renders the worksheet at 144 dpi. Its 1,191 × 1,684 image matches
the PDF page geometry, has 9,555 nonwhite pixels, contains 2,541 exact `#123456`
fill pixels and 9 exact `#ABCDEF` font pixels, and has zero pixels of the
overridden red fill. Independent text extraction finds cell value `8`. This
establishes visible conditional colors in that fixture, not editor/PDF parity.

The [ODF ZIP/XML check](engine/odf-fixtures/external-xml-receipt.json) verifies
all three regenerated fixtures: CRCs, first uncompressed `mimetype` entry,
well-formed content/styles/meta/manifest XML, exact expected paragraph text, and
the single `-18.00pt` hanging indent. It is not a full ODF schema validator or an
office-application rendering comparison.

The actual Flutter font-subset tests also pass. PDF-reopened and directly
generated identical subsets have zero differing pixels. The separate cross-cmap
Latin comparison retains its measured **559-pixel difference**. Synthetic
supplementary aliases do not establish real emoji/CJK coverage. See
[Flutter metrics](editor/render/metrics.json).

## Audit and reproduction

`verify_final.py` independently reconstructs event counts and selected suites,
verifies command and log hashes, matches before/after/current/committed source
inputs, checks runtime/lock identity, reconstructs incoming inventories, checks
all captured ancestry, and compares the exact advertised remote head and Git
tree. It binds fixture files and external verification receipts to committed
bytes, recomputes saved raster results and ODF semantics, and checks recorded
external command exits and log hashes. It does not rerun tests or access GitHub
Actions.

**The audit passed against published evidence checkpoint
`27c0a928a53cda7dcaa89e483fec23fd1c50e75d`**, tree
`f1e49bd6eb2c7f4548b1bd6cd7999d14e0ca298c`, at 06:51:41 UTC
(07:51:41 Europe/Berlin). The complete
[source qualification receipt](source-qualification.json) preserves that
checkpoint's result. The following documentation-only commit carries this
receipt without changing tested inputs; the same auditor is run again against
the final published head. The separate
[independent review](independent-final-review.json) also passed, reconstructing
all test lifecycles and 688 unique recorded inputs with no blocking findings.

With the recorded runtime and dependencies available, run from the repository
root into a new output directory to preserve these receipts:

```bash
python docs/validation/office-fidelity-20261117/validate.py --cohort engine --output /path/to/new/engine
python docs/validation/office-fidelity-20261117/validate.py --cohort editor --output /path/to/new/editor
python docs/validation/office-fidelity-20261117/validate.py --cohort harper --output /path/to/new/harper
python docs/validation/office-continuation-20261117/verify_pdf_visuals.py --directory /path/to/new/engine/logical-render
python docs/validation/office-fidelity-20261117/verify_odf_fixtures.py --directory /path/to/new/engine/odf-fixtures --output /path/to/new/engine/odf-fixtures/external-xml-receipt.json
python docs/validation/office-fidelity-20261117/verify_conditional_pdf.py --directory /path/to/new/engine/conditional-render
python docs/validation/office-fidelity-20261117/verify_final.py --head FULL_PUBLISHED_SHA --branch codex/text-rendering-20261116 --output /path/to/new/final-audit.json
```

The final auditor checks the committed evidence directories in this report;
new reproduction outputs remain separate. Poppler and Python/Pillow are external
validation tools, not shipped engine dependencies. Earlier license review and
original notices remain intact. Exact editor/headless shaping parity still
requires the shared font identity, glyph-position and source-cluster pipeline
described in the [rendering strategy](../../text-rendering-strategy.md).
