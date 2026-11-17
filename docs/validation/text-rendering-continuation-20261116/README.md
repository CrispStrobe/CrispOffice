# PDF character encoding and integrated text qualification

This continuation repairs Unicode extraction and TrueType subset defects, then
integrates incoming Office and proofing work through a fixed source cutoff. The
work is preserved on `codex/text-rendering-20261116` in
[PR #72](https://github.com/CrispStrobe/quds_office_suite/pull/72).

**Final qualification passed: 626 tests across 47 files, with no failures,
errors or skips.** All three cohorts passed strict analysis and formatting.
The tested production/test tree is
**`c6aab884eb478672d36da5c03cd20873d7e8c42c`**. Later checkpoint changes contain
only evidence; the [independent source qualification](source-qualification.json)
binds the receipts, logs and retained rendering artifacts to the committed
source. Each cohort's before/after/current input hashes match.

The genuine **Flutter 3.47.8 / Dart 3.13.7** runtime, official component hashes,
restoration method and successful enforced lockfile resolution are preserved in
[runtime provenance](runtime-resume/README.md) and its
[ready receipt](runtime-resume/runtime-ready.json). Historical full-archive
verification and this resumption's verified selected components retain their
separate attribution.

## Rendering repairs

A glyph ID identifies a font outline; several Unicode scalars can share that
outline. Using glyph IDs as PDF character codes previously collapsed those
scalars into one `ToUnicode` entry. Painting could look correct while extraction,
copy and search returned incorrect text.

[`PdfCidEncoding`](../../../packages/quds_office_engine/lib/src/pdf/pdf_font.dart)
assigns each supported scalar a deterministic character code/CID, reserving zero
for `.notdef`. An explicit `CIDToGIDMap` selects the actual subset glyph, widths
are indexed by CID, and `ToUnicode` preserves the authored scalar. Immutable maps
and subset-binding checks prevent serialization against incompatible font bytes.
The [writer](../../../packages/quds_office_engine/lib/src/pdf/pdf_document.dart)
emits the mapping stream; the
[Office exporters](../../../packages/quds_office_engine/lib/src/pdf/office_pdf_export.dart)
use its codes. Repertoires exceeding 65,535 mapped characters split across font
resources, with existing assignments reusable. Low-level identity encoding
remains available to callers.

The [subsetter](../../../packages/quds_office_engine/lib/src/fonts/font_subsetter.dart)
aligns glyph records before choosing short `loca` storage, preventing odd byte
offsets from rounding down and truncating outlines. It discovers and remaps
composite dependencies without recursive outline expansion, rejects missing
components and cycles, and checks truncated simple/composite records. `OS/2`
typography, weight/style and embedding metadata survive; Unicode coverage and
character extrema are recomputed. Partial subsets clear legacy code-page claims
conservatively. Version-3 `post` metadata avoids stale glyph names; hint-program
tables remain preserved. Earlier supplementary-Unicode cmap and UTF-16BE
`ToUnicode` fixes remain in place.

The [structural](../../../packages/quds_office_engine/test/font_subset_structure_test.dart),
[CID](../../../packages/quds_office_engine/test/pdf_cid_encoding_test.dart) and
[export regressions](../../../packages/quds_office_engine/test/pdf_unicode_alias_export_test.dart)
cover malformed fonts, ownership, metadata, aliases, incompatible subsets,
Word/sheet/presentation output and the 65,536-character resource boundary.

## Integrated source and preservation

The final inventory cutoff is **2026-11-16T20:10:54.959Z**. Its
[ancestry check](integration-185/ancestry-remote.json) includes **185/185** observed
heads, representing **126 distinct commit SHAs**: 92 fork branches, 85 fork PR
heads, four upstream branches and four upstream PR heads. No objects or ancestors
are missing at published integration `c6aab884`. Later arrivals are outside this
fixed snapshot.

The [merge receipt](integration-185/merge-receipt.json) records five clean merges:
pinned main `63194d8e`, English `377e312a`, German `3ebe347f`, Zotero recovery
`b87f9d6c`, and combined proofing `bdd752e0`. Earlier
[166-head integration](resume/integrated-ancestry.json) and
[patch-equivalence evidence](resume/complete-patch-equivalence.json) remain
available. Incoming ODS work includes page setup and header/footer roundtrips,
alongside earlier filter predicates, row groups and geometry fixes.

The [English/German review](integration-185/late-proofing-review.json) found no
merge or license blocker. English automatic hyphenation dispatches `en`/`en-US`
to US patterns and `en-GB` to British patterns, preserving original UTF-16
positions and existing discretionary-hyphen fitting. Protected text,
mixed-language words and unsupported dialects are skipped. German changes add
bounded compound spelling repair and guarded finite verb-agreement rules; the
existing lexicon is unchanged.

The [Harper review](integration-185/late-harper-review.json) covers source mapping
after soft-hyphen removal, grapheme-safe findings, host-owned vocabulary and
asynchronous revision checks, plus additional dialect labels. These changes
touch shared Word presentation paths, so the expanded gates include contextual
measurement, shaped wrapping, hyphenation, correction geometry and proofing UI.

Implementation, recovered evidence and integration checkpoints were saved
incrementally. Checkpoint `bc195165` preserves the earlier completed local
gates. **GitHub Actions were not queried, polled, awaited, or rerun.**

## Final local qualification

The [runner](validate.py) records the exact commands, captured harness,
compressed logs, event summaries and input hashes before/after execution.
Production libraries, selected tests/support, fonts, manifests, lockfile and
package configuration form each cohort's input boundary. The source target above
has **411 engine, 482 editor and 392 Harper recorded inputs**. Successful
qualification requires passing commands and unchanged inputs.

| Integrated cohort/check | Result | Evidence |
| --- | --- | --- |
| Engine: 27 files covering fonts/PDF, bidi, ODS, English/German proofing and Word measurement | **407 passed** | [Receipt](qualified-engine/receipt.json) |
| Editor: 17 files covering loading/painting, surfaces, fallback, shaped wrapping, hyphenation and proofing UI | **196 passed** | [Receipt](qualified-editor/receipt.json) |
| Harper: 3 files covering provider, source text and source contract | **23 passed** | [Receipt](qualified-harper/receipt.json) |
| Strict analysis and formatting for the scoped changes | **All six static checks passed** | Cohort receipts above |
| Final source/input and retained-artifact binding | **Passed: source, logs, artifacts and 185 refs** | [Qualification](source-qualification.json) |

The 407 engine, 196 editor and 23 Harper tests form **626 disjoint final
tests**. These are scoped cohorts, not the full repository suite. Overlapping
historical and repeated runs are not added together. The runner retains the
incoming 60-second progress reports, 900-second test/analyzer limits and
120-second format limit with process-group cleanup. Captured runners preserve
the exact scope of each historical invocation.

### Completed evidence retained with its original attribution

Before the 185-head integration, the [engine gate](engine-final/receipt.json)
passed **171 tests** across 17 files with **397 unchanged inputs**. The
[editor gate](editor-final/receipt.json) passed **66 tests** across eight files
with **462 unchanged inputs**. Both passed strict analysis and formatting.
Engine source was `6a07cb8f`; the editor's HEAD advanced from that commit to
evidence checkpoint `f23675a` while its hashed inputs stayed unchanged. These
results do not independently qualify the later proofing/ODS changes.

The recovered [169-test engine run](engine-attempt1/receipt.json) also passed.
The [resumption audit](resume-audit/receipt.json) verified its artifacts and log
hashes. Against baseline production `0d19b16`, the same 20 probes produced
**10 assertion failures, nine errors and one success**. That
[baseline receipt](baseline/receipt.json) reproduces the defects; it is an
expected failure comparison. The audit verified 508 baseline source paths and
all three probe/support files. The restored pinned lock matches SHA-256
`344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.

### Flutter painting and independent PDF evidence

The final real Flutter tests used `FontLoader`, `TextPainter` and `Canvas`.
[Shared-glyph aliases](qualified-editor/render/shared-glyph-aliases.json) retained the
exact scalar sequence, measured **209.84375** logical pixels, painted **3,355 ink
pixels**, and produced **zero differing pixels** between the PDF-reopened subset
and a directly generated subset with the same cmap.
[The supplementary-Unicode fixture](qualified-editor/render/metrics.json) measured
**170.6875** logical pixels for both reference and subset, with zero differences
against the identical direct subset. It differed from the Latin reference by
**559 pixels**; original-font/cross-cmap bitmap equivalence is unclaimed.
The [rendered diagnostic](qualified-editor/render/unicode-subset-preview.png)
shows both rows and the comparison's scope.

The [independent Poppler rerun](resume-audit/poppler-recheck/receipt.json) compared
CID-encoded output with an identity-glyph raster control: **zero differing
pixels**, **320 × 112 at 72 dpi**, **2,109 nonwhite pixels** each. Visual review
found clean, unclipped outlines. Extraction from both the encoded PDF and Word
export returned **U+0041 U+1F600 U+20000 U+0041 U+005A** exactly, removing only
trailing U+000A/U+000C. No Unicode normalization was applied. The identity PDF is
only a raster control because its legacy extraction collapses aliases.

Artifact/producer hashes, 11 scoped rendering source/font/probe inputs and
the producer lock matched the audited integration. The final [source qualification](source-qualification.json)
binds that retained evidence to the final tested source. Fresh engine fixture
bytes exactly match the inputs already rendered by Poppler. Synthetic aliases
use Latin outlines; they establish neither actual emoji/CJK coverage nor full
shaping parity.

## Licenses and remaining scope

The [license audit and integration addendum](license-audit.md) record no new
production dependency, native binding, font binary or GPL/LGPL component.
Existing bundled OFL fonts remain unchanged. The numeric OS/2 table transcription
retains its complete
[MIT FontTools notice](../../../packages/quds_office_engine/third_party/fonttools/LICENSE).
Installed Poppler is an external validation tool, not a shipped dependency.

Incoming handwritten proofing code is MIT. New
[English pattern data](../../../packages/quds_office_engine/third_party/hyphenation/ENGLISH.md)
is specifically **Kuiken-permissive for US** and **MIT for GB**, with original
grants preserved in source and generated comments. The restricted underlying
OUP word list is not shipped. Both upstream sources match pinned commit
`5684c0f5`; the deterministic
[generator](../../../packages/quds_office_engine/tool/proofing/generate_english_hyphenation.py)
`--check` passed: US 4,938 patterns/14 exceptions; GB 8,527/8. German and Harper
add no dictionary/native dependency. This is a scoped delta review, not a license
certification of the inherited dependency closure.

The Harper cohort uses **injected transport**. It does not establish fresh
native or Wasm backend acceptance; no Harper backend binary is installed in the
restored runtime. Historical backend receipts retain their original attribution.

The [strategy](../../text-rendering-strategy.md) keeps Flutter for the current
editor and evaluates HarfBuzz/ICU and Parley/HarfRust/Skrifa for shared shaping.
Raqm requires an eligible SheenBidi/FreeType-FTL configuration and pinned audit.
No shaping backend is introduced here. Word/PDF still needs a shared contract
for exact font identity, positioned glyphs, source clusters, language/features
and line-boundary context. Complete Unicode/SFNT/PDF conformance, cross-platform
parity and performance gains remain unestablished.

## Reproduction

Activate the recorded runtime and unchanged locked workspace first. From the
repository root, use fresh output directories so the committed evidence remains
available for comparison:

```sh
python3 docs/validation/text-rendering-continuation-20261116/validate.py --cohort engine --output ../quds-local-validation/engine
python3 docs/validation/text-rendering-continuation-20261116/validate.py --cohort editor --output ../quds-local-validation/editor
python3 docs/validation/text-rendering-continuation-20261116/validate.py --cohort harper --output ../quds-local-validation/harper
```

The editor command uses `flutter` from PATH; `--flutter` accepts the verified
launcher recorded in the runtime report. The committed
[independent verifier](verify_final_qualification.py) checks the three saved
`qualified-*` cohorts, source/receipt hashes and rendering/ancestry evidence
without rerunning tests or contacting GitHub Actions.
