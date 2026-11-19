# Independent review — final captured-source qualification

**PASS: 2,018 distinct substantive Dart/Flutter cases across 129 suites.**

This review covers source commit
`39843ed4874c7b56572c7aa8195716e5892aeca2` and the complete
`combined-final-qualification` run. The earlier 1,985-case replay at `59f13897`
is preserved separately and is not added to this total.

| Cohort | Suites | Distinct substantive cases |
| --- | ---: | ---: |
| Engine review and Zotero | 42 | 717 |
| Editor Notes, headers, review and Zotero | 73 | 1,154 |
| Studio review and navigation | 10 | 117 |
| Mail UI | 4 | 30 |
| Total | 129 | 2,018 |

The reviewer independently reconstructed suite/name identities from raw
reporter events, excluding successful loaders and lifecycle events. It checked
every start/completion, terminal success, announced and observed suites, exact
committed selection and execution commands. All selected suites produced
substantive cases. There were no failed or skipped events, errors,
incomplete/repeated completions, duplicate substantive identities, overflow
diagnostics or missed-tap diagnostics. Stderr was inspected as well.

Strict analysis of all 30 committed targets ended with no issues. Formatting
checked the same 30 targets and reported zero changes. Both exited successfully
and their raw/compressed log hashes match. The final raw count is 33 higher
than the first complete run; exact identity additions/removals are retained in
`case-delta-from-first.json`.

## Provenance checks

- All 4,992 ordinary source inventory records match Git blobs at the exact
  frozen source commit. Documentation-only evidence commits during execution
  do not alter this source comparison.
- The source inventory and all 11,948 environment records are identical before
  and after the run. Independently hashing current files confirmed the recorded
  source/environment bytes remained present and unchanged at review time.
- All six harness and plan files match the frozen commit, before-run hashes and
  current bytes. The effective package configuration matches its recorded hash.
- Raw log hashes, compressed log hashes, decompressed byte equality and the
  receipt's saved JSON evidence hashes all agree.
- The run contains exactly the four planned test groups followed by strict
  analysis and formatting. No runner or final-inspection error was reported.
- The earlier 14 targeted-runner controls remain applicable to byte-identical
  control/runner/parser/source-binding files. Their original raw logs contain
  14 successful methods, no skips, a successful terminal summary and matching
  hashes. These are preserved controls, not a claim of another fresh execution.

`peer-audit.json` contains the final guards, counts, timestamps and hashes.
`peer-cases.json` lists all 2,018 unique suite/name identities; individual cohort
audit files also provide per-suite counts and event details.
`control-source-continuity.json` records the retained controls separately.
`audit_union.py` is the independent reproduction code. This review did not
rerun application tests or rely on GitHub Actions.

This is targeted local qualification, not a whole-repository test run. It does
not qualify offline-browser lifecycle/CSP/performance, installed Studio/real OS
IME, browser Mail persistence, or independent human linguistic review. Those
checks remain separate and open. Native fixture/build results are a separate
cohort and must be deduplicated before making any combined unique-case claim.
