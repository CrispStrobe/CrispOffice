# Independent ODT recovery consumers — 17 November 2026

A fresh complete run passed **26 of 26 consumer fixtures** and **104 of 104
XML-part validations** against the official OASIS ODF 1.3 schemas. The accepted
source is [`966196f386ec1776c836664b3eb7c93e8e92605c`](https://github.com/CrispStrobe/quds_office_suite/commit/966196f386ec1776c836664b3eb7c93e8e92605c),
tree `4287330a433e915d58ca779adfacb75942c6ab04`.

The run took place on 17 November 2026, **17:19:50–17:20:08 Europe/Berlin**
(16:19:50–16:20:08 UTC). Historical passes are not included in these totals.
The [full receipt](final-receipt.json) records all commands, versions, per-fixture
assertions, measurements, source identities and output hashes.

| Check | Fresh result |
| --- | ---: |
| Original section/list consumer fixtures | 24 / 24 passed |
| New paragraph-decoration and live-footer fixtures | 2 / 2 passed |
| Official ODF XML parts | 104 / 104 passed |
| Source inputs unchanged before/after | 395 / 395 |
| Runtime inputs unchanged before/after | 10,420 / 10,420 |
| Generated fixture inventory unchanged | Passed |
| Frozen source HEAD unchanged | Passed |
| Evidence archive files restored and verified | 344 / 344 |

## What the two new fixtures establish

### Paragraph decorations stay independent

`paragraph-distinct-shading-borders` places three paragraphs next to one another
with otherwise equal paragraph properties. LibreOffice's reopened DOCX retains:

| Paragraph | Background | Four borders |
| --- | --- | --- |
| `RedShade` | `FF0000` | Blue `0000FF`, single, 0.5 pt |
| `GreenShade` | `00FF00` | Magenta `FF00FF`, single, 0.5 pt |
| `PlainUnshaded` | No fill | No borders |

The PDF raster independently contains the two intended fill colors around the
corresponding words: **3,522 red pixels** and **3,680 green pixels** inside the
specified text-line regions. The figure was also visually inspected. These
checks catch paragraph-style cache aliasing and unintended decoration carryover.
They do not claim arbitrary border widths, styles or malformed-color consumer
behavior; those are separate source/test concerns.

### Live footer page numbers keep their suffix and styling

`page-field-styled-footer` has two pages and the authored footer cache
`1  |  Al Tahreer Neighborhood Profile`. The independent PDF contains:

- Page 1: `1 | Al Tahreer Neighborhood Profile`
- Page 2: `2 | Al Tahreer Neighborhood Profile`

The token checks require the current page number followed by the complete title
on each page. LibreOffice's reopened DOCX retains a real `PAGE` field. Its visible
field-result and suffix runs are both **bold, blue `0000FF`, and 14 pt**. The
second-page raster contains **1,032 blue text pixels** in the measured footer
bounds and was visually inspected. The DOCX's cached result happens to be `2`;
the PDF's independently observed `1`/`2` values establish dynamic numbering.

The [official-schema check](page-number-schema-check.json) confirms that
`text:page-number` does **not** require an attribute: the number-format group,
`text:fixed`, `text:page-adjust` and `text:select-page` are optional. A minimal
ODF 1.3 document containing `<text:page-number/>` validates. The relevant primary
sources are the [official ODF 1.3 schema](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/schemas/OpenDocument-v1.3-schema.rng)
and [ODF 1.3 Part 3](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html),
section 7.3.4. Missing mandatory attributes were not the incoming field defect.

## Historical expectations were retained

The exact prior `runner-source/make_fixtures.dart` and `verify_consumers.py` were
restored from `final-consumers-cf60.tar.xz`. Their bytes match the archived hashes.
The first 24 newly generated fixture specifications equal the historical
specifications exactly. The historical `check_fixture` function is byte-identical
in the extended runner. No old receipt was combined with the fresh accepted run.

All original section geometry, normal headers/footers, parity, list labels,
continuous-section and indentation checks pass again. In particular:

- RTL section headings end at **539.916 / 539.911 pt**, against the original
  **540 pt** expectation, with an exact **18 pt** line step.
- Ordinary RTL paragraphs end at **539.903 / 539.931 pt** and start at **65.9 pt**,
  satisfying the original physical **540 pt right / 66 pt left** bounds.
- The leading picture is on its intended second page at **36 pt** from the left,
  measuring **39.75 × 21 pt** against the authored **40 × 20 pt** and the unchanged
  **1 pt** raster tolerance.
- The reopened text frame retains exactly **(60, 100, 180, 40) pt** page-relative
  position and dimensions.

PDF conversion retains automatic blank pages through `IsSkipEmptyPages=false`.
The two RTL rasters were visually inspected in this run, alongside the two new
recovery rasters. Per-fixture limitations from the earlier suite still apply:
this is bounded consumer evidence, not universal Office round-trip qualification.
Frame fill/outline/internal insets and arbitrary wrap behavior remain outside
its measured guarantees.

## Inputs, tools and evidence

The run used genuine **Dart 3.13.7**, **LibreOfficeDev 26.8.0.0.alpha0** build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, Poppler `pdftotext` **25.03.0**, and
`pdfinfo`/`pdftoppm` **26.05.0**. The runtime map includes **557 font files**.
The historical nonfatal Pillow `Image.getdata` deprecation warning is retained
in the top-level stderr log; no command failed or was skipped.

The canonical workspace's existing package configuration and lock were used
without dependency resolution. The runner verifies that its engine and legacy
parser libraries resolve to the frozen source checkout. Its input maps use the
canonical package configuration, so the separate test harness's temporary
source-root analyzer configuration does not alter or evade these guards.

The [evidence index](evidence/final-966196f3-index.json) binds all 344 members of
`evidence/final-966196f3.tar.xz`, **871,456 bytes**, SHA-256:

`9a4ff35ab6dd4dbfeee9964284360ec09c3919a28bb551296b3a5f18e7e33520`

The archive was restored into a fresh directory and every file's size and SHA-256
verified. It includes generated ODTs, LibreOffice PDFs/DOCX files, Poppler text and
bounding boxes, rasters, stdout/stderr logs, before/after source/runtime maps,
the exact original and extended runners, official schemas and their download
provenance, the receipt and the visual-review record. The receipt's raw output
hashes were verified separately before packaging.

The schemas were downloaded directly from OASIS and match the original pins:

| Schema | SHA-256 |
| --- | --- |
| Main ODF 1.3 | `40bad03efdbb02825230d357da0aa6ac679934c5bf56c6281752c0c24d58e4e6` |
| ODF 1.3 manifest | `8aee71f03484be112af972d622cc9031280c007b0a454ae8815e8e333c9bdd17` |

## Reproduction

Restore the archive and its exact runners, prepare the locked canonical
workspace against source `966196f3`, and regenerate local package paths when
using another host. Recorded absolute paths identify the accepted environment;
they are not portable configuration. Preserve the recorded tools and fonts to
compare the same geometry. Use a fresh output directory:

```bash
python3 recovery-runner/verify_consumers.py \
  --output /absolute/fresh/output \
  --schemas /absolute/restored/schemas \
  --dart /absolute/dart-sdk/bin/dart \
  --repo /absolute/canonical/workspace \
  --source-repo /absolute/checkout \
  --expected-head 966196f386ec1776c836664b3eb7c93e8e92605c
```

`--repo` is the prepared canonical workspace; `--source-repo` is its actual Git
checkout. Both must point to the selected source. The runner refuses a different
HEAD or dirty production libraries and verifies all before/after input maps.

No GitHub Actions, workflow, check-run or CI-status endpoint was queried or
awaited. These files were prepared without staging, committing or changing the
frozen product source.
