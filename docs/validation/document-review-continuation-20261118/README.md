# Document review continuation — 18 November 2026

## Result

Writing findings and change decisions remain available inside the editable Word
workspace. This continuation adds stable incremental findings, progressive
results, richer persistent review controls, and a bounded action-feedback area.
It builds on the earlier live review and read-only two-document comparison.

The final product validation ran on commit
`3925c63fca2f824a95566c1258caf5db1086e530`, tree
`5e46936f2bc1d6ae9484aba4e9086a69d4605915`.
Later delivery commits contain documentation, validation records and visual
fixtures; the tested application source remains unchanged.

**361 tests passed, zero failed and zero skipped.** Strict analysis, formatting
and whitespace checks passed. All 610 recorded source, selected-test, manifest
and font files matched before and after the run. GitHub Actions status was
neither queried nor awaited.

## What changed

### Writing checks during editing

An edit immediately invalidates the affected paragraph's findings. Findings
from unchanged paragraphs are verified against their current text, language,
story, field state and protection, then rebound to the current document revision.
They remain visible and actionable during the typing pause and the next check.

New results appear before the whole document finishes. Progress publication is
bounded to avoid rebuilding the entire review state for every short paragraph.
A partial result does not claim complete document coverage. Unavailable or
failed providers retain their explicit coverage information.

A current inline suggestion menu stays open during unrelated progress.
Choosing a correction while another paragraph is checking remains undoable;
older responses cannot resurrect stale findings. Correction and stale-source
feedback stays visible above the pane's scrolling content.

Ordinary background providers retain the 400 ms debounce. Manual providers run
only for explicit Check document/F7 requests. A full check can supply its
ordinary results to subsequent background checks, but background mode never
inherits manual findings or manual coverage. Repeated explicit requests share
the active check even after it publishes progress.

The Writing pane now exposes document-language selection and
**Review ignored findings again**. Language changes are undoable and preserve
explicit run and paragraph languages. Restoring ignored findings preserves
personal dictionary entries and does not invoke manual inference. F7 also works
from pane controls.

### Changes without leaving the document

The Changes pane now provides:

- Collapsible author, change-type and text filters, with shown/total counts.
- Navigation through exactly the displayed changes.
- Accept N shown / Reject N shown, using whole-batch validation and one undo step.
- All markup, original and final paragraph previews that do not resolve changes.
- Current source-attachment checks and explicit invalid/conflicted-range notices.
- Inspection of valid protected text while keeping mutation controls disabled.
- The next pending change after a decision, or the nearest previous change at
  the end; Undo/Redo retain the corresponding review selection.

The paragraph preview includes all pending changes in that paragraph, regardless
of the list filter. English, Arabic/RTL, narrow layouts, large text, keyboard
access and viewing mode are covered by interaction tests.

See the [usage and embedding guide](../../document-review.md).

## Incoming work

The [initial audit](incoming-audit.json) enumerated 204 fork branches, 165 PR
heads across all states, and four upstream branches. They matched the previous
saved frontier apart from the review branch's already-saved evidence commits.
Main `f383c826` and the late native-spelling evidence were already included.
The audit preserves the earlier ancestry and equivalence evidence for
superseded branch heads.

During implementation, a new Zotero citation-workflow branch and PR #166
appeared, and main advanced with two thesaurus planning/documentation commits.
The [late integration record](late-integration.json) accounts for **205 fork
branches, 166 PR heads and four upstream branches**.

| Input | Integrated head |
| --- | --- |
| Main | `556c55c0ef312eda2cca11600021d293a81ab44b` |
| Zotero citation workflow / PR #166 | `3668ed92829dfa012ec5b129943a86738ebb7992` |
| Review source before integration | `3a36ae46ea99ceaa1c212ae5cfe08bc501bb0229` |
| Remote integration commit | `40790cb2c8c0ebe8c4a6472f3378fa581abf0b00` |

The integration used Git's actual three-way merge. Three conflicts were
resolved: both changelog groups were retained, and the current review pane and
regressions were preserved over incoming formatting of their earlier versions.
All five latest-main documentation files match main exactly. Incoming Zotero
implementation, tests and validation records were retained.

The remotely created integration tree exactly matched the local Git result
`02e5b6d5baa127921beff46d4c0aec822f3a5204`. Both incoming heads are ancestors
of the final tested source. No incoming branch was force-pushed or rewritten.

## Final local validation

| Gate | Result |
| --- | --- |
| Editor, 26 suites | 348 passed; 0 failed; 0 skipped |
| Studio, 3 suites | 13 passed; 0 failed; 0 skipped |
| Total | **361 passed; 0 failed; 0 skipped** |
| Strict analysis of 17 changed Dart files | No issues; exit 0 |
| Formatting | Clean; exit 0 |
| Whitespace | Clean; exit 0 |
| Before/after source binding | 610 files; no mismatches |
| HEAD / tracked working tree during checks | Unchanged / clean |

