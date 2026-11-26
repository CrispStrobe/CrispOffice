# Final mail validation after the last main merge

Qualified source commit: `46645673bc944d1bb518703108234ba6836afc91`.
Its second parent is main `c37614eaca5778b22fcd15755b7a6dd20a20ca92`.

**239 tests passed; none failed or skipped.** The source run exited 0, and all
557 captured source/test/fixture SHA-256 values were unchanged after the run.
This final result supersedes the earlier 238-test gate at `1bd81015` and the
146-test pre-merge gate. Those receipts remain available separately; their
counts are not added to this final total.

| Qualification group | Tests passed |
| --- | ---: |
| New canonical rich body model and grammar | 45 |
| New Word conversion and editor document compatibility | 33 |
| New bounded rich preview data | 9 |
| New rich MIME/submission behavior | 10 |
| New real SQLite draft/recovery/Outbox storage | 14 |
| Existing Studio submission compatibility after main merge | 19 |
| Existing Studio Outbox privacy and content boundaries | 28 |
| Incoming main Word paragraph mark behavior | 6 |
| Incoming main XML reader | 9 |
| Incoming main core Outbox | 16 |
| Incoming main store codec | 39 |
| Incoming main cache cleanup and account-scoped view expiry | 11 |
| **Total** | **239** |

The new-rich groups account for 111 tests, existing Studio compatibility for 47,
and incoming-main compatibility for 81. The 14 SQLite storage tests include
accepted Sent-copy receipt values `true`, `false`, and legacy `null` across an
actual close/reopen; all retain the accepted terminal state, frozen MIME bytes,
wire hash, rich content, and Bcc recovery without becoming retryable.

## Last main delta and analysis

The final main commit changes only `xml_reader.dart` and `xml_reader_test.dart`.
The new test verifies namespace scope restoration through nested tags and shared
namespace snapshots where no declaration changes. The complete 12-file runtime
gate was rerun against this merge, including Word conversion and real storage.
Comparing the 557 fingerprints with the previous qualification confirmed that
only those two intended XML files changed.

Fresh strict analysis of the exact updated XML source and its exact test exited
0 with **no issues**. The prior strict pure-Dart analysis of 20 exact-byte
production/relative-dependency files and 7 selected tests also had no issues;
all 27 inputs were verified byte-identical at the final source commit. That
prior analysis was not rerun. Its original log and receipt are retained and
referenced by the latest analysis receipt.

Production source is never rewritten by the harness. Studio pure test
adaptations are limited to the real `package:test` API, its real `Fake` import,
and equivalent synchronous `expect` assertions. All five incoming test files
are copied without changes. The incoming Word test uses the original
410,820-byte Liberation Sans fixture, SHA-256
`075e71be4c58beda172ecb574a799308f04c3d054c6a5b7434954d3b0f1b28d8`.
Its relative path is preserved by running from the harness engine package.

## Runtime and scope

- Official Dart 3.13.7, matching the repository's Flutter 3.47.8 pin.
- All 76 resolved hosted dependency versions match the repository lockfile.
- Actual sqlite3 package 3.9.1 and its official hook-produced SQLite 3.54.1 binary.
- Source-isolate tests preload the exact hook binary for FFI symbol lookup;
  no native backend, package implementation, or Flutter runtime is substituted.
- One test runner with concurrency 1 and package:test's supported source compiler.
- A disk guard was active; no disk abort occurred. Minimum free space remained
  21,475,328 bytes. No production correction was required by the final gate.

This qualifies pure-Dart model, Word conversion, MIME/submission, durable
storage, and compatibility behavior. It does not establish an executed Flutter
widget test run, installed app behavior, browser/plugin runtime, or live provider
delivery. Genuine Flutter/sky_engine source analysis has its separate receipt.
The late XML-only change did not change the UI targets or require another SDK
download.

## Current evidence and reproduction

- `logs/latest_main_pure_validation.log`: complete expanded 239-test log.
- `logs/latest_main_events.jsonl`: original machine-readable test events.
- `latest_main_verification.json`: counts, commands, exits, log hashes, disk guard.
- `latest_main_source_manifest.json`: 557 source hashes and post-run comparison.
- `latest_main_test_copies.json`: original/copied test hashes and adaptations.
- `latest_main_environment.json`: pins, lockfile hashes, SQLite and font hashes.
- `logs/latest_main_xml_analysis.log` and `latest_main_analysis_verification.json`:
  fresh XML result, exact input hashes, and unchanged prior-analysis qualification.
- `logs/merged_final_pure_analysis.log`, `merged_analysis_verification.json`, and
  `analysis_root/source_manifest.json`: retained clean prior 20-source/7-test
  analysis, whose inputs were verified unchanged at this source commit.
- `HARNESS_RECIPE.md` and `create_validation_harness.py`: standalone source-linked
  reproduction instructions using a full official SDK and normal disk capacity.

The reusable generator creates all 12 selected test copies, the unchanged font
fixture, and the pure analysis overlay including the final XML source/test.
Its Python syntax was checked. The equivalent session harness ran this recorded
final gate; no redundant full qualification of the generator output was run.
