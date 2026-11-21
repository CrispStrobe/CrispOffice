# Typing latency, autocorrect and adaptive proofing roadmap (21 November 2026)

Owner request: make Word typing fluent, add Word-style autocorrect (German
quotes and spaced en dash), and schedule proofing intelligently instead of
pausing it entirely or rechecking after every keystroke.

This roadmap records the order of work and the measurement protocol. Each
item is implemented, tested and measured before the next one starts.

## Measurement protocol

Baseline benchmark:

```sh
cd packages/quds_office_editor/example
QUDS_TYPING_BENCHMARK=1 flutter test --no-pub \
  test/studio_typing_proofing_benchmark_test.dart
```

Capture the `TYPING_BENCHMARK` and `TYPING_BENCHMARK_KEYS` JSON lines.

Record for every change:

| Field | Why it matters |
|---|---|
| `handlerMs.p50/p95/max` | synchronous work through the real IME path |
| `frameMs.p50/p95` and `jankyKeystrokeFrames` | build/layout/paint after a key |
| `backgroundMsPerGap.p50/p95/max` | proofing work that competes with typing |
| `proofingPasses`, `providerCalls` | how often proofing actually runs |
| `sessionNotifications`, `rebuilds.statusLine/wordEditor/workspace/ribbon` | notification and widget churn |
| `TYPING_BENCHMARK_KEYS` | controller-only cost after fitting, formatting and notes |

Widget tests run in debug JIT; absolute timings are not release numbers, so
compare back-to-back runs with the same load. Also run the targeted unit and
widget tests for the changed area, and a release smoke test for feel.

## Ordered work

### 1. Word-style autocorrect for typing

- Smart double quotes:
  - German: opening `„`, closing `“`.
  - English: opening `“`, closing `”`.
  - Decide opening vs closing from the preceding character, not from a toggle.
- Smart single quotes/apostrophes:
  - Between letters: `’` (don’t, it’s).
  - German opening/closing: `‚` / `‘`.
  - English opening/closing: `‘` / `’`.
- Spaced dash:
  - `word - word` becomes `word – word` (U+2013, Halbgeviertstrich).
  - `--` becomes `–`; `---` becomes `—` when followed by a space.
- Apply only to text the user types, never pasted text or an active IME
  composition.
- Preserve undo grouping, formatting, caret position and selection.
- Add controller tests for German/English quotes, apostrophes, dash forms,
  pasted text, selected text and undo.

### 2. Adaptive trailing proofing delay

Replace the fixed word-completion timer with a cadence-aware trailing delay:

- Measure inter-edit interval and recent proofing pass cost.
- Slow editing: check the edited paragraph after about 150–250 ms.
- Fast bursts: postpone to a trailing 350–600 ms; never start a word pass in
  the middle of a burst.
- Keep sentence-completion grammar and pause/background passes.
- Only paragraphs with changed text are checked; unchanged results are reused.
- Skip checks while an IME composition is active.
- Add tests for slow typing, bursts, pause, sentence end and stale-pass
  rejection.

### 3. IME composition and stale-result suppression

- Suppress proofing passes while `TextEditingValue.composing` is active.
- Drop provider results whose captured text no longer matches the current
  paragraph revision.
- Add a test that a composing sequence performs no provider calls.

### 4. Worker/isolation audit

Hunspell, Harper, Arabic morphology and language detection already use worker
transports. Audit remaining main-isolate work:

- German/Arabic deterministic rules and the bundled lexicon.
- Report assembly, language routing and proofing geometry.
- Batch paragraph requests per worker round-trip.
- Move pure deterministic checks to a long-lived isolate if measurements show
  more than the 4 ms slice budget.

### 5. Paint and layout separation

- Separate the caret/selection layer from the page text canvas.
- Separate proofing squiggles from text repaint; cache squiggle geometry until
  a line or its findings change.
- Skip painting off-screen pages.
- Keep proofing findings updates to `markNeedsPaint`, never relayout.

### 6. Chrome throttling

- Status line, review strip and footer counts update on a trailing interval,
  not on every controller notification.
- Ribbon remains keyed by formatting/selection state (already implemented).
- Measure rebuild counts before and after.

## Baseline (21 November 2026, debug benchmark)

From `TYPING_BENCHMARK` on the current mixed 180-paragraph document:

- handler p50 4.0 ms, p95 5.79 ms, max 26.31 ms
- frame p50 7.73 ms, p95 11.48 ms
- background per gap p50 0.72 ms, p95 7.81 ms, max 74.86 ms
- proofing passes 41, provider calls 44, detector calls 3
- session notifications 6, controller notifications 306
- rebuilds: status line 310, word editor 310, workspace 10, ribbon 10

The owner’s installed app uses release/AOT. Proofing was temporarily set to
“On pause” as a stopgap; item 2 replaces that with adaptive scheduling.

## Progress

### Item 1 — autocorrect (implemented)

`packages/quds_office_editor/lib/src/embed/word_autocorrect.dart` and the IME
path in `office_controller.dart`.

- German/English smart double quotes and single quotes, apostrophes between
  letters, spaced en dash and `--`/`---` substitution.
- Only single-character typing through a collapsed, non-composing IME value is
  corrected; paste and composition are untouched.
- Tests: `word_autocorrect_test.dart` (4 cases, including the real IME path).

Measured: no additional controller notifications or frames; substitutions are
performed in the existing paragraph edit. The 300-keystroke benchmark contains
no quote/dash input, so its timing is unchanged by this item.

### Item 2 — adaptive trailing proofing (implemented)

`WordProofingSession._noteTypingCadence` and `_wordCompletionDelay`:

- Tracks an EWMA of inter-keystroke gaps.
- Fast typing (<180 ms average) trails a word check by 350 ms; medium (180–300
  ms) by 250 ms; slower typing keeps the 150 ms word completion.
- The timer is restarted by each further word completion, so a provider pass
  never starts in the middle of a burst.
- Sentence completion and pause/background passes retain their behavior.
- Tests: the 21-case proofing schedule suite passes; the test helper’s
  `_afterWord` now allows the adaptive maximum of 400 ms.

Benchmark, same debug machine, before/after:

| Metric | Before | Adaptive |
|---|---|---|
| Proofing passes / provider calls | 41 / 44 | 31 / 32 |
| Background per gap p50 / p95 / max (ms) | 0.72 / 7.81 / 74.86 | 0.65 / 8.24 / 76.97 |
| Session notifications | 6 | 6 |
| Status-line / Word editor rebuilds | 310 / 310 | 309 / 309 |

The pass count fell by about a quarter. Handler/frame numbers in the
back-to-back run moved upward because the machine was under higher load during
the second run; they are not attributed to this change. The next measurement
must be taken with the load recorded and the benchmark run twice.

### Item 3 — IME composition suppression (implemented)

`WordEditorController.notifyListeners` no longer forwards proofing observation
while a non-collapsed IME composition is active. The commit notification
observes the final text and schedules the normal check. This prevents provider
work against intermediate composition text.

### Next

Item 6
(status-line trailing throttle) are the next low-risk changes. Item 4 is an
audit because the native providers already use worker transports. Item 5 is a
larger renderer change.
