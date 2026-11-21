# Incremental Word relayout (20 November 2026)

Typing in the Word view re-laid out the whole section on every keystroke —
for a one-section document, the whole document. The typing benchmark
(`packages/quds_office_editor/example/test/studio_typing_proofing_benchmark_test.dart`,
180 paragraphs, 21 pages, see
[typing-proofing-20261120.md](typing-proofing-20261120.md)) measured
~115–140 ms per keystroke in debug JIT, and all 300 of 300 keystrokes missed a
16.7 ms frame. This change makes a keystroke cost roughly the edited
paragraph, and an edit that moves everything below (Enter, a new wrapped
line) a re-pagination without reshaping, while producing exactly the layout a
full relayout produces.

## Root cause

`WordEditorController.relayout(localEdit: true)` (IME, typing, Backspace,
Delete, Enter, joins) called `WordLayoutEngine.layout(document,
fromSectionIndex: sectionIndexAtCaret, reuse: documentLaidOut)`. The engine's
only reuse was *section-level*: pages of sections before the caret's section
were copied, and the caret's section and every later section were laid out
from scratch (`_layoutSection`). In a one-section document that is the whole
document, every keystroke.

Of a full layout (117 ms for the benchmark document, local, debug), 103 ms is
line breaking (`LineBreaker.breakLines` with host run shaping,
`WordRunMetrics.measure`); placing lines and pages is the rest.

## Design

The body flow is greedy and forward-only: a top-level block's layout depends
only on the flow state when it starts — pages so far, page index, column,
y, column top, whether the page being filled has content, the preceding
paragraph's after spacing and the running paragraph index — and on the block.
There is no keep-with-next/widow control across top-level blocks today.

1. **Checkpoints.** Every layout records that state before each visible
   top-level block (`_Checkpoint`), plus the block's identity and paragraph
   text, and how each page was made (`_PageOrigin`: section, first-in-section,
   number of flow frames). It is stored on the `LaidOutDocument`
   (`supportsIncrementalReuse`).
2. **Dirty blocks.** A local edit passes `dirtyParagraphs` (the caret
   selection's paragraphs after the edit; the ruler passes its targets). The
   engine compares each section's visible blocks with the recorded ones:
   identity, text, and whether they contain a dirty paragraph. The longest
   clean prefix and suffix bound the dirty range (inserted/removed blocks
   included), widened by one block on each side (edits can adjust a
   neighbour, e.g. split/join).
3. **Resume.** Layout restarts at the first dirty block's checkpoint: finished
   pages before it are reused as they are, the partial page's earlier lines and
   frames are restored, and the flow continues.
4. **Converge and splice.** After the last dirty block, at every block
   boundary the flow state is compared with that block's old checkpoint. When
   equal (and no text-wrapping frame is on the page, and the set of sections
   on earlier pages agrees), the rest of the old layout is exactly what a full
   layout would produce: the old partial page's remaining lines/frames are
   joined with the new ones and the page is made again with its recorded
   arguments (chrome, line numbers); all later pages are reused. Paragraph
   indices of reused lines and boxes are shifted when paragraphs were
   inserted or removed (TOC-entry and line-number boxes keep theirs);
   carried-over checkpoints on the spliced page are corrected for a different
   number of lines in the new prefix (an empty paragraph has height but no
   line).
5. **Line-break cache.** Each paragraph's `BrokenLine`s are kept with the
   width environment they were made for (max width, break mode, document
   hyphenation/language). They are read only for blocks an incremental layout
   proved unchanged, so an edit that moves everything below re-paginates the
   rest of the document without reshaping it.

Fallbacks (the existing section-level path, i.e. previous behaviour):
field updates (non-local edits), missing or foreign state, a changed section
list, a change of note numbering, note references' sections or note content
(including a declared-dirty note paragraph), and the switch below.
Header/footer editing stays a full layout. Convergence is simply not declared
when a wrapping frame is on the page at that point. Footnotes, endnotes and
paint fitting are covered by the follow-up below.

Switches: `WordLayoutEngine.incrementalLayout` (start a build with
`--dart-define=QUDS_FULL_RELAYOUT=true` to turn it off: local edits then use
the section-level path) and `WordLayoutEngine.verifyIncrementalLayout`
(`--dart-define=QUDS_VERIFY_INCREMENTAL_LAYOUT=true`: after every incremental
layout a full layout runs and a mismatch throws, naming the first differing
fingerprint line). `WordIncrementalLayoutStats` counts incremental layouts,
convergences, fallbacks, blocks laid out and reused line breaks.

No line-box metric or layout rule changed; the change is checkpointing,
invalidation and reuse around the existing algorithms.

### Studio chrome

`SuiteWorkspace` rebuilt its whole chrome (ribbon, panes, status line) on
every Word controller notification. It now rebuilds on a Word notification
only when a value the chrome shows changes (`_wordChromeKey`: history and
dirty state, page count and visible page, caret paragraph and selection kind,
editing modes, selected objects, review pane, run and paragraph formatting at
the caret, text direction); the status line listens to the controller itself.
Anything outside the key is refreshed by one trailing rebuild 400 ms after
notifications pause.

## Equivalence (correctness gate)

`packages/quds_office_editor/test/word_incremental_layout_equivalence_test.dart`
drives the controller's real edit paths and, after every local edit, compares
`wordLayoutFingerprint(controller.documentLaidOut)` with the fingerprint of a
fresh engine's full layout of the same model (every line box and glyph
position, page assignment, list markers, boxes, header/footer and note
lines). Script per target paragraph (first, middle, last body paragraph and a
table-cell paragraph): typing, long text that wraps and pushes content to
later pages, typing mid-paragraph, Backspace, deleting the long text (content
moves back), Enter split + Backspace join, three empty paragraphs + typing +
six Backspaces, forward Delete join + Enter, a selection across three
paragraphs deleted, multi-line plain paste, bold (full relayout) then typing,
undo then typing.

