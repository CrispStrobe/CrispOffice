# IMAP reader scaling follow-up — not implemented

## Status and scope

This is a read-only source review of frozen commit `dfb2822953156496f60efd62f68ff4dc885c93ab` during local
qualification. No product source, test, runtime file, Git reference, or active test
process was changed by this review. No additional test or benchmark was launched.
The issue below is an existing scaling inefficiency, not a new security fix.

The timings and 454 protocol-case results below come only from the earlier
`97393efd` gate. That protocol group completed successfully, but its overall gate
failed a separate EOF fixture and stopped before Node qualification. No aggregate
acceptance is implied. The source review was recorded at `dfb28229`; all six
product/test files listed below are byte-identical between `97393efd` and
`dfb28229`. This note does not use results from the later `dfb28229` gate.

## Exact observation from the completed reporter stream

Log: `/workspace/scratch/82189ef49fff/office-mail-gate-97393efd/native/checks/enough-mail-protocol-regressions.jsonl`

Log SHA256: `22e82bf5cfd899e5010aa3bc8e61ae60c440ee68d85f39bcb4d9c4ee0200f57f`

The stream has 454 non-hidden successful test completions, zero skipped
cases, zero unfinished started tests, and terminal success at
109788 ms. Individual reporter times are elapsed milliseconds from
the test process, not independent per-test CPU measurements.

| Test ID | Test | Start ms | Finish ms | Elapsed ms | Result |
| --- | --- | ---: | ---: | ---: | --- |
| 104 | ImapResponseReader many literals in one response do not overflow the stack | 7464 | 92018 | 84554 | success |
| 633 | SMTP: a command whose write fails is rejected | 109761 | 109782 | 21 | success |
| 634 | POP: a command whose write fails is rejected | 109782 | 109785 | 3 | success |

The apparent wait after the POP test name was not a pending POP command:
the POP write-failure case completed in 3 ms and the protocol group emitted its
terminal success event immediately afterward. Any later outer-run wall delay
cannot be attributed to this case from this reporter evidence.

## Concrete scaling mechanism

`test/imap/imap_robustness_test.dart`, lines 85–94, constructs one input chunk:
11 prefix bytes, 100,000 repetitions of the 9-byte string `X {1}\r\na `,
and 8 suffix bytes. Total input size is **900,019 bytes**. Each literal has
length one; the test is exercising a long sequence of literals, not one oversized
literal. It asserts that one complete response is delivered without stack overflow.

`ImapResponseReader._process` is iterative and advances normally: it consumes a
protocol line and then its one-byte literal. The scanning and response append
steps do not explain quadratic work for this input.

The concrete bottleneck is `OptimizedBytesBuilder.takeFirst` in
`lib/src/private/util/uint8_list_reader.dart`, lines 196–236, especially line 221:

```dart
final updatedChunk = chunk.sublist(chunkStartIndex);
```

For every partial consumption, `Uint8List.sublist` allocates and copies the
entire unconsumed suffix. Both `readLine` and `readBytes` call this method. The
single-chunk fixture therefore performs 200,000 partial consumptions, with a
large suffix copied after each short read.

For n repetitions, after each header and literal consumption the suffix lengths
are respectively `9k + 1` and `9k`, for k running from n down to 1. Thus this code
copies exactly:

```text
sum(k=1..n, (9k + 1) + 9k) = 9n² + 10n
n = 100,000: 90,001,000,000 suffix bytes = 90.001 GB (decimal)
```

That count excludes the much smaller required output copies, strings, object
allocation overhead, and garbage collection. It is derived from the source and
fixture lengths; it is not a measured memory-bandwidth or peak-memory result.
The exact regression took **84.554 seconds** by its reporter events in this run
and still completed within the configured 900-second child-process budget.

The response reader, byte builder, and regression test have no diff between
`ec8bd9cf` and this frozen source. Git blame attributes the `takeFirst` implementation
to commit `9ee120bd0`; this review does not attribute the defect to the current
Studio or SMTP changes.

## POP write-failure source check

`test/write_failure_test.dart`, lines 34–47, connects an in-memory failing socket
and expects `client.noop()` to reject with a `PopException`. The fixture's `flush`
returns an immediate failed future. `PopClient.sendCommand` calls `_write`, which
uses `ClientBase.writeOrFail`; its error handler clears the current command and
completes that command's future with the client error. There is no external mail
provider or intentional long timer in that test. Its 3 ms passing completion
matches the source-level behavior.

## Deferred follow-up

A future change can remove repeated suffix copying by retaining a read cursor or
an appropriate view of the remaining chunk, while preserving literal octets,
fragmentation behavior, and ownership/lifetime semantics. Such a change was
**not implemented or tested here**. Keep the existing 100,000-literal regression
and run the byte-reader/IMAP/POP fragmentation regressions against any future
implementation; do not weaken the stress size to hide the scaling cost.

This note makes no claim of external-provider acceptance, deployment,
end-recipient delivery, exploitability, or a new product qualification result.

## Reviewed source identities

Paths are relative to `/workspace/scratch/82189ef49fff/quds_office_suite`.

| File | SHA256 |
| --- | --- |
| `third_party/enough_mail/lib/src/private/util/uint8_list_reader.dart` | `f56b2399361666a0842dc7ead69f5c5d70296e868acd87ed0610c3482ef3a9a2` |
| `third_party/enough_mail/lib/src/private/imap/imap_response_reader.dart` | `f355e1e5788d58b5c877f0916b2d07af74efcc88137b96af9a558a5c6feb005d` |
| `third_party/enough_mail/test/imap/imap_robustness_test.dart` | `eb2bc62f1975d18ba825ff98075f8e57ec6c5f818544db4a3707acf18696a8c7` |
| `third_party/enough_mail/test/write_failure_test.dart` | `d66187add5969ac3180911b2d578fadeaf2126eb909dfeaeae7b95487cc87361` |
| `third_party/enough_mail/lib/src/pop/pop_client.dart` | `4004c947a847418aa5b9867c8597b152f715931ca40f414c0c7d5fd451fb89b2` |
| `third_party/enough_mail/lib/src/private/util/client_base.dart` | `660c7780730a1621934fa529840c6158cfbe8dea8d86ba1fc9aa9412e5baf286` |
