# Text rendering continuation: implementation and local qualification

Date: **16 November 2026**. Final gate receipts were re-read at **20:04:50 UTC**.

This continuation improves TrueType subset integrity and preserves authored
Unicode when several characters share one PDF font glyph. The final local
engine and Flutter editor gates passed, as did independent PDF raster and text
extraction checks. The implementation keeps the existing Flutter editor and
adds no shipping shaping library or font asset. Shared positioned-glyph shaping
between the editor and headless export remains future work.

The [rendering strategy](../../text-rendering-strategy.md) explains the design
and current backend evaluation. The [scoped license audit](license-audit.md)
records the shipping-material comparison and retained attribution.

## Final outcomes

| Check | Observed result | Evidence |
| --- | --- | --- |
| Final engine cohort | **279 tests passed** across 19 test files; analysis with fatal infos and formatting checks passed; **399 input hashes unchanged** | [engine-final/receipt.json](engine-final/receipt.json) |
| Final editor cohort | **66 tests passed** across 8 test files using the actual Flutter test engine; analysis and formatting checks passed; **462 input hashes unchanged** | [editor-final/receipt.json](editor-final/receipt.json) |
| Independent PDF validation | Passed: exact raster equality and exact authored Unicode extraction from the encoded and Word-export PDFs; source and input snapshots unchanged | [poppler-final/receipt.json](poppler-final/receipt.json), [producer receipt](poppler-final/producer-receipt.json) |
| Differential baseline probes | 20 completed probes: **1 success, 10 failures, 9 errors** against the exact integrated pre-change source | [baseline/receipt.json](baseline/receipt.json) |
| Final source and evidence binding | **Passed, zero mismatches**: 483 unique recorded input files, 40 runtime evidence files, and ancestry of all 166 observed refs checked at `103a18d` | [source-binding.json](source-binding.json) |

The engine gate finished at 19:59:50 UTC, the independent PDF check at 20:02:07
UTC, and the editor gate at 20:04:19 UTC. These are scoped local qualifications,
not a claim that every test in the repository was run. The command arrays,
selected files, compressed logs, runtime artifacts, and input hashes are retained
beside each receipt. No GitHub Actions job, check, or status was used or awaited.

The earlier [engine gate](engine-attempt1/receipt.json) passed 169 tests and the
earlier [editor gate](editor/receipt.json) passed 66. Those cohorts overlap the
final runs; **their counts must not be added to the final counts**. The later
engine cohort also includes the affected ODS reader and legacy-reader suites
after incoming ODS changes were integrated.

## What changed

### TrueType subset structure and metadata

The subsetter now aligns glyph records before computing `loca` offsets, so
odd-length source records survive short-offset encoding. The short-versus-long
`loca` decision includes that padding. It retains complete composite component
records and instructions while remapping component glyph IDs. Bounded graph
processing and structural checks reject cycles, dangling component references,
and truncated glyph data with an SFNT error; invalid requested or cmap glyph
IDs are excluded rather than indexing outside the source glyph array.

The output retains font-wide `OS/2` metrics and embedding metadata while
recomputing Unicode repertoire flags and character extrema for the subset.
Code-page flags are cleared conservatively for partial subsets. A version 3
`post` table retains style metrics without stale glyph names or download-memory
estimates. These operations preserve the source buffers. Preserving embedding
metadata does not grant permission to embed an arbitrary supplied font.

The relevant implementation and regression probes are
[font_subsetter.dart](../../../packages/quds_office_engine/lib/src/fonts/font_subsetter.dart),
[font_subset_structure_test.dart](../../../packages/quds_office_engine/test/font_subset_structure_test.dart),
and [font_subset_unicode_test.dart](../../../packages/quds_office_engine/test/font_subset_unicode_test.dart).
This is targeted hardening of the exercised TrueType path, not a general font
sanitizer or a certification of every SFNT/OpenType format.

### Independent PDF character codes, glyph IDs, and Unicode

Office PDF exports now allocate a distinct CID for each mapped Unicode scalar,
including distinct scalars that use the same glyph. An explicit `CIDToGIDMap`
selects the embedded subset glyph, CID widths use that glyph's advance, and
`ToUnicode` maps the CID back to the authored scalar. This preserves search and
extraction without changing which outline the alias should paint.

