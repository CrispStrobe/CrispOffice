# Final Word and Zotero integration qualification — 2026-11-20

The bounded Word/Zotero qualification is accepted at published commit
`c62338c65571aa399da5592455b651fa5c6a9317`, tree
`d8e43e6f43b0726e8fefded52c185e387291916d`. The [accepted summary](accepted-summary.json)
and [fresh receipt](qualification.json) distinguish new executions from incoming
results whose raw events and exact source inputs were independently audited.
Eight explicitly named editor exclusions remain exclusions, not passes.

## Source and integration decisions

This checkpoint reconciles incoming main
`0a2afc41bae4e719b77657a7e2d8d3e7ec02849b` with the earlier qualified Word/Mail
work. The final `word_layout.dart` and `word_deserializer.dart` are byte-identical
to that incoming main. They preserve inline header pictures, use actual
`WmlVisual` node identity and placement for duplicate projections, and include
incoming table/style and native fidelity corrections. The 13-case identity
suite distinguishes two projections of one node from distinct nodes that
share an image asset at the same position. Our 17-case style suite retains
the explicit color and bold-off regressions; the 41-case contained-text suite
retains the 31.2-point inner-content fixture and its exact glyph/roundtrip checks.

The historical VBA compiler remains unchanged. Incoming main also contains
the missing braces in the Zotero protocol test that blocked the earlier
strict-analysis attempt. The qualified Mail union has its own result package;
Mail cases are not counted here.

## Fresh results at the published checkpoint

| Fresh scope | Passing cases | Files | Exclusions |
| --- | ---: | ---: | ---: |
| Affected macro/runtime/CLI/MCP residual | 663 | 19 | 0 |
| Word native/layout residual | 223 | 16 | 0 |
| Editor layout consumers | 96 | 4 | 8 named no-paragraph cases |
| Zotero engine residual | 188 | 8 | 0 |
| Zotero editor residual | 143 | 7 | 0 |

All three test commands exited successfully with successful terminal reporter
events, exact expected file populations, and every started test completed
once. The whole engine strict analyzer and the selected editor tests/tools
analyzer passed with fatal infos enabled. Formatting was checked without
writing files. The receipt records exact commands, working directories,
durations, stdout/stderr hashes, runtime binaries and source seals.

The engine tests used Dart 3.14.1 and the pinned package:test runner. Editor
tests used Flutter 3.47.8 with Dart 3.13.7. Fresh tests read the pinned workspace
configuration without dependency resolution or shared SDK/cache changes.
Each command used a separate receipt-local temporary directory. CLI-created
fixture directories in the engine package were removed by normal test teardown.

## Retained incoming results and source boundaries

| Audited incoming scope | Retained passes | Files | Treatment |
| --- | ---: | ---: | --- |
| Word VM | 946 | 25 | The incoming 15-case style suite is superseded by our fresh 17-case suite |
| Word Node/dart2js | 758 | 7 | Separate platform execution; overlaps VM/compiler populations |
| Font loader | 9 | 1 | Includes the two new actual lowercase filename-alias fixtures |
| Zotero engine | 282 | 6 | 234 unchanged cases plus the superseding 48-case protocol rerun |
| Zotero editor | 114 | 2 | Exact relevant editor inputs; unrelated Mail changes explicitly excluded |

The frozen [incoming audit](incoming-retention-audit.json) verified 191 archive
members across the two incoming archives, all recorded member hashes, raw
terminal events and complete case identities. These executions retain their
original Dart 3.13.7/runtime attribution. They are not described as new runs on
our Dart 3.14.1 engine runtime.

The incoming Word evidence binds 492 tracked inputs to its executed Git
source. At the final checkpoint the differences are four Zotero helpers and
our expanded style test. The style test is rerun in full. The four helpers
serve citation/session/note operations, with no changed callers in the macro
and layout paths covered by the retained Word cohort; their Zotero behavior
is separately covered by the incoming publication evidence and fresh residuals.
All 430 tracked inputs of the retained Zotero engine scope match the final
source. All 27 font inputs match. The broader 1,010-input Zotero editor seal
differs only in four Mail implementation files. The editor library and relevant
Zotero tests/support have no references to those Mail implementations, and Mail
is separately qualified. Every difference and its hashes are in the audit.

The verified incoming archives remain in their original repository paths:

- `../mail-bulk-actions-20261120/evidence-final-main.tar.gz`
- `../mail-bulk-actions-20261120/evidence-publication.tar.gz`

