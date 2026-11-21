# The slowest Studio keystroke (21 November 2026)

After incremental layout ([incremental-layout-20261120.md](incremental-layout-20261120.md))
the Studio typing benchmark
(`packages/quds_office_editor/example/test/studio_typing_proofing_benchmark_test.dart`,
see [typing-proofing-20261120.md](typing-proofing-20261120.md)) still had one
keystroke of ~200–360 ms per 300-keystroke run, while the
controller-level first keystroke after a paint fit cost 3–4 ms. This traces
that keystroke and fixes it.

## Instrumentation

- `WordEditorController.debugEditPhase` (null in normal use) receives the
  phases of a typed keystroke: `model` (text and direction sync), `undo`
  (undo snapshot and command commit, including the listeners the command
  stack notifies), `layout` (relayout), `caret`, `notify` (listener
  fan-out). With `WordEditorController.debugTimeListeners` on when listeners
  are added, every controller listener is timed by name.
- The widget benchmark now reports per-phase distributions, the eight
  slowest keystrokes with their phases, and after which keystrokes a
  proofing pass ended.
- `integration_test/typing_profile_test.dart` runs the same document and
  300-keystroke script in **profile mode** on the Linux embedder
  (`flutter drive --profile -d linux` under Xvfb, driver
  `test_driver/typing_profile_driver.dart`). Each handler is a
  `KEY_HANDLER` `TimelineTask`; the run is recorded with `traceAction`
  (GC, frame build/raster), phases come from the same hook.
  `tool/perf/keystroke_trace_report.py` prints the slowest keystrokes, the GC
  slices inside each handler, and frame and phase totals.
- Workflow `Keystroke trace` (`.github/workflows/keystroke-trace.yml`):
  both harnesses, three runs each, with the fix switched off and on in the
  same build (`--dart-define=QUDS_LAZY_DOCUMENT_LAYOUT=false`).

## Finding

In every run the slowest keystroke is **keystroke 0**, and almost all of it
is `layout`: debug 327–365 ms of which 313–353 ms layout; profile
111–126 ms of which 110–123 ms layout. The other phases of key 0 are under
5 ms, there is no GC inside any handler (profile timeline: 0.0 ms; 5–9 ms
of GC in the whole run, all between frames), and no other keystroke comes
close.

Cause: the benchmark (like any host that swaps documents) assigns
`controller.document = …` and calls `refresh()`, which only notifies.
`documentLaidOut` stayed the **previous document's** layout, so the canvas
kept painting the old layout and the first keystroke was the first layout
of the new document — a full one (the incremental path rejects state of
another document). Worse, the fallback could reuse pages of the old document
for sections before the caret's. Studio's own open path
(`loadBytes` → `_acceptOpenedWord` → `relayout()`) lays out before typing,
so the cost lands on the first keystroke only where a document is assigned
without a relayout — but then always.

Ruled out by the same measurements: undo snapshots (`undo` p50 0.5 ms; the
snapshot clones one paragraph's inlines, not the document), listener fan-out
(p50 0.3–0.4 ms per listener), proofing scheduling (passes end after
keystrokes 23, 48, 73, …; none of those is slow), caret/selection (< 1 ms),
GC (none inside handlers), periodic work (no every-Nth pattern).

## Fix

- Assigning a different `document` marks the layout stale; the next read of
  `documentLaidOut` (the canvas's next paint) or `relayout()` lays the new
  document out in full. `relayout(localEdit: true)` on a replaced document
  is a full layout. Switch: `WordEditorController.layoutReplacedDocumentOnRead`
  (`--dart-define=QUDS_LAZY_DOCUMENT_LAYOUT=false` keeps the old layout until
  the next relayout, as before).
- The engine no longer reuses pages of a layout made for another document
  (`layout(reuse:)` with foreign state lays out from the start).

Tests (equivalence suite): a replaced document is laid out on the next read
and equals a fresh full layout; its first keystroke is incremental; with the
switch off the old layout stays until the first edit, which lays the new
document out in full and equals a fresh layout.

## Results (GitHub-hosted ubuntu-latest, same build, switch off / on)

Run 44873417666, three runs per variant. Handler p50 / p95 / max in ms.

| Mode | Switch | Handler | Slowest keys | Over 16.7 ms |
|---|---|---|---|---|
| debug (widget test) | off | 3.2 / 8.1 / 183.8 · 3.2 / 5.8 / 198.3 · 3.2 / 7.4 / 188.3 | key 0 in every run | 22 · 18 · 22 |
| debug (widget test) | on | 3.1 / 6.2 / **13.7** · 3.0 / 6.3 / **17.6** · 3.1 / 5.8 / **16.5** | 0, 99, 173, 17 | 22 · 21 · 16 |
| profile (Linux, Xvfb) | off | 4.5 / 10.3 / 111.4 · 4.5 / 10.2 / 126.1 · 4.5 / 11.8 / 116.2 | key 0 in every run | — |
| profile (Linux, Xvfb) | on | 4.8 / 12.3 / **25.6** · 4.9 / 12.9 / **29.2** · 5.0 / 12.6 / **24.5** | 235, 176, 152 | — |

(Run 44871878582 agrees: debug max 257–304 → 20–23 ms.) Profile frame build
p50 5.3–5.5 ms; raster p50 29–44 ms is Xvfb's software rasterizer, not
representative of a GPU. A local interleaved debug A/B (load average 7–15)
gave max 318.7 → 18.5 ms.

The profile handler p50 (~4.5 ms) is close to debug's: on Xvfb the
host-shaped run measurement (`TextPainter` per run) dominates layout in
both modes.

## Next targets (measured, not changed here)

- **Line-wrapping keystrokes** (keys ~150–250 in profile, 10–24 ms, almost
  all `layout`): a new line moves everything below; the flow re-paginates
  with cached line breaks until a page break absorbs the shift.
- **Studio chrome listener spikes**: `_rebuildWord` (SuiteWorkspace)
  occasionally takes 9–21 ms in profile, always inside the `undo` phase,
  i.e. when the command stack's notification during the commit reaches the
  controller's listeners (they run again from the keystroke's own
  notification).

## Follow-up: line-wrapping keystrokes and chrome notifications

### Why a wrapped line re-paginated the rest of the document

A keystroke that adds a line moves every later block down by one line. The
incremental layout converges only where the flow state at a block boundary
equals the previous layout's (page, column, y, lines on the page, notes):
with greedy page filling the shift carries over every page break (each page's
last line moves to the next page), so in a document without hard breaks it
never converges and every later block was laid out again — from cached line
breaks, but still through paragraph placement (run properties, metrics,
glyph construction, hyperlink/comment lookups per glyph): ~91 blocks for a
keystroke at paragraph 90 of 180.

### Translation of unchanged paragraphs (`QUDS_TRANSLATE_PARAGRAPHS`)

An unchanged paragraph that the previous layout placed entirely on one page
(no frames, no notes, no breaks) and that the flow now reaches on the same
page and column, with the same column top and adjacent spacing, is not laid
out again: its previous lines move to the new height. Every line top and
glyph baseline is recomputed with paragraph layout's own arithmetic (line
heights, recorded baseline leading/ascent and vertical-alignment shift), so
the result is bit-identical to a fresh layout; a paragraph whose lines would
cross the page bottom is laid out normally. Only the paragraph that crosses
each page boundary is re-placed (from cached breaks). The line objects move
from the replaced layout (no copies). Switch:
`WordLayoutEngine.translateParagraphs`
(`--dart-define=QUDS_TRANSLATE_PARAGRAPHS=false`). Equivalence: full suite
71 passed / 8 skipped, POI corpus 44 / 4, engine incremental tests 25, plus a
switch-off test.

