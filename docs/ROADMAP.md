# Quds Office Suite — Roadmap (post Wave 4)

Waves 1–4 are implemented in-tree. Later work should keep [STANDARDS.md](STANDARDS.md)
and [MISSION.md](MISSION.md) honest as coverage changes.

## Proofing and German hyphenation — 16 November 2026

The accepted [P1–P8 proofing plan](PROOFING.md) is now implemented in the fork:
offline German spelling, source-preserving German hyphenation, seven original
writing checks, configurable terminology, Word squiggles/F7 review, undoable
suggestions and optional English Harper/mobile spelling adapters. The shared
contract keeps unavailable, unsupported, failed and successful checks distinct.

The Word session checks all modeled body/table/frame, note, header/footer and
comment stories, honors language overrides and `noProof`, rejects stale results,
and protects generated fields, locked content and active IME composition.
Personal vocabulary has an explicit host persistence contract. The dialog's
language and hyphenation controls save Word settings; full-story checking does
not imply navigation to every auxiliary-story canvas. See the plan's user and
host guidance for exact limits.

New local continuation evidence records [232 hyphenation/layout/export engine
checks](validation/proofing-20261116/hyphenation-resume/engine/hyphenation-validation.json),
[19 editor painting/note/small-capital checks](validation/proofing-20261116/hyphenation-resume/editor/receipt.json),
a fresh [38-test German core run with ten JavaScript checks and exact dictionary
regeneration](validation/proofing-20261116/german-resume/receipt.json), and
[real Harper native/Wasm, adapter and license checks](validation/proofing-20261116/harper-resume/receipt.json).
The [final integration receipt](validation/proofing-20261116/final/receipt.json)
records consolidated session/UI/context-menu, affected-package and release web
packaging checks. The [later remote audit](validation/proofing-20261116/final/remote-freshness.json)
and [reconciliation record](validation/proofing-20261116/final/reconciliation.json)
cover the concurrent ODS hyperlink, Zotero and sibling proofing work. All eight
incoming hyphenation cases are retained; they exposed and now cover LTR/RTL
caret and hit-testing fixes. Harper was rebuilt and verified after merging its
source-bound packaging and notice changes.
These are scoped, source-bound records; overlapping suites are not summed.
The earlier German core receipt and model probe are retained separately.
No GitHub Actions queue was waited for.

The German lexicon is finite and based on a pinned 2016 MIT word-list snapshot,
not complete morphology or contemporary universal vocabulary. The experimental
German ONNX model stays evaluation-only: its retained probe corrected 9/18
error cases exactly and changed 1/12 valid controls, including Swiss spelling.
No model inference is enabled in the application. Browser HTTP/CSP/painting,
non-Linux native Harper targets and real mobile dictionary behavior retain
separate acceptance gates; Node Wasm tests do not discharge them.

The initial roadmap and its acceptance criteria remain in [PROOFING.md](PROOFING.md),
with delivered component/data licenses, release behavior, retained-versus-new
validation provenance and remaining coverage boundaries.

## Office preservation continuation — 14 November 2026

The interrupted session described additional fixes, but those changes were not
present in remote `main` at `b0335829428d50968258219c4fdced15d546f7c9`.
The [scoped recovery plan](office-recovery-20261114.md) is the active checklist.
Work is saved incrementally to `codex/office-recovery-20261114` in this repository
and CrispCloud. Earlier test counts and coverage reports remain evidence only
for their recorded source snapshots.

The canonical formula, spreadsheet-style, Word-protection and signed-package
tasks (REC-01–04) are implemented and validated. The current source receipt
records 1,256 engine tests, 539 editor tests, 440 fidelity-tool controls, all 350
engine output files, and zero OpenXML schema errors in those 350 files. One
existing editor comparison test needs a local PDF fixture and remains skipped.
App lifecycle and actual-save acceptance also passed: 241 host tests, all 149
required output/reference files, zero schema errors in those files, and 16
independent render inputs across four first-save baselines. The scoped plan
records the exact source identities and the remaining browser/device/authentic
signature gates. Source and app results retain their separate evidence.

## Wave 1 — PDF correctness (done)

- Print ranges, Excel geometry, outline bookmarks, notes links, list/TOC paint
- See [STANDARDS.md](STANDARDS.md)

## Wave 2 — Word depth (done)

- Fields: `HYPERLINK`, `FILENAME`, `FILESIZE`, `AUTHOR`, `TITLE`, `MERGEFIELD`
- Deeper `numbering.xml` (multi-level counters, restart, `%1`…`%9` labels)
- Richer `styles.xml` (`basedOn`, fonts, document.styles round-trip, table grid-like styles)
- Justified caret/selection regression coverage in the editor

## Wave 3 — Excel & PowerPoint print (done)

- Excel PDF: print titles / repeating rows, true cell borders vs gridlines, header/footer tokens
- Formula stubs: `HYPERLINK`, `ADDRESS`, `CELL`, `INFO`, `FIXED`/`DOLLAR`, limited `ASC`/`BAHTTEXT`
- Pivot/PowerQuery naming kept honest (simple SUM pivot; CSV helper only)
- PPT: stroke outlines, hyperlink URI annots, chart `rtl` write from `ChartDisplay` / sheet RTL

## Wave 4 — Platform (done)

- Multi-face glyf embed via `OfficeFontSet` / `OfficeFontResolver` (CFF/`FontFile3` deferred)
- Optional `PdfSaveOptions` (`pdfA`, `tagged`) — no PDF file-encryption API (OOXML crypto remains)
- Optional PPT media package IO: `package:quds_office_engine/quds_office_engine_optional.dart`
- Mission Phase 1–5 restored in [MISSION.md](MISSION.md)

## Wave 5+ — PDF file program

Phase 6 landed: `PdfFile`, `QudsPdfViewer`, `QudsPdfEditor`, incremental
save, AcroForm fill, XFDF, page surgery, CCITT, Standard-14 / WinAnsi,
CFF→OTTO host wrap, ActualText, ViewerPreferences, layer toggle, Type 2/3
`sh`, struct reading order, signature ByteRange status. Remaining limits
(in-engine CFF raster, remaining JBIG2 arithmetic/symbol regions, JPX,
full CMS/PAdES trust, certified PDF/A) are in
[STANDARDS.md](STANDARDS.md). Contract: [PDF.md](PDF.md).

Widget composer follow-ups that landed after 0.3.1:

- `MultiPage` splits [Table] across pages and repeats `repeat` header rows;
  vertical columns flow as separate children so a nested table can span.
- `BoxDecoration.gradient` (`LinearGradient`) paints as color strips.
- `Chart` draws value labels, a y-axis guide, and a legend (bar / line / pie).

Still out of the widget composer (do not pretend): PDF axial shading objects,
package:pdf chart dataset API, barcode/svg, and MultiPage span inside a
single `Expanded` row.

- P6.1 COS + Standard encryption
- P6.2 Display list + `QudsPdfViewer`
- P6.3 Markup + incremental save + `QudsPdfEditor`
- P6.4 AcroForm + deeper fonts
- P6.5 Page surgery, OCG, XFDF
- P6.6 PDF/A–UA honesty, redact, signature verify
- P6.7 Studio + README + performance

Do not skip sub-phases. Do not route OOXML export through `PdfFile`.

## Architecture reminder

- `quds_office_engine` — pure Dart, no `dart:ui`
- `quds_office_editor` — Flutter `RenderBox` / `LeafRenderObjectWidget` only
- No `TODO` stubs; no `dynamic`; general-purpose fixtures only in tests
