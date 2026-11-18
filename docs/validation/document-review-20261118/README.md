# Document review: local validation and integration

## Resumed completion

The continuation recovered the saved branch and draft PR #162, then reconciled
the remote inventory of **201 fork branches, 163 PR heads, and four upstream
branches**. The original audit's 194 unchanged branch tips retain their earlier
ancestry/equivalence evidence. All changed or new tips are included in checkpoint
`366e9b343047b254dd9b78263b5fb02c52a40ae5` (tree
`d25edc0bad66e22074aa23f84f3ace5839222ec5`). Its parents preserve the earlier review
checkpoint, main `517f6d10` including PR #163, and the independent macbook golden
reference repair `ca42a7fa`. See [the resumed audit](resume-incoming-audit.json).

An independent readiness review found one additional input-validation defect:
the shared XML reader permits fragments and unclosed elements at EOF, so the
old comparison preflight could accept truncated content or a foreign-namespace
body as an empty Word document. Checkpoint
`41c15e2309ae4100126381adb702b27410a52069` (tree
`cc036c7190f868fb0bc4414f6efa0055df4904f5`) requires one complete Word root and
exactly one direct body in its namespace before import. Regression controls cover
17 malformed variants and three valid nonempty namespace forms, alongside the
existing real-file and valid-empty-document tests. Shared XML parser behavior
and production dependency manifests are unchanged.

[Resumed verification](resume-verification.json) records the targeted local
checks, exact source hashes, commands, and logs for these additions:

| Resumed check | Result |
| --- | ---: |
| spaCy distribution, installer controls and optional entity validation | 14 passed |
| Review dialog, narrow layouts, filtering, undo, stale reports and export | 13 passed |
| Studio comparison decoder and spaCy setup | 17 passed |
| Strict analysis of five changed/relevant files | No issues |
| Golden path selection from repository and package directories | Identical correct results |

All **44 selected tests passed, with zero skipped**. All 560 recorded Dart
source, manifest and selected test files remained unchanged and match the tested
commit. Runtime executable hashes and the workspace lock also match the pinned
Flutter 3.47.8 / Dart 3.13.7 setup. Golden images were not regenerated.

The final remote check found main had joined the same two incoming histories in
`f383c826205e321eda3ed3bdbcd584e9a2d4da14`. A Git merge-tree calculation with
the tested commit produced the identical tree `cc036c71`; no additional source or
test changes were introduced. The final evidence checkpoint preserves that main
commit as a parent as well.

The earlier 358 checks and subsequent 47 field regressions below remain historical evidence
for their recorded source revisions; they are not represented as new full-suite
runs. Every resumed checkpoint was saved without force-pushing, with its remote
tree verified against the local Git tree. GitHub Actions were not queried or
awaited.

## Earlier verification

The initial integrated code at `5bcb20dec3169ce3e4c0162a94fe94dd53b7bc47`
(tree `a86161dae80b5462f57d4ad6e09c1cad09aacc12`) passed **358 selected
tests** locally, with no selected tests skipped. Strict analysis of the changed
engine/editor and incoming spaCy sources reported no issues.

[verification.json](verification.json) binds that tested commit, commands, logs,
runtime, and 39 changed Dart source/test hashes. All 39 matched after the
earlier main reconciliation at `15eb4bf1ca0fdc65375038de9031c00edd78e961`
(tree `5516a02d0d22b415d003361eb8728bf2bcc33755`). The sole additional production
library change at that point was the incoming footer PAGE-field builder repair. **47 additional
engine regressions passed**, with strict analysis reporting no issues. See
[latest-main-verification.json](latest-main-verification.json) for the separate
source binding and logs. The corresponding evidence update changed documentation only.

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
| `9ecf4c42` | Supplemental field regressions and the prior final validation record |
| `366e9b34` | Resumed reconciliation of main, PR #163 and the Mac golden helper |
| `41c15e23` | Complete Word XML preflight and malformed-input regression controls |

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
