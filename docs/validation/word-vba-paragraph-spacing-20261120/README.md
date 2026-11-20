# Word VBA paragraph spacing — incremental qualification

Date: 20 November 2026 (Europe/Berlin).

## Intake checkpoint

The continuation starts from `c7e721b7703766491fd4459b69de30bf68d9010d`,
including the completed cached-Mail workspace and the prior Word main
`3ee4e3622c9a2198d384ed1cb296ab092a8838d0`. The independent
[intake review](incoming-review.md) verifies all 23 captured fork branches,
262 fork PR heads, four upstream branches and four upstream PR heads.
All heads are contained or have recomputed exact-tree/changed-path equivalents.
The raw captures and machine-readable review are retained beside this record.

The Mail archive's 347 members and 5,648 source bindings were independently
checked, including raw accepted-event recounts. This is evidence verification,
not a claim that the Mail suite was freshly executed in this continuation.

Remote checkpoint branch: `codex/word-vba-paragraph-spacing-20261120`.
Checkpoints use expected-head, non-forced remote updates. GitHub Actions,
workflow runs and status checks are not queried or awaited.

## Implemented bounded extension

- `ParagraphFormat.LineSpacingRule` with `wdLineSpaceAtLeast`,
  `wdLineSpaceExactly` or `wdLineSpaceMultiple`, followed by `LineSpacing`.
- One explicit rule/amount pair lowers to one native `docx.lineSpacing` edit.
  Scalar computation and helper calls may separate the setters; another
  document write, a different target or an unfinished pair is refused.
- `ParagraphFormat.Space1`, `Space15` and `Space2` statement/Call forms.
- Word-only `LinesToPoints` and `PointsToLines`, both unqualified and on
  `Application`, with one positional actual numeric argument.
- Existing typed aliases, ByVal helpers, nested With, transaction policies,
  recording/replay and opaque VBA-part preservation remain applicable.

Point values must be positive exact twentieth-points whose native integer
fits signed 32-bit positive twips. Multiple spacing uses 12 points per line;
its native value is the requested points divided by 12. The adapter does not
guess a point value from an existing automatic line height. Existing preset
behavior remains the same.

## Acceptance plan and current status

Implementation is present at this checkpoint; final qualification is pending.
Development runs have exercised the new compiler, native edits and actual
example through integration, CLI, VM and JavaScript paths. Independent review
found and prompted fixes for parenthesized preset calls, common decimal line
conversion and preset source-ambiguity guards. Development results and earlier
failures are not final acceptance and will remain separately recorded.

Acceptance requires compiler/refusal cases, native preservation and layout
coverage, end-to-end transactions and the actual BAS example on Dart VM and
compiled JavaScript, complete prior Word/Office regression coverage, strict
engine analysis and formatting. Original test files will run as separate VM
suites when supported by the recreated local runtime. Raw logs, source/runtime
identities and final remote consistency will be recorded before publication.

Primary contracts: Microsoft's
[LineSpacingRule](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.linespacingrule),
[LineSpacing](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.linespacing),
[LinesToPoints](https://learn.microsoft.com/en-us/office/vba/api/word.application.linestopoints),
[PointsToLines](https://learn.microsoft.com/en-us/office/vba/api/word.application.pointstolines),
[Space1](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.space1),
[Space15](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.space15)
and [Space2](https://learn.microsoft.com/en-us/office/vba/api/word.paragraphformat.space2).
Expectations are specification-derived and bounded by the explicit dialect;
an installed Microsoft Word host is not part of this headless qualification.
