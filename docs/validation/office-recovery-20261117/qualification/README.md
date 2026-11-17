# Frozen-source local qualification — 17 November 2026

The selected continuation cohorts passed at source
`966196f386ec1776c836664b3eb7c93e8e92605c`, Git tree
`4287330a433e915d58ca779adfacb75942c6ab04`.
The run started at **17:20:04 Berlin time** and finished at **17:24:42**
(16:20:04–16:24:42 UTC). The source and HEAD remained at that commit.

The [compact receipt](evidence/summary.json) records accepted totals, exact
exclusions, runtime versions, command scopes and input counts. The
[archive index](evidence/qualification-966196f3-index.json) binds every member of
the [complete evidence archive](evidence/qualification-966196f3.tar.xz).

## Accepted results

| Primary cohort | Selected files | Substantive passing cases | Explicit exclusions or skips |
| --- | ---: | ---: | --- |
| Engine Zotero, Dart VM | 19 | 390 | None |
| Editor Zotero, actual Flutter | 13 | 186 | None |
| Engine integration, Dart VM | 97 | 2,126 | Two unavailable private-PDF early returns excluded |
| Editor integration, actual Flutter | 37 | 396 | None |
| Harper contracts, Dart VM | 3 | 29 | None |
| GECToR contracts, Dart VM | 11 | 193 | One optional native-fixture case skipped |
| **Primary total** | **180** | **3,320** | **Two excluded no-op successes and one explicit skip** |

The primary runner reports 3,322 successes before excluding the two private-PDF
cases. No primary failures, errors, unexpected skips or missing selected suites
were accepted.

The separate Node lane passed **282 executions across 14 files**. Its exact
multiset of suite paths, case names and outcomes equals the corresponding VM
cases. These are repetitions of primary cases. The combined Dart/Flutter/Node
total is **3,602 substantive passing executions**, not 3,602 unique cases.

The ancillary Python controls ran 108 cases: **107 passed** and one optional
converter-dependency case was skipped. Python results are reported separately
from the application cohorts.

Both new writer suites passed on VM and Node: 22 page-field cases and 20
paragraph-decoration cases, **42 cases in total**.

## Coverage retained and added

The exact original 174 package/test paths are retained. The archived baseline
plan is SHA-256 bound, and the runner rejects any missing original selection.
The six additional engine suites are:

- `test/odf_frame_extraction_test.dart`
- `test/odt_section_integration_test.dart`
- `test/proofing/german_lexical_gap_test.dart`
- `test/proofing/german_spelling_quotes_test.dart`
- `test/odt_page_field_fidelity_test.dart`
- `test/odt_paragraph_decoration_test.dart`

The primary cohorts are disjoint by package and test file. This is the selected
continuation scope; it is not a claim that every repository test was executed.
Historical qualifications and development checks are not added to these totals.

The Node lane selects focused ODT/ODF/ODP regression suites whose test and
relative-helper imports support Node/dart2js. Seven unchanged suites import
`dart:io` and remain covered on VM:

- `odf_export_text_fidelity_test.dart`
- `odp_presentation_writer_test.dart`
- `odp_table_fidelity_test.dart`
- `odt_comment_fidelity_test.dart`
- `odt_document_writer_test.dart`
- `odt_header_footer_fidelity_test.dart`
- `odt_structure_fidelity_test.dart`

These seven files are selection exclusions from the repetition lane, not skipped
primary tests. The plan records every candidate, selected file, excluded file,
reason and reviewed source hash. Node used concurrency two, a 600-second process
limit, a 180-second suite-loading limit and a 60-second per-case timeout; it
completed in 83.386 seconds.

## Exact exclusions and skips

The two inherited `pdf_file_test.dart` cases below return before their assertions
when `/home/mohammed/Desktop/al_tahreer_profile.pdf` is unavailable. The fixture
was absent, so both runner successes are explicitly removed from substantive
pass counts:

