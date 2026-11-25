# Merged mail validation receipt

Qualified source commit: `1bd81015ecd261708b2b8254d8f9a9ef57b94c37`.
This checkpoint includes main `20c36e5ac1f21add8d3d75420ab43f8fc527eefe`.

**238 tests passed; none failed or skipped.** The source run exited 0, and all
557 captured source/test/fixture SHA-256 values were unchanged after the run.
The previous 146-test pre-merge run is retained separately and is not added to
this final total.

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
| Incoming main XML reader | 8 |
| Incoming main core Outbox | 16 |
| Incoming main store codec | 39 |
| Incoming main cache cleanup and account-scoped view expiry | 11 |
| **Total** | **238** |

The new-rich groups account for 111 tests, existing Studio compatibility for 47,
and incoming-main compatibility for 80. The 14 SQLite storage tests include
accepted Sent-copy receipt values `true`, `false`, and legacy `null` across an
actual close/reopen; all retain the accepted terminal state, frozen MIME bytes,
wire hash, rich content, and Bcc recovery without becoming retryable.

The incoming Word test uses the original 410,820-byte Liberation Sans fixture,
SHA-256 `075e71be4c58beda172ecb574a799308f04c3d054c6a5b7434954d3b0f1b28d8`.
Its relative fixture path is preserved by running from the harness engine package
directory. All five incoming test files are exact copies with no adaptations.

Strict pure-Dart analysis also exited 0 with **no issues** on 20 exact-byte
production/relative-dependency source files and 7 selected tests. The analyzer
uses real package dependencies. The tests receive only the documented
`flutter_test` to `package:test` API adaptation, real `Fake` import, and equivalent
synchronous `expect` assertion where necessary. Production files are unmodified
by the harness.

## Runtime and scope

- Official Dart 3.13.7, matching the repository's Flutter 3.47.8 pin.
- All 76 resolved hosted dependency versions match the repository lockfile.
- Actual sqlite3 package 3.9.1 and its official hook-produced SQLite 3.54.1 binary.
- Source-isolate tests preload the exact hook binary for FFI symbol lookup;
  no native backend, package implementation, or Flutter runtime is substituted.
- One test runner with concurrency 1 and package:test's supported source compiler.
- A disk guard was active; no disk abort occurred, and minimum free space remained
  24,379,392 bytes. The final gate required no production edits after the checkpoint.

This is model, Word conversion, MIME/submission, durable storage, and compatibility
qualification. It does not establish an executed Flutter widget test run,
installed app behavior, browser/plugin runtime, or live provider delivery.
Separate genuine Flutter/sky_engine source analysis has its own receipt and
should be described as static analysis.

## Evidence and reproduction

- `logs/merged_final_pure_validation.log`: complete expanded 238-test log.
- `logs/merged_final_events.jsonl`: original machine-readable test events.
- `merged_final_verification.json`: counts, commands, exits, log hashes, disk guard.
- `merged_final_source_manifest.json`: 557 source hashes and post-run comparison.
- `merged_test_copies.json`: exact original/copied test hashes and adaptations.
- `logs/merged_final_pure_analysis.log` and `merged_analysis_verification.json`:
  strict-analysis result and scope.
- `analysis_root/source_manifest.json`: exact-byte analyzer source copies.
- `merged_environment.json`: exact pins, lockfile hashes, SQLite and font hashes.
- `HARNESS_RECIPE.md` and `create_validation_harness.py`: standalone source-linked
  reproduction instructions using a full official SDK and normal disk capacity.

The reusable generator now creates all 12 selected test copies and the unchanged
font fixture. Its Python syntax was checked. The equivalent session harness ran
the recorded final gate; the generator was not rerun through an additional full
qualification after expansion, avoiding a redundant validation run.
