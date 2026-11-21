# Proofing scheduling

The native Word editor separates spelling, grammar and document-wide background
work. `WordProofingSession.schedule` accepts a `WordProofingSchedule`; Studio
persists its user-facing settings in the existing proofing settings group.

| Setting or trigger | Behavior |
| --- | --- |
| While typing | A completed word schedules spelling after 150 ms; completing a sentence or paragraph schedules the enabled provider groups |
| On pause | Automatic work waits for the configured pause |
| Manual | Only explicit commands such as Check document or F7 run |
| Pause | Defaults to 1,500 ms; Studio accepts whole milliseconds from 300 through 5,000 |
| Background checking | Checks remaining text after an idle interval, prioritizing the visible pages and then distance from the caret; default idle interval is three seconds |
| Spelling / grammar | Independently enables automatic work for those provider groups; explicit checks retain their separate coverage |
| Hide typing errors | Keeps findings touching the active typing position hidden until the word is completed or the caret leaves it |

`OfficeProofingProvider.categories` identifies spelling-only providers. A
provider reporting other or mixed categories is scheduled with grammar. The
service's optional `only` filter selects providers; the editor merges partial
results for the same text in provider order. It retains verified results while
other paragraphs or provider groups are still being checked.

Pause and completion work does not continuously display progress chrome.
Background and explicit passes can show a checking indicator after one second.
Passes yield after a four-millisecond main-isolate budget. Language detection is
performed for the text about to be checked after sentence completion or a pause,
rather than for each completed word. Edits, document replacement and provider
configuration changes retain the session's generation and source checks.

Changing the schedule cancels pending automatic timers and schedules work under
the new settings. Explicit checking remains available independently of the
automatic mode. This replaces the earlier continuous-typing maximum-delay
schedule; embedding hosts should configure `schedule` rather than the removed
`maxDelay` parameter or internal caret-deferral controls. The existing `debounce`
constructor argument maps to the schedule's pause for compatibility.

`word_typing_proofing_schedule_test.dart` covers the scheduling rules and
compares a settled automatic result with an explicit complete check. The other
proofing session, language, correction, navigation and pane suites cover its
consumers. Timing measurements in older performance reports retain their
original source and configuration; they are not measurements of this schedule.