- `TrueType subsets without cmap get ToUnicode cmap for the host`
- `JPEG with DCT SMask attaches softMaskJpeg for the host`

The GECToR native case
`real native dual heads own their output and reject use after dispose`
was skipped because its four pinned library/model fixture environment variables
were not provided. The evidence does not claim native-model acceptance for it.

The Python case
`test_qualification.TinyConverterTests.test_real_quantizer_preserves_both_head_matrices`
was skipped with the runner reason
`Install qualification requirements for the tiny converter control`.
The archived Python runtime record identifies optional dependency availability.
No other skips or missing selected tests were accepted.

## Static checks and unchanged inputs

All four strict analysis commands passed with fatal infos enabled: 80 selected
engine paths, 18 editor paths, 10 Harper paths and 29 GECToR paths. All 77
handwritten formatting targets passed with language version 3.12. Generated
proofing data remain checked against their committed manifests and are outside
the handwritten formatting scope. All 13 executed commands passed.

The run used genuine Flutter 3.47.8, Dart 3.13.7 and Node v24.22.1. The canonical
workspace resolved 109 packages offline before qualification. The enforced lock
remained unchanged at SHA-256
`344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.

| Before/after map | Recorded inputs | Result |
| --- | ---: | --- |
| Tracked source inputs outside historical reports | 3,449 | Unchanged |
| External dependency files | 5,099 | Unchanged |
| Selected runtime files, including Node | 14 | Unchanged |
| Canonical workspace files and links | 118 | Unchanged |
| System fixture entries | 6 | Unchanged |
| Harness inputs | 9 | Unchanged |

The system map includes five required fonts and the absent private-PDF fixture
entry. The runtime map binds the selected executables, snapshots and platform
inputs; it does not claim a hash inventory of every SDK installation file.
The normalized analyzer configuration was restored after analysis. Source
bytes matched the frozen commit before and after execution, and the final HEAD
was exactly `966196f386ec1776c836664b3eb7c93e8e92605c`.

## Evidence and reconstruction

The archive contains **103 files / 7,941,044 uncompressed bytes**. Its compressed
size is **893,116 bytes**, with SHA-256
`5f7e3b60530bc8070684f6aa1bd23957a3e1d86629c8ca6f30097e2ab29411a2`.
Every member was restored into a new scratch directory and checked against its
indexed size and SHA-256; the restored member set matched exactly.

The archive preserves all 91 files from the accepted run under `qualification/`,
including compressed raw stdout/stderr, JSON event summaries, generated
artifacts, exact command arguments, the plan, all before/after maps and the
terminal receipt. `qualification/run-used.py` is the exact executed runner.
`harness/` preserves its companion Python runner, original baseline plan,
provenance and synthetic acceptance controls. `setup/` preserves the executed
canonical workspace setup scripts, environment and receipts. `plan-only/`
preserves the separately generated identical plan.

The original terminal receipt is `qualification/receipt.json` inside the
archive; its SHA-256 is
`d4be506e8730d6693ebe0dcab769d94c5c2c67c72867e6f88158ad4e6dad424d`.
The event streams retain their original gzip bytes; command receipts also bind
the corresponding decoded stdout/stderr hashes. The member index hashes the
exact payload bytes after removing the outer tar.xz compression.

To inspect evidence, extract the archive into a new directory, compare its
member set with the index, and verify each file's recorded size and SHA-256.
For a fresh execution, restore the recorded SDK/cache and enforced workspace
lock, check out the exact source commit, and use the archived runner with
`--repo`, `--source-commit`, `--flutter-root`, `--workspace` and a fresh `--output`
directory. `--plan-only` inspects the selection without running application
tests. Setup files retain the original execution paths; adapt only environment
locations when reconstructing them. The archive does not bundle SDK binaries,
external dependencies or the Git repository.

No assertions, application source or HEAD were changed during this run. No
GitHub Actions, workflow, check-run or commit-status endpoint was queried,
awaited or rerun. Independent office-consumer checks have separate evidence
and are not part of these test totals.