Font resources are immutable once emitted and hold at most **65,535 mapped
characters**, with CID zero reserved. Larger repertoires split across bounded
resources and reuse an existing resource for already encoded characters. Font
construction validates that every encoding glyph ID is in range and agrees
with the target subset's Unicode mapping, rejecting mismatched subsets rather
than silently painting a different glyph. Existing callers that omit the
optional encoding retain the identity-mapped behavior.

The implementation is in
[pdf_font.dart](../../../packages/quds_office_engine/lib/src/pdf/pdf_font.dart),
[pdf_document.dart](../../../packages/quds_office_engine/lib/src/pdf/pdf_document.dart),
and [office_pdf_export.dart](../../../packages/quds_office_engine/lib/src/pdf/office_pdf_export.dart).
The [CID tests](../../../packages/quds_office_engine/test/pdf_cid_encoding_test.dart)
and [Office export tests](../../../packages/quds_office_engine/test/pdf_unicode_alias_export_test.dart)
exercise mapping, widths, validation, shared-glyph aliases, and actual resource
splitting/reuse. Word, worksheet, and presentation export paths are covered by
the engine cohort.

## Why the baseline matters

The baseline was an independent `git archive` of
`0d19b16e10c6bc8492f47880321df2d9f2561223`, after the initial incoming histories
had been integrated. The harness verified the baseline production-source blobs,
copied only the current regression probes and support fixture separately, and
resolved the unchanged dependency lock with the verified SDK. It checked that
Pub resolved the baseline engine itself. The original source stayed unchanged
and the probe hashes still matched the current probes at completion.

Against that source, the two probe files produced 1 success, 10 assertion
failures, and 9 errors. The recorded failures include short-`loca` truncation,
composite structure handling, absent subset metadata, Unicode alias loss, and
oversized resource handling. The errors include malformed-input and missing-table
paths; they are not presented as successful rejection tests. Those same probe
files pass in the final engine cohort.

This differential result establishes that the new probes detect the targeted
pre-change defects. It does not turn the deliberately failing baseline into a
qualification pass, establish a performance improvement, or prove complete
Unicode layout correctness. See [validate_baseline.py](validate_baseline.py)
and the [baseline receipt](baseline/receipt.json) for the exact comparison and
individual outcomes.

## What the rendering evidence proves

### Actual Flutter font loading and painting

The editor tests load font bytes reopened from exported PDFs through Flutter's
real `FontLoader`, then measure and paint with `TextPainter` and Canvas. They
compare the reopened font with a directly generated subset having the same
Unicode cmap. Both supplementary-character transport and several Unicode
aliases of one outline are exercised.

The [main render metrics](editor-final/render/metrics.json) record **zero differing
pixels** between those identical-subset paths. They also explicitly record
**559 differing pixels** against the separate Latin-cmap PDF subset reference, despite
equal measured widths. The [shared-glyph metrics](editor-final/render/shared-glyph-aliases.json)
record zero differing pixels for the corresponding shared-alias comparison.
The tests therefore establish PDF font transport and identical-subset rendering;
they do not establish original-font/subset or cross-cmap bitmap equality.

The editor's PDF text path reloads embedded font bytes and paints Unicode.
Its successful render is not by itself an independent test that a PDF renderer
follows the emitted `CIDToGIDMap`. The separate Poppler check addresses that
mapping boundary.

### Independent PDF rasterization and extraction

The [final Poppler receipt](poppler-final/receipt.json) compares
[encoded-aliases.pdf](poppler-final/encoded-aliases.pdf) with
[identity-glyph-reference.pdf](poppler-final/identity-glyph-reference.pdf).
They use the same embedded font and glyph placements; their character encoding
paths differ. At **72 dpi**, both rendered images are **320 × 112 pixels**, each
contains **2,109 nonwhite ink pixels**, and the exact RGB comparison finds
**zero differing pixels**. No alignment, rescaling, or pixel tolerance is used.

External `pdftotext` extraction from both the encoded PDF and the
[Word export](poppler-final/word-unicode-aliases.pdf) exactly matches
**`A😀𠀀AZ`**: `U+0041 U+1F600 U+20000 U+0041 U+005A`. The comparison removes
only trailing newline and form-feed characters from extracted text; authored
text is unchanged. The identity PDF is a raster control only: it deliberately
does not preserve the aliases for extraction.

