# Final bounded ODF qualification — 17 November 2026

**All 156 selected tests passed on the final frozen canonical source.** Strict
analysis and formatting passed for all 12 changed Dart files. The additional
Python and JSON tooling checks passed, as did offline dependency resolution with
the unchanged lock. The test reporter recorded no errors, failures or skips.

Qualified source: [`f510060e35d580cbc361985a123927705c92ddc4`](https://github.com/CrispStrobe/quds_office_suite/commit/f510060e35d580cbc361985a123927705c92ddc4),
tree `15f19ae4c6b97760755fa25061af29312f98f348`.
Execution completed at `2026-11-17T09:09:35.294750+00:00`.

## Qualification chain and exact scope

| Stage | Qualified commit | Fresh substantive test passes | Selected files |
| --- | --- | ---: | ---: |
| Accepted full qualification | `837d06edbde08a2465e99cbbb15927ee4c87d8ac` | 2,576 | 144 |
| ODT list amendment | `2ae8bf3420bd20ec33115c96a44a38a0d3a78df0` | 26 | 3 |
| Final ODF amendment, this receipt | `f510060e35d580cbc361985a123927705c92ddc4` | 156 | 12 |

The full run reported 2,578 raw successes; two named early-return cases that
require an unavailable private PDF were excluded from its substantive count.
The two later stages overlap earlier suites. Their counts stay separate and
are not added to the full run as unique tests. Each stage retains its own source,
commands, raw logs, input maps and terminal receipt. The broad full run is not
represented as having executed again on the final commit.

Compared with the qualified ODT-list source, this candidate changes exactly 14
tracked files outside the evidence directory: five production Dart files, six
test files and three morphology tooling files. `source-delta.json` records every
old and new Git blob and mode, including newly added files. The production delta
is limited to:

- `packages/quds_office_engine/lib/src/extract/office_search_text.dart`
- `packages/quds_office_engine/lib/src/extract/office_text_extractor.dart`
- `packages/quds_office_engine/lib/src/odf/odf_text.dart`
- `packages/quds_office_engine/lib/src/slide/serial/odp_presentation_writer.dart`
- `packages/quds_office_engine/lib/src/word/serial/odt_document_writer.dart`

All **3,321 previously qualified inputs outside that exact delta** are unchanged.
All **3,335 current tracked non-evidence inputs** match the final source commit.
Dependency manifests and the dependency lock are unchanged. The morphology
addition contains tools and a diagnostic corpus; it changes no German runtime
implementation.

## Fresh checks and behavioral coverage

| Check | Result |
| --- | --- |
| Isolated workspace, offline enforced dependency resolution | Passed; original 108-package graph and lock retained |
| Strict analysis of every changed Dart source, test and tool | Passed; 12 paths, fatal infos enabled |
| Dart 3.12 formatting of those same paths | Passed; no files modified |
| Morphology Python syntax, JSON schema and command help | Passed; 256 corpus cases parsed |
| ODF, extraction, search and field-boundary regression suites | **156 passed in 12 files** |

The morphology checks validate syntax, corpus structure and the command-line
entry point. They do not execute a new grammar-quality comparison or establish
a new morphology score. Existing German runtime qualification remains attributed
to the full run.

The selected engine suites are:

| Suite | Main boundary exercised |
| --- | --- |
| `odf_covered_cell_extraction_test.dart` | Covered stories and nested covered cells stay out of ODT, ODS and ODP extraction; namespace, fallback and byte-budget boundaries remain enforced |
| `odp_presentation_writer_test.dart` | Modeled presentation output, including transition handling |
| `odp_table_fidelity_test.dart` | Table text colors, RTL placement, paragraph direction, header intent, rectangular grids, geometry and whitespace |
| `odt_header_footer_fidelity_test.dart` | Header/footer styles, breaks, media, story boundaries and visible cached fields with hidden instructions suppressed |
| `odt_paragraph_properties_test.dart` | Paragraph spacing, line-spacing rules, direction, alignment and style reuse |
| `odt_table_merge_test.dart` | Merged-cell structure and retained source stories |
| `odt_document_writer_test.dart` | Writer structure and contiguous list grouping |
| `odf_export_text_fidelity_test.dart` | Visible text, whitespace and hidden Zotero instructions during export |
| `odt_structure_fidelity_test.dart` | ODT paragraph and block structure |
| `office_search_fidelity_test.dart` | Visible search text, selected package parts and bounded archive/text expansion |
| `word_field_span_test.dart` | Field spans, nested fields and surrounding text |
| `word_zotero_simple_field_test.dart` | Cached citation results, rich fields, opaque metadata and PAGE-field boundaries |

The JSON reporter parser resolves selected and reported paths against the exact
command working directory and requires equality of the physical suite sets.
Every successful test completion is retained in `receipt.json`; no fixture
exclusions were needed for this final selection. Cross-component host-reader
execution has its own companion-host evidence.

## Input and execution integrity

Before/after maps match for source, external dependencies, runtime, workspace,
system inputs and harness. The temporary analyzer package graph was restored to
its original absence. The checkout's commit and tracked contents remained
unchanged throughout the pass.

The maps bind 5,099 external dependency files, 13 runtime artifacts, 12 workspace
inputs, six observed system paths and 10 harness inputs. The system map retains
the known absence of the private PDF; this selection does not depend on it.
`runtime-base-equivalence.json` additionally proves that the complete runtime,
external-dependency and system-input maps are byte-identical across the accepted
full run, the ODT-list amendment and this final ODF amendment. It binds each
compared map with its SHA-256 digest.

`receipt.json` records four required checks and one setup command, their exact
arguments and working directories, exit codes, timestamps, raw-log digests and
compressed-log digests. `workspace-setup.json` records the fresh isolated wrapper,
unchanged copied manifests and links into the final canonical checkout. Neither
previous qualification workspace was repointed.

## Reproduction

Use the restored Flutter 3.47.8 / Dart 3.13.7 runtime and the already cached
locked dependencies documented with the accepted full qualification. Keep
`run_final_odf.py` and the supplied `run_qualification.py` beside one another.
The exact executed runner and helper are preserved inside this evidence as
`run-used.py` and `shared-helper-used.py`.

```sh
. /path/to/runtime/env.sh
python3 run_final_odf.py \
  --repo /path/to/quds-at-f510060e \
  --source-commit f510060e35d580cbc361985a123927705c92ddc4 \
  --flutter-root /path/to/runtime/flutter-sdk \
  --workspace /path/to/new-final-odf-workspace \
  --base-evidence /path/to/accepted/odt-amendment \
  --output /path/to/new-final-odf-evidence
```

Use new workspace and output paths for each attempt. The runner checks the exact
source pin and allowed delta before resolving the isolated workspace. Its base
receipt and source map are hash-bound in `source-delta.json`. Runtime setup and
tooling checks contribute no application-test count.

No GitHub Actions, workflow or CI-status endpoint was queried or awaited. This
bounded local qualification establishes the recorded regression behavior; live
external office applications and general native-ODF roundtrip fidelity were not
requalified by these commands.
