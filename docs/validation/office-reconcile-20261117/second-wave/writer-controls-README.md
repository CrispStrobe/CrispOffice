# Second-wave Office source controls and focused qualification

## Exact source bindings

The first controls run against incoming main
`914d74f13d1ae75d9b45ea0e51873c31ff63ec62`. All 319 isolated engine library files
were checked against their Git blob identities. This run has six assertion
failures, one passing page-precedence control and no skips. Its generated
two-column ODT also fails the official ODF 1.3 RelaxNG schema because column
attributes are attached directly to `style:section-properties`.

The merged source was locally `eaa0f92a016e0d39426af19e52b1f3454d77693a`, published
as `674bd994a16cfafec1f504884bea62d4054c6c70` with the identical tree
`5102f2d1f8e0e81b24a76ff0c6c78ec4fbef9537`. The morphology branch already repairs
the column structure, invalid gap omission and empty-section anchoring. The
unchanged seven-test file consequently has three passes and four paragraph-cache
failures on this merged source, with no skips.

The final source was locally `418f47647f9cdb532e3a21f134f4dc6d70c63399`, published
as `4a4101c11d471adf525849b38dea0a52b9c0b394` with the identical tree
`62c8d234db993466083bb42a5ccacc408aa6c8e0`. The source-specific commit changes one
paragraph-style cache key to include columnBreakBefore and keepTogether, and
adds the unchanged seven-test file. No other product code changes in this
commit. Both local-to-remote mappings were independently verified using exact
Git tree equality and empty diffs.

## Accepted focused qualification

All **505 substantive cases across 29 current ODT, ODP and shared ODF files pass**,
with no failures or skips. All seven new control cases are included in those 505;
they are not an additional pass count. Every selected file appears in the raw
suite output, every started test terminates once, and the terminal completion
reports success. All input library/test/config hashes remain unchanged during
the run and the source inputs match the recorded Git commit.

Strict analyzer checks on the writer and new test, their formatting checks, and
Git whitespace checks all pass. The same fixture generator used for the failing
incoming schema control now emits valid ODF content on the final source.
`final-source-binding.json` records the exact mappings, unchanged test identity,
Git verification counts and schema comparison.

These results qualify this focused Dart/ODF scope. Full canonical, host, native,
and LibreOffice acceptance are recorded by their separate fresh runs; the
focused count must not be added to a full run that already includes these cases.

## Preserved evidence

The incoming-main and merged-before failed controls remain distinct and unchanged.
The original source audit describes the findings before reconciliation. The
feature patch-equivalence record covers the three new feature/vendor/main-squash
triplets. Raw events, exact tests/runners, package configuration, schema receipts,
ODT artifacts, XML content, static-check logs and size/hash index are included.

`run_controls.py` accepts explicit engine, test, package-config, source and phase
arguments. `run_focused.py` reproduces the recorded all-ODT/ODP/ODF selection.
`verify_columns_schema.py` takes the same source/config binding and emits an ODT
with the archived fixture generator before RelaxNG validation. Their recorded
absolute runtime paths refer to the recovered pinned SDK and dependency cache;
change paths when reproducing in another workspace, keeping the source commits,
test bytes, package versions and schema identity fixed.

No GitHub Actions or CI endpoint was queried or awaited.
