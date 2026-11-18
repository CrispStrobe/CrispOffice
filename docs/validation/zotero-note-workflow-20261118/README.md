# Zotero citations in existing notes and native keyboard commands

## Qualified result — 18 November 2026

The application checkpoint is **`ff1518517dd9f67e214ff56fe7eef06349f5223a`**
(tree `9a2014756626b256509df78d5ca0efedcd3c967a`), on
[`codex/zotero-note-workflow-20261118`](https://github.com/CrispStrobe/quds_office_suite/tree/codex/zotero-note-workflow-20261118),
with [PR #170](https://github.com/CrispStrobe/quds_office_suite/pull/170) targeting
`codex/document-review-20261118`.

**1,489 distinct targeted local test cases passed.** All final gates ran
against that exact application commit. This directory, the validation-index
entry and a clarification of historical native acceptance in the Zotero guide
were added afterward without changing
the tested application source.
All source checkpoints were saved remotely as the implementation progressed,
using expected-head, non-forced updates and `[skip ci]` commit messages. No
GitHub Actions, workflow, check, or commit-status endpoint was queried, awaited,
or rerun.

## User-visible change

The preceding PR #168 recognized body citations and provided direct Zotero
commands, but the separate Notes pane did not supply its caret to those commands.
This increment closes that gap and supports citation insertion inside an
existing authored footnote or endnote.

- Click in the **Notes** text editor, then use **Insert → References → Add/Edit
  citation**. A caret or selection inside a citation edits that field; another
  valid note position inserts a citation into that note. Explanatory text,
  character formatting, the body reference and native note identity remain.
- Multiple citations can share the note. The native transaction supplies
  reading order and the physical note index, including insertion before,
  between or after existing note citations and across paragraphs. A new nested
  note is not created.
- **Insert basic citation** and imported CSL sources also use the note caret.
  Opening the ribbon or Zotero workspace retains the target. Returning focus
  to the body switches citation commands back to the body.
- Undo/redo restores both the content and note selection. Ordinary note-text
  undo keeps the next citation attached to the visible Notes editor, including
  when the body has a parked selection. Stale offsets are clamped after history
  changes.
- Native Studio uses **Ctrl+Alt+C** for Add/Edit citation and **Ctrl+Alt+R** for
  Refresh; macOS uses **Cmd+Alt+C/R**. Ribbon tooltips expose these Quds defaults.
  The editor no longer consumes Ctrl/Meta+Alt+C as Copy. The commands require an
  editable Word document and available native transport, and do not stack over
  another dialog. Closing the workspace releases its transport and allows
  another invocation.

The [Zotero guide](../../zotero-support.md) documents the workflow and embedding
APIs. `WordNoteEditingTarget` records the owning `WmlNote`, selection and IME
composition in `WordNotes.editableText(note)` coordinates. The Notes pane maps
paragraph separators and the hidden automatic-marker separator consistently,
and synchronizes text/selection after native operations and history changes.
Custom hosts must clear or update that target when moving focus or directly
changing their body caret. Raw coordinate changes alone are not a substitute
for the documented focus lifecycle.

Native insertion accepts inline-style citations in an authored note or the
matching footnote/endnote kind. It refuses an opposite note kind, a bibliography
inside a note, nested note references, and an unsupported conversion that would
discard explanatory note text. Apply-time guards verify note identity, ID,
paragraph ownership/order, body anchor, revision, caret, selection and IME
state. Cancellation, a removed/replaced target, or a stale staged result leaves
the live document unchanged. The existing locked, malformed and unsupported
field protections remain in force.

## Final local qualification

| Disjoint gate | Test files | Passed cases |
| --- | ---: | ---: |
| Engine Zotero, note editing/numbering and note-reference fidelity | 29 | 549 |
| Editor Zotero, notes, keyboard, proofing, review and thesaurus | 52 | 737 |
| Studio transport, shortcuts, comments/review and language setup | 7 | 107 |
| Incoming spaCy providers | 6 | 67 |
| Incoming engine thesaurus provider | 1 | 24 |
| Python thesaurus compiler | 1 | 5 |
| **Total** | | **1,489** |

All commands exited zero. The JSON-reported engine/editor/Studio gates contain
zero failed, skipped, error or unfinished test events. Their **1,393**
passing cases and the **96** provider/compiler cases are disjoint. Development
runs, independent reproductions and earlier historical qualification are not
added to the total. The four new Zotero regression files contain **98**
cases, already included in the appropriate rows above:

| New regression file | Passed cases |
| --- | ---: |
| `word_zotero_note_insertion_test.dart` | 41 |
| `word_zotero_note_target_test.dart` | 33 |
| `word_zotero_notes_pane_test.dart` | 13 |
| `studio_zotero_shortcuts_test.dart` | 11 |

Strict Dart analysis with `--fatal-infos` and formatter checks pass for all
**42 changed product/test Dart files** under `packages/` and `apps/`. Historical
evidence fixtures and the thesaurus benchmark tool are outside this analysis
selection. Application whitespace checks pass for the full
change relative to the initial review base, as does the final application
checkpoint's own diff. The combined source required one incoming test
dependency declaration (`crypto` in the editor dev dependencies) and formatter
normalization; the resolved dependency lock did not change.

Separately, the thesaurus integrity verifier checked **1,037 bundled files**
(518 English, 519 German), including compressed/logical hashes, membership,
alias/shard placement and bounded lexical controls. These file checks are not
counted as test cases.

### Source and runtime binding

- Main gates: **1,432** application/configuration fingerprints match
  before and after, with the same HEAD, clean tracked tree, lock, package
  configuration, Dart binary and Flutter test binary.
- Provider gates: **1,613** source/asset fingerprints and their runtime,
  dependency-lock and package-configuration hashes also match. The two source
  manifests overlap and must not be summed.
- Genuine **Flutter 3.47.8 / Dart 3.13.7**, framework
  `737ba8f885dc774b53b442759999a312c9461e4e`, and the unchanged 110-package
  workspace graph were used. The official SDK archive and 162 hosted dependency
  archives were hash-verified; their provenance is retained under `runtime/`.
- Exact root lock SHA-256:
  `344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.

`qualification.json` gives the compact result. `results/main-summary.json` and
`results/provider-results.json` retain commands, working directories, elapsed
times and outcomes. The complete engine/editor/Studio JSON event streams are
gzip-compressed; source inventories are compressed without changing their
contents. `manifest.json` hashes every evidence file except itself.
The independent [raw-result and source audit](results/independent-evidence-review.md)
confirms the case counts, disjoint file selections and exact Git-blob matches
for the 2,472 distinct inputs represented by the overlapping source manifests.

### Failures found and corrected during development

The retained development archive records failures as well as passing runs.
They do not weaken or inflate the final source-bound gate:

- An independent undo reproduction found two real note-target bugs: a caret
  beyond the restored note text, and loss of the active note target when the
  generic history path collapsed a parked body selection. The controller now
  restores a clamped note target after that adjustment; both cases have
  permanent widget regressions.
- The editor originally intercepted Ctrl/Meta+Alt+C as Copy. Its key handler
  now leaves both native Zotero accelerators to the host command mapping.
- A canvas caret ticker made `pumpAndSettle` unsuitable for the Notes widget
  fixture. Tests now use bounded route/native frames and disable unrelated
  background proofing. Protocol fixtures were corrected to use actual field
  responses and complete automatic-marker properties.
- Studio fixture corrections covered platform-override cleanup, native
  transport control, and distinguishing passive clipboard availability checks
  from a copy operation. Existing HTTP transport tests still run in the final
  Studio gate.
- Incoming formatter differences and the missing `crypto` test dependency
  were corrected before freezing the final source. The initial failed analysis
  and final passing analysis are preserved.

The first provider Dart command had a silent startup period, then completed
successfully on its original invocation. It did not require a retry or a source
change.

## Reconciliation of recent work

The first fetch/audit preceded the Zotero changes and captured **380 refs**:
207 fork branches, 169 PR heads and four upstream branches. Work started from
review `eedf2aee`, already containing PR #168, then incorporated thesaurus
`315beeb3` and main `4fbc8741`.

A bounded second fetch closed at **2026-11-18 18:58:08 UTC (19:58:08 CET)**.
It captured **384 refs**: **210 fork branches, 170 PR heads and four upstream
branches**. The observed newer heads were integrated before final qualification:

| Captured head | Preserved contribution |
| --- | --- |
| Review `b5d4df516db210a6f8ea566b290988dab5652630` | New review documentation/evidence, included through the spaCy merge |
| spaCy `9a90262da555705758fa233f7d4e339ff453a0dc` | English/French bundle/catalog/provider and Studio language-setup work; also includes our earlier engine checkpoint |
| Mail baseline `0e07d24714e6261123fcb835c36a592d6827982d` | Reconciliation history and exact Shift+F7 modifier guard; no new Mail implementation in that captured head |
| Thesaurus `eb1ff4dddbf65384bc61e2e7a0973360f76729ce` | Writing-pane Shift+F7, IME refusal without taking focus, narrow status layout and regressions |

The resulting application source includes **356 captured refs by ancestry**.
The other **28 refs point to 14 historical heads** whose work was freshly
verified as equivalent: ten through patch equivalence, three through identical
integrated trees, and the remaining PR #140 head through all 37 changed files
matching its integrated equivalent. **Zero captured refs are unaccounted for.**
This is a bounded observation, not a claim about commits arriving after that
snapshot.

Conflict resolution retained the note target types exactly once, the incoming
proofing declarations, guarded Shift+F7, Alt+F7 review navigation, exactly one
thesaurus shortcut-map entry, IME behavior, narrow status layout, and the Zotero
handlers. An independent read-only merge review checked these resolutions.
The initial and final inventories, per-head evidence and incoming branch review
are retained under `reconciliation/`.

## Incremental remote checkpoints

| Commit | Saved work |
| --- | --- |
| `fcb8a4b06b256b762074456eb3c9e412d0193722` | Initial reconciled review, thesaurus and main baseline |
| `a4915a555f70919fc7c6cfae3eb31764195593b7` | Existing-note native engine support and regressions |
| `595e94c15732966c1bb42f846b14bb0db4b964e0` | Notes controller/pane targets, offline insertion and undo fixes |
| `09a1a701c21b6c8b79ce5a9ab65239a393bcc12a` | Studio shortcuts, transport lifecycle and Zotero guide |
| `18c6667e13f9eb3538123a0e160270e7d25a3eb6` | Final captured incoming review, spaCy, Mail baseline and thesaurus heads |
| `ff1518517dd9f67e214ff56fe7eef06349f5223a` | Qualification dependency/format fixes; exact tested application source |

The merge publication preserves the incoming heads as parents. Publication
receipts record local/API commit identities and equal Git trees. The later
evidence commit preserves this report without changing application source.

## Reproduce the selected gates

Use the pinned Flutter SDK and dependency cache described in `runtime/`.
The saved bootstrap source records this session's restoration and paths; it is
provenance, not a portable installer. The runners accept explicit checkout and
output directories. Output must remain outside the checkout.

From the delivered branch, create a clean detached worktree at the tested
source so an evidence-only HEAD does not change the run's identity:

```bash
quds_evidence="$PWD/docs/validation/zotero-note-workflow-20261118"
quds_validation="$PWD/../quds-zotero-notes-validation"
quds_results="$PWD/../quds-zotero-notes-results"
git worktree add --detach "$quds_validation" ff1518517dd9f67e214ff56fe7eef06349f5223a
cp "$quds_evidence/runtime/workspace-pubspec.lock" "$quds_validation/pubspec.lock"

# Set FLUTTER_ROOT and PUB_CACHE to the pinned SDK and populated package cache.
# Resolve from quds_validation, using the saved lock:
cd "$quds_validation"
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" pub get --offline --enforce-lockfile

python3 "$quds_evidence/run_local.py" \
  --repo "$quds_validation" \
  --expect-commit ff1518517dd9f67e214ff56fe7eef06349f5223a \
  --output "$quds_results/main" \
  --analysis-targets "$quds_evidence/analysis-targets.json"
python3 "$quds_evidence/run_incoming_providers.py" \
  --repo "$quds_validation" \
  --expect-commit ff1518517dd9f67e214ff56fe7eef06349f5223a \
  --output "$quds_results/providers"
```

`plan.json` is the exact main suite selection, with concurrency two. The main
runner invokes the Flutter tool snapshot directly with `--no-version-check`
and `--no-pub`. The provider runner documents its seven Dart suites and Python
checks. These local commands do not require GitHub CI.

## Acceptance boundary

This run qualifies the model, DOCX serializer/deserializer reopen paths,
controller, real Flutter widgets, native command guards and controlled transport
behavior. The incoming spaCy provider tests use synthetic backends and loopback
installer fixtures; they do not download or execute language models.

No new live Zotero desktop/account transaction, installed full application
build, or actual Microsoft Word/LibreOffice reopen acceptance was performed
for this increment. Historical native acceptance in the guide retains its
original source identity. The Notes pane exposes main-flow paragraphs, not
note tables or text frames; the native engine can accept an anchored note table
paragraph supplied by an embedding host. Bibliographies still require a body
insertion point, and unsafe authored-note conversions are deliberately refused.