The fixture maps supplementary emoji/CJK code points to existing **Latin
outlines**. It tests Unicode mapping and transport, not emoji/CJK font coverage,
color glyph rendering, or multilingual shaping. The result is one controlled
raster fixture at one resolution, not platform-wide rendering parity. The
producer receipt links these PDFs to the final engine run; the verifier also
records executable versions, commands, source/input hashes, PNGs, text, and
artifact hashes. Its recorded tools are `pdftoppm` 26.05.0 and `pdftotext` 25.03.0.

### Separate auto-hinting diagnostic

The [diagnostic receipt](autohint/receipt.json) holds outline and advance data
fixed while changing the cmap. It demonstrates cmap-sensitive auto-hinting in
Matplotlib 3.10.8's bundled **FreeType 2.6.1**, with equal native and unhinted
controls for the exercised glyphs. That is evidence about that diagnostic
runtime. It does **not** identify Flutter 3.47.8's exact native rasterization
cause or justify an original-font/subset bitmap-parity claim.

## State-of-the-art direction and license boundary

The current change keeps Flutter's existing text stack. The
[strategy](../../text-rendering-strategy.md) evaluates HarfBuzz plus ICU as a
conservative future native shaping route, the explicitly configured
Raqm/HarfBuzz/SheenBidi/FreeType-FTL route, and the modern
Parley/Fontique/HarfRust/Skrifa/ICU4X stack. That document includes pinned-source
checks, component roles, license choices, and remaining integration risks.
None of those candidate backends was added by this continuation.

The [license audit](license-audit.md) finds **no new shipping GPL/LGPL component,
package dependency, native binding, library, or font binary in the audited
rendering delta**. The nine manifests, fourteen bundled fonts, existing font
notices, and inherited lock contents were preserved within that comparison.
The numeric OpenType Unicode-range transcription from MIT-licensed FontTools
4.61.1 has its copyright and full MIT text retained in the new
[FontTools notice](../../../packages/quds_office_engine/third_party/fonttools/LICENSE).

The audit is scoped to the stated revisions and rendering changes; it is not
a certification of every inherited dependency. Poppler is an already-installed
external validation executable and is neither linked nor bundled by this
change. Its use does not imply that every development executable on the host
has a permissive license. Existing font licenses and embedding rights remain
separate from the licenses of the text-processing code.

The major architectural limit remains: export is still based on mapped code
points rather than a shared positioned-glyph result. Complete source-cluster
mapping, contextual ligatures, mark positioning, language/feature selection,
bidi ordering, shaping-aware line breaks, and identical editor/headless layout
are not established by these fixes. A future backend must carry the actual
resolved face, selected glyph IDs, positions, source clusters, variation inputs,
and line-boundary context through layout, subsetting, and PDF extraction.

## Incoming histories and durable checkpoints

The [initial inventory](incoming-inventory.json) observed **151 branch/PR heads**
and the initial integration reached `0d19b16`. The subsequent
[refresh inventory](incoming-refresh-before-merge.json) observed **166 refs**:
79 origin branches, 79 origin PR heads, four upstream branches, and four upstream
PR heads. Its 17 missing refs were classified against `59b69ac`, before the
later integration; that pre-merge snapshot must not be read as the final branch's
ancestry result.

The [merge review](incoming-merge-review.json) identifies the nine minimal
missing heads and proves that their reviewed integration at `6bf486e` yields the
same tree as the incoming-main merge,
`754fd323403c79e822f33421d132cdc9c022b0e4`. All eight non-main top-commit patches
match their corresponding main squash patches. Four conflicts occur across
two files: older capability wording in `docs/office-remaining-gaps.md`, and an
older insertion point in the ODS test file. Keeping the combined main-side
contents retains both filter and row-outline work. No production conflict
occurred.