Corpus: synthetic mixed German/English/Arabic (RTL) 120 paragraphs;
headings + TOC + lists + inline image + tables (one spanning pages) + page
breaks + justified/shaded paragraphs; four sections with continuous,
next-page and odd-page breaks, 2 and 3 columns, header/first-page
header/footer with page numbers and line numbers; footnotes, a footnote
continued onto the next page and endnotes (incremental since the follow-up);
and every `.docx` under the legacy parser and engine fidelity fixtures, the
Word-native layout references and four Word line-box references
(`QUDS_EQUIVALENCE_POI=1` adds the 48 Apache POI documents). An
engine-level test (`packages/quds_office_engine/test/word_incremental_layout_test.dart`)
covers direct model edits with a fresh engine (growth/shrink, insert/remove,
table cell, columns, later section, property changes, fallbacks).

Result (local): 61 passed, 8 skipped (image-only fixtures without
paragraphs); POI corpus 44 passed, 4 skipped; engine-level 6 passed. Two
documents (`bookmark_copy_expected.docx`, POI `WordWithAttachments.docx`)
used to stop their script when a cross-paragraph delete left a bookmark end
without its start; that editor bug is fixed (follow-up below) and the suite
now fails on any model error instead of printing it.

The fingerprint itself is checked to be deterministic (two full layouts
agree) for every document before editing.

## Results

### Controller micro-benchmark (local, debug, same document)

| Operation | Before | After |
|---|---|---|
| `insertText` (one character), p50 | 122 ms | 2.4 ms |
| `relayout(localEdit: true)`, p50 | 125 ms | 1.6 ms |
| Enter (moves everything below), p50 | ≈ full layout | 9.5 ms |
| Backspace join, p50 | ≈ full layout | 10.4 ms |

### Typing benchmark, local (MacBook, debug JIT, one build)

"before" is the same build with `--dart-define=QUDS_FULL_RELAYOUT=true`
(section-level path), run back to back; load average 2–5.

| Metric | Before | After (layout) |
|---|---|---|
| Keystroke handler p50 / p95 / max (ms) | 115.0 / 158.3 / 242.8 | 3.7 / 10.6 / 226.8 |
| Frame after keystroke p50 / p95 (ms) | 7.4 / 13.9 | 6.3 / 12.0 |
| Keystrokes over 16.7 ms (handler + frame) | 300 / 300 | 36 / 300 |

The remaining maximum is the first keystroke after the document was loaded
(paint-fitted): one full layout that records state.

### Studio chrome A/B, local (both with incremental layout)

