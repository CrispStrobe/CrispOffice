# Document review: local validation and integration

The integrated code at `5bcb20dec3169ce3e4c0162a94fe94dd53b7bc47`
(tree `a86161dae80b5462f57d4ad6e09c1cad09aacc12`) passed **358 selected
tests** locally, with no selected tests skipped. Strict analysis of the changed
engine/editor and incoming spaCy sources reported no issues.

[verification.json](verification.json) binds that tested commit, commands, logs,
runtime, and 39 changed Dart source/test hashes. All 39 still match after the
last main reconciliation at `15eb4bf1ca0fdc65375038de9031c00edd78e961`
(tree `5516a02d0d22b415d003361eb8728bf2bcc33755`). The sole additional production
library change is the incoming footer PAGE-field builder repair. **47 additional
engine regressions passed**, with strict analysis reporting no issues. See
[latest-main-verification.json](latest-main-verification.json) for the separate
source binding and logs. This final evidence update changes documentation only.

## Incoming history

The initial audit covered **198 fork branch tips, 159 PR heads, and four upstream
branches**. Current main was `1e07cb85`, containing merged PRs through #159.
The sole open draft #153 already had its exact head in main. Historical retained
tips were accounted for by ancestry, exact patch equivalence, equivalent merge
trees, or the ODT continuation's changed-file equality. Superseded work was not
replayed over its later fixes.

The first integration preserved the new Zotero reconciliation commit
`146cdead`. A later fetch found three more branches updated during this task;
the integrated source checkpoint preserves all three histories as parents:

| Branch | Included tip | Incoming work |
| --- | --- | --- |
| `codex/zotero-workspace-20261118` | `d36413a2cc8e1de9fd7493b5d1baf2900e63f04b` | Reference inspection, staged selection, metadata and layout regressions |
| `codex/native-spelling-continuation-20261118` | `d6a9ca51b16daa9d3d54e163bc723b76659d70ac` | Soft-hyphen projection, accented suggestions and identifier guards |
| `integrate/native-spacy-distribution-20261118` | `8cd413c1e0454278abd703264bdda589a90f2d48` | Optional NER interfaces, installer support and Studio display |

Only the two package changelogs conflicted. Both branches' entries were retained,
alongside the document-review entries. There were no production-code merge
conflicts. Full records: [initial audit](incoming-audit.json) and
[follow-up audit](incoming-followup-audit.json).

While draft PR #162 was being opened, main advanced again. The branch now also
contains `5588726c705700ab8ab08c34472e0f88d059cf29`, including complete footer
PAGE-field packets, separate reviewed macOS golden references, and the newer
Zotero/spelling evidence. Only the two changelogs conflicted again; both sets of
entries were kept. Existing Linux references and incoming Mac references were
preserved byte-for-byte. GitHub reported PR #162 mergeable after reconciliation.

## Remote checkpoints

Progress was saved on `codex/document-review-20261118` throughout the work:

| Commit | Checkpoint |
| --- | --- |
| `32e10e24` | Initial recent-history integration |
| `b0044f5a` | Comparison engine, review workspace and controller tests |
| `213398ee` | Working UI, real file input, regression tests, guide and screenshots |
| `5bcb20de` | Three latest incoming branches and final comparison hardening |
| `9b7b2634` | Baseline validation logs, source bindings and final screenshots |
| `15eb4bf1` | Latest main reconciliation, footer PAGE repair and Mac references |

Direct Git push credentials were unavailable, so authenticated GitHub Git-data
operations created the commits and updated the branch with an expected-head
check. Each uploaded tree matched the local Git tree exactly. No force push was
used. Commit messages include `[skip ci]`; no Actions workflow status was
queried, no Actions job was dispatched, and no CI queue was awaited.

## Local checks and supplemental verification

| Group | Result | Evidence |
| --- | ---: | --- |
| Comparison/revision engine plus incoming Zotero and German spelling | 115 passed | [Engine test log](integrated-engine-tests.txt) |
| Editor review, navigation, notes, spelling projection and Zotero details | 118 passed | [Editor test log](integrated-editor-tests.txt) |
| Studio comparison inputs, workspace, linguistic analysis and setup | 39 passed | [Studio test log](integrated-studio-tests.txt) |
| Seven spaCy unit suites | 86 passed | [spaCy test log](integrated-spacy-tests.txt) |
| Engine strict analysis | No issues | [Engine analysis](integrated-engine-analysis.txt) |
| Editor/Studio strict analysis | No issues | [Editor analysis](integrated-editor-analysis.txt) |
| Incoming spaCy/Studio strict analysis | No issues | [spaCy analysis](integrated-spacy-analysis.txt) |
| Latest-main field/builder/fidelity regressions | 47 passed | [Supplemental engine tests](latest-main-engine-tests.txt) |
| Latest-main builder/fidelity strict analysis | No issues | [Supplemental analysis](latest-main-engine-analysis.txt) |

The comparison controls include 180 seeded Unicode reconstruction scenarios at
three work budgets, insertion/deletion alignment, repeated paragraphs, source
identity preservation, invalid and detached revisions, TOCs, empty cached fields,
field locks, bookmark pairing, independent frame scopes, comment anchors, and
nontext object placement. Oversized and cyclic inputs fail boundedly; dense
differences keep complete text while declaring a coarser match.

Widget checks cover independently selected files, unchanged source documents,
redline displays, reviewer filters, filtered batch undo/redo, read-only controls,
stale reports, export cancellation/errors, late picker completion, and 360 × 740
LTR/RTL layouts. The strict Studio decoder rejects spreadsheets, missing content,
foreign XML roots and missing bodies, while accepting valid empty Word files.

The native runtime was Flutter **3.47.8** / Dart **3.13.7**, framework revision
`737ba8f885dc774b53b442759999a312c9461e4e`. Hosted dependencies were restored from
the committed locks; their archive hashes were checked. The isolated workspace
linked current source without modifying production dependency manifests. See
[runtime-ready.json](runtime-ready.json) for executable hashes and setup details.

For this recovered runtime, `flutter test` in the recorded commands was invoked
through the genuine compiled Flutter tool:
`dart "$FLUTTER_ROOT/bin/cache/flutter_tools.snapshot" test --no-pub ...`.
This avoided a dependency-upgrading launcher during offline qualification.

## Rendered screens

The screens were rendered by Flutter using real fonts and sample DOCX inputs.
Three capture-harness tests passed. These are UI evidence, not a native Word
layout-equivalence oracle.

- [Tracked-change workspace](screenshots/review-desktop.png)
- [Side-by-side comparison](screenshots/comparison-side-by-side.png)
- [Inline comparison](screenshots/comparison-inline.png)
- [Narrow Arabic change detail](screenshots/review-arabic-mobile-detail.png)

## Boundaries and migration

This run did not build every platform application package or qualify live native
spaCy/NER models, installed-worker/FFI operation, live Hub downloads, or capsule
distribution. The incoming branches retain their own qualification records.

Document tracking remains supported text insertions/deletions. Comparison is a
read-only report of modeled text, formatting and structure; its scope field and
warnings list exclusions. It does not produce a merged/redline DOCX or certify
binary/rendered equality.

The former mutating `WordCompare.compare` helper produced invalid revision
ranges. It now throws before mutation and is deprecated in favor of
`WordDocumentComparison.compare` / `WordCompare.diff`.
`WordEditorController.compareWith` returns the safe report. The
[usage and migration guide](../../document-review.md) explains the host APIs.
