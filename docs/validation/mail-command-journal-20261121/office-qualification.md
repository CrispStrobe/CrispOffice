# Incoming Office qualification and golden reconciliation

The seven affected original Linux golden suites pass **17 tests** against **26
live reference images**, using the default exact comparator and no
`--update-goldens` flag. The final run exited zero, emitted one successful
terminal event, and retained identical before/after hashes for **4,098 source
and data inputs**. The original editor acceptance entrypoints also passed 578
cases, with eight source-authored skips for picture-only fixtures that contain
no paragraphs to edit. A focused supplement passed twenty additional original
reference-document cases, for **598 unique editor passes**. This report covers
the incoming Office work; the overall Mail
milestone and final repository intake are recorded separately.

The complete raw logs, cases, receipts, input hashes, experiments and inspected
scene images are in [office-qualification-evidence.tar.xz](office-qualification-evidence.tar.xz).
[office-qualification.json](office-qualification.json) records exact commands,
runtime versions, hashes, baseline changes and scope. GitHub Actions were neither
queried nor awaited.

## Why the incoming references did not initially pass

The maintenance branch refreshed its images at `809cdbd7737cae61a45376e44d06ec3a00002294`
and then merged newer main at `15271321a9f4550c1ab796a2cf9eaed910824574`.
Newer main already contained `e975cec13b289fe067ef406cd3044701ecc44744`, which changed
default table-cell padding from 5.4 points to 4.25 points (85 twips). The refreshed
images therefore described an older layout even on the maintenance branch itself.

All comparisons below used Flutter 3.47.8, revision
`737ba8f885dc774b53b442759999a312c9461e4e`, Dart 3.13.7 and the same locked
dependencies and bundled fonts. Each run has stable input seals in the archive.

| Source and isolated experiment | Passed | Failed | Finding |
| --- | ---: | ---: | --- |
| Original refresh source `809cdbd7`, unchanged | 16 | 1 | Only the existing nested-cell fixture's heading changed after DOCX export. |
| Maintenance merge `15271321`, unchanged | 6 | 11 | The same failures as the integrated intake source; all ten emitted comparison images were byte-identical. |
| Maintenance merge, changing only padding back to 5.4 in the isolated worktree | 16 | 1 | Restoring the old padding removes every additional failure. This experiment did not change production. |
| Current 4.25-point padding, explicit fixture style, reviewed current references | 17 | 0 | Exact comparisons and all structural, character, native-save and independent-reference assertions pass. |

The repository keeps the intended 4.25-point padding. Thirteen image references
were updated after inspecting every affected scene. Thirteen incoming references
remain byte-identical. The obsolete fourth tall-table page was removed because
the full authored content now fits on three pages.

### Tall table: complete content on three pages

The updated test checks all 120 tokens from `T000` through `T119` in order and
requires every nonspace source character to have exactly one laid-out glyph
offset. It also requires the following paragraph and the late footnote. These
checks run on the original document and every one of three reopened exports.

The three inspected pages contain tokens 000–039, 040–087 and 088–119,
respectively. The last page retains the note reference, “After the table” and
“Late table note.” The cells remain within their page, and there is no missing
continuation. Page count alone is not the acceptance criterion.

### Nested scene: explicit native heading style

The nested-cell fixture used `WordToc.applyHeading` to create a 16-point heading
but left its `Heading1` native style unspecified. On export, the catalog's
20-point heading style supplied the unpainted paragraph mark. The visible run
remained 16 points, while the final line box grew from 21.12 to 26.4 points. This
was already the sole failure on the original refresh source.

The fixture now explicitly authors its intended 16-point `Heading1` style,
including Arial, bold, color and spacing. New assertions require its 21.12-point
line box before and after export and verify that the reopened paragraph mark is
16-point bold Arial. No production rendering or style-cascade code was changed.
The original scene and all three reopened exports now have the same PNG SHA-256:
`7b84d316c266a030bf046b7a1bc44ce6ee1056403c8f84e273d8165c785b2210`.

## Visual review and native-save coverage

| Affected scenes | Review and retained oracle |
| --- | --- |
| RTL page | Arabic and mixed-direction text remain visible; the table uses the narrower intended inset. |
| Imported fidelity page | Heading, links, table text, decoded picture, footnote/endnote labels and footer remain visible. |
| Structure create, edit page 2, remove | Cell insets and resulting geometry follow the retained padding. Authored placed frames and editing effects are preserved. |
| Nested-cell page | Picture, inner table, TOC links and page number, external frame and the explicit 16-point heading remain visible through three native saves. |
| Grid unchanged, format, replace, unmerge | Every authored Latin character and its cell containment are asserted. Scripted output still must match independently authored raw-XML reference pixels through three direct and three isolate saves. |
| Tall table pages 1–3 | All tokens, continuation cells, trailing paragraph and footnote remain present, with exact source-offset coverage. |

