# Word latest-main integration qualification — 2026-11-20

The affected Word follow-up is accepted at remote commit
`cf25a0a3d80ee18d2550161af182bacc4e49d18f`, with the eight editor exclusions
documented below. The [accepted summary](accepted-summary.json) combines a
frozen run at `cdd98460` with one test-only correction at `cf25a0a3`.
It preserves the original failed result and does not claim a universal
zero-skip run.

## Captured source

| Checkpoint | Commit | Tree |
| --- | --- | --- |
| Incoming main | e975cec13b289fe067ef406cd3044701ecc44744 | Recorded in source history |
| Frozen Word/native/editor run | cdd98460c2eed261719c660351f11adc962e2ca5 | aee18e93719bc51dcd94c003ac9dfab3c0851bdc |
| Test-only correction | cf25a0a3d80ee18d2550161af182bacc4e49d18f | 0780f20f27df62004404496d8e5c529c4bdccd87 |

Incoming main changed Word layout and deserialization and added eight editor
font filename aliases. Integration repaired two concrete regressions:
header-picture loss and first-row table styles overriding explicit run color
or bold-off formatting. The VBA compiler, automation sources and macro test
sources remained unchanged from the earlier `85f4ef96` checkpoint.

The only changes from the frozen run to the focused follow-up are the Word
contained-text test geometry and the unrelated Mail cached-host test formatter
cleanup. No engine or editor production file changed between those checkpoints.
All 1,117 captured source inputs and captured runtime inputs matched before
and after each run; each run also ended at its expected HEAD with a clean tree.

## Accepted results and counting

| Scope | Accepted result | Evidence treatment |
| --- | --- | --- |
| Affected macro/runtime/CLI/MCP integration | 709 passed across 23 files; no failures or skips | Exact subset of the historical 3,598-case macro corpus |
| Word native/layout | 312 passed across 26 files; no failures or skips | 271 unchanged cases plus the superseding 41-case suite |
| Editor consumers | 103 passed across 5 files; 8 explicitly skipped | No failed cases; skipped image-only editing scenarios are not passes |
| Strict analysis | Passed | Whole engine, editor font source and five editor test files, then corrected Word fixture; fatal infos enabled |
| Corrected fixture formatting | Passed | No formatter changes required |
| Actual word_measurements.bas | Passed on VM and optimized dart2js/Node | Byte-identical BAS input; equal eight-operation results |
| Actual word_named_measurements.bas | Passed on VM and optimized dart2js/Node | Byte-identical BAS input; equal thirteen-operation results |

The 709 refreshed macro identities match every historical case in the selected
23 files, with no added, missing or duplicate identities. They **must not be
added to 3,598**. The other 2,889 historical macro identities were not rerun in
this follow-up. The 312 native and 103 passing editor cases are separate
non-macro qualification scopes. The broader historical measurement acceptance
remains in the [measurement report](../word-vba-unit-conversions-20261120/README.md).

The [initial raw receipt](initial-qualification.json) remains `success=false`:
it recorded 709 macro passes, 311 native passes and one fixture failure, and
103 editor passes with eight skips. Its strict predicate rejects any failed
or skipped case. The [focused receipt](focused-qualification.json) passed all
41 cases in the corrected file, with exactly the same case identities, plus
strict analysis and formatting. Its success flag qualifies that correction
and unchanged-input retention; it does not turn editor skips into passes.

## Regressions reproduced and repaired

### Header and footer pictures

The incoming renderer could remove both projections of one shared visual,
drop distinct same-sized images, and discard legitimate body or header
pictures using dimension and payload-length guesses. The repair deduplicates
only the same visual at the same placement. Continuous sections carry the
recorded body-frame prefix and regenerate header/footer frames, avoiding
lossy filtering of body pictures afterward.

The new 11-case suite includes native DOCX roundtrips, header and footer
projections, equal-length distinct PNG payloads, separate placements, body
pictures near a header and continuous sections. Development reproduction
passed two cases and failed nine before the repair; all 11 passed afterward
and again in the sealed frozen run. An additional 18-case development layout
check is retained as corroboration and is not added to the accepted counts.

### Explicit first-row formatting

Two authored XML cases reproduced first-row table styles replacing explicit
custom/default-black text colors and explicit `w:b` values of `0` or `false`.
The small deserializer repair respects the existing direct-property markers
for `color` and `b`. Both cases failed before the repair; all 17 cases in the
whole style/layout suite passed afterward and in the frozen run.

Development evidence is labeled as such and is not substituted for the sealed
final run. The archive preserves its source hashes, raw failures, successful
reruns and incoming/final source snapshots.

### Contained Indic text fixture

The frozen run found one exact-line expectation in
`word_contained_text_wrap_test.dart` that assumed a 42-point outer cell with
5.4-point padding on each side: 31.2 points of content width. Incoming main's
intentional 4.25-point padding expands that same cell's text area to 33.5
points. The first line can then legitimately contain `A` plus the first
complete Indic conjunct. No codepoint or cluster ownership was lost.