Per wrapping keystroke at paragraph 90 (engine only, JIT warmed, 51 wrapping
keystrokes of 4000, interleaved, MacBook, 1-min load noted), p50 / p95 / max:

| Run | Load | Translation off | Translation on |
|---|---|---|---|
| 1 | 16.2 / 17.3 | 21.6 / 89.3 / 106.9 ms | **4.4 / 11.7 / 22.3 ms** |
| 2 | 16.3 / 25.0 | 24.0 / 72.7 / 122.2 ms | **5.8 / 45.1 / 71.3 ms** |

Non-wrapping keystrokes p50 2.2–2.7 → 1.9–2.7 ms. A temporary phase split
(load ~50) put 2.35 s of 2.52 s in paragraph placement without translation;
with it, translation cost 4 µs per block.

### Chrome notifications (`QUDS_COALESCE_EDIT_NOTIFY`)

Every typing edit commits an undo command; the command stack's notification
made the controller notify its listeners before the relayout, and the edit
notified them again afterwards: 10 listener calls per keystroke in Studio,
two of them `SuiteWorkspace._rebuildWord`. Typing edits (`insertText`,
Backspace/Delete, Enter, IME updates) now fold the command notification into
their own: one notification per keystroke, after the relayout. Switch:
`OfficeController.coalesceEditNotifications`
(`--dart-define=QUDS_COALESCE_EDIT_NOTIFY=false`); test
`word_edit_notification_test.dart` (once vs. twice, undo intact).

What `_rebuildWord` costs: computing the chrome key walked the document four
times — `document.paragraphs.toList()` (87 µs in debug for 180 paragraphs),
`activeRunProps` (114 µs), `tableAtCaret` (190 µs) and `sectionAtCaret`
(160 µs) each list every paragraph. For body typing the key now derives run,
table and section from the one paragraph it already found. The 9–21 ms
profile-mode spikes attributed to it earlier coincided with layout spikes on
the same 2-core runner while Xvfb's software rasterizer ran (raster p50
29–44 ms per frame); they are not the listener's own work.

Studio typing benchmark (debug, 300 keystrokes, the same build with
`QUDS_TYPING_BENCHMARK_BASELINE=1` switching both off; interleaved, load
10–15 at the start of each run):

| Run | Variant | Chrome calls per key (p50/max) | Listener calls per key | Chrome ms per key p50 / p95 / max | Wrapping keys handler p50 / p95 / max (n=8) |
|---|---|---|---|---|---|
| 1 | off | 2 / 3 | 10 | 0.27 / 0.50 / 8.56 | 18.5 / 42.5 / 42.5 |
| 1 | on | **1 / 2** | **5** | 0.17 / 0.48 / 5.57 | 14.7 / 98.3 / 98.3 |
| 2 | off | 2 / 3 | 10 | 0.58 / 1.67 / 21.5 | 44.5 / 54.0 / 54.0 |
| 2 | on | **1 / 2** | **5** | 0.26 / 0.60 / 2.67 | 19.1 / 21.5 / 21.5 |

The call counts are deterministic; the Studio timings at this load (another
lane's release build left the machine at 10–40) vary by 2–3× between runs of
the same variant, so the engine-only table is the timing evidence. Headline
hosted numbers were not taken: GitHub Actions concurrency for the account was
saturated by other repositories.
