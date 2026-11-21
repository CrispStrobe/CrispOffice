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
