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
footnotes/endnotes (page reserves and note numbering are document-wide), field
updates (non-local edits), missing or foreign state, a changed section list,
and the switch below. Header/footer editing stays a full layout. Paint-metric
fitting (`fitPaintMetrics`) moves glyphs in place, so it discards the state;
the next local edit lays out once from the start and is incremental after
that. Convergence is simply not declared when a wrapping frame is on the page
at that point.

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
header/footer with page numbers and line numbers; footnotes (fallback path);
and every `.docx` under the legacy parser and engine fidelity fixtures, the
Word-native layout references and four Word line-box references
(`QUDS_EQUIVALENCE_POI=1` adds the 48 Apache POI documents). An
engine-level test (`packages/quds_office_engine/test/word_incremental_layout_test.dart`)
covers direct model edits with a fresh engine (growth/shrink, insert/remove,
table cell, columns, later section, property changes, fallbacks).

Result (local): 61 passed, 8 skipped (image-only fixtures without
paragraphs); POI corpus 44 passed, 4 skipped; engine-level 6 passed. Two
documents (`bookmark_copy_expected.docx`, POI `WordWithAttachments.docx`)
stop their script when a cross-paragraph delete leaves a bookmark end without
its start and the next *full* relayout rejects the model
(`WordLink.ensureHeadingBookmarks`): an editor issue independent of this
change, reported by the suite rather than hidden.

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

### Hosted runners

Workflow `Incremental layout benchmark`
(`.github/workflows/incremental-layout-benchmark.yml`): typing benchmark ×3 on
macOS and Ubuntu, and editor/engine/Studio suites, each on the merge base
("before") and the branch ("after"). Results: see below (pending).

## Remaining work

- The first local edit after a paint-metric fit lays out the whole document
  once; fitting only new lines (or making fitting non-destructive) would
  remove it.
- Footnote/endnote documents still use the section-level path: checkpoints
  would need the note reserves and note numbering state.
- A future keep-with-next/widow rule across top-level blocks must extend the
  dirty range (or disable reuse) — the equivalence suite will catch it.
