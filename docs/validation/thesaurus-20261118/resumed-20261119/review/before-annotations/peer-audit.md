# Independent review — first complete qualification

**PASS: 1,985 distinct substantive Dart/Flutter cases across 129 suites.**

This review covers only source commit `59f13897fd5aafccc234c58f41370dd786703418`
and the `combined-qualification` run. Later incoming-source replays are separate
runs and must not be added to this count.

| Cohort | Suites | Distinct substantive cases |
| --- | ---: | ---: |
| Engine review and Zotero | 42 | 714 |
| Editor Notes, headers, review and Zotero | 73 | 1,125 |
| Studio review and navigation | 10 | 116 |
| Mail UI | 4 | 30 |
| Total | 129 | 1,985 |

The reviewer reconstructed identities from raw reporter events, excluding
successful loaders and lifecycle events. It checked every start/completion,
terminal success, announced and observed suites, exact committed selection and
execution commands. All selected suites produced substantive cases. There were
no failed or skipped events, errors, incomplete/repeated completions, duplicate
substantive identities, overflow diagnostics or missed-tap diagnostics. Stderr
was also inspected. The count does not come solely from the runner receipt.

Strict analysis of the 29 committed targets ended with no issues. Formatting
checked the same 29 targets and reported zero changes. Both exited successfully
and their original/raw and compressed log hashes match.

## Provenance checks

- All 4,992 ordinary source inventory records match Git blobs at the exact
  frozen source commit.
- The source inventory and all 11,948 environment records are identical before
  and after the run. Independently hashing current files confirmed the recorded
  source/environment bytes remained present and unchanged at review time.
- All six harness and plan files match the frozen commit, before-run hashes and
  current bytes. The effective package configuration matches its recorded hash.
- Raw log hashes, compressed log hashes, decompressed byte equality and the
  receipt's saved JSON evidence hashes all agree.
- The run contains exactly the four planned test groups followed by strict
  analysis and formatting. No runner or final-inspection error was reported.

`peer-audit.json` contains the final guards, counts, timestamps and hashes.
`peer-cases.json` lists all 1,985 unique suite/name identities; the individual
cohort audit files also provide per-suite counts and event details.
`audit_union.py` is the independent reproduction code. This review did not
rerun application tests or rely on GitHub Actions.

This is targeted local qualification, not a whole-repository test run. It does
not qualify offline-browser lifecycle/CSP/performance, installed Studio/real OS
IME, browser Mail persistence, or independent human linguistic review. Those
checks remain separate and open.
