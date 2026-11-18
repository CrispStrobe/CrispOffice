# Independent native storage review

> **Preservation status: raw artifacts were not uploaded.** Only this README
> was recovered through the GitHub API after workspace disk exhaustion. The 24
> referenced raw logs, receipts and source manifests, plus their copy manifest,
> remain local in `docs/validation/mail-store-20261118/review/`; they could not be
> read or uploaded after filesystem commands stopped launching. Their links below
> do not imply that those files are present on the remote branch.
>
> The results below describe runs observed before that failure. They do not claim
> that the final combined qualification passed. The remotely recovered
> `checks/receipt.json` is explicitly a **BLOCKED observation summary**, not the
> original raw qualification receipt.

The accepted development runs contain **16 adversarial repository tests and five
actual SIGKILL recovery tests: 21 distinct cases**. Earlier attempts and later
qualification runs repeat these cases; their counts are not additive. These cases
also form part of the package's full qualification suite, so do not add 21 to that
suite's total.

Raw logs, stderr, analysis output, source manifests and existing receipts were
copied without modification. `evidence-manifest.json` records their SHA-256 hashes
and byte lengths. Scratch orchestration scripts and dependency caches are excluded.

## Accepted results and source binding

| Evidence | Result | Binding |
| --- | --- | --- |
| `repaired.jsonl` | 16 passed; zero failed, skipped or error events | `review.json` records the test source hash and per-attempt raw log hashes. Development source changed between attempts; a complete before/after implementation manifest and original argv were not captured for this run. A successful complete qualification is still required to provide that broader binding. |
| `crash-final.jsonl` | Five passed; zero failed, skipped or error events | `crash-receipt.json` retains exact original argv, working directory, timestamps and process observations. `crash-source-before.json` and `crash-source-after.json` contain 31 identical source/lock hashes. |
| `analysis.stdout` | Fatal-info analysis of the adversarial test passed | The test source hash is retained in `review.json`. |
| `crash-analysis-final.stdout` | Fatal-info analysis of the crash test and child fixture passed | The same two files appear in the accepted crash source manifests. |

The accepted crash run started at 2026-11-18 20:37:54 UTC and finished at
20:38:29 UTC. Its five `SIGKILL` observations each record an actual child process
exit of `-9`. The `process_signals` list also preserves five `CHILD_STDERR` messages
containing ordinary Dart native build-hook progress; these are diagnostic output,
not five additional kills or test cases.

## Reproduced defect and earlier attempts

The adversarial observer test exposed a real integration defect: a transaction
that rolled back caused a second header-stream snapshot even though its row writes
were correctly rolled back. The first failing run and a focused confirmation after
startup notifications drained both reproduce it. Inspection of the installed
Drift 2.35.4 implementation confirmed that transaction cleanup forwarded queued
table invalidations after rollback. The repository now awaits a successful
transaction before publishing invalidations, and the final regression passes.

| Retained log | Outcome and interpretation |
| --- | --- |
| `first.jsonl` | 12 passed and one failed: the reproduced rollback-notification defect. |
| `notification-confirmation.jsonl` | The same observer regression failed again after draining startup events. |
| `notification-control.jsonl` | Suite loading failed while the concurrently edited codec temporarily lacked `decodeDraftBody`; no substantive test executed. |
| `crash-first.jsonl` | Suite loading failed because the new fixture's generic inference left a possibly-null repository value; this was a test-harness compile error. |
| `crash-repaired.jsonl` | All five kill barriers were reached, but all five tests stopped at an overly strict empty-stderr assertion on ordinary `Running build hooks...` progress. They did not establish recovery acceptance. |

The crash harness now retains normal child stderr as evidence, rejects actual
fixture failure markers, and completes the reopen/state assertions. Only
`crash-final.jsonl` is the accepted five-case crash result.

The other findings in `review.json` came from source inspection followed by passing
regressions: retired profiles needed to reopen for durable credential cleanup;
provider identities and tombstone/journal rows needed quota coverage; and logout
with a foreign profile needed a typed failure without invalidating either session.

## Recovery boundaries exercised

The child fixture uses the public native opener and pauses at an explicit `READY`
barrier. Its parent sends SIGKILL, then opens the same database container. The
uncommitted boundaries are `afterSyncRecords`, `beforeSyncCursor`,
`afterDraftBlobs`, and `afterOutboxWrite`; each preserves the old cursor, records,
draft revision, owned bytes and queued outbox state. A fifth case kills only after
a submitting outbox save has returned successfully, then verifies durable recovery
to `uncertain` with the exact wire hash and recipient envelope. A further reopen
confirms that the recovered state persisted.

These are native SQLite process-termination checks. They do not establish browser
storage runtime behavior, operating-system reboot recovery, or sudden power-loss
durability. The earlier `review.json` limitation about graceful-reopen adversity
tests remains preserved as originally written; the separate crash receipt supplies
the later actual-process-termination evidence.

## Reproduction

With the repository's verified Flutter/Dart toolchain and locked dependencies,
run from `packages/quds_mail_store`:

```sh
dart test --reporter json test/adversarial_store_test.dart
dart analyze --fatal-infos test/adversarial_store_test.dart
dart test --reporter json test/crash_recovery_test.dart
dart analyze --fatal-infos test/crash_recovery_test.dart tool/transaction_crash_fixture.dart
```

These are reproduction commands, not a reconstruction of missing historical argv.
The exact original crash command and working directory remain in
`crash-receipt.json`. No GitHub Actions run, job or status was queried, awaited or
rerun for this review.
