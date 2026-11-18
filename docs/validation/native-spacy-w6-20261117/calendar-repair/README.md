# Incoming calendar-relative date repair

The latest Office main adds calendar-relative sheet conditions. The retained
[initial controls](../main-refresh-controls/first.json) expose incorrect date
boundaries outside UTC: Europe/Berlin fails one of twelve cases, and
America/Los_Angeles fails seven. The exact original resolver is preserved in
[initial-resolver.dart](initial-resolver.dart), with its incoming-main identity
in [initial-manifest.json](initial-manifest.json).

The repair changes **two constructor expressions** in
`sml_conditional_format.dart`. Today and month-offset boundaries now use UTC
civil dates built from the injected clock's year, month and day. This preserves
the intended local calendar day; it does not convert the clock's instant with
`now.toUtc()`. Day/week/month arithmetic therefore shares the spreadsheet
serial date representation and avoids timezone and daylight-saving offsets.
Grammar and proofreading sources are unchanged.

[Final checks](final.json) pass with source/lock hashes unchanged throughout:

| Check | Result |
| --- | --- |
| Focused sheet regressions in UTC | 178 passed, including the 8 new calendar controls |
| Same 8 calendar controls in Europe/Berlin | 8 passed |
| Same 8 calendar controls in America/Los_Angeles | 8 passed |
| Original 12-case boundary probe, unchanged | 12 passed in each of UTC, Berlin and Los Angeles |
| Static analysis of the resolver and new test | Zero issues |

The new controls cover inclusive seven-day endpoints, Sunday week boundaries,
near-midnight local dates, the Berlin and Los Angeles DST transition dates,
and month/year rollover. Repeating them in different timezones does not add
independent calendar cases. The original negative receipt and logs remain
unchanged. No provider default, native model, grammar planner or evaluation
panel changed as part of this repair, and no GitHub Actions endpoint was queried.
