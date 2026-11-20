# Typing latency and as-you-type proofing (20 November 2026)

The owner reported that typing in the Word view lags, that every keystroke
seems to trigger a spelling/grammar recheck, and that the status bar is redrawn
constantly ("Waiting to check…"). This records the measurements, the root
causes, the changes and the remaining work.

## Benchmark

`packages/quds_office_editor/example/test/studio_typing_proofing_benchmark_test.dart`
(skipped unless `QUDS_TYPING_BENCHMARK=1`) mounts the full Studio, loads a
mixed German/English/Arabic document of 180 paragraphs (21 laid-out pages),
lets the initial check settle and then types 300 characters through the real
IME path into paragraph 91: 150 characters at 8–12.5 characters per second, a
100-character burst at ~33 characters per second, a 1.2 s pause and 50 more
characters. The Studio's ordinary providers (German spelling, German writing
rules, Arabic writing rules) are wrapped in counters, and a counting language
detector stands in for CLD3 (2 ms isolate round trip). It prints one
`TYPING_BENCHMARK {json}` line:

| Field | Meaning |
|---|---|
| `handlerMs` | IME update through every synchronous controller listener (proofing, editor, Studio), per keystroke |
| `frameMs` | The following frame: build, layout, paint |
| `backgroundMsPerGap` | Main-isolate time spent in timers before the next keystroke (proofing passes) |
| `jankyKeystrokeFrames` | Keystrokes whose handler + frame exceeded 16.7 ms |
| `proofingPasses`, `providerCalls`, `detectorCalls/Texts` | Proofing work |
| `sessionNotifications`, `controllerNotifications` | Change notifications |
| `rebuilds` | Element rebuilds of the Studio status line, review strip (`reviewStripLabel` = its status button, `reviewStrip` = the strip itself), workspace, ribbon and Word editor |
| `statusLabelChanges` | Changes of the visible writing-status label |

A second, widget-free test prints `SESSION_KEYSTROKE`: the proofing session's
own synchronous cost per keystroke (observe the edit, then read the findings
the canvas paints), on the same document with settled results.

Widget tests run in debug JIT with fake time. Absolute numbers are higher than
a release build; only compare runs made back to back under similar load. The
local runs below alternate base and branch builds in one worktree
(base `c16e1213`, the branch point); load averages are recorded with each run. The
`Typing proofing benchmark` workflow repeats the comparison on hosted
macOS and Ubuntu runners.

## Root causes (evidence)

1. **Every keystroke republished the whole document's proofing state.**
   `WordProofingSession._invalidate` (run from `observeDocument` on every
   content notification) captured all paragraphs (per-paragraph JSON keys,
   language routing, grapheme scans) and rebuilt every report, issue and the
   findings map, synchronously, so cached findings were rebound to the new
   revision. Measured: 0.52–0.66 ms p50, 0.93–1.65 ms p95 per keystroke for 180
   paragraphs (debug), growing linearly with document length.
2. **The status flipped to "Waiting to check…" on every edit**, and back after
   each pass ("Checking…" on every pass, however short). Both status bars
   (`WordReviewStatusBar`, the Studio footer strip) listened to the whole
   controller and recomputed language, tracked-change count and status on every
   keystroke and every proofing notification.
3. **Passes notified ~20 times regardless of work.** Every pass visited every
   paragraph (with a timer yield each), and published progress every
   paragraphs/20, each publication capturing the whole document and rebuilding
   the editor and the Studio. Paragraphs whose language no provider supports
   (here the 30 English paragraphs) were "rechecked" on every pass because
   their reports are incomplete.
4. **No deadline for continuous typing.** The 400 ms debounce restarted on every
   keystroke, so steady typing was never checked, and natural word pauses just
   above 400 ms started passes mid-word that flagged unfinished words.
5. **Studio chrome rebuilt per keystroke**: a new `ThemeData`
   (`ColorScheme.fromSeed`) on every workspace build made every Theme-dependent
   widget rebuild, and the footer walked the document for word, paragraph and
   comment counts (2 ms per build for word count alone).
