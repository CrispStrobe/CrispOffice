# Independent local-validation audit

Status: **verified_complete**. Frozen product commit: `f0122cb5bff5b6cf6a6f69f043545dabc2930791`.

Source verification: **current worktree bytes and frozen Git object identity**.

10 of 10 cohorts have completed and passed the independent audit: **2884 application cases across 134 suites**. Pending or running cohorts are excluded from this total.

| Cohort | Audit status | Passed cases | Suites |
|---|---|---:|---:|
| engine-zotero | verified | 642 | 29 |
| editor-zotero | verified | 632 | 43 |
| engine-rendering | verified | 191 | 11 |
| editor-rendering | verified | 101 | 9 |
| engine-vba | verified | 743 | 21 |
| mail-host | verified | 318 | 11 |
| mail-mime | verified | 115 | 6 |
| mail-transport | verified | 113 | 2 |
| engine-docx | verified | 23 | 1 |
| editor-docx | verified | 6 | 1 |

The independent selection contains 134 distinct suite paths, with no overlapping selections if the machine-readable errors list is empty. The audit verifies raw completion events, lifecycle exclusions, final success, per-suite counts, artifact checksums, source bytes against the frozen commit, resolved dependency inventories, workspace metadata, named runtime hashes and unchanged input digests. It checks identities by suite path and complete test name across cohorts.

Static final analysis/formatting audit: **verified**, 54 Dart targets. Actual CLI-process test cases completed: **30**; genuine Dart executable: **True**.

Supplemental SDK capture began `2026-11-20T04:39:55.233963+00:00`, finished `2026-11-20T04:39:57.186999+00:00`, and contains 1144 files. It precedes every observed core-cohort start: **True**. Exact cohort start times and capture-boundary observations are retained in the machine-readable audit. No earlier baseline is claimed for any run already in progress. Final after-capture comparison is recorded in audit.json.

See `audit.json` for exact checks, failures, paths and limitations, and `application-cases.json.gz` for every recounted application identity. This auditor ran no tests and modified no product or runtime files.

Existing-evidence verification requires the recorded checkout, SDK and dependency filesystem layout; absolute paths in receipts are not silently remapped. The exact replay invocation is:

```sh
python3 /workspace/scratch/ee4fc9e59992/final-validation/qualified/independent-audit/audit_validation.py --frozen f0122cb5bff5b6cf6a6f69f043545dabc2930791 --repo /workspace/scratch/ee4fc9e59992/quds_office_suite --sdk /workspace/scratch/ee4fc9e59992/zotero-toolchain/flutter-sdk --baseline a452efdadc9000c51a8e5e9ba2f16405d4979e2e --evidence /workspace/scratch/ee4fc9e59992/final-validation/qualified --out /workspace/scratch/ee4fc9e59992/final-validation/qualified/independent-audit --runner /workspace/scratch/ee4fc9e59992/final-validation/run_validation.py --static /workspace/scratch/ee4fc9e59992/final-validation/qualified/static --finish
```

Use the final invocation only after all ten accepted receipts exist. To reproduce tests in a different checkout, first use the portable qualification runners to create fresh receipts for that environment.
