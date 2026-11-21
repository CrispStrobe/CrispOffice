# When as-you-type proofing runs (21 November 2026)

The owner asked for proofing "in sensible intervals, not after each
keystroke", modelled on what other editors do, and for settings. This
document compares how established editors schedule checking (with sources),
describes the resulting scheduler in `WordProofingSession`, lists the
settings, and records the measurements.

Earlier typing work (lazy republication, coalesced status, time-sliced passes)
is in [typing-proofing-20261120](../performance/typing-proofing-20261120.md).

## 1. How other editors schedule checking

Researched 21 November 2026. Source links are pinned to these commits:
Chromium `0cfae948c88a`, LibreOffice core `a418b990c2ec`, LanguageTool
`462361ea0db7`, languagetool-for-libreoffice `6f9eb45bb8f3`,
languagetool-browser-addon `c3b19196aa29`, vscode-ltex `74484ff6e0f1`, ltex-ls
`7c031d792110`. **[unverified]** marks what no primary source settles.

| Editor | Spelling runs | Grammar runs | Region | Word/sentence being typed |
|---|---|---|---|---|
| Chromium/Blink | After any edit or caret move: a "hot" idle callback (200 ms timeout); a "cold" pass 1000 ms later, then every 200 ms while work remains | No separate trigger; grammar marks arrive with the same platform results | Hot: whole field ≤128 chars, else paragraph ≤1024 chars, else ±512 chars around the caret. Cold: 16 KB chunks until the idle deadline; later ±64 chars around the caret | Hot mode only clears the marker of the word being typed and checks nothing; a later cold pass can flag it (from the code, not tested) |
| LibreOffice Writer | Idle time (`Idle`, lowest priority) via `SwLayIdle`: visible area first, then the whole document, one paragraph per step, stops on any input | Background thread (`GrammarCheckingIterator`), one sentence per request | Spelling: invalidated ranges of dirty paragraphs. Grammar: unchecked paragraphs, sentence by sentence | A miss containing the cursor is held back (`FreshState::CURSOR` → `PENDING`) until the cursor moves. New grammar marks in the cursor paragraph appear 2000 ms after the check or when the cursor leaves |
| macOS NSTextView | `isContinuousSpellCheckingEnabled` | `isGrammarCheckingEnabled` (separate switch) | **[unverified]** not documented | **[unverified]** not documented |
| Microsoft Word | "Check spelling as you type" | "Mark grammar errors as you type" | **[unverified]** not documented | **[unverified]** not documented |
| Google Docs | Automatic red underlines when suggestions are on | Blue underlines | **[unverified]** not documented | **[unverified]** not documented |
| LanguageTool browser add-on (open-source legacy) | 1500 ms debounce of `input` events, stale replies dropped | Same request | The whole field | Not excluded |
| LanguageTool for LibreOffice | Called by Writer's grammar iterator; background checking can be switched off | Per paragraph or sentence; text-level rules in a separate queue | Paragraph, or whole text for text-level rules | As Writer |
| LTEX (VS Code) | `ltex.checkFrequency`: `edit` (default, "on every keystroke"), `save`, `manual` | Same as spelling | Whole document; a sentence cache skips checked sentences | Not excluded |

