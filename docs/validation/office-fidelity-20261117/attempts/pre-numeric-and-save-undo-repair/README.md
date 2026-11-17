# Superseded first combined qualification

The first full local run used published source `fa0f9c201a147bbf8a88fd17d48b77fa00300812`.
Engine: 1,380 passing tests. Harper: 29 passing tests. Editor: 367 passing
and three erroring tests, all in saved worksheet rename undo for pending formula
types. Analysis and formatting passed in all cohorts, and each before/after input
map was unchanged. The run is not the final accepted qualification.

The expanded editor cohort exposed a saved conditional-state/rename interaction.
Independent review also found that the newly enabled conditional formulas could
invoke unbounded numeric rounding/power loops despite their structural budgets.
No dangerous giant-loop negative probe was executed. Both issues are repaired
before the replacement qualification; all cohorts are rerun because engine inputs
are shared. These historical counts are not added to final counts.

Exact receipts, JSON event logs, source/runtime inputs and generated artifacts are
retained here at their original source attribution. External PDF/ODF checks of
these artifacts are also historical and must not be substituted for the fresh
final-source checks. No GitHub Actions, checks or statuses were queried.