Their exact sizes and SHA-256 values are in the accepted summary. They are
referenced rather than duplicated here. The three actual BAS examples retain
verified byte-identical input and equal VM/optimized-JavaScript results:
`word_line_spacing.bas`, `word_measurements.bas`, and
`word_named_measurements.bas`.
The font cases use controlled fixture directories, including the lowercase
aliases; they do not establish default installed-font discovery on every
operating system.

## Case identity and counting

| Accepted scope | Identity-preserving combination | Passing cases | Files |
| --- | --- | ---: | ---: |
| Previously affected macro/runtime subset | 663 fresh + 46 retained | 709 | 23 |
| Native/layout union | 223 fresh + 175 retained | 398 | 32 |
| Editor layout and fonts | 96 fresh + 9 retained | 105 | 5 |
| Zotero engine selection | 188 fresh + 282 retained | 470 | 14 |
| Zotero editor selection | 143 fresh + 114 retained | 257 | 9 |

The archive contains every case identity, source attribution, and occurrence
number for these unions. The native union includes the incoming new header,
table-style, border/style identity suites and the two added distinct-node
identity regressions. Its 398 cases replace the earlier narrower 312-case
native scope; they are not an additional 398 cases to add to it.

The 709 macro identities belong to the historical 3,598-case/69-suite macro
corpus. Neither these reruns, the retained compiler suites, nor the 758 Node
results are added to that historical total. This report makes no aggregate
count across the overlapping VM, Node, compiler, native and editor populations.

## Eight explicit editor exclusions

All eight are in `word_incremental_layout_equivalence_test.dart`, with exact
reason **`no paragraphs to edit`**. Their case-name prefix is
`incremental layout equals full layout fixture ` followed by the paths below.
These image-only fixtures provide no editable paragraphs for this harness;
the fixtures and expectations were not changed.

- `legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-both.docx`
- `legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-control.docx`
- `legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-horizontal.docx`
- `legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-margin-quarter.docx`
- `legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-negative-quarter.docx`
- `legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-outline-shadow.docx`
- `legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-quarter.docx`
- `legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-vertical.docx`

## Source/runtime seals and external fixtures

The fresh runner's captured package source inputs, runtime binaries, package
configuration, immutable audit and old-worktree configuration matched before
and after execution. HEAD stayed at the published source, and the tree was
clean at both boundaries. The two tracked reference-fixture directories under
`docs/validation/word-native-layout-20261120/reference` and
`docs/validation/word-line-boxes-20261120/reference` were bound by that clean
Git tree, rather than by the package-only per-file seal. A separate manifest
in the archive compares every file in those directories byte-for-byte with
the immutable c62338c6 Git objects; it does not relabel them as before/after
snapshot members.

## Preserved earlier failed attempt

The nested `historical-80e240ec-attempt` evidence preserves the source
`80e240ec1f557c1ac7c170a8273de41dfaac0f20` attempt. Its 470 engine and 257 editor
cases passed, but the original collector then used the wrong working directory
to resolve relative suite paths. The preserved continuation recounted the
original raw streams using each recorded command's working directory, verified
source/runtime seals and ran the remaining checks. It did not rerun those tests.

That historical receipt remains `success=false`: strict engine analysis found
`curly_braces_in_flow_control_structures` at the protocol test's single-line
conditional. Incoming main supplied the braces correction. The old successful
test events are not presented as acceptance of the old checkpoint, nor counted
again on top of the final selected populations. Both collector scripts, the
interruption record, corrected recount, raw events and source/runtime seals
are preserved inside its deterministic nested archive.

## Boundaries and reproduction

This is local source/runtime qualification, not installed Microsoft Word COM
execution or fresh external Zotero/Word/LibreOffice acceptance. Existing
DOCM opaque-part preservation checks do not certify cryptographic signatures
after modification. Existing edited `w:ind` group ownership remains unchanged.
Zotero vertical merges, nested research tables and active ODT citation transfer
remain outside the supported contracts described in the usage guide.

The [evidence archive](local-qualification.tar.gz) contains the exact runner,
commands, raw stdout/stderr, case IDs, seals, independent incoming audit,
mapping records and preserved failed attempt. It excludes SDKs, caches,
compiled test assets and transient fixtures. [The manifest](receipt-manifest.json)
binds each archive member and each top-level receipt by SHA-256 and size.

To reproduce the fresh selection with the same dependency/runtime setup, use
the exact commands and per-command cwd in `qualification.json`; engine commands
run from `packages/quds_office_engine`, editor commands from
`packages/quds_office_editor`. The archived runner has session-specific absolute
paths and an immutable expected HEAD. Reproduction elsewhere requires explicit
path remapping and a new evidence directory, not overwriting these records.
No GitHub CI result was awaited or used as a gate.
