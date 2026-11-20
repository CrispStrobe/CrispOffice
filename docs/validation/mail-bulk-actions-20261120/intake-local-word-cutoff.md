# Word regressions retained from the frozen source cutoff

Status: **PASS**. The captured `ba6b170c1e011853128af6dcb9333ae9e22e79a1` reconciliation added no production behavior beyond the accepted Word implementation. It preserved thirteen additional compiler cases and one integration case that were not present in the first combined qualification.

The named compiler suite now checks explicit numeric-string conversion for all ten conversion functions, large metric arithmetic, the exact converted tab boundary and the shared source-work limit. The integration addition preserves existing tab stops, paragraph/run formatting and native values through validation, save/reopen and replay, and verifies that playback does not become a new recording.

## Executed targeted gates

| Gate | Result |
| --- | --- |
| Expanded named compiler + integration suites on VM | **171 passed**, zero failures/skips |
| Expanded named compiler suite on JavaScript/Node | **160 passed**, zero failures/skips |
| Strict formatting and analysis | Parser and two expanded suites clean |
| Source binding | All **369** scoped inputs unchanged during the run |

The [targeted receipt](intake-local-word-cutoff-validation.json) contains exact commands, stdout/stderr hashes and terminal outcomes. Only the two named test files differ from the prior accepted snapshot; all **367 other inputs**, including the production compiler, the other seven VM suites, other four portable compiler suites, and all three BAS/portable drivers, remain identical. Their earlier acceptance remains applicable.

The [combined cohort record](intake-local-word-combined-cohorts.json) replaces the two old named-suite results with the complete rerun. It accounts for **771 passing VM cases across nine suites** and **725 passing JavaScript/Node cases across five suites** on the final source. These are assembled qualified cohorts, not a claim of one 771-case or 725-case invocation. The actual earlier broad runs were 757 VM and 712 Node; the actual later focused runs were 171 VM and 160 Node. The portable compiler cohort overlaps the VM cohort and must not be added into a unique-test total.

## Merge decisions

The production parser, corrected nonnumeric-Variant fixture and large-scalar regression were retained exactly. The two named suites gained the additional cases without dropping their prior test names. The merge preserved main's Office coordinate/native-unit citations and the incoming consolidated measurement contract.

The newer Word unit-conversions README remains at its original path. The incoming historical checkpoint README and reconciliation record are retained under their distinct filenames, with all newer evidence preserved. The [merge receipt](intake-local-word-cutoff-merge.json) records these decisions and the scoped delta.

The [first final Word summary](intake-local-word-final.md) preserves the original 757/712 acceptance and all diagnostic history, including the eight declaration-order fixture failures and the interrupted nonaccepted run. No GitHub Actions, workflow runs or status endpoints were queried or awaited.
