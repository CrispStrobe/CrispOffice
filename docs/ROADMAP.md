# Quds Office Suite — Roadmap (post Wave 4)

Waves 1–4 are implemented in-tree. Later work should keep [STANDARDS.md](STANDARDS.md)
and [MISSION.md](MISSION.md) honest as coverage changes.

## English/German offline thesaurus — 18 November 2026

The [thesaurus workstream](roadmaps/thesaurus/README.md) now includes full
OEWN 2025 and OpenThesaurus 17 November packs, deterministic compilation,
manifest/file verification, lazy offline lookup, bounded word-form support,
and guarded Word replacement. The dialog is available from Review, the
context menu and Shift+F7, with lookup-language override and actual source
notices. Lookup adds no proofing finding or undo entry; explicit replacement
uses one undo unit and preserves the existing source protections.

The [data notices](roadmaps/thesaurus/licensing-and-notices.md) document the
actual MIT-code / CC BY 4.0-and-WordNet-English / CC BY-SA 4.0-German boundary.
TH1–TH4 have source, compiler, provider, controller and UI evidence. TH5 still
requires installed-desktop and actual offline-browser acceptance plus
independent human linguistic review. The
[continuation report](validation/thesaurus-20261118/continuation/README.md)
records the completed local checks, measurements and environment blockers.

The [HF pipeline review](roadmaps/thesaurus/hf-pipeline-review.md) remains a
separate source/metadata audit. No combined school-vocabulary database or
additional corpus family is imported by the dedicated thesaurus packs.

## Proofing and German hyphenation — 16 November 2026

The accepted [P1–P8 proofing plan](PROOFING.md) now has implementations in the
fork: offline German spelling, source-preserving German hyphenation, seven
original writing checks, configurable terminology, Word squiggles/F7 review,
undoable suggestions and optional English Harper/mobile spelling adapters.
The shared contract keeps unavailable, unsupported, failed and successful
checks distinct. The engine remains pure Dart, with custom editor surfaces
and shared PDF layout.

The Word session traverses modeled body/table/frame, note, header/footer and
comment stories, honors language overrides and `noProof`, rejects stale results,
and guards generated fields, locked content and active IME composition.
Imported comments receive inherited proofing styles, including explicit
`noProof` resets. Generated page-number metadata invalidates old findings even
without a text edit. Corrections restore the active caret and selection through
undo/redo, and a dialog controller swap starts a fresh check without retaining
the old controller's notices. Personal vocabulary has an explicit host
persistence contract. Whole-story checking does not imply canvas navigation
to every auxiliary story; see the plan for user and host behavior.

Local component evidence records [231 engine hyphenation/layout/export tests
and 85 editor rendering/caret regressions](validation/proofing-20261116/continued-hyphenation/README.md),
[38 German core tests, ten compiled-JavaScript checks and exact dictionary
regeneration](validation/proofing-20261116/german-resume/README.md),
[19 proofing geometry/mobile-protocol tests](validation/proofing-20261116/continued-renderer/README.md),
and [real Harper native/Wasm, adapter and license checks](validation/proofing-20261116/harper-resume/README.md).
The final integrated source `ca294cf8668706b45f40031ed9a2db52e5737cd2`
passed all six local validation groups: toolchain identification, full-engine
fatal-info analysis, editor library/13 selected test-file fatal-info analysis,
host-library fatal-info analysis, **189 selected editor tests**, and the host
web build. The editor total includes 30 session, 33 correction and 13 dialog
tests. All 684 recorded source inputs remained unchanged during validation;
see the [final integration evidence](validation/proofing-20261116/integration-resume/README.md).
A separate [212-test engine reconciliation run](validation/proofing-20261116/continued-comments-and-merges/README.md)
passed, including comment styles, incoming ODS/Zotero behavior and exact
hyphenation regeneration. These are scoped checks, not a claim that every
repository test ran; overlapping suites are not summed.

The integrated commit reconciles `main` at `7edb096`, Zotero at `b6a6b4c`, and
the original proofing branch at `93c13aa`. The remote inventory covered 53
branches and 62 pull requests at the **2026-11-16 13:40:49 UTC** cutoff.
No GitHub Actions queue was waited for.

The German lexicon is finite and based on a pinned 2016 MIT word-list snapshot;
it does not provide complete morphology or contemporary universal vocabulary.
The experimental German ONNX model stays evaluation-only: its retained probe
matched 9/18 expected error corrections and changed 1/12 valid controls,
including Swiss spelling. No model inference is enabled in the application.
Browser startup was blocked before a page loaded, and Node transport/Wasm
checks do not establish browser HTTP/CSP/visual acceptance. Non-Linux native
Harper targets and real mobile dictionary behavior require separate acceptance.

The initial roadmap, license policy and acceptance criteria remain in
[PROOFING.md](PROOFING.md), with delivered data/component licenses, optional
backend installation, retained-versus-new evidence and coverage boundaries.

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