The run includes **40 new document-review regressions** in this continuation,
existing proofing, selection, gestures, focus/IME, revision and comparison
coverage, plus **49 tests for the newly integrated Zotero workflow**.
The four visual fixture cases and performance diagnostics are counted
separately.

The identical before/after manifest hash is:

```text
0f13ff2d5d64ee49ddfe8fd9f7f78ea09c560af0527cc2476e16b46e60a8cc28
```

Evidence:

- [Final verification receipt](checks/verification.json)
- [Editor case results](checks/editor-cases.json) and
  [raw editor events](checks/editor.jsonl.gz)
- [Studio case results](checks/studio-cases.json) and
  [raw Studio events](checks/studio.jsonl.gz)
- [Strict analysis](checks/analysis.log), [formatting](checks/format.log),
  [whitespace](checks/whitespace.log)
- [Before source manifest](checks/source-before.json) and
  [after source manifest](checks/source-after.json)
- [Reproducible check runner](run_checks.py)
- [Runtime provenance](runtime.json)

The runtime is Flutter **3.47.8** / Dart **3.13.7**. The official SDK archive,
Dart executable, Flutter test executable and locked dependency archives were
verified against the recorded hashes. Dependency resolution was offline with
the lock enforced. No product manifests or SDK pins were changed.

Earlier failed attempts are preserved separately under [attempts](attempts).
They include the test-fixture expansion timing correction, a typed fixture-list
repair, an old selection expectation updated for retained findings, and the
initial full run that exposed offscreen action feedback. The original stale
action regression passed unchanged after the product feedback fix. Those
earlier attempts are not substituted for the final passing run above.
An [early proofing prototype patch](attempts/root-early-prototype.patch.gz) is also
preserved from the older restored checkout; it is historical working material,
not the final application source.

## Typing-cost diagnostic

A weak per-paragraph snapshot cache reuses grapheme segmentation only after a
fresh scan confirms unchanged text, language runs, story membership, field
boundaries, generated-content flags, control protection and revision guards.
Field depth is updated before reuse, including fields spanning sections.
When there are no provider results to retain, invalidation stays behind the
normal typing debounce.

The same local Flutter-test JIT fixture used 500 paragraphs of approximately
80 characters, 30 warm-up edits and 100 measured edits. It timed only
`observeDocument()`, excluding setup and painting.

| Fixture | Median before | Median after | p95 before | p95 after |
| --- | ---: | ---: | ---: | ---: |
| No findings | 5.880 ms | 1.8445 ms | 9.067 ms | 2.804 ms |
| 499 retained findings after each edit | 9.766 ms | 5.0895 ms | 14.426 ms | 6.707 ms |

These are proofing-update measurements on this host, not complete editor frame
times, native build results or a performance guarantee. The recorded raw events
contain the fixture's reported statistics; individual per-edit samples were
not emitted.

[Method, source hashes and results](performance/summary.json) ·
[Executed fixture and publication normalization](performance/invalidate_timing_test.dart) ·
[Before events](performance/before.jsonl) · [After events](performance/after.jsonl)

## Visual review

The [rendering harness](render_previews.dart) uses the actual editable document
canvas and review pane with bundled Liberation Sans, Noto Naskh Arabic and
Material Icons. Documents and checker results are visibly labelled fixtures;
they do not represent installed native-model output.

Four visual cases produce seven images, inspected separately from the regression
test count. The fixtures include fitted narrow canvases and assert that no open
menu obscures a capture:

| View | Image |
| --- | --- |
| Original paragraph preview | [Desktop original](screenshots/changes-original-desktop.png) |
| Final paragraph preview | [Desktop final](screenshots/changes-final-desktop.png) |
| Expanded filters and batch controls | [Desktop controls](screenshots/changes-filter-controls-desktop.png) |
| Filtered batch review | [Desktop filtered](screenshots/changes-filtered-desktop.png) |
| Findings while later text is checking | [Writing in flight](screenshots/writing-in-flight-desktop.png) |
| Narrow English layout | [English](screenshots/changes-english-narrow.png) |
| Narrow Arabic/RTL layout | [Arabic](screenshots/changes-arabic-narrow.png) |

[Rendering receipt](visual-verification.json) · [Raw rendering events](visual-events.jsonl.gz)

## Remote preservation

[Publication records](publication.json) identify the incremental checkpoints,
their parent and tree hashes, and readback checks. Each branch update used the
expected previous head without force-pushing. Commit messages include
`[skip ci]`.

The source checkout and test runtime had to be restored after the initial
scratch environment disappeared. Remote checkpoints retained the work, and the
recovered runtime independently performed the final checks recorded above.

## Scope

This validation covers the targeted local controller, widget and interaction
workflows and their incoming Zotero integration. It does not claim a complete
repository test run, full platform application builds, native macOS UI
execution, or live optional-model inference. Tracking remains supported text
insertions/deletions; document comparison remains a read-only report.
