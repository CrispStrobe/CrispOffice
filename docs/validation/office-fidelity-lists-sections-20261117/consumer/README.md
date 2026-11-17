# Independent ODT list and section consumer checks

This directory contains a small source-generated qualification against the official OASIS ODF 1.3 schemas, LibreOffice, and Poppler. It distinguishes XML validity from observable page, text, list-marker, and paragraph geometry. No GitHub Actions jobs, checks, or commit statuses are queried or awaited.

## Accepted result

The final run used published source [`cf60a17bcd825dc9b4ecdf840d54e6a0271d3647`](https://github.com/CrispStrobe/quds_office_suite/commit/cf60a17bcd825dc9b4ecdf840d54e6a0271d3647), tree `4a1a29d5029d25da9700b56a1fd244f3f5679547`, from 15:36:41 to 15:36:56 UTC on 17 November 2026. All **24 semantic fixtures** and **96 XML-part validations** passed. All **392 source inputs**, **10,420 runtime inputs**, and generated fixture bytes remained unchanged during the run.

The [full receipt](final-receipt.json) records every command and per-fixture assertion. The [accepted evidence index](evidence/final-consumers-cf60-index.json) binds **309 archived files**, including raw outputs, full input inventories, and the exact runner sources. The archive is `evidence/final-consumers-cf60.tar.xz`, SHA-256 `25e826d37d837730c8af0efbc88e6e399823f5b0b5c22bc29911d15c2d2dfe9b`; all files were restored and hash-verified. No historical failed receipt was combined into the final passing result, and no heading expectation was relaxed.

The RTL section heading now ends at 539.916/539.911 pt, satisfying the authored 540 pt edge, with an exact 18 pt line step. The independent ordinary RTL control ends at 539.903/539.931 pt on the right and begins at 65.9 pt on the left, satisfying the authored 540/66 pt bounds. The leading picture occupies the intended second page with a measured left edge of 36 pt and raster dimensions 39.75 × 21 pt, within the declared 1 pt tolerance for its 40 × 20 pt source. The frame's reopened page-relative geometry is exactly `(60, 100, 180, 40)` pt.

The final heading, ordinary RTL paragraph, and picture rasters were visually inspected in addition to the programmatic checks. The other representative section/list rasters were inspected in the preceding recorded attempt; the full final suite's semantic assertions ran afresh. The checker emitted one non-fatal Pillow `Image.getdata` deprecation warning. The recorded Pillow/runtime bytes remain pinned; no tool failed or was skipped.

## Final scope

The source generator declares 24 named fixtures. Every fixture carries explicit page sizes and expected text locations; further checks are selected per fixture rather than implied for every document.

| Cases | Observable assertions |
| --- | --- |
| Section begins with list, nested content-control list, table, nested content-control table, picture, or text frame | Target page size, body text and section header/footer placement. The leading red picture is checked on the target page with its authored size and left edge. Frame text is checked on the new page, and DOCX import retains page-relative position and dimensions. |
| Empty section | Separate page with its authored page geometry and header, followed by the next section on its own page. |
| Equivalent continuous sections | No forced page break. An empty intervening section does not change any measured body-word coordinates. Equivalent picture or comment header content does not split the page. |
| Continuous section changes page geometry | Explicit page-boundary fallback, recorded as a limitation rather than continuous layout parity. |
| Odd/even starts after one or two prior pages | Physical target-page parity, automatic blank pages when required, and subsequent content on the immediately following page. LibreOffice DOCX import retains the requested odd/even section kind. |
| Section heading and ordinary RTL paragraphs | Exact 18 pt line spacing and physical asymmetric left/right indents; the heading retains direct paragraph formatting when it activates the section. |
| Skipped levels, initially nonzero levels, mixed markers, continuation/restart, complex labels, native start override | Visible marker text, expected sibling indentation and nesting, or explicit vertical order according to each fixture's declared expectations. |

Each generated package has `content.xml`, `styles.xml`, `meta.xml`, and `META-INF/manifest.xml` validated against the checksum-pinned official schemas in `schema-sources.json`. PDF rendering and DOCX import are separate consumer checks. Schema success alone does not establish visual fidelity.

## Reproduce locally

Use the repository's unchanged dependency lock and an activated package configuration. The checker rejects engine or legacy-parser package mappings to a different checkout. The declared Dart executable must be genuine; do not substitute a stub or silently change dependencies.

```sh
python docs/validation/office-fidelity-lists-sections-20261117/consumer/verify_consumers.py \
  --output /absolute/path/to/a/fresh/consumer-output \
  --schemas /absolute/path/to/the/two/official/schemas \
  --dart /absolute/path/to/dart
```

The checker hashes the selected engine and legacy-parser libraries, source manifests, dependency lock, activated package configuration, and the generator/checker before and after each run. It also hashes the Dart SDK, LibreOffice/Poppler runtime trees, font files, Python XML/image modules, schemas, and activated external dependency libraries. It preserves raw command output, generated ODTs, imported DOCXs, PDFs, Poppler text/bounding boxes, one inspected page raster per fixture, and the complete hash inventories. These hashes bind the reported run to the recorded files; they do not promise a completely hermetic operating system.

The tested LibreOffice build is LibreOfficeDev 26.8.0.0.alpha0, build `2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. The primary runtime provides Poppler `pdfinfo`/`pdftoppm` 26.05.0; `/usr/bin/pdftotext` reports 25.03.0. Exact executable paths, versions, and file hashes are in each receipt.

The PDF export filter explicitly sets `IsSkipEmptyPages=false`. LibreOffice otherwise suppresses automatically inserted blank pages in PDF output, which would hide the physical-page distinction that the odd/even tests are designed to measure. The property is documented in [LibreOffice's PDF command-line parameters](https://help.libreoffice.org/latest/en-GB/text/shared/guide/pdf_params.html?DbPAR=BASE&System=LINUX).

Page sizes allow 0.2 pt numeric/serialization tolerance. Text edges and sibling indentation allow 0.3 pt, line spacing allows 0.15 pt, and the empty-continuous-section comparison allows 0.1 pt per coordinate. The red-picture check allows 1 pt for 96 dpi raster boundaries, and reopened frame geometry allows 0.1 pt. The nesting check requires at least 10 pt of additional indentation. Expected word occurrences are unique, and all required visible list labels must match whole extracted lines.

## Preserved controls and failures

The historical baseline contains 20 fixtures: 19 semantic failures and one passing changed-page-size fallback, while all 80 XML parts passed their schema checks. Its actual checkout was `56dc162bf9a1003189e36e1f2a4678620c824546`; its ODT writer bytes match incoming commit `097475fbda96aa4a6497d92f28d10f1aa5f640b4`. It is preserved as `evidence/baseline-097.tar.xz` with its original 20-fixture generator/checker and an explicit index. The baseline used 392 source and 5,392 runtime input hashes; later harness revisions additionally bind activated external dependency bytes. The filename denotes the incoming writer baseline, not a claim that the baseline process ran at HEAD `097475f`.

A later complete attempt at `59b8d494fcc6a2bc1f527577f36b7aabc0b93b53` passed 22 of 23 semantic fixtures and all 92 XML parts. Its source tree is exactly `8f2bd001ef09e2bf8eba45f08701196d760e662f`, also published as `4fdac35c8da50e9c62ffab4a86dd2397c21186b4`. The actual receipt remains labeled with the commit it ran from. The full attempt, both original harness sources, and its 297-file index are preserved under `evidence/final-attempt-59b8*`.

The failed assertion exposed inherited RTL indentation behavior. On a 600 pt page with 36 pt margins and model indents left=30 pt/right=24 pt, physical right-aligned text should end at 540 pt. Both ordinary and section-start ODT paragraphs instead ended near 533.916 pt. A controlled diagnostic changed only the serialized horizontal paragraph margin values and moved the same text exactly 6 pt to 539.916 pt. The native DOCX control separately demonstrated that this LibreOffice build mirrors the native `w:jc=right` interpretation with `w:bidi`; it was not used as an ODT physical-edge oracle.

The writer was corrected to map the model's physical indents to ODF's directional paragraph margins. The original 540 pt assertion was retained. An ordinary RTL control additionally requires a 66 pt physical left edge. The directional behavior is explicitly described by the note in [ODF 1.4 Part 3, §20.440](https://docs.oasis-open.org/office/OpenDocument/v1.4/os/part3-schema/OpenDocument-v1.4-os-part3-schema.html#property-text_relative-tab-stop-position); generated files remain ODF 1.3 and are validated against the ODF 1.3 schemas. Diagnostic evidence is separately archived as `evidence/heading-diagnostic-4fd*`, with 394 source and 10,420 runtime hashes unchanged during its fresh run.

## Limits

These fixtures establish the listed section/list behaviors for the recorded tools and fonts. They do not qualify all ODT features, all consumers, unrestricted round trips, or Word/LibreOffice shaping equivalence. Complex cached list labels are preserved as literal visible labels; they are not converted into fully editable multilevel numbering definitions.

Equivalent comment headers are checked for page continuity and retained visible header text; the suite does not assert that LibreOffice shows auxiliary-story annotations. The picture check measures its target page, left edge, width, height, and red-pixel coverage; its vertical position follows the paragraph/header layout and is recorded without an independent authored-coordinate assertion. Frame page placement, imported geometry, and text are covered. Inherited frame limitations remain: this LibreOffice build supplies a default blue fill/outline when the writer omits these properties, and the model's default internal insets are not retained. Fill, stroke, internal insets, and arbitrary wrap behavior are outside this suite's accepted claims.

## Evidence reconstruction

The four `evidence/*-index.json` files retain exact archive hashes and per-file relative hashes. Verify an archive's SHA-256 before restoring it to a fresh directory, then compare the restored file set and every hash against its index. Source/runtime input hashes and original absolute paths are preserved in each `inputs.json.gz`; paths identify the recorded environment rather than promising identical installation paths on another machine. Each archive retains its original runner files, so historical receipts must be reviewed with those versions instead of the current expanded harness.

`checker-controls.json` separately records seven positive/negative checker controls against preserved artifacts: acceptance of the authored picture/frame, rejection of missing pictures, wrong picture page/size, and wrong or missing frame anchors. These are validation of the checker and are not counted as additional final consumer fixtures.
