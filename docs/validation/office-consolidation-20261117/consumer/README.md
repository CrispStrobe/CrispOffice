# Independent consumers for the consolidated Office source

The complete consumer run passes **29/29 fixtures and 116/116 official ODF
XML-part validations** at published source
`f5021f1c364baf010049fda2dd4bf7f414deda79`, Git tree
`afd7a513dfa91472f58c27ead4d8be3f4b75c262`.

The run started on **17 November 2026 at 18:51:04 Berlin time** and finished at
**18:51:33** (17:51:04–17:51:33 UTC). All results below are fresh executions
against that source. Historical results and the separate development probe
are not added to these counts.

| Check | Accepted result |
| --- | ---: |
| Prior section/list/recovery fixture specifications retained exactly | 26/26 |
| New tab and table consumer fixtures | 3/3 |
| Complete independent consumer fixture run | 29/29 |
| Official ODF 1.3 XML parts | 116/116 |
| Source input hashes unchanged | 400/400 |
| Runtime input hashes unchanged | 10,420/10,420 |
| Archive members restored and hash-verified | 384/384 |
| Directly inspected final rasters | 7 |

The [full receipt](final-receipt.json) retains commands, versions, per-fixture
assertions, measurements and output hashes. The [archive index](consumer-index.json)
binds every file in [the evidence archive](consumer-f5021f1c.tar.xz).

## New independent checks

### Paragraph tabs retain distinct configurations

Nine otherwise identical adjacent paragraphs exercise two different left tab
positions, right and center alignment, dot/hyphen/underscore/plain leaders at the
same position, and repetition of the first configuration. LibreOffice's reopened
DOCX retains every exact tab position, alignment and leader choice.

The PDF independently establishes the positions below. The declared page-left
margin is 36 pt and the unchanged geometric tolerance is 0.4 pt.

| Paragraph target | Authored tab | Expected page coordinate | Observed coordinate |
| --- | --- | ---: | ---: |
| NearTarget | Left, 90 pt | 126 pt left edge | 126.100 pt |
| FarTarget | Left, 180 pt | 216 pt left edge | 216.100 pt |
| RightTarget | Right, 270 pt | 306 pt right edge | 306.054 pt |
| CenterTarget | Center, 200 pt | 236 pt center | 236.098 pt |
| UndottedTarget | Left, 220 pt | 256 pt left edge | 256.100 pt |
| RepeatedNear | Left, 90 pt | 126 pt left edge | 126.100 pt |

The gap between prefix and target contains **53 black pixels for dots, 112 for
hyphens and 188 for underscores**, versus **zero** in the plain gap. The sampled
region is fixed at 100–240 pt horizontally and follows the relevant text line.
LibreOffice's DOCX leader values distinguish the three characters; the raster
checks establish that each leader is actually visible. Poppler joins the leader
and following text into one word box, so geometric alignment claims for those
three targets rely on the reopened tab definitions rather than guessed
substring positions in that box.

### Row heights remain minimums

The first table row has an authored minimum of 18 pt and four text paragraphs
with exact 18 pt line spacing. All four lines appear in order. The following
row begins **73 pt** below the first line, confirming expansion beyond the
authored minimum. A second row contains one line but requests a 72 pt minimum;
the following row begins **72 pt** below it.

LibreOffice's reopened DOCX retains **18 pt and 72 pt** row heights with
`w:hRule="atLeast"`. It does not convert either minimum into a fixed-height
constraint. The exposed text following the table remains visible.

### Cell colors and borders survive normalization

Two mixed-case valid six-digit colors reopen as **ABCDEF** and **AA6611** and
produce the corresponding blue/orange PDF backgrounds. A third cell supplies
the invalid value `not-a-color`; its background is omitted, while all four
authored black, single, half-point borders remain. A plain neighboring cell
retains a white background and no exposed bottom/right border.

The independently reopened DOCX checks all four borders on each decorated cell.
Raster samples contain 1,653 and 1,708 pixels matching the intended colored
backgrounds; the invalid/plain samples remain predominantly white. Official ODF
validation additionally rejects invalid color syntax if it reaches an XML part.

## Earlier consumer coverage is preserved

The extended generator invokes the exact previous 26-fixture generator. Its
first 26 specifications are compared in full with the authenticated prior
manifest, SHA-256
`19bf753029ae5bf2549b451ee518b1d960478b2f6d6dc9af0f566037e4659845`.
The historical `check_fixture` function and the complete recovery checker remain
byte-identical. Original assertions and tolerances were not weakened.

The section/list/parity/frame checks, independent paragraph shading, actual
footer page numbers and complete styled title all pass again. The prior 540 pt
RTL edges, 18 pt line spacing and authored frame geometry remain covered by
their original assertions. PDF conversion keeps automatic blank pages with
`IsSkipEmptyPages=false`.

The three new fixtures, paragraph-decoration fixture, styled second-page footer
and both RTL fixtures were directly inspected; see [the visual review](visual-review.json).
All 29 fixtures were checked programmatically. This is bounded export consumer
coverage; it does not establish arbitrary ODF preservation, arbitrary border
styles or general Office interoperability.

## Runtime and reproducibility

The run used Dart **3.13.7**, LibreOfficeDev **26.8.0.0.alpha0** build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, Poppler `pdftotext` **25.03.0**,
and `pdfinfo`/`pdftoppm` **26.05.0**. The official OASIS ODF 1.3 schemas match
their existing pins:

| Schema | SHA-256 |
| --- | --- |
| Main ODF 1.3 | `40bad03efdbb02825230d357da0aa6ac679934c5bf56c6281752c0c24d58e4e6` |
| ODF 1.3 manifest | `8aee71f03484be112af972d622cc9031280c007b0a454ae8815e8e333c9bdd17` |

The source, dependency and runtime inventories are checked before and after the
run. The consumer uses the unchanged canonical workspace package configuration;
the application qualification's temporary analyzer configuration does not alter
its imports or identity checks. Source HEAD and every generated fixture remained
unchanged. The inherited nonfatal Pillow deprecation warning remains in the raw
stderr log; no command or fixture failed or skipped.

The archive is **937,068 bytes**, with **384 files / 2,890,900 uncompressed bytes**.
Its SHA-256 is:

`3c5c324e79581d0eb8fff4b0c829e54947f7c60281e288e6368476c6608319fd`

It contains generated ODTs, LibreOffice PDFs and DOCX files, Poppler text and
bounding boxes, rasters, every command's stdout/stderr, before/after identity
maps, exact historical and extended runners, schema inputs, the full receipt,
visual review and packaging script. Every archive member was extracted into a
fresh directory and checked for exact size and SHA-256; its member set matched
the index with no omissions or extras.

Restore the archive, prepare the recorded canonical workspace against the exact
source, and provide a fresh output directory. Adjust only environment paths:

```bash
python3 consolidation-runner/verify_consumers.py \
  --output /absolute/fresh/output \
  --schemas /absolute/restored/schemas \
  --dart /absolute/dart-sdk/bin/dart \
  --repo /absolute/canonical/workspace \
  --source-repo /absolute/source/checkout \
  --expected-head f5021f1c364baf010049fda2dd4bf7f414deda79
```

The consumer requires the same relevant tools/fonts for comparable geometry.
It verifies source HEAD, production-library cleanliness, package routing,
historical specifications, schema pins and all before/after input inventories.

No GitHub Actions, workflow, check-run or commit-status endpoint was queried or
awaited. Product source and HEAD were not changed by the consumer work.