**Chromium/Blink.**
[`idle_spell_check_controller.cc`](https://github.com/chromium/chromium/blob/0cfae948c88a94f60a0ae76e2a67f51b875b5971/third_party/blink/renderer/core/editing/spellcheck/idle_spell_check_controller.cc)
defines `kHotModeRequestTimeoutMS = 200`, `kColdModeTimerInterval = 1000 ms` and
`kConsecutiveColdModeTimerInterval = 200 ms`
([L40-L43](https://github.com/chromium/chromium/blob/0cfae948c88a94f60a0ae76e2a67f51b875b5971/third_party/blink/renderer/core/editing/spellcheck/idle_spell_check_controller.cc#L40-L43)).
Every content or selection change cancels cold mode and requests a hot idle
callback
([L215-L237](https://github.com/chromium/chromium/blob/0cfae948c88a94f60a0ae76e2a67f51b875b5971/third_party/blink/renderer/core/editing/spellcheck/idle_spell_check_controller.cc#L215-L237)),
so typing always preempts background work. Hot mode picks the whole field, the
paragraph or ±512 characters around the caret
([hot_mode_spell_check_requester.cc L57-L96](https://github.com/chromium/chromium/blob/0cfae948c88a94f60a0ae76e2a67f51b875b5971/third_party/blink/renderer/core/editing/spellcheck/hot_mode_spell_check_requester.cc#L57-L96)).
When the last command was typing and the caret sits at its end,
`CurrentWordIfTypingInPartialWord` makes hot mode *only remove* markers on that
word ([L37-L55](https://github.com/chromium/chromium/blob/0cfae948c88a94f60a0ae76e2a67f51b875b5971/third_party/blink/renderer/core/editing/spellcheck/hot_mode_spell_check_requester.cc#L37-L55),
[L113-L119](https://github.com/chromium/chromium/blob/0cfae948c88a94f60a0ae76e2a67f51b875b5971/third_party/blink/renderer/core/editing/spellcheck/hot_mode_spell_check_requester.cc#L113-L119)):
a word is checked once a separator is typed or the caret moves. Cold mode sends
16 KB chunks while `deadline->timeRemaining() > 0`, keeping progress between
slices, and after a full pass rechecks ±64 characters unless more than 1024
characters changed
([cold_mode_spell_check_requester.cc L144-L296](https://github.com/chromium/chromium/blob/0cfae948c88a94f60a0ae76e2a67f51b875b5971/third_party/blink/renderer/core/editing/spellcheck/cold_mode_spell_check_requester.cc#L144-L296)).
Results for text that changed in flight are discarded
([spell_checker.cc L307-L399](https://github.com/chromium/chromium/blob/0cfae948c88a94f60a0ae76e2a67f51b875b5971/third_party/blink/renderer/core/editing/spellcheck/spell_checker.cc#L307-L399)).

**LibreOffice Writer.** The document idle job runs at the lowest priority and
returns while any action is pending
([DocumentTimerManager.cxx L49-L155](https://github.com/LibreOffice/core/blob/a418b990c2ec17e9e3cb025edb533213c8595089/sw/source/core/doc/DocumentTimerManager.cxx#L49-L155)).
`SwLayIdle` "first, spellcheck[s] the visible area"
([layact.cxx L2416-L2420](https://github.com/LibreOffice/core/blob/a418b990c2ec17e9e3cb025edb533213c8595089/sw/source/core/layout/layact.cxx#L2416-L2420)),
then the whole document, one wrong-dirty paragraph at a time, returning as
soon as `Application::AnyInput` reports input
([L2098-L2185](https://github.com/LibreOffice/core/blob/a418b990c2ec17e9e3cb025edb533213c8595089/sw/source/core/layout/layact.cxx#L2098-L2185)).
`SwWrongList::Fresh` reports a miss only "if the cursor position is outside the
word, so that the user is not annoyed while typing"
([wrong.cxx L356-L366](https://github.com/LibreOffice/core/blob/a418b990c2ec17e9e3cb025edb533213c8595089/sw/source/core/text/wrong.cxx#L356-L366));
the paragraph becomes `PENDING` and is finished on the next cursor move
([txtedt.cxx L1466-L1550](https://github.com/LibreOffice/core/blob/a418b990c2ec17e9e3cb025edb533213c8595089/sw/source/core/txtnode/txtedt.cxx#L1466-L1550)).
Grammar runs on its own thread, one sentence per `doProofreading` call
([gciterator.cxx L612-L760](https://github.com/LibreOffice/core/blob/a418b990c2ec17e9e3cb025edb533213c8595089/linguistic/source/gciterator.cxx#L612-L760));
grammar marks for the cursor paragraph are repainted 2000 ms after the check or
when the cursor leaves it
([GrammarContact.cxx](https://github.com/LibreOffice/core/blob/a418b990c2ec17e9e3cb025edb533213c8595089/sw/source/core/txtnode/GrammarContact.cxx#L34)).

**macOS.** Apple documents separate switches,
[`isContinuousSpellCheckingEnabled`](https://developer.apple.com/documentation/appkit/nstextview/iscontinuousspellcheckingenabled)
and [`isGrammarCheckingEnabled`](https://developer.apple.com/documentation/appkit/nstextview/isgrammarcheckingenabled),
and an asynchronous
[`requestChecking(of:…)`](https://developer.apple.com/documentation/appkit/nsspellchecker/requestchecking(of:range:types:options:inspelldocumentwithtag:completionhandler:))
that returns a sequence number for discarding stale requests. When NSTextView
checks, what region and whether the word being typed is exempt are
**[unverified]** (undocumented).

**Microsoft Word and Google Docs.** Word documents "Check spelling as you type",
"Mark grammar errors as you type" and "Recheck Document"
([support](https://support.microsoft.com/en-us/office/check-spelling-and-grammar-in-office-5cdeced7-d81d-47de-9096-efd0ee909227));
Google Docs documents red spelling and blue grammar underlines and a manual
check ([help](https://support.google.com/docs/answer/57859)). Neither
documents timing, region or the word being typed: **[unverified]**.

**LanguageTool.** The open-source browser add-on uses
`BG_CHECK_TIMEOUT_MILLIS = 1500` and `.debounce(1500)` with `switchLatest()`
([textarea.js L36, L554-L571](https://github.com/languagetool-org/languagetool-browser-addon/blob/c3b19196aa299c335bdf88074087ae833b5f5977/webextension/cs/textarea.js#L554-L571)).
The LibreOffice extension runs inside Writer's grammar iterator and offers
"Disable background-processing check of text"
([ConfigurationDialog.java L629-L680](https://github.com/languagetool-org/languagetool/blob/462361ea0db7890bdafcee7009c3116dc00ccc9b/languagetool-gui-commons/src/main/java/org/languagetool/gui/ConfigurationDialog.java#L629-L680)).
LTEX checks "on every keystroke" by default, cancels the check in flight on
every change and relies on a sentence cache
([package.nls.json](https://github.com/valentjn/vscode-ltex/blob/74484ff6e0f1f810fc24d57ba51286c347b31cf3/package.nls.json#L536),
[LtexTextDocumentService.kt L134-L150](https://github.com/valentjn/ltex-ls/blob/7c031d792110a824951aa003acd3ada158a515b4/src/main/kotlin/org/bsplines/ltexls/server/LtexTextDocumentService.kt#L134-L150)).

**What this means.** Every editor with documented internals uses two tiers:
cheap checks of the text near the caret right after an edit, and an idle-time
pass over the rest that any input preempts and that resumes where it stopped,
visible text first. Nobody flags the word being typed (Blink clears it,
Writer holds it until the cursor leaves). Grammar is per sentence and runs
after sentence end or a pause of about 1–1.5 s (Blink's cold delay 1000 ms, the
LanguageTool add-on 1500 ms), and Writer delays grammar marks in the paragraph
being edited. Stale results are dropped, and checked text is cached.

## 2. The scheduler

`WordProofingSession` (`packages/quds_office_editor/lib/src/proofing/word_proofing.dart`).
Providers declare their categories
(`OfficeProofingProvider.categories`); a provider that reports only
`spelling` (German lexicon, Hunspell, platform spelling) is in the *spelling*
group, every other provider (German and Arabic writing rules, Harper, spaCy,
GECToR) in the *grammar* group. `OfficeProofingService.check(…, only:)` runs one
group; a paragraph's cached reports record which groups they contain, and a
later pass adds only the missing group to results for the same text.

| Trigger (default mode "While typing") | Providers | Scope | Delay | Shows "Checking…" |
|---|---|---|---|---|
| **Word completed**: a space or punctuation typed at the caret | Spelling | The paragraph being typed | 150 ms, not postponed by further typing | Never |
| **Sentence completed**: `. ! ? … ؟ 。` typed, or Enter after typing | Spelling + grammar | Edited paragraphs | 150 ms | Never |
| **Pause**: no edit for the pause (default 1.5 s) | Spelling + grammar | Edited paragraphs (typed in, changed elsewhere by paste/undo/replace, or new) | Pause | Never |
| **Idle**: no input for 3 s | Spelling + grammar | Every unchecked paragraph: visible pages and their neighbours first, then outward from the caret | 3 s since the last input | After 1 s |
| **Load / configuration change** (nothing cached yet) | Spelling + grammar | Whole document | Pause | After 1 s |
| **Check document / F7** | All, including manual providers | Whole document | Immediate | After 1 s |

Rules:

- **No forced passes during continuous typing.** The 2.5 s deadline is gone.
  Letters alone never start a check; only completing a word or sentence, a
  pause, or idle time does.
- **The word being typed is never flagged.** An edit counts as typing when
  the caret moved by exactly the length change of its paragraph (typing or
  deleting at the caret; undo, corrections and replacements do not). While
  the caret stays there, any finding that contains it or ends at it stays
  hidden, including existing marks on that word; a caret move shows them
  from the cache without a provider call. A finding that merely starts at
  the caret (the next word) is shown. Explicit checks show everything.
- **Language detection** runs only for the text a sentence, pause, idle or
  explicit pass is about to check, never per word. Until then an edited
  paragraph is routed with its previous detection when that was a single
  language and script.
- **Idle-time work yields to input.** Background passes run in 4 ms slices;
  any edit cancels the pass at the next slice and restarts the idle timer;
  results already checked stay cached, so the next idle pass resumes.
- **Status without flicker.** Checks of the typed text never publish a
  "checking" state; a settled result stays on screen while they run, and a
  check that changes no mark on screen does not notify listeners at all
  (the Studio otherwise rebuilds its chrome per notification). "Checking…"
  appears only for idle, load and explicit passes that run for 1 s.
- **Stable underlines.** While an edited paragraph waits for its check, marks
  in its unchanged text stay painted (moved with the text after the edit);
  only marks touching the edited range disappear. A spelling-only word check
  keeps the paragraph's previous grammar marks where the text is unchanged
  until the next grammar check replaces them (they do not count as checked).
- **Modes.** "When I pause" disables the word and sentence triggers.
  "Only when I click Check document" disables every automatic check
  (`WordProofingSchedule.automatic`); explicit checks are unchanged.
- **Hosts** can provide the visible paragraphs (`visibleParagraphs:`; the Word
  controller passes the lines of the visible page and its neighbours).
  Hosts that notify before moving the caret (history batches) are handled by
  reading the caret in a microtask after the edit.

## 3. Settings

`WordProofingSession.schedule` takes a `WordProofingSchedule`; assigning it
takes effect at once (pending checks are rescheduled, results kept). The
Studio's Settings dialog has a **Proofing** section, localized in English,
German and Arabic, persisted in the versioned settings store (#269):

| Setting | Key | Default |
|---|---|---|
| Checking mode: "While typing (recommended)", "When I pause", "Only when I click Check document" | `proofing.checkingMode` | While typing |
| Check spelling while typing | `proofing.checkSpellingWhileTyping` | on |
| Check grammar while typing | `proofing.checkGrammarWhileTyping` | on |
| Pause before checking (0.3–5 s, 0.1 s steps) | `proofing.pauseMilliseconds` | 1500 |
| Check the whole document in the background | `proofing.backgroundCheck` | on |
| Hide errors in the word I'm typing | `proofing.hideTypingErrors` | on |

The ribbon's **Check as you type** switch (`proofing.checkAsYouType`) stays;
turning it on from "Only when I click Check document" selects the recommended
mode. Invalid stored values fall back to their defaults one by one.

## 4. Evidence

### Tests

`packages/quds_office_editor/test/word_typing_proofing_schedule_test.dart`
(fake time, a spelling-only and a grammar provider): the loaded document is
checked once after the pause; no provider call while a word is typed, one
spelling call per completed word; continuous typing (6 s of letters) makes no
call; the word under the caret is never flagged, even by the pause pass, and
is shown when completed; an existing flag stays hidden until the caret leaves
and is then shown without a provider call; hiding can be turned off; grammar
runs at sentence end and after the pause, not at word completion; Enter checks
the completed paragraph's grammar; "When I pause" and an adjustable pause;
manual mode makes no automatic call and Check document still checks
everything; spelling or grammar can be turned off and the other group is added
later without rerunning the first; without background checking only edited
text is checked; background passes wait for idle time, start next to the caret
and stop when the user types, then resume; typing checks never show
"Checking…" (status changes once, to the new result); explicit checks still
show progress; a word check that changes no mark does not notify; a provider
without declared categories runs on the grammar schedule; and scheduled
checking settles to exactly the findings of one explicit full check.

`example/test/studio_settings_test.dart`: every new value survives save and
load; invalid values (unknown mode, pause out of range, non-integral or
non-numeric) fall back one by one; the workspace restores a stored schedule,
the Settings dialog changes it at once (mode, switches disabled in manual
mode, pause slider snapping to 0.1 s) and the changes are saved.

Updated expectations of the old schedule: the notes pane waited 1 s for the
old 600 ms pause; an inline-correction test expected the interrupted third
paragraph to be rechecked at the next pause instead of in idle time.

### Typing benchmark

`example/test/studio_typing_proofing_benchmark_test.dart`
(`QUDS_TYPING_BENCHMARK=1`; described in
[typing-proofing-20261120](../performance/typing-proofing-20261120.md)): the full
Studio, 180 paragraphs / 21 pages of German, English and Arabic, 300 characters
typed through the IME path into paragraph 91 (about 40 words, several sentence
ends, a 100-character burst and a 1.2 s pause). It now also reports the
session's own pass count (`sessionPasses`; the older `proofingPasses` only sees
passes that publish "checking") and per-keystroke rates. The benchmark's
counting provider forwards `categories`, so the Studio's German spelling
provider runs on the word schedule.

"Before" is `84046975` (main at the branch point: 600 ms idle pause, 2.5 s
deadline); "after" is this branch. Debug JIT widget test with fake time.

#### Local (MacBook, three alternating rounds, 1-minute load 5–9)

Values are rounds 1 / 2 / 3.

| Metric | Before | After |
|---|---|---|
| Passes started (`sessionPasses`) | 11 / 11 / 11 | 41 / 41 / 41 (one per completed word or sentence, 3 at pauses) |
| Passes per keystroke | 0.037 | 0.137 |
| Provider calls (paragraph × provider) | 22 | 44 (word checks call only the spelling provider) |
| Provider calls per keystroke | 0.073 | 0.147 |
| Provider time, total (ms) | 110 / 109 / 110 | 118 / 128 / 119 |
| Language detection calls | 11 | **3** (only at sentence ends and pauses) |
| Session notifications | 22 | **6** (0.02 per keystroke; checks that change no mark are silent) |
| Writing-status label changes | 7 | **5** (0.017 per keystroke; issue counts only, never "Checking…") |
| Studio workspace / ribbon rebuilds | 13 | **10** |
| Keystroke handler p50 / p95 (ms) | 3.9 / 5.7 · 3.9 / 5.9 · 3.9 / 5.7 | 3.8 / 6.0 · 4.0 / 7.3 · 3.9 / 6.5 |
| Frame after keystroke p50 / p95 (ms) | 6.2 / 10.4 · 6.0 / 10.4 · 6.0 / 10.7 | 6.2 / 9.6 · 6.5 / 11.4 · 6.1 / 8.6 |
| Keystrokes over 16.7 ms (handler + frame) | 21 / 21 / 22 | 19 / 25 / 18 |
| Timer work between keystrokes p50 / p95 (ms) | 0.3 / 3.5 · 0.3 / 4.1 · 0.3 / 3.8 | 0.3 / 6.5 · 0.3 / 7.6 · 0.3 / 6.5 |
| Proofing session cost per keystroke p50 / p95 (ms) | 0.03 / 0.04 | 0.03 / 0.04 |
| Findings at the end | 66 | 65 (the misspelling at the caret stays hidden until the caret leaves) |

Reading the table:

- The old scheduler checked continuous typing every 2.5 s, whatever was typed,
  and flagged unfinished words at the caret; the new one checks a word once,
  when it is completed, which is what Blink and Writer do. That is more, but
  much smaller, passes (one spelling call for one paragraph), so provider calls
  double while provider time stays within 10–15 %.
- Everything the user sees got calmer: 6 instead of 22 notifications (each one
  rebuilds the Studio chrome), 5 instead of 7 status changes, no "Checking…",
  no underline blinking in the paragraph being typed, and language detection
  only 3 times.
- Handler and frame times are unchanged within noise (frame p95 is equal or
  lower); timer work between keystrokes p95 rises by about 3 ms because word
  checks now run in those gaps instead of every 2.5 s.

An intermediate version that notified after every word check measured frame
p95 25–34 ms and 49–73 slow keystrokes: each notification rebuilt the
workspace, and underlines elsewhere in the typed paragraph disappeared on
every keystroke and came back with every check. Keeping unaffected marks
(moved with the text) and skipping notifications that change no mark removed
both.

#### Hosted runners (workflow `Typing proofing benchmark`, run 44875203604)

Base `84046975`, branch `3de1a21f` (the scheduler of this change). Three runs
per job; each variant ran on its own runner VM. The counters were identical
in every run and match the local runs: passes 11 → 41, provider calls 22 →
44, language detection 11 → 3, session notifications 22 → 6, status label
changes 7 → 5, workspace rebuilds 13 → 10, findings 66 → 65.

| Runner | Variant | Handler p50 / p95 (ms) | Frame p50 / p95 (ms) | Timer work p50 / p95 (ms) | Slow keystrokes | Provider time (ms) |
|---|---|---|---|---|---|---|
| ubuntu-latest | before | 3.9 / 6.6 · 3.8 / 6.5 · 3.8 / 6.9 | 5.7 / 13.1 · 5.3 / 12.2 · 5.3 / 13.3 | 0.3 / 5.4 · 0.3 / 5.2 · 0.3 / 5.0 | 27 · 23 · 26 | 165 · 133 · 135 |
| ubuntu-latest | after | 4.3 / 8.3 · 4.3 / 7.3 · 4.1 / 7.1 | 6.3 / 11.8 · 6.3 / 11.1 · 6.0 / 10.8 | 0.4 / 8.9 · 0.5 / 9.1 · 0.4 / 8.9 | 28 · 26 · 23 | 156 · 155 · 165 |
| macos-latest | before | 6.1 / 13.1 · 6.2 / 11.3 · 5.5 / 11.6 | 10.7 / 24.7 · 10.4 / 28.9 · 9.6 / 28.2 | 0.7 / 7.7 · 0.7 / 11.6 · 0.6 / 7.8 | 169 · 177 · 123 | 198 · 230 · 158 |
| macos-latest | after | 6.1 / 15.8 · 5.7 / 11.6 · 7.7 / 20.4 | 10.7 / 26.7 · 9.0 / 21.5 · 14.9 / 40.9 | 0.7 / 13.5 · 0.6 / 11.5 · 1.0 / 15.8 | 167 · 118 · 259 | 185 · 179 · 243 |

On the stable Ubuntu runners, frame p95 is about 1.5 ms lower and handler p95
about 0.8 ms higher. Timer work between keystrokes p95 rises by about 4 ms
because word checks now run in those gaps. Slow keystrokes are unchanged. The
shared macOS runners vary more within one job than between variants, and
their third "after" run was an outlier. Treat the timing differences as
within noise. The measured effect is in the counters.

The `Studio example tests` jobs of the same run fail only
`dump_gallery_shots_test` on the branch. The baseline fails the same test,
plus `studio_mail_cached_host_test`. The other 1780 tests pass on the branch.