6. **Dominant and not proofing: full relayout per keystroke.** The IME path
   calls `relayout(localEdit: true)`, which lays out from the caret's section;
   a one-section document is laid out completely, 21 pages here. Measured
   ~124 ms per keystroke in debug JIT for this document (`insertText` 114 ms),
   which is why `handlerMs` barely moves below. This is owned by the Word layout
   lane and is not changed here (see Remaining work).

Provider placement: Hunspell, Harper, Arabic morphology and language ID
already run in worker isolates (`*_transport_native.dart`); the deterministic
German/Arabic rule engines and the bundled German lexicon run on the UI
isolate, and now only for changed paragraphs, in time-sliced passes.

## Changes

Session (`packages/quds_office_editor/lib/src/proofing/word_proofing.dart`):

- **Lazy republish.** An edit only marks published results stale
  (`_pendingPublish`); the document is captured once, on the first reader of
  `summary`/`isCurrent`/`issuesAt` or at the next pass. Consecutive keystrokes
  coalesce. `findingsByParagraph` (read by the canvas on every frame) serves
  the previous findings minus paragraphs whose text changed, without a
  capture, so underlines elsewhere stay put. Observable summaries are
  unchanged: a reader gets exactly what the eager publish produced.
- **Scheduling** (`WordProofingTiming`): background passes start after an idle
  pause of **600 ms**; the first edit after a pass sets a **2.5 s** deadline that
  later keystrokes do not postpone, so continuous typing is still checked.
  A deadline pass defers a spelling finding that ends at the collapsed caret
  (the word being typed); the next idle pass, or moving the caret away,
  publishes it without a provider call. Explicit checks (F7, Check document)
  are unchanged and check everything immediately.
- **Passes visit only paragraphs without a reusable result**, the edited
  paragraph first, yield after each **4 ms** slice, and publish progress about
  twenty times per pass over the *changed* paragraphs (so one dirty paragraph
  means one start and one final notification). A paragraph whose providers
  declare its language unsupported is reused instead of rechecked; transient
  failures and provider-reported `unsupported` replies are still retried.
  Document snapshot validation compares paragraph keys instead of JSON-encoding
  the whole document. Language detection runs once per pass for changed text
  (cached by text in the detector), never per keystroke.
- **Coalesced status** (`WordProofingSession.status`, a
  `ValueListenable<WordProofingStatus>`): changes only on real transitions.
  A settled result stays visible while the next pass waits; "Waiting to check…"
  appears only when there is no settled result; "Checking…" appears only after
  a pass has run for **300 ms**. Reading the summary inside a build never
  notifies (status updates from a lazy flush are deferred to a microtask).

Status chrome:

- `WordReviewStatusBar` is a `StatefulWidget` that listens to the status and to
  the controller, rebuilding only when a shown value changes; the editor keeps
  one instance per controller so its own per-keystroke rebuilds skip it.
- Studio: the footer strip moved to `StudioReviewStrip`
  (`example/lib/studio_review_strip.dart`) with the same rules and one cached
  instance per controller/language/layout; footer counts (words, paragraphs,
  comments) are reused while typing and refreshed 700 ms after the last edit;
  the workspace `ThemeData` is memoized by its inputs.

Underlines: proofing results only repaint the canvas (`markNeedsPaint`); they
never relayout. Painting reads the findings of the laid-out lines it draws.

Settings: the existing **Check as you type** switch (`proofing.enabled`) keeps
its default (on in the editor). The intervals are constructor parameters of
`WordProofingSession` (`debounce`, `maxDelay`, `checkingIndicatorDelay`) with
defaults from `WordProofingTiming`.

## Results

### Local, back to back (MacBook, debug JIT widget test)

Two rounds at 1-minute load average 3–8 (rounds 3 and 4; each "before" run is
immediately followed by its "after" run). Values are round 3 / round 4.

