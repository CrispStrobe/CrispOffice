# Office fidelity resume — 17 November 2026

This continuation resumes the saved `8106752e` source and completes new local
qualification after integrating later work. The working branch remains
`codex/office-fidelity-20261117`, with draft PR #101. No GitHub Actions, check,
or commit-status endpoints are queried or awaited. Checkpoint messages use
`[skip ci]`.

## Incoming scope, saved before implementation

The snapshot captured **232 named references / 155 distinct head commits**:

| Source | References |
| --- | ---: |
| Fork branches | 121 |
| Fork PR heads | 103 |
| Upstream branches | 4 |
| Upstream PR heads | 4 |

The fork observation completed at **17 November 2026, 15:03:11 Europe/Berlin**;
upstream completed concurrently. Synthetic PR merge refs are excluded. The
[exact observations](incoming/) preserve each ref, SHA, and observation time.
Across this and the three earlier observations, **245 reference/revision pairs
covering 167 commits** are retained, including superseded tips.

The integration adds main `3458c897`, ODT comment PR #103 and its original/vendor
history, Zotero landing PR #102, morphology qualification/license evidence, and
updated GECToR qualification tools/evidence. The ODT merge retains the repaired
note resolver and table/story behavior while adding the incoming comment
writer once. Duplicate older note helpers and duplicate comment loops were
excluded during conflict resolution. Incoming evidence remains intact.

The saved integration is **`fc44377279ced4589e637360e5f67501012e022c`**. Every
captured head is an ancestor. The Git tree was verified byte-for-byte against
the local integrated result before updating the remote branch with its expected
previous head. Later remote arrivals are outside this finite qualification
cutoff.

## Fidelity improvements

The [export guide](../../odf-export-fidelity.md) describes the exact mappings and
limits. The resumed changes address two independently reproduced defects:

- **Comment stories:** visible main-body anchors take precedence over hidden or
  auxiliary occurrences; recursive annotations and note expansion are bounded;
  ambiguous definitions do not silently bind to an arbitrary body. Author,
  initials, date text, formatting, line breaks, lists, links, and media are
  retained in valid ODF structures. A LibreOffice-specific hyperlink-text loss
  is repaired without adding text to the source model.
- **Presentation rotation:** text and picture frames rotate about the authored
  center with explicit affine transforms. Rotated tables use cell text frames
  because the tested consumer ignores native table rotation. Ordinary tables
  remain structural tables; rotated-table native editability is an explicit
  limit of the visual fallback.

The inherited paragraph spacing, merged/empty/ragged tables, headers/footers,
notes, slide transitions, conditional formatting, and logical PDF text work
remain in the integrated source and selected local validation scope.

## Reproducible local qualification

Activate genuine Flutter 3.47.8 / Dart 3.13.7 and the recorded unchanged workspace
lock, then use the existing [bounded-cohort harness](../office-fidelity-continuation-20261117/validate.py).
It runs engine, actual Flutter editor, Harper, and JavaScript/Node cohorts in
separate invocations. Engine/editor test batches use two workers and release
compiler temporary files between batches. Every output directory must be fresh.

The source closure, fixtures, SDK, full Flutter artifact directory including
fallback fonts, stock launcher internals, compiled Flutter tool, activated
dependencies, and exact lock are bound before and after each cohort. Authored
Dart is strictly formatted and analyzed; generated proofing data retains its
manifest-pinned bytes and remains in strict analysis. Runtime setup provenance
and readiness smoke results are saved [separately](runtime/); smoke results are
not final-cohort counts.

[generate_fixtures.py](generate_fixtures.py) requires a passed engine receipt for
the saved source, then combines test-generated packages with the supplementary
ODF fixtures in a fresh directory. [verify_consumers.py](verify_consumers.py)
checks the exact generated inventory against official OASIS schemas and fresh
LibreOffice/Poppler outputs. Independent receipt review reconstructs counts
from raw events rather than trusting runner summaries.

## Final local results

