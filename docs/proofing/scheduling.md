# Word proofing scheduling

Word proofing separates checks of text being edited from checks of the rest of
the document. Hosts configure the behavior through `WordProofingSchedule` on
`WordProofingSession.schedule`; Studio persists the corresponding writing
preferences. The defaults below describe scheduling policy, not measured
response-time guarantees.

## Automatic modes and defaults

| Setting | Default | Behavior |
| --- | --- | --- |
| `mode` | `WordProofingMode.whileTyping` | Complete words trigger spelling; complete sentences and pauses trigger the enabled provider groups. |
| `checkSpelling` | `true` | Enable automatic calls to spelling-only providers. |
| `checkGrammar` | `true` | Enable automatic calls to grammar, style and mixed-category providers. |
| `pause` | 1,500 ms | Restart the pause timer after each content edit. |
| `backgroundCheck` | `true` | Check otherwise unchecked document text after loading and during idle time. |
| `backgroundIdle` | 3 seconds | Idle interval used to schedule remaining document work after the pause check. |
| `hideTypingErrors` | `true` | Hide findings touching the typing caret until the word completes or the caret leaves. |

`WordProofingMode.onPause` suppresses word and sentence completion checks; it
still checks after a pause and allows the configured background work.
`WordProofingMode.manual` disables automatic checks. The session's `enabled`
switch remains a separate automatic-checking control. Explicit **Check document**
and **F7** checks remain available when automatic checking is disabled, including
when either provider-group preference is off.

Studio accepts pause values from 300 to 5,000 ms and normalizes persisted values
through its settings schema. The public schedule also exposes `backgroundIdle`
for embedding hosts; Studio does not persist or expose that interval as a
setting. Its existing `proofing.checkAsYouType` preference remains independent
of the new mode, spelling, grammar, pause, background and typing-error choices.

## Triggers, scope and ordering

Word completion uses the collapsed caret after the edit's synchronous work has
finished. An edit counts as typing when the caret moves by exactly the length
change of its paragraph. Corrections, replacements, undo and edits elsewhere
therefore do not automatically hide findings as though a word were being typed.
Whitespace and punctuation complete a word; letters, combining marks, numbers,
apostrophes, underscores and hyphens keep it open. Sentence-final punctuation
or Enter at offset zero after typing completes a sentence or paragraph.
Deletion at the caret can keep a word in progress but does not complete it.

Completion work starts after `WordProofingTiming.wordCompletion` (150 ms). A
pending word check can become a sentence check, but further completions do not
postpone that pending timer. Continued typing therefore does not indefinitely
delay checks of completed words. Pause and idle timers are postponed by new
input.

| Trigger | Provider groups | Paragraph scope |
| --- | --- | --- |
| Completed word | Enabled spelling-only providers | The typing paragraph. |
| Completed sentence or paragraph | Both enabled groups | Edited, newly inserted or incompletely checked paragraphs; when no results are cached and background checking is enabled, this may be the initial document-wide pass. |
| Typing pause | Both enabled groups | Edited or incompletely checked paragraphs; the initial pass may cover the document when background checking is enabled and no cached results exist. |
| Background idle | Both enabled groups | Remaining unchecked paragraphs, with the typing/caret paragraph first, then visible paragraphs, then increasing distance from the caret. |
| Explicit check | All ordinary providers; manual providers when requested | Document-wide coverage, reusing valid ordinary cached results. |

Automatic checks skip provider groups that are not configured and avoid
sending an empty selection for already settled groups. Letters alone do not
start a forced pass during continuous typing.

Automatic background work never invokes the separate manual provider service.
An explicit pass that includes manual providers checks them again instead of
treating an earlier automatic pass as manual coverage. Unsupported-language
results are retained as settled results so they do not cause repeated automatic
calls for unchanged text.

## Provider API

