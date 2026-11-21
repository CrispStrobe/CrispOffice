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
finished. Whitespace and punctuation complete a word; letters, combining marks,
numbers, apostrophes, underscores and hyphens keep it open. Sentence-final
punctuation or a change of paragraph during editing completes a sentence or
paragraph. Deletion that moves the caret backwards does not complete a word.

Completion work starts after `WordProofingTiming.wordCompletion` (150 ms). A
pending word check can become a sentence check, but further completions do not
postpone that pending timer. Continued typing therefore does not indefinitely
delay checks of completed words. Pause and idle timers are postponed by new
input.

| Trigger | Provider groups | Paragraph scope |
| --- | --- | --- |
| Completed word | Enabled spelling-only providers | The typing paragraph. |
| Completed sentence or paragraph | Both enabled groups | Edited, newly inserted or incompletely checked paragraphs. |
| Typing pause | Both enabled groups | Edited or incompletely checked paragraphs; the initial pass may cover the document when background checking is enabled and no cached results exist. |
| Background idle | Both enabled groups | Remaining unchecked paragraphs, with the typing/caret paragraph first, then visible paragraphs, then increasing distance from the caret. |
| Explicit check | All ordinary providers; manual providers when requested | Document-wide coverage, reusing valid ordinary cached results. |

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
another provider call.

Content edits invalidate the active generation. Results are accepted only for
the current document, revision and provider configuration. Unchanged paragraphs
reuse cached reports; a spelling-only pass does not count as a completed grammar
check. Document replacement clears document-owned cached state. Language
detection runs for the selected sentence/pause/background scope rather than for
each completed word.

Checks of the text being typed publish their results when finished and do not
show the **Checking…** indicator. Background and explicit passes can show it
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
