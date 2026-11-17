# Paragraph-anchored ODF extraction correction

Source: `fa9821a7c9634a97aec6a8cf4d2617a926838934`, parent
`4fdac35c8da50e9c62ffab4a86dd2397c21186b4`. The product patch and 18 new
regression cases are included in `source.patch`. This is correction-specific
validation before the final combined source freeze; final qualification is
owned by the root report.

The shared ODF decoder now returns text-box paragraphs consumed by a surrounding
paragraph anchor. The streaming extractor accepts those separate paragraph
results, and bounded search uses the same shared decoder. Anchor inline text
stays contiguous, followed by its text-box stories in source order. Empty
text-box anchor wrappers add no synthetic paragraph. Ordinary empty paragraphs
and explicit spaces, tabs, and line breaks remain. Exact namespace identity,
annotation and covered-cell suppression, inline note/ruby exclusions, and the
cumulative UTF-8 expansion budget are tested. Nested boxes emit each paragraph
once. The original failing whitespace assertion remains byte-for-byte unchanged.

## Accepted local results

| Cohort | Passing cases | Files | Failures / errors / skips |
| --- | ---: | ---: | --- |
| Dart VM | 113 | 6 | 0 / 0 / 0 |
| JavaScript / Node repeats | 41 | 3 | 0 / 0 / 0 |
| Executions | 154 | 9 file executions | 0 / 0 / 0 |

These counts were reconstructed independently from the raw test events in
`summary.json`. Node repeats cases from three VM files. Both cohorts passed
strict scoped analysis and formatting. Source, complete selected SDK/runtime
inputs, and the preserved lock were unchanged before/after. Genuine Flutter
3.47.8 / Dart 3.13.7 and Node 24.22.1 were used. Dependency manifests and the
preserved lock were not edited. Exact commands, runtime identity, source hashes,
and gzip-compressed stdout/stderr are in each cohort receipt.

## Retained unsuccessful attempts and receipt correction

`development-vm.jsonl` and `development-attempt.json` retain an initial command
that lacked the task TMPDIR. It failed before the first assertion because the
host `/tmp` directory was unavailable; the original terminal stderr was not
separately captured, while the same loader error and stack are in its JSON
events. The corrected driver sets TMPDIR explicitly. This attempt is excluded
from accepted test totals.

The initial VM driver completed all six test files and both strict gates, then
raised a KeyError while choosing a runtime-manifest metadata key. The exact
initial driver, `vm-driver.log`, and `vm/receipt-before-finalization.json` are
retained. `bookkeeping-correction.json` gives the one-line repair. VM receipt
finalization rechecked current source and runtime identity; the original
`runtime-after.json.gz` exactly matches the fresh `runtime-finalization.json.gz`.
No test assertions were rerun to repair the receipt. The corrected driver was
then used for Node. `vm/receipt.json` explicitly records this finalization and its
later source check. All raw test and command streams remain unchanged.

The root report separately preserves the 4fd regression-failing full VM receipt.
No GitHub Actions jobs, checks, or commit statuses were queried or awaited.

## Reconstruction

`manifest.json` outside the archive binds every archived file and its size.
The archive deliberately excludes generated TMPDIR/config files. Extract it to
an empty directory, verify each manifest SHA-256 and exact member list, then
read `summary.json` and the two cohort receipts. The archive contains every raw
log, metadata receipt, source patch, setup/restoration record, and driver used
for this scoped qualification. `reconstruction-check.json` records a successful
independent extraction and exact digest comparison.
