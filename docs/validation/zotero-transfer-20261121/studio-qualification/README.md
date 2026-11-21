# Studio qualification and native fixture corrections

The accepted combined eight-suite Studio process completed **189 tests with
no failures, skips, or raw runtime diagnostics** in **113.893 seconds**.
It also had no non-JSON output lines and an empty stderr. Runner version 5
checks raw Flutter/runtime errors as well as JSON test results before
accepting a process.

All 1665 captured source inputs were unchanged during the run.
`QUDS_TYPING_BENCHMARK=1` enabled all three optional benchmark cases.
Concurrency was 1, with a 150-second inactivity watchdog and 900-second
maximum runtime; neither watchdog triggered. The process exited normally
with terminal success.

## Accepted evidence

`accepted-combined24165f5c/summary.json` is the final Studio acceptance receipt
for the combined source. It records the exact command, runtime, environment, source
fingerprints, JSON results, and raw-diagnostic decision. The adjacent raw
events and case list retain all individual outcomes.

The eight suites cover Mail capture projection, mailbox sessions, cached
hosts, cached mail, Studio settings, Zotero citing transport, Zotero
shortcuts, and the typing/proofing benchmark. The four additional cases
verify disposal and repository cancellation for IMAP, EWS, Gmail, and Graph.

Both the starting and ending source commits were
`24165f5ca6aff2d2a0c371ea473d82eba1e10f16`, after merging the newly advanced
remote main `290dfa43`. This rerun includes the incoming proofing behavior,
native test I/O waits, and benchmark forwarding changes as well as the
Zotero transfer work and fixture corrections. The full source manifests
record the exact tested contents. No product or test source changed during
this final replay.

## Rejected runs retained for diagnosis

| Directory | Observed result | Acceptance |
| --- | --- | --- |
| `initial-failed-incomplete/` | 181 JSON successes, one native fixture timeout, then a stalled benchmark loader | Rejected; interrupted and incomplete |
| `final/` | 185 JSON successes, but four raw Flutter unhandled closed-database exceptions | Rejected; its original JSON-only acceptance flag is invalidated by the raw audit |
| `accepted-clean189/` | 189 JSON successes and no raw errors on the prior source snapshot | Passed that snapshot; superseded for final acceptance after the additional main merge |
| `accepted-combined24165f5c/` | 189 JSON successes, no raw errors or other output diagnostics on the combined source | Final accepted Studio gate |

The historical directory name `final/` is retained to preserve the earlier
evidence. Its `accepted_process: true` value came from runner version 4,
which did not include non-JSON runtime errors in its acceptance decision.
`final/raw-diagnostic-audit.json` explicitly rejects that run and identifies
all four offending raw lines. The original receipt and logs are unchanged.
Neither rejected run is counted as a successful gate.

## Native I/O wait correction

The initial failure was `confirmed native cleanup restores quota-blocked
draft admission after reopen`. It failed while preparing the initial native
database fixture, before reaching a quota or UI assertion. The helper's
1000 fake-clock iterations expired after approximately 238 milliseconds of
actual test time, before native file I/O had finished.

`packages/quds_office_editor/example/test/support/mail_outbox_store.dart`
now uses a bounded 15-second `Stopwatch` deadline while retaining the
required fake-timer pumping and yielding one real millisecond between
turns. It still returns the original result or propagates the original
error. Product code, quota limits, and test assertions were not changed.
The exact helper before and after, plus hashes and the diagnosis, are in
`native-fixture-correction/`. Source snapshots use a `.dart.txt` suffix so
they remain evidence rather than additional analyzer inputs.

## Native fixture ownership correction

The rejected 185-test run emitted a raw unhandled exception for each
provider: `Bad state: This database has already been closed`. Its stack
traversed Drift's abandoned-transaction rollback after SQLite had closed.
The error appeared during each `view and body save warnings survive success
in the other scope` case, immediately following the corresponding failed
initial-view-save case.

The cached-host fixture removed its widget, which initiated asynchronous
host disposal, then called `owner.close()` itself. That bypassed the host's
existing cancellation and read-drain ordering. Live repository reads run
outside the draft owner's serialization queue, so the competing fixture
close could close SQLite while a watch read transaction was still active.

The corrected fixture observes the actual host-owned close completion
through `_Owner.whenClosed`. Teardown releases test cancellation gates,
removes the widget, and awaits that completion, including any close error.
It does not initiate a competing close. Four new provider cases hold
repository cancellation, verify that the owner remains open, release the
gate, and verify completed cancellation and close. No production shutdown
code changed.

`native-close-before/` retains a minimal unchanged-source reproduction:
two IMAP cases produced JSON successes and one raw unhandled exception.
`native-close-after/` retains the same pair plus the new disposal regression:
three cases passed with no raw error. `native-close-correction.json` records
the exact source hashes and causal diagnosis. Both the subsequent full
189-test gate and the final combined-source 189-test replay had no raw errors.

`files.json` records SHA-256 hashes for every retained file in this bundle
except itself. Raw runtime diagnostics must remain part of acceptance;
green JSON case results alone are insufficient.
