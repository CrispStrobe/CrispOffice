# ODT lists and sections — 17 November 2026

Continuation of `8eb01db06c1457fa04ab3f3b8b2ef8fef791fb43` on
`codex/office-fidelity-20261117`. Work is saved as incremental
remote checkpoints with `[skip ci]`. GitHub Actions, check, and commit-status
endpoints are neither queried nor awaited.

PR #101 merged while these reports were being finalized, at **17 November 2026,
16:43:05 Berlin time**. [Draft PR #111](https://github.com/CrispStrobe/quds_office_suite/pull/111)
preserves the evidence and audit follow-up; its initial 20 changed files are all
under `docs/`. The [publication-state receipt](publication-state.json) records
the observed later main head `9941c80d`, including subsequent page-number-field
work. Those later main changes are outside this qualification. All final test
and consumer results below bind the exact source `cf60a17b`, not the later main
tree or its integration conflict resolutions.

## Incoming histories

The [recorded snapshot](incoming/) contains 240 named references: 126 fork
branches, 106 fork PR heads, four upstream branches, and four upstream PR
heads. One branch moved between REST collection and Git fetch, so both exact
revisions are retained: 241 reference/revision pairs and 162 distinct heads.
The Git observation completed at 2026-11-17 14:49:26 UTC (15:49:26 Berlin).
Later arrivals are outside this finite snapshot.

Every captured head is an ancestor of integration checkpoint
`097475fbda96aa4a6497d92f28d10f1aa5f640b4`. It includes ODT sections PR #104,
nested lists PR #106, their original/vendor histories, morphology PR #105,
the optional GECToR provider/manual editor lane, and ODF annotation extraction.
The complete prior final consumer evidence remains byte-for-byte unchanged.
The conflict decisions and exact revisions are saved in `incoming/`.

## Implementation

The [export guide](../../odf-export-fidelity.md) defines the mappings and limits.
This continuation adds 89 regression cases: 40 lists, 26 sections, five RTL
paragraph mappings, and 18 anchored text-box extraction/search cases:

- Repeated authored levels retain sibling relationships; mixed marker kinds,
  supported decimal starts/restarts, default child resets, and continuation
  preserve visible numbering without changing source paragraphs or native XML.
- Auxiliary and hidden list stories cannot consume visible body counters.
  Complex cached markers remain literal; unsupported native numbering semantics
  and full editable numbering round trips remain explicit limits.
- Section activation reaches lists, nested content controls, tables, pictures,
  frames, and empty sections. First-paragraph formatting remains direct.
- Odd/even first pages use a temporary parity master followed by the normal
  section master. Shared header annotations remain single definitions.
- Equivalent continuous sections avoid an extra page break. Image bytes and
  authored comment references determine story equivalence; empty equivalent
  continuous sections add no paragraph. Changed page styles use a page-boundary
  fallback. First/alternating headers and inherited native stories remain outside
  the bounded writer.
- Physical paragraph indents retain their authored sides in RTL output.
  Anchored text-box paragraphs remain extractable and searchable, preserving
  surrounding inline text and suppressing hidden stories without duplication.

No new font or model binaries are committed. Incoming work adds the optional
GECToR workspace/package manifests; the existing dependency lock remains exact.
The one missing locked package was restored from its official archive after
checksum verification; [runtime/restoration.json](runtime/restoration.json)
records that restoration.

## Incoming-work qualification

The [incoming validation archive](incoming-validation/README.md) retains raw
events, source/runtime identities, the original failed static receipt, and its
bounded correction. All 86 archived files have been restored and hash-verified.

| Cohort | Passing executions | Explicit skips | Test files |
| --- | ---: | ---: | ---: |
| Optional GECToR VM | 97 | 1 | 8 |
| Engine integration VM | 78 | 0 | 5 |
| Actual Flutter editor | 119 | 0 | 6 |
| Node engine repetitions | 49 | 0 | 3 |
| **Dart/Flutter executions** | **343** | **1** | **22 file executions** |
| Ancillary Python checker tests | 65 | 0 | 2 modules |

The native-inference test is explicitly skipped without its pinned fixture
inputs; adapter tests do not establish native inference. Original GECToR tests
use `dart:io` fixture loaders, so no JavaScript GECToR suite is claimed.

The initial engine runtime tests passed, but strict gates found two missing
braces and a note-test formatting difference. The exact correction and
subsequent strict-gate requalification remain separate from that failed receipt.
Qualification binds the incoming source and the small corrected source;
the independent audit confirms exact Git blobs, modes, and current bytes for
the explicitly selected **85 proofing/GECToR files** against corrected source
`56dc162b`. This is scoped file equality, not a claim that the entire historical
import closure equals the final product.

## Final ODF qualification

Qualified product source is **`cf60a17bcd825dc9b4ecdf840d54e6a0271d3647`**, tree
`4a1a29d5029d25da9700b56a1fd244f3f5679547`. Both final cohorts and the complete
consumer run used that exact published commit. Later checkpoints contain only
reports, evidence, and independent review; qualified source and tests remain
unchanged.

| Final cohort | Passing executions | Test files | Failures / errors / skips |
| --- | ---: | ---: | --- |
| Dart VM | **353** | **18** | **0 / 0 / 0** |
| JavaScript / Node repetitions | **236** | **10** | **0 / 0 / 0** |
| **Final executions** | **589** | **28 file executions** | **0 / 0 / 0** |

Node repeats ten VM files; it does not add 236 unique cases. All 89 new
regressions run on both platforms. The VM cohort also covers adjacent ODT
paragraph, table, header/footer, note/comment, ODP transform/table, extraction,
and search behavior. The original failing 19-case text-fidelity file is unchanged
and passes. Its fixture-writing helper is optional, but its assertions ran.

Strict scoped analysis and formatting passed for all three changed production
files and selected tests. Every command completed, and the runner's raw events
cover the exact declared files. Both cohorts bind **1,670 source inputs** and
**8,606 runtime inputs**, with source/runtime/lock/HEAD unchanged before and
after. The runtime is genuine **Flutter 3.47.8 / Dart 3.13.7 / Node 24.22.1**.
The [final qualification archive](qualification-evidence/README.md) preserves
all 49 raw evidence and harness files, restored and hash-verified.

`consumer/make_fixtures.dart` and `consumer/verify_consumers.py` define 24
independent consumer fixtures. The saved incoming-writer controls validated
80 XML parts but failed 19 of 20 semantic fixtures, demonstrating that schema
success alone missed the section and list defects. Original controls, checker
source, and failures are preserved in `consumer/evidence/baseline-097.tar.xz`.

The [final consumer run](consumer/README.md) passed **24/24 semantic fixtures**
and **96/96 XML-part validations** against official OASIS ODF 1.3 schemas.
Fresh LibreOffice and Poppler outputs check page sizes/text placement, list
markers/indentation, parity, and the empty-continuous comparison. PDF conversion
explicitly sets `IsSkipEmptyPages=false` so automatic parity blanks remain
measurable. Its **392 source inputs**, **10,420 runtime inputs**, and generated
fixtures are unchanged; the runtime scope includes **557 font files**.
All 309 accepted consumer evidence files are restored and hash-verified.

The RTL heading's two right edges measure **539.916 / 539.911 pt** against an
authored **540 pt** edge, with an exact **18 pt** line step. An ordinary RTL
control independently checks the **540 pt right / 66 pt left** edges. The
leading picture is present on its authored page with left edge **36 pt** and
measured dimensions **39.75 x 21 pt**, within the declared **1 pt** raster
tolerance for **40 x 20 pt**. Reopened frame position and size are exactly
**(60, 100, 180, 40) pt**, relative to the page. Assertions remain explicit per
fixture; no whole-feature round trip is inferred from these measurements.

The first final attempt found an anchored-frame extraction regression and a
pre-existing RTL indent reversal. Both failed receipts and the independent
ordinary-ODT, DOCX, and one-variable ODT margin controls remain archived. The
fixes retain the original extraction expectation and physical-geometry oracle;
the final cohorts rerun from the corrected published source. General frame
fill, outline, and text insets remain outside this section-placement check.

The [extraction-correction archive](extraction-correction/README.md) additionally
preserves the isolated 113-pass VM / 41-pass Node development qualification,
including its environment-only failed load and receipt-bookkeeping correction.
Those repetitions and the seven consumer-checker controls are not added to the
final 589 executions or 24 consumer fixtures.

## Independent review and reconstruction

The [independent code review](independent-code-review.json) found no blocker in
the section/list interaction, deferred master selection, auxiliary counters,
or physical RTL mapping. The evidence checker independently reconstructs raw
event outcomes and exact suite coverage, checks current source/runtime hashes
and the Dart import closure, verifies captured ancestry and prior evidence
preservation, and restores every indexed archive. The
[passing audit](independent-review.json) verifies **1,109 archived files across
eight archives** and **16,164 current file paths**. Its import closures cover
**887 VM / 879 Node Dart files**. All **83 files / 3,617,117 bytes** in the prior
`office-fidelity-resume-20261117` report retain the exact Git subtree and current
bytes from `8eb01db0`. The [published-tree rerun](published-tree-review.json)
also passed against saved evidence commit `b8568306d22588d37597ef6bdc9ee5148c7bf085`,
with the same qualified source and accepted evidence.

An initial audit needed support for the extraction archive's declared `prefix`
field alongside `archive_prefix`. The failed receipt, exact adapter correction,
and first passing receipt remain in `attempts/`; qualified source and evidence
did not change. The final audit additionally enforces the explicit prior-evidence
and 85-file proofing-equivalence gates.

To inspect results without rerunning office tools, restore each indexed archive
to a fresh directory and compare its exact member list, sizes, and SHA-256 values.
The [qualification instructions](qualification-evidence/README.md) distinguish
archive-only verification from reproducing tests with the recorded runtime.
Historical receipts retain their actual source IDs, including the exact-tree
binding from local `59b8d494` to published `4fdac35c`.
The small `qualification-evidence/local-source-checkpoints.bundle` preserves
the exact local commit objects referenced by historical receipts. Its verified
prerequisites are all in the published branch, so a fresh clone can reconstruct
those source IDs without inventing equivalent commit metadata.

## Remaining limits

Complex list markers use literal visible labels and do not become fully editable
native multilevel numbering. Changed page geometry or normal header/footer
content in a continuous section uses an explicit page-boundary fallback.
First-page/alternating header selection, inherited native story reconstruction,
columns, and line numbering remain outside the section writer.

The tested consumer supplies default frame fill/outline when properties are
omitted, and internal text insets are not retained. Frame geometry is qualified;
complete frame styling is not. Anchored text-box extraction follows document
traversal order, and nested table content becomes visible paragraphs rather
than separate structured table entries. Optional native GECToR inference is
unqualified without its pinned fixtures. Earlier comment-picture and rotated
table editability limits remain documented in the export guide.

These are scoped regression and consumer checks. They do not requalify every
previous test cohort or claim complete Office round trips or universal shaping.