"off" is `suite_workspace.dart` from main (workspace rebuilds on every Word
notification), "on" is the branch; alternated in two rounds, load average
6–7 (1 min). Values are round 1 / round 2.

| Metric | Chrome rebuild per keystroke (off) | Selector (on) |
|---|---|---|
| Keystroke handler p50 / p95 (ms) | 5.6 / 14.2 · 5.4 / 18.7 | 5.3 / 10.7 · 5.3 / 11.2 |
| Frame after keystroke p50 / p95 (ms) | 8.8 / 22.5 · 9.6 / 25.9 | 8.3 / 18.8 · 8.8 / 19.8 |
| UI-isolate work between keystrokes p50 / p95 (ms) | 31.6 / 80.2 · 34.9 / 80.1 | **0.5 / 6.5 · 0.5 / 5.5** |
| Keystrokes over 16.7 ms (handler + frame) | 108 · 119 | 64 · 77 |
| Rebuilds: workspace / ribbon | 310 / 310 | **13 / 13** |
| Rebuilds: Word editor / status line | 601 / 310 | 313 / 313 |
| Rebuilds: review strip status button | 311 | 19 |

The workspace rebuild ran in a post-frame callback, so it showed up as work
between keystrokes (~32 ms each), competing with the next keystroke and
proofing; it is now gone except when the chrome's shown state changes.
Proofing counters (passes, provider calls, detections, findings) are
unchanged.

### Hosted runners

Workflow `Incremental layout benchmark`
(`.github/workflows/incremental-layout-benchmark.yml`): typing benchmark ×3 on
macOS and Ubuntu, and editor/engine/Studio suites, each on the merge base
("before", `e59b8918`-era main at the merge base) and the branch ("after").
Run 44730466515, three benchmark runs per job, each variant on its own VM.

| Runner | Variant | Handler p50 / p95 (ms) | Frame p50 / p95 (ms) | Between keystrokes p50 (ms) | Over 16.7 ms |
|---|---|---|---|---|---|
| ubuntu-latest | before | 163.4 / 229.1 · 165.3 / 234.0 · 163.0 / 224.4 | 10.1 / 17.7 · 10.2 / 18.4 · 9.9 / 18.0 | 42.9 · 43.7 · 42.2 | 300 · 300 · 300 |
| ubuntu-latest | after | **4.8 / 8.6 · 4.9 / 8.0 · 4.9 / 9.0** | 7.3 / 16.7 · 7.3 / 17.6 · 8.0 / 17.0 | **0.4 · 0.4 · 0.5** | **46 · 53 · 53** |
| macos-latest | before | 227.8 / 387.6 · 268.7 / 424.0 · 205.4 / 351.3 | 14.9 / 40.1 · 15.5 / 39.2 · 13.0 / 31.7 | 55.5 · 60.1 · 47.9 | 300 · 300 · 300 |
| macos-latest | after | **5.7 / 13.3 · 5.7 / 12.7 · 5.4 / 10.5** | 9.3 / 24.5 · 9.7 / 24.5 · 8.4 / 21.6 | **0.7 · 0.6 · 0.6** | **126 · 136 · 100** |

Rebuilds per 300 keystrokes, identical on every hosted run: workspace and
ribbon 310 → 13, Word editor 601 → 313, review-strip status button 311 → 19.
Proofing counters unchanged (11 passes, 22 provider calls, 66 findings).
The remaining keystrokes over budget are dominated by the debug-mode frame
(build/paint of the editor, p95 17–25 ms) rather than the handler; the
maximum handler time is the one full layout after the paint fit at load.

Suites on the same run (failing test names compared, not counts):

| Suite | Before | After |
|---|---|---|
| Editor (`flutter test`) | 22 failing (goldens, frame wrap, tab gap, bookmark history, Zotero guards) | the same 22 names; the new equivalence suite passes |
| Engine (`dart test`) | 0 failing | 0 failing, incl. the new engine-level test |
| Studio example (`flutter test`) | 7 failing (licence pages, keychain probes, gallery dump, saved mail) | the same 7 names |

## Follow-up (20 November 2026, evening)

### Cross-paragraph delete orphaned bookmark endpoints