| Metric | Before | After |
|---|---|---|
| Proofing session cost per keystroke, p50 / p95 (ms) | 0.49 / 0.77 · 0.49 / 0.75 | **0.03 / 0.06 · 0.04 / 0.07** |
| Keystroke handler p50 / p95 (ms) | 128.8 / 194.1 · 116.8 / 154.4 | 115.0 / 150.9 · 138.1 / 194.4 |
| Frame after keystroke p50 / p95 (ms) | 9.4 / 16.3 · 8.7 / 12.3 | 7.6 / 14.5 · 9.1 / 14.6 |
| Timer work between keystrokes p50 / p95 / max (ms) | 29.0 / 59.2 / 204 · 26.4 / 41.0 / 139 | 24.2 / 38.8 / 60 · 31.1 / 46.5 / 65 |
| Keystrokes over 16.7 ms (handler + frame) | 300 / 300 | 300 / 300 |
| Proofing passes during 300 keystrokes | 2 | 11 (every 2.5 s while typing) |
| Paragraphs sent to providers (calls) | 4 | 22 |
| Language detection calls / texts | 2 / 300 | 11 / 11 |
| Session notifications | 44 | **22** |
| Controller notifications | 644 | 622 |
| Writing-status label: changes / distinct labels | 4 / "Waiting to check…" ↔ counts | 7 / issue counts only, no "Waiting" or "Checking" |
| Studio review strip rebuilds (strip / its status button) | 301 (built with the workspace) / 601 | **7** / 311 |
| Studio workspace, ribbon, status line rebuilds | 301 each | 310 each |
| Word editor rebuilds | 601 | 601 |
| Final findings | 66 | 66 |

Earlier rounds under heavier load (other lanes building; load 8–18) show the
same pattern with larger absolute times: session cost 0.66 / 1.65 → 0.05 /
0.22 ms and 0.52 / 0.93 → 0.04 / 0.11 ms (p50 / p95). The first baseline under
load ~35–80 measured handler p50 368 ms, p95 1530 ms; frame p50 23 ms, p95
139 ms.

Reading the table:

- The proofing work done synchronously per keystroke fell by ~12× (and no
  longer grows with document length); "Waiting to check…" no longer appears
  while typing over a settled result, and "Checking…" never appeared because no
  pass ran for 300 ms.
- Passes increased from 2 to 11 on purpose: the old debounce never fired during
  steady typing. Each pass now sends only the edited paragraph to the
  providers (2 calls per pass) and notifies twice instead of ~22 times.
- Handler and frame times are within run-to-run noise: they are dominated by
  the full-section relayout (root cause 6, ~115–140 ms per keystroke in debug),
  which is outside this change. Every keystroke still exceeds a 16.7 ms frame
  in this debug benchmark for that reason.
- The review strip's own state rebuilds 7 times instead of with every
  workspace rebuild; its status button still rebuilds once per keystroke
  because an inherited dependency above it changes (see Remaining work).

HOSTED_RESULTS

## Tests

- New `test/word_typing_proofing_schedule_test.dart`: typing below the idle
  pause starts no pass and the pass rechecks only the edited paragraph;
  continuous typing is checked by the deadline (one pass per deadline);
  the unfinished word is deferred and published on caret move without a
  provider call; the status keeps the settled result while typing and shows
  checking only after the delay; **background scheduling settles to exactly
  the findings of one explicit full check of the same text** (44 findings over
  40 paragraphs after edits in four places).
- Updated expectations that encoded the old flicker: "Waiting to check…" after
  typing over a settled result, and "Checking…" after 1 ms
  (`word_live_review_surface_test.dart`, `studio_review_status_test.dart`).
  Tests that pumped a hard-coded 450 ms for the old 400 ms debounce now pump
  `WordProofingTiming.idle` plus 50 ms.

TEST_RESULTS

## Remaining work

- **Per-keystroke relayout of the whole section** (root cause 6) is the largest
  remaining typing cost. Paragraph-level incremental layout (relayout from the
  edited paragraph until line breaks and page positions converge, reusing
  earlier pages) belongs to the Word layout lane.
- The Studio workspace still rebuilds its whole chrome (ribbon, footer line)
  on every controller notification, and something above the footer still
  invalidates Theme-dependent descendants once per keystroke
  (`reviewStripLabel` rebuilds); selector-style listening for the ribbon would
  remove most of that work.
- German and Arabic rule engines still run on the UI isolate per changed
  paragraph; moving them into the existing worker transport would remove the
  remaining pass cost for long paragraphs.
