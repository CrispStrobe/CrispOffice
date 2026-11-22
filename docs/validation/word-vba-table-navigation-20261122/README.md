# Word table navigation continuation

## Intake

Work began from remote main `5d18df8dccaed89fd42720bb63dae09ae83d90ae`.
The [captured intake](intake.json) independently checked all 34 retained fork
branch heads and all four upstream branch heads as ancestors of that commit.
The explicit open-PR query returned no results; the 100 most recent PRs were
already merged. No intake merge was necessary. GitHub Actions are not a gate
for this continuation.

## Scope under development

Extend the bounded Word source adapter with typed `Rows`, `Row`, `Columns`,
`Column` and `Cells` selectors. An explicitly selected row or column supplies
its cells, which lower to the existing guarded table-cell operations. Required
named `Index` arguments and `Table.Cell(Row:=, Column:=)` support conventional
Word VBA template code without document reads during compilation.

Whole-table `Cells`, collection enumeration/counts, whole-row/column ranges,
merged-cell geometry and live property reads remain separate capabilities.

## Validation status

Implementation and local qualification are in progress. This checkpoint records
intake and scope only; it does not claim completed tests or installed Word
compatibility. Final commands, source identity and results will be recorded
before publication.