The test-only correction defines a 31.2-point content width and derives the
outer grid as `contentWidth + 2 * LaidOutLine.tableCellPad`. It retains every
exact glyph-index, containment, text, direct-save, isolate-save and repeated
roundtrip assertion. The whole 41-case suite passed. The accepted native union
replaces all 41 prior cases from that file, including its original failure;
the other 271 native cases have unchanged production and test inputs.

## Eight explicit editor exclusions

All exclusions occur in `word_incremental_layout_equivalence_test.dart` and
emit the exact reason **`no paragraphs to edit`**. Their full case-name prefix
is `incremental layout equals full layout fixture `, followed by each exact
fixture path below. The files load but contain no editable paragraphs for
this editing-equivalence harness. They were not changed or counted as passes.

| Exact fixture path after the case-name prefix | Reason |
| --- | --- |
| legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-both.docx | no paragraphs to edit |
| legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-control.docx | no paragraphs to edit |
| legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-horizontal.docx | no paragraphs to edit |
| legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-margin-quarter.docx | no paragraphs to edit |
| legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-negative-quarter.docx | no paragraphs to edit |
| legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-outline-shadow.docx | no paragraphs to edit |
| legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-quarter.docx | no paragraphs to edit |
| legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-vertical.docx | no paragraphs to edit |

Full case names, files, occurrences and reasons are also in accepted-summary.json
and the raw editor events. The passing editor scope covers 66 incremental
equivalence scenarios, 19 header/footer navigation cases, ten page-layout
cases, seven font-loader cases and one inline-picture history case. No extra
image-only probe was run.

## Font alias coverage and other limits

The existing font-loader tests use display-style filenames such as Arial.ttf,
Arial Bold.ttf and Arial Italic.ttf, with licensed Liberation-based fixtures
and synthetic family metadata. They exercise metadata validation, limits,
precedence, rejection and fallback. The eight new lowercase entries
`arial.ttf`, `arialbd.ttf`, `ariali.ttf`, `arialbi.ttf`, `times.ttf`,
`timesbd.ttf`, `timesi.ttf` and `timesbi.ttf` were source-reviewed and
statically analyzed. No alias-specific runtime probe or default host discovery
on macOS, Windows or Linux is claimed.

The raw initial runner's selection-rationale sentence overstates alias-specific
fixture coverage. It is preserved verbatim for integrity; the
[qualification clarifications](qualification-clarifications.md) and this
report supply the correction.

No installed Microsoft Word host, live COM object model or full VBA
compatibility is claimed. DOCM tests retain opaque VBA bytes and the documented
native XML ownership boundaries; they do not validate cryptographic signatures
after modification. Existing replacement of an edited `w:ind` group is unchanged.

## Evidence, runtimes and reproduction

[local-qualification.tar.gz](local-qualification.tar.gz) contains the unmodified
frozen and focused receipts; all raw test, analyzer, formatter and portable
execution logs; case identities and the accepted native union; before/after
source/runtime seals; both repair reproductions; the exact executed Python
runners and environment scripts; and relevant pinned runtime metadata.
It also retains the follow-up runner's initial preflight rejection, which
stopped before any product test because its path allowlist omitted the already
authorized Mail formatter file. That scope assertion was corrected before
the successful run; no source or test expectation was altered for it.

The archive includes historical macro case identities to independently verify
the 709-case overlap. SDKs, package caches, test/build outputs, compiled kernels,
fonts and generated JavaScript bundles are excluded. Source snapshots and BAS
drivers are text inputs, not generated build outputs.

The [manifest](receipt-manifest.json) records the size and SHA-256 of every
uncompressed archived member and the archive itself. Members are sorted;
tar timestamps, ownership and modes are fixed; gzip timestamp and filename
are fixed. Two serializations were compared byte-for-byte when packaging.

Engine tests used Dart 3.14.1 and the pinned package:test 1.31.1 runner. Editor
tests used Flutter 3.47.8 / Dart 3.13.7. Portable JavaScript ran on Node
v24.22.3. The runtime records include SDK archive/executable hashes, the
workspace dependency resolution, package configuration, and the unchanged
repository lockfile. The earlier engine bootstrap is documented in the linked
measurement report.

To reproduce, use isolated checkouts at the two captured commits and rebuild
the pinned runtimes rather than modifying a shared worktree. Raw command arrays
record every executed argument and working directory. The archived scripts
retain their original absolute environment paths; remap those path constants
in a working copy when relocating the harness. Run `qualify_word_main.py` at
`cdd98460` first, using an empty output directory, then run
`qualify_word_main_followup.py` at `cf25a0a3` against that preserved first output.
The original frozen run is expected to retain the one fixture failure and eight
editor exclusions; the focused correction must pass all 41 cases without skips.
Both runners require a clean captured HEAD and seal their inputs before and
after execution. No GitHub Actions run, check status or workflow result was
awaited or used as a gate.
