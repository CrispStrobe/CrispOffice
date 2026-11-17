# Destination-main ODT note qualification — 17 November 2026

**The landing amendment passed 114 source regression tests and two supplemental
note-boundary tests.** Strict analysis and formatting passed for the changed
writer, its test and the supplemental probe. Offline dependency resolution
retained the accepted lock. No errors, failed cases, skips or fixture exclusions
occurred.

Qualified source: [`b2dc226e2ed82cda8f1bada18fb0a1e17347b5fc`](https://github.com/CrispStrobe/quds_office_suite/commit/b2dc226e2ed82cda8f1bada18fb0a1e17347b5fc),
tree `642436fb32d73cb73706a4dd1c1fce32d0f2fb8b`.
Execution completed at `2026-11-17T09:28:19.645765+00:00`.

## Why this bounded amendment was necessary

The destination main had advanced to
`fb3d3a4d275f0be7161c13a4763fcd6cac3e2c13`, adding ODT footnote and endnote
export after the previously captured main. A normal merge preserves that main
and the saved recovery `d95701cffb7bd6ca9085d073c2297373932f374e`. The qualified
commit has those exact two parents. `landing-ancestry.json` verifies both
ancestors and confirms that the remotely saved candidate has the same tree as
the local normal merge.

The source delta from the accepted ODF source
`f510060e35d580cbc361985a123927705c92ddc4` consists of exactly three paths:

- `packages/quds_office_engine/lib/src/word/serial/odt_document_writer.dart`
- `packages/quds_office_engine/test/odt_document_writer_test.dart`
- `packages/quds_office_engine/README.md`

The note implementation was retained as authored. Note bodies call the existing
block, paragraph and inline writers, preserving the integrated list, table,
paragraph, header/footer and hidden-field boundaries. The new source test covers
a plain footnote; the supplemental evidence exercises the interaction with
Zotero fields and richer note blocks.

`source-delta.json` binds the prior accepted receipt and source map and records
both commits' Git blobs and modes. Every one of the **3,332 inputs outside the
exact delta** remains identical to the accepted ODF source. All **3,335 current
tracked non-evidence inputs** match the qualified commit. No earlier production,
test or evidence file was rewritten by this qualification.

## Qualification chain

| Stage | Exact source commit | Fresh substantive test passes | Selected files |
| --- | --- | ---: | ---: |
| Accepted full qualification | `837d06edbde08a2465e99cbbb15927ee4c87d8ac` | 2,576 | 144 |
| ODT list amendment | `2ae8bf3420bd20ec33115c96a44a38a0d3a78df0` | 26 | 3 |
| ODF amendment | `f510060e35d580cbc361985a123927705c92ddc4` | 156 | 12 |
| Destination-main notes, this receipt | `b2dc226e2ed82cda8f1bada18fb0a1e17347b5fc` | 114 source + 2 supplemental | 8 source + 1 supplemental |

These are separate executions on separately identified source commits. Later
selections overlap earlier suites and are **not added as unique tests**. The full
run recorded 2,578 raw successes, with exactly two named private-PDF early-return
cases excluded because that fixture was unavailable. No such exclusion applies
to this note amendment. The two earlier failed full-run preflight attempts remain
preserved and contribute no accepted test count.

## Fresh checks

| Check | Result |
| --- | --- |
| Fresh isolated workspace, offline enforced dependency resolution | Passed; original 108-package graph and dependency lock retained |
| Strict analysis, fatal infos enabled | Passed for the changed writer, changed test and supplemental probe |
| Dart 3.12 formatting | Passed for those same three paths; source files unchanged |
| Eight canonical ODT, extraction and search regression suites | **114 passed** |
| Supplemental note-boundary suite | **2 passed**, exact expected count enforced |

The source cohort is deliberately bounded to ODT writing and the adjacent
boundaries:

| Source suite | Passes |
| --- | ---: |
| `odt_document_writer_test.dart` | 4 |
| `odf_export_text_fidelity_test.dart` | 19 |
| `odt_structure_fidelity_test.dart` | 4 |
| `odt_header_footer_fidelity_test.dart` | 9 |
| `odt_paragraph_properties_test.dart` | 13 |
| `odt_table_merge_test.dart` | 26 |
| `odf_covered_cell_extraction_test.dart` | 12 |
| `office_search_fidelity_test.dart` | 27 |

`count-reconciliation.json` compares the raw reporter streams with the accepted
ODF stage: the same selection previously had 113 cases, and its only count change
is the one newly added upstream footnote case. Historical cases are freshly
executed here, not reused as new passes.

The two supplemental tests use the actual `OdtDocumentWriter` and inspect its
emitted note XML. They establish:

- Footnotes and endnotes with the same source ID keep their distinct bodies and
  emitted IDs. Cached Zotero results remain visible; private field instructions
  remain absent. Authored spaces, tabs and line breaks survive, repeated content
  XML is identical, and the original field instructions in the model are unchanged.
- An endnote containing paragraphs, a list and a merged table retains those block
  boundaries and visible cached list text. Covered-cell stories remain stored in
  their covered XML positions, and private field instructions remain suppressed.

The supplemental file stays in the evidence and isolated wrapper. It was not
added to or substituted into the production checkout. The host's handling of
note bodies and covered-cell visibility has separate actual writer-to-reader
evidence. These canonical XML checks do not claim new note-body search coverage;
the existing search cohort continues to qualify its recorded cases.

## Integrity and evidence

All source, dependency, runtime, workspace, system and harness maps match before
and after execution. The temporary analyzer package graph was restored to its
original absence. The checkout remained at the exact qualified commit.

The maps bind 5,099 external dependency files, 13 runtime artifacts, 12 workspace
inputs, six observed system paths and 12 harness inputs. Before running the
commands, the runner required the complete dependency, runtime and system maps
to equal the accepted ODF stage; `base-environment-equivalence.json` records that
comparison. The earlier ODF evidence in turn proves their equality to the full
qualification environment.

`receipt.json` contains four required commands and one setup command, their
arguments, working directories, timestamps, terminal outcomes and both raw and
compressed log hashes. Each reported suite path must resolve to an exact selected
physical file. `workspace-setup.json` records unchanged manifests, the original
lock read from the qualified Git object, source links and the copied probe hash.
The prior workspaces were not repointed.

## Reproduction

Use the same restored Flutter 3.47.8 / Dart 3.13.7 runtime and cached locked
dependencies as the accepted qualification. Keep `run_note_amendment.py`,
`run_qualification.py` and `odt_note_boundary_test.dart` together. Their executed
bytes are also preserved as `run-used.py`, `shared-helper-used.py` and
`note-probe-used.dart` in this evidence directory.

```sh
. /path/to/runtime/env.sh
python3 run_note_amendment.py \
  --repo /path/to/quds-at-b2dc226e \
  --source-commit b2dc226e2ed82cda8f1bada18fb0a1e17347b5fc \
  --flutter-root /path/to/runtime/flutter-sdk \
  --workspace /path/to/new-note-workspace \
  --base-evidence /path/to/accepted/final-odf \
  --output /path/to/new-note-evidence
```

Each attempt requires fresh workspace and output paths. Runtime setup contributes
no application-test count. No GitHub Actions, workflow or CI-status endpoint was
queried or awaited. External office applications and general native-ODF roundtrip
fidelity were not requalified by these commands.