Root cause: `_deleteStructuredSelection` removes every top-level block the
selection covers completely and trims the partially covered first and last
paragraphs. Trimming keeps zero-width inlines (`WmlRunEdit.replaceRange`), but
a removed block took its `WmlBookmarkBoundary` endpoints with it. A bookmark
starting in a removed paragraph and ending in a kept one (or the reverse) kept
one half; the next full relayout (`WordLink.ensureHeadingBookmarks` →
`WordBookmarks.ranges`) or save threw "Bookmark end … has no matching start".
The same happened in header/footer/comment stories (`_deleteStorySelection`
drops the paragraphs between the first and last) and when deleting a table.

Fix (Word's rule): `WordBookmarks.clampRemoved` runs after the removal with the
endpoints collected from the removed paragraphs. A range with both endpoints
removed is gone; a range with one endpoint removed keeps its name and the lost
endpoint is reinserted at the deletion point (the end of the trimmed first
paragraph, the join point in a story, or the start of the paragraph after a
deleted table), i.e. it is clamped to the remaining content. Undo restores the
original endpoints. Other paired markers: comment ranges are per-run
`commentIds` and are written from them, so they cannot be orphaned (tested);
inline content-control boundaries cannot span paragraphs; permission ranges
are not modeled; complex-field boundaries cut by a delete were already
degraded to plain result text by the serializer (`WordFieldSpans.unbalanced`).

Tests: `packages/quds_office_editor/test/word_cross_paragraph_marker_delete_test.dart`
(both fixtures, enclosed and cut ranges, starts and ends removed, table
deletion with undo, comment ranges, header story; every case saves, checks
the saved `document.xml` pairs every bookmark (and comment) endpoint, and
reopens to the same ranges). In the equivalence suite both fixtures now run
their whole script. Found separately, not changed here: the serializer writes
a comment range spanning paragraphs as one start/end/reference triple per
paragraph, and `WordWithAttachments.docx` gets an extra preserved
`commentRangeEnd` from source XML on save even without edits.

### First keystroke after paint fitting or a formatting change

Root cause: `fitPaintMetrics` (document load, formatting changes, table and
object edits) moves glyphs in place and therefore discarded the incremental
state, so the next keystroke was a full layout (≈150 ms on ubuntu-latest,
debug JIT).

Fix: `_fitLaidOut` records the engine values it overwrites (line x/width,
glyph x/advance — everything fitting changes) in a `Float64List` keyed to the
layout. The next local edit puts them back (O(glyphs), well under a
millisecond) and relayouts incrementally; the result is unfitted, exactly as
the full relayout after an edit was before. The section-level path
(`QUDS_FULL_RELAYOUT=true`) still discards the state of a fitted layout.

### Footnotes and endnotes on the incremental path

Note placement is part of the flow state: each checkpoint records the number
of footnotes placed (a prefix of the placement order) and the note slices
already reserved on pages not yet finished. A layout keeps the final slices
per page, the placement order, the shaped note stories, the number of flow
pages, the page endnotes were appended to (and its note lines/frames before
them), and signatures of note order/labels/reference sections and note
content. Resuming restores finished pages' slices and the checkpoint's pending
slices and placements; convergence additionally requires equal placements and
identical pending slices; the splice takes the old final slices for the
reused pages and the rest of the old placement order. Note-overflow pages and
endnotes are made again after the flow (the old endnote page is reused
without its endnote lines). Any change of numbering, labels, reference
sections or note content falls back.

### Results (hosted, `Incremental layout benchmark`)

New in the benchmark: `TYPING_BENCHMARK_KEYS`, controller-level `insertText`
cost (layout included, no widgets) in the 180-paragraph benchmark document:
10 rounds of fit → first keystroke, 5 more keystrokes, bold toggle → first
keystroke; then 100 keystrokes in the same document with six footnotes and
two endnotes (21 pages). Three runs per job, p50 / p95 in ms.
"before" = `5ad4461a` (branch point), "after" = `81691cde`; run 44793468103,
except macOS "before", which comes from run 44818807443 (`base=5ad4461a`):
the first run's macOS "before" job started after main had integrated this
branch, so its merge base was the branch itself.

| Runner | Variant | First after fit | First after formatting | Following keys | Notes document | Notes, first key |
|---|---|---|---|---|---|---|
| ubuntu-latest | before | 153.5 / 231.2 · 149.5 / 222.8 · 154.5 / 219.5 | 152.4 / 226.9 · 150.7 / 208.5 · 149.8 / 205.6 | 2.8 / 6.7 · 2.7 / 7.5 · 2.7 / 6.3 | 161.2 / 243.0 · 159.3 / 233.4 · 159.8 / 230.8 | 161.6 · 161.0 · 154.4 |
| ubuntu-latest | after | **3.8 / 7.1 · 2.7 / 6.6 · 2.6 / 6.8** | **3.6 / 5.2 · 2.8 / 5.1 · 2.8 / 5.7** | 1.6 / 3.2 · 1.6 / 6.2 · 1.7 / 2.6 | **1.7 / 3.6 · 1.6 / 3.5 · 1.8 / 3.3** | **6.2 · 7.6 · 8.6** |
| macos-latest | before | 168.3 / 264.4 · 252.2 / 311.0 · 212.5 / 270.6 | 157.2 / 278.7 · 212.3 / 421.8 · 183.8 / 256.1 | 2.7 / 4.1 · 3.3 / 9.2 · 2.9 / 6.2 | 175.5 / 285.6 · 217.7 / 342.4 · 203.9 / 312.5 | 124.6 · 170.6 · 208.2 |
| macos-latest | after | 4.0 / 11.9 · 2.9 / 6.3 · 3.2 / 8.2 | 3.6 / 5.3 · 2.7 / 4.7 · 2.7 / 4.8 | 2.0 / 3.3 · 1.8 / 3.0 · 1.8 / 2.6 | 2.5 / 3.9 · 2.6 / 4.1 · 2.3 / 3.5 | 7.7 · 6.4 · 6.0 |

Second run (44818807443, "before" `5ad4461a`, "after" the branch with
current main merged), p50 of the three runs: ubuntu first-after-fit
135.0 · 138.3 · 138.4 → **3.2 · 3.5 · 3.3**, first-after-formatting
132.2 · 136.4 · 136.5 → **3.2 · 2.6 · 2.8**, notes document 137.9 · 140.3 ·
141.0 → **1.7 · 1.6 · 1.7**; macOS first-after-fit 3.5 · 5.0 · 4.8,
first-after-formatting 4.3 · 4.2 · 6.1, notes document 3.4 · 3.6 · 5.5 (after).

Studio typing benchmark (300 keystrokes through the IME, handler p50 / p95 /
max ms, keystrokes over 16.7 ms):

| Runner | Variant | Handler | Over 16.7 ms |
|---|---|---|---|
| ubuntu-latest | before | 5.3 / 9.4 / 351.9 · 4.9 / 8.3 / 360.9 · 5.0 / 8.6 / 353.8 | 57 · 35 · 39 |
| ubuntu-latest | after | 3.6 / 7.8 / 243.2 · 3.5 / 6.8 / 201.5 · 3.9 / 7.8 / 202.6 | 27 · 24 · 26 |
| macos-latest | before (44818807443) | 6.1 / 14.2 / 483.6 · 6.7 / 18.4 / 403.2 · 5.9 / 15.5 / 457.8 | 157 · 206 · 149 |
| macos-latest | after | 4.9 / 11.7 / 303.6 · 3.7 / 5.6 / 232.7 · 4.4 / 8.2 / 282.6 | 79 · 17 · 43 |

The remaining Studio maximum (one keystroke of ~200 ms) is not layout: the
controller-level first keystroke after the fit is 3–4 ms. It is the first
IME keystroke in the widget test (first-use costs outside the layout path);
attributing it is open.

Suites on the same run (failing test names compared): editor 20 / 20, same
names (the new marker-delete and equivalence tests pass); engine: the same
names plus `office_vba_powerpoint_cli_test.dart` "late PowerPoint failure and
extension mismatch preserve existing output" (the VBA CLI lane being fixed
separately on main); Studio: 5 before, 1 after (`dump_gallery_shots_test`).

## Remaining work

- The first IME keystroke in the Studio benchmark still cost ~200 ms: traced
  and fixed in [keystroke-trace-20261121.md](keystroke-trace-20261121.md) (the
  benchmark assigned a new document without a relayout; the first keystroke
  was that document's first, full layout).
- Paint fitting still runs over the whole document after formatting changes;
  fitting only changed lines would make those edits cheaper as well.
- A future keep-with-next/widow rule across top-level blocks must extend the
  dirty range (or disable reuse) — the equivalence suite will catch it.