A diagnostic capture comparator wrote each original authored scene without
changing repository goldens. It required subsequent renders with the same scene
name to be byte-identical; the table-grid suite's independent scripted/reference
pixel comparisons remained active. Only the thirteen inspected changed reference
PNGs were copied into the repository. The final acceptance run then used the
seven unmodified test entrypoints and the default comparator with all assertions
active. Diagnostic capture success is not used as the golden pass.

The fidelity feature matrix also no longer lists the obsolete fourth Linux
table-page image. Historical macOS references and their provenance were retained;
this Linux run does not qualify or regenerate macOS raster expectations.

## Other incoming acceptance evidence

### Editor aggregate and supplemental reference documents

The actual `vertical_table_acceptance.dart` entrypoint and the separately
isolated `embed_test.dart`, `word_header_footer_navigation_test.dart` and
`office_system_fonts_test.dart` completed in 140.523 seconds with 578 passes,
eight skips, no errors and 5,717 identical before/after input hashes. The eight
skips were declared by the original test because its floating-picture fixtures
have no paragraphs to edit; their names and exact skip events are preserved.

That test also conditionally discovers sixteen native-layout DOCX references and
four selected line-box references under `docs/validation`. Sparse checkout had
left those directories absent. All twenty exact tracked DOCX files were
materialized and verified against their Git blob IDs, and the reference
directories were added to the persistent sparse patterns. A focused run executed
exactly those twenty original cases, without changing their assertions: **20
passes**, no skips/errors, 14.466 seconds and 4,102 stable input hashes, including
every selected DOCX. The first run contains none of these reference paths, so the
598-pass union does not double-count them. The supplemental corpus and runner are
included in the archive.

After the main editor run completed, one imported source changed:
`packages/quds_mail_transport/lib/src/cloud/provider.dart`. The later change
keeps HTTP 410 responses out of the provider's proven-no-write rejection list.
This is outside Word/editor behavior, and the new bytes were independently
qualified by the focused **105-case transport gate**. The exact old/new hashes,
source patch and complete transport receipt/log are preserved as the sole
explicit source bridge. The 578-case editor run is not claimed to have executed
again after that change. The later golden and twenty-case supplementary inputs
match the current source without a bridge. The verifier checks this distinction
and rejects any other changed repository input.

### Historical engine and failure diagnostics

The archived first source-stable engine VM aggregate passed 825 cases on the
initial integrated source. Its preceding successful-test run is preserved only
as a diagnostic because the harness changed during execution. Later engine
acceptance after the numeric preference correction is recorded separately in the
milestone's final qualification; these counts must not be added together.

The first complete Node aggregate is retained as a failure: 807 passed, 17 had
unsupported filesystem operations and one exposed differing VM/JavaScript
interpretation of integral JSON numbers. The seventeen I/O cases still ran on
the VM. Root's subsequent portable Node and corrected numeric-preference gates
are separate receipts; this report does not relabel the failed aggregate.

The initial legacy IMAP account-retirement regression also remains in the
archive. It exposed a final acknowledged receipt being lost after a live account
identity changed; production repair and current host qualification belong to the
Mail evidence.

## Verification and reproduction

To verify every archive member, independently recount the final test events and
compare the sealed repository inputs with a supplied checkout:

```sh
python3 docs/validation/mail-command-journal-20261121/verify_office_qualification.py --repo .
```

The archive includes the source-closure runners. With the pinned runtime and
locked dependencies available, copy `runners/run_incoming_goldens.py` outside the
checkout and run its `goldens --repo /absolute/checkout --output /new/output`
cohort. The runner's receipt gives the exact underlying CLI and all seven target
files. It does not update reference images. Hashes include transitive Dart
imports/exports/parts, conditional sources, tracked assets/fixtures/fonts/goldens,
dependency configuration, lockfile and the runner itself.

## Later Word branch review

[word-late-increment-review.json](word-late-increment-review.json) records the
read-only comparison of `426fbc92` through `4163368b`. Its `52eace9e` native
deserializer and two regression suites are already byte-identical to the
integrated target. Current layout also retains the newer per-page vertical merge
and physical-row geometry work. The alternate shared-node identity test differs
only in equivalent fixture construction and its name. The useful new material is
the 24 historical evidence files from `6eea7224` and `e7d9055f`, whose exact blobs
are listed for retention. The captured later advance from `58cc4283` through
`8206975d` to `0e4e999a` contains only documentation and evidence: seventeen Mail
files, ten new Word delivery files and one documentation-link update. Exact API
commit parents and file blobs are also recorded in the review. This review is
not a new final remote-ref cutoff.
