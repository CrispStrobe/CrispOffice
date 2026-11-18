# Independent spelling review

The reviewed native identifier and German projection changes had no remaining
blocking finding in the saved review. Its original source and regression-file
SHA-256 hashes are recorded in [review.json](review.json), against integrated
baseline `4dceb86e9fae51877bb5b7dc01e7a8bc721cb6ea`.

## Recovery note

The review record was pushed before the previous session ended, but its raw
before/after test logs and execution receipt were not. References to
`identifier-review-before.txt`, `identifier-review-after.jsonl` and
`identifier-review-receipt.json` in the saved JSON name those unavailable
artifacts; they are not evidence recovered in this continuation. The historical
observations below are preserved as recorded and excluded from current
acceptance totals. Use the source-bound qualification in the
[resume report](README.md) for delivery-level results.

Both implementation-file hashes in the saved review still match checkpoint
`f482b06fc47545c8b03124c30ea78f54e8e4b9e5`. Two native test files subsequently
received analyzer-only edits in that checkpoint: removal of a redundant import
and redundant interpolation braces. Their old hashes therefore describe the
earlier review inputs, not the final test bytes.

## Issue found and repaired

The first native interval implementation inspected only the beginning of each
grapheme for numeric or connector markers. Unicode Prepend characters can occur
before the marker inside that same grapheme. For example, a native spelling
response for `Fe\u06004\u0301ler` could still offer to rewrite the identifier.
The adjacent fragment in `\u06004\u0301Feler` and a soft-hyphen-projected variant
were also exposed. The German projected guard used the same prefix-only
assumption.

The saved review reports that independent native regressions reproduced **three
failing tests** while two preservation controls passed. Both providers now
inspect the complete grapheme for numeric/connector markers and retain its exact
start and end. The reviewer
did not edit production implementation files.

After the repair, the saved review reports that the independent native suite
passed **all five tests**, with zero failures and zero skips, and that source
and test hashes remained unchanged during that run. The unavailable earlier
failure log was described as an observation of the first implementation, not
an isolated unchanged-main baseline run. These counts are historical review
claims, not newly verified executions.

## Review conclusions

The native binary lookup correctly protects markers within a reported span and
at its trailing boundary. Preceding marker-cluster adjacency is retained. The
marker list is sorted by its single grapheme traversal, so native result order
does not affect lookup. Whole-cluster marker scans remain linear in total text
length.

German projection removes only discretionary soft hyphens for protection checks.
Its tokenizer and published ranges keep source offsets, with grapheme and
protected-range validation in both views. The canonical comparison additions
cover e/E diaeresis and s/S caron and compose after removing soft hyphens; this
remains a limited explicit composition map. The inspected implementation and
independent native controls preserve separated prose, explicit hyphen parts,
CJK findings, combining marks and supplementary characters.

The native controls use a controlled spelling service. They do not establish
physical Android/iOS dictionary behavior, target-device performance, browser
execution or full application acceptance. German execution results are recorded
by the implementation agent and are not included in this reviewer's five-test
execution count. No Actions, workflow, check-run or CI-status endpoint was used.