Publication encountered a concurrent writer on the primary branch. Incoming
code was integrated there as `3a8306e`; the independently prepared `0634236`
contained the same code plus evidence. Both histories were reconciled into
`5ed98a0`. When the primary branch advanced again to `6a07cb8`, the reconciliation
was preserved on **`codex/text-rendering-20261116-continuation`** rather than
overwriting the concurrent work. The existing primary review is
[PR #72](https://github.com/CrispStrobe/quds_office_suite/pull/72).

The continuation also retains the documentation-only audit from `6a07cb8`,
including its `resume-audit/` evidence. The final engine and editor runs started
from `3a8306e`, and their source/input snapshots remained unchanged throughout
qualification. Later publication commits add documentation and evidence to the
same production/test bytes. Gate receipts retain their actual `head_before` and
`head_after` fields rather than substituting later publication identifiers.
The [binding verifier](verify_binding.py) checks the completed receipts, raw-log
hashes, current source, runtime bundle, preserved license inputs, and all 166
observed incoming heads against a fixed checkout.

### Completed source binding

The [source-binding receipt](source-binding.json) passed at
`103a18d4919cf830c6193c986648e16301b3b17d` with **zero mismatches**. It derives the
279 engine and 66 editor outcomes from the actual saved test-event logs, verifies
their raw log hashes, and binds the 483 unique recorded input files to the
working tree and committed source where tracked. It also verifies all 40 runtime
evidence files, preserved dependency/font inputs, independent PDF artifacts,
and ancestry of every head in the saved 166-ref snapshot. The subsequent
publication of this receipt and documentation does not change the tested
production or test bytes. The verifier's own SHA-256 is retained in the receipt.

The [first binding attempt](source-binding-attempt1.json.gz) is preserved. Its
only mismatch was an audit-script classification error: a repository-wide
manifest predicate counted 12 files against the expected nine project manifests.
All 12 were unchanged. The corrected verifier separately checks the nine root,
app and package manifests and the three historical validation-fixture manifests,
then requires their disjoint union to cover every tracked `pubspec.yaml` at both
revisions. No source, test, dependency, or expected byte comparison was relaxed.
This audit correction required no application test rerun.

## Runtime provenance and local reproduction

The tests used **Flutter 3.47.8 / Dart 3.13.7**. The framework source is the
unchanged official Flutter tag at
`737ba8f885dc774b53b442759999a312c9461e4e`; Dart and native Flutter artifacts came
from verified complete official archives. The offline launcher runs a CLI
kernel compiled from unchanged official Flutter tool sources with the official
Dart executable. It does not substitute a renderer or modify SDK source.

The [runtime README](runtime/README.md), [runtime receipt](runtime/runtime.json),
[archive checks](runtime/archive-integrity.json), and
[Pub cache receipt](runtime/pub-cache-receipt.json) retain download integrity,
actual version output, executable and kernel hashes, package resolution, and
the earlier setup attempts. Setup failures are recorded separately from
application test outcomes. The resolved lock SHA-256 is
`344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.

From the repository root in the qualified workspace, these commands create a
fresh reproduction directory and leave the retained receipts intact:

```bash
source /workspace/scratch/796b63b8623e/toolchain/env.sh

QUDS_VALIDATION=docs/validation/text-rendering-continuation-20261116
QUDS_REPRO=$(mktemp -d /workspace/scratch/796b63b8623e/quds-text-repro.XXXXXX)

python3 "$QUDS_VALIDATION/validate.py" \
  --cohort engine \
  --output "$QUDS_REPRO/engine"

python3 "$QUDS_VALIDATION/validate.py" \
  --cohort editor \
  --flutter /workspace/scratch/796b63b8623e/toolchain/flutter_cli.sh \
  --output "$QUDS_REPRO/editor"

python3 "$QUDS_VALIDATION/verify_pdf_rendering.py" \
  --input "$QUDS_REPRO/engine/render" \
  --output "$QUDS_REPRO/poppler" \
  --producer-receipt "$QUDS_REPRO/engine/receipt.json"
```

On another machine, supply the corresponding genuine SDK/launcher and resolve
the pinned workspace before running the same harness. The engine and editor
commands run tests, analyze the affected Dart files, check formatting, and bind
inputs before and after. `verify_pdf_rendering.py` requires Python/Pillow and
external `pdftoppm`/`pdftotext`; its output directory must be new or empty.
Use the exact command arrays and `validate-used.py` copies in a receipt directory
when reproducing that historical run rather than the current harness version.

The separate [baseline harness](validate_baseline.py) requires an isolated
archive of its fixed baseline with the source manifest described in the script.
It verifies those blobs before copying probes; it should not be pointed at the
active working tree. Its expected failing outcomes remain differential evidence,
not an acceptance gate.