All four cohorts ran from the same published product source,
**`07481e944799e282f15e6286192b926cff1165df`**, tree
`771ba003a0fa805ee40b8585c0c4691f73a9c044`. Their local HEAD, source inputs,
complete runtime inputs, and dependency lock remained unchanged throughout.
Later checkpoints contain evidence, documentation, and the isolated consumer
oracle correction described below; production Dart and selected tests remain
identical to this qualified source.

| Cohort | Reported passing cases | Test files | Recorded source inputs |
| --- | ---: | ---: | ---: |
| Engine | **1,938** | **88** | **1,120** |
| Actual Flutter editor | **370** | **34** | **1,200** |
| Harper adapter/contracts | **29** | **3** | **1,031** |
| **Main cohorts** | **2,337** | **125** | — |
| JavaScript/Node repetitions | **132** | **6** | **1,038** |
| **Total reported executions** | **2,469** | **131** | — |

Node repeats six engine test files; it is not an additional 132 unique cases.
The new regression coverage is **58 cases**: 35 comment cases and 23
presentation-transform/table cases. These all run on both VM and Node.

Every final cohort passed strict scoped analysis, formatting, exact batch/suite
coverage, and input checks, with **zero reported failures, errors, or skips**.
Eighteen generated proofing-data files are excluded from formatting only; their
exact manifest-pinned bytes were verified before and after and remained in
strict analysis. Two inherited tests in `pdf_file_test.dart` return early when
`/home/mohammed/Desktop/al_tahreer_profile.pdf` is absent: the TrueType-cmap and
JPEG-with-DCT-soft-mask host cases. This fixture is absent here. Runner success
does not establish that those optional fixture assertions ran.

The [independent audit](independent-review.json) reconstructed all counts from
raw event streams and verified **1,302 unique source inputs**, **8,607 unique
runtime inputs**, the actual package import/source closure, unchanged lock,
framework/executable pins, and all captured ancestry. It also checks literal
Unicode separators inside JSON test names correctly. Development controls,
setup smoke tests, interrupted historical runs, and auditor self-tests are
excluded from the totals. The [published-tree audit](published-tree-review.json)
then passed against evidence checkpoint `9400b6ec`, checking the same recorded
source/runtime inputs and incoming ancestry after the reports and artifacts
were saved remotely.

The [incoming GECToR Python tooling run](evidence/ancillary/gector-tooling.log)
separately reported 18 passing tests and one optional converter-control skip. This is ancillary tooling evidence, not a
qualification of the native/model backends and not part of the Dart totals.

## Independent office and PDF evidence

The [consolidated consumer qualification](consumer-qualification.json) covers
**43 named ODF fixtures / 172 XML-part validations** against the official OASIS
ODF 1.3 schemas. It combines 27 general Word/slide fixtures with 16 centered
rotation fixtures. The 16 rotation fixtures cover positive and negative angles,
text, an asymmetric picture, LTR/RTL/ragged/empty rotated tables, and authored
outlines. Wrapped and full-turn angles are additionally covered by the VM/Node
regression tests.

The consumer is the recorded LibreOfficeDev 26.8.0.0.alpha0 build, with Poppler
used for raster and text measurements. The rotation run independently binds
**6,730 unchanged inputs**, including **557 font files**, LibreOffice/Poppler,
Dart, source, configuration, and Python image/XML dependencies.

The [independent consumer review](independent-consumer-review.json) reconstructed
the composition and verified 7,758 current file hashes, including the complete
rotation manifests and 1,122 fixture-generation source inputs. It found no
blockers. Some general fixtures have schema and import coverage without an
additional semantic assertion; the recorded per-fixture checks define the scope.

Measured results include:

- A 120 × 40 point frame at (60, 80), rotated +90 degrees, appears at the exact
  bounds **(100, 40)–(140, 160)**. The old writer's fixture disappeared from the
  slide. Asymmetric picture colors establish clockwise direction separately
  from the rectangle's symmetric bounds.
- **33 color/geometry checks** pass. A two-point authored outer outline has the
  expected bounds **(99, 39)–(141, 161)**. Short/ragged table frames retain fixed
  dimensions, and RTL physical cell placement survives. Color-bound comparisons
  allow 1.5 points for consumer rasterization and image resampling; the largest
  observed difference was 1.5 points.