`OfficeProofingProvider.categories` declares the categories a provider can
produce. A provider declaring exactly `{OfficeProofingCategory.spelling}` is in
the spelling group. All other providers, including mixed-category providers and
providers using the default set of every category, are in the grammar group.
This lets existing provider subclasses retain their full checks at sentence and
pause boundaries. A provider whose category getter throws is also treated as a
grammar provider.

`GermanSpellingProvider`, the platform spelling adapter and the Hunspell adapter
declare their spelling-only category. Hosts adding a dictionary provider should
make the same declaration only when its findings are exclusively spelling
findings. A mixed grammar/spelling provider remains indivisible: automatic
grammar selection governs its whole call, including any spelling findings it
returns.

`OfficeProofingService.check` accepts the optional `only` provider predicate.
The scheduler uses this to select a provider group without creating another
service or changing ownership. Service validation, timeout handling and result
merging continue to apply to the selected providers.

## Results, interaction and lifecycle

Changing `session.schedule` cancels pending automatic timers and schedules work
under the new policy when automatic checking is enabled. It preserves checked
results. Disabling typing-error suppression immediately releases the hidden
typing position. Caret movement can reveal a cached finding without making
another provider call. A finding beginning at the caret belongs to the next
word and remains visible; a finding containing or ending at the caret, including
a zero-width finding there, can be hidden. Explicit checks release the typing
position and show all findings.

Content edits invalidate the active generation. Results are accepted only for
the current document, revision and provider configuration. Unchanged paragraphs
reuse cached reports; a spelling-only pass does not count as a completed grammar
check. Document replacement clears document-owned cached state. Language
detection runs for the selected sentence/pause/background scope rather than for
each completed word.

Checks of the text being typed publish their results when finished and do not
show the **Checking…** indicator. If their visible marks do not change and results
already exist, they update the summary without notifying the session's ordinary
listeners; `silentPassCount` records those passes and status has its own notifier.
Background, explicit and initial document-wide passes can show **Checking…**
after `WordProofingTiming.checkingIndicatorDelay` (1 second). Passes yield between
units of work after the `sliceBudget` (4 ms) is consumed; a synchronous provider
call itself cannot be preempted by this budget. Slow or blocking providers should
use the existing worker/isolate transports where appropriate.

These choices reduce repeated paragraph work and keep pending checks separate
from the UI's progress indicator. They do not establish comparative performance
against other editors. The earlier investigation and its measurement limits are
recorded in [typing latency and proofing](../performance/typing-proofing-20261120.md).
Any performance claim for a later build needs a new target-specific run.

## Regression coverage

The scheduler contract is exercised by
`packages/quds_office_editor/test/word_typing_proofing_schedule_test.dart`, with
the session, incremental, capture-cache, priority, manual and draft proofing
suites covering adjacent behavior. Provider and Studio settings suites cover
category routing and preference persistence. Execution results for an integrated
build belong in its source-bound validation record; this document is the API
contract, not a test receipt.

## Host migration

This replaces the earlier continuous-typing maximum-delay schedule. Embedding
hosts should configure `schedule` rather than the removed `maxDelay` parameter
or internal caret-deferral controls. The existing `debounce` constructor
argument maps to the schedule pause for compatibility.

## Comparative source notes

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

The surveyed implementations use different policies. The cited Blink and
Writer code illustrates interruptible idle work and special treatment of the
caret's word; the LanguageTool and LTEX examples use other trigger and caching
choices. These observations motivate Quds' separate completion, pause and
background policies without establishing a universal editor design or a timing
promise for Microsoft Word, Google Docs or any other product. The comparison
records the incoming branch's cited source research, not a new measured
interoperability or performance test of these editors.

## Studio settings keys

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

## Additional scheduling regression cases

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

## Measurement boundary

No new comparative typing measurements are supplied by this integration. The
benchmark harness records current-run scheduling and notification counters, but
its presence is not a performance result. The earlier timing investigation
linked above retains its original source, debug-runtime and load qualifications;
new target-specific measurements are required for claims about this final build.
