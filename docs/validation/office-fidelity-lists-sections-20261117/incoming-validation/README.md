# Incoming-work local qualification

This archive preserves the scoped local validation of integration commit
`097475fbda96aa4a6497d92f28d10f1aa5f640b4` and the isolated strict-gate correction
`56dc162bf9a1003189e36e1f2a4678620c824546`. The correction can be reconstructed
from the published integration using `strict-correction.patch` inside the
archive. Later ODT changes have separate qualification.

| Cohort | Passed | Explicit skips | Test files |
| --- | ---: | ---: | ---: |
| GECToR VM | 97 | 1 | 8 |
| Engine integration VM | 78 | 0 | 5 |
| Actual Flutter editor | 119 | 0 | 6 |
| Node engine repetitions | 49 | 0 | 3 |
| **Dart/Flutter executions** | **343** | **1** | **22 file executions** |
| Ancillary Python checker tests | 65 | 0 | 2 modules |

The Node cases repeat three engine files. GECToR's native-inference fixture is
explicitly skipped without pinned model/library inputs; no neural inference is
claimed. Its original test fixtures depend on `dart:io`, so no GECToR JavaScript
suite was run.

The initial engine run passed all 78 runtime cases but failed strict analysis
(two missing-brace lint findings) and formatting (one note regression). The
failed receipt remains intact. A two-file nonsemantic correction was followed
by successful strict gates and the 49 Node cases; exact reversal controls and
the patch are archived. This is a composite qualification, not an uninterrupted
all-pass original engine attempt.

Dart/Flutter cohorts bind their source/runtime inputs before and after and
preserve the original enforced dependency lock. Runtime: Flutter 3.47.8,
Dart 3.13.7, Node 24.22.1. The initial offline setup failure and exact restoration
of the pinned `url_launcher_android` 6.3.33 archive are retained. No manifest or
lock edits were made during qualification. No GitHub Actions/check/status
endpoint was queried or awaited.

## Restore and verify

`incoming-validation.tar.xz` contains **86 files**, including every raw event
stream, failed static receipt, correction, complete runtime/source manifests,
per-test summary, reconstruction scripts and detailed report. Its SHA-256 is
`19f6e427602c077ae0796dac55d0ae1c9fb9fa71c429288c4132067606dcdbd0`.
The adjacent [manifest.json](manifest.json) lists every restored file's hash and
size. [summary.json](summary.json) is the compact cohort summary.

```sh
python3 verify_archive.py restored-incoming-validation
```

The destination must not already exist. The verifier checks the archive digest,
rejects unsafe/duplicate members, restores files and verifies the exact file
set, byte counts and hashes. The saved reconstruction check passed for all 86
files. The restored `README.md` describes all source boundaries and limitations;
`summary.json` contains per-file and per-test reconstructed outcomes.