- All ten comment fixtures reopen through the independent DOCX representation.
  Body references resolve to the expected comments; author, initials, valid
  dates, text, simple hyperlink destination/text, and separate note bodies are
  checked. The retained ODF pictures/tabs and unique auxiliary-story annotations
  remain explicit consumer limitations.
- Exact paragraph spacing measures **18.0 / 18.0 points**; minimum spacing
  measures **24 points**. Styled header/footer text, lists, seven note bodies,
  two resolving repeated note references, visible note-table text, and hidden
  continuation suppression pass their consumer assertions.
- The conditional-style PDF retains the expected fill/font colors, has no
  pixels of the overridden red fill, and retains the externally extracted cell
  value.

The logical-text PDF comparisons remain pixel-identical at 120 dpi:

| Fixture | Raster dimensions | Differing pixels |
| --- | ---: | ---: |
| Word | 993 × 1404 | **0** |
| Worksheet | 993 × 1404 | **0** |
| Rotated slide | 1200 × 675 | **0** |

### Preserved RTL oracle correction

The initial general consumer run validated all 108 XML parts and passed 26
fixtures. Its single failed assertion incorrectly required Poppler to return
Arabic word code points in logical source order. The saved bbox strings
contained the expected characters in reordered sequences; the rendered words
were correctly positioned.

The published verifier correction (`86242782`) identifies this two-word fixture
by distinct exact Unicode character multisets, requires exactly two words, and
checks their coordinates independently. Six negative controls reject swapped
positions, missing/extra/duplicate words, and changed character multiplicities.
A fresh run requalified **only** the affected RTL fixture, after rechecking the
complete original 27-package inventory and generation receipt. Its raster is
byte-identical to the initial raster; the measured first-cell x coordinate is
317.622 points, versus 133.909 for the second cell.

The composite keeps the 26 originally passing results and this one qualified
replacement. The original failed receipt is preserved in
[evidence/odf-consumer](evidence/odf-consumer/), and the correction is preserved
[separately](evidence/odf-rtl-correction/). This is a verifier correction with no
product-source change; it is not reported as an uninterrupted all-pass consumer
attempt.

## Saved checkpoints and evidence reconstruction

| Saved checkpoint | Purpose |
| --- | --- |
| `fc443772` | All captured incoming histories and conflict decisions |
| `685b3413` | Genuine runtime setup and reproducible consumer checks |
| `5907daee` | Bounded comment stories and visible anchors |
| `07481e94` | Complete product source, rotation, linear date handling, final harness |
| `fa03e8bb` | Passed engine cohort and independent PDF artifacts |
| `0f8ee502` | Passed editor and Harper cohorts |
| `86242782` | Passed Node cohort, independent audit, development evidence, RTL oracle repair |
| `9400b6ec` | Passed consumer evidence, independent consumer review, complete qualification report |

All writes verify the Git tree and use an expected previous branch head. The
qualification checkout stayed at `07481e94` while a separate evidence checkout
saved the finished cohorts, so incremental remote saves did not change the
source under test.

[Evidence manifests](evidence/) index every archived file by SHA-256 and byte
count. Archives are split into small ordered parts for reliable remote saving;
identical members are deduplicated inside each archive. Reconstruct and verify
all final archives into a fresh directory with:

```bash
python docs/validation/office-fidelity-resume-20261117/unpack_evidence.py \
  --output /absolute/fresh/evidence-directory
```

The [development bundle](development/README.md) has its own reconstruction
instructions and records the exact limits of historical controls. It is kept
separate from final qualification. No dependency manifest, pinned lock, or font
binary was changed by this continuation.

## Limits

These are selected cohorts and bounded fixtures, not a claim that the complete
repository test suite or every office document is qualified. The inherited
optional host-PDF early returns remain distinct from runner-reported skips.
GECToR's lightweight Python tooling tests do not requalify its model/native
backends. Valid ODF retention is distinct from consumer retention: the tested
LibreOffice conversion omits some annotation pictures/tabs and annotations in
auxiliary stories. Comment ranges and thread metadata, arbitrary imported
transforms, complete ODF round trips, and shared editor/headless shaping remain
outside this continuation.
