# Native Dart provider validation — 17 November 2026

This checkpoint contains the first complete real-model guarded provider run and
an independently authenticated replay of the original raw F32 logits. Native
F32/mixed conversion evidence is in [the native qualification](../2026-11-17-native/README.md).

## Retained development-mode run

`provider-jit-v1.json` executes the verified mixed GGUF through the actual Dart
worker, tokenizer, all decoding passes, read-only German lexicon, guards,
provider and `OfficeProofingService`. It preserves all warmup observations and
three timed repetitions per input. All 30 corpus cases returned their expected
operational status: 28 de-DE checks succeeded and two de-CH checks explicitly
reported unsupported. All eight integration controls and the three long-input
structural controls passed. The file seals 62 source/dependency files before
and after execution; no code changed during the run.

The conservative policy yields 5/18 expected corrections, versus 9/18 for the
unguarded reference, with all ten supported clean controls unchanged. The
four held valid changes and the Swiss unsupported cases are visible in full.
This is evidence of implementation behavior, not broad quality qualification.

Warm checks up to 64 WordPieces: median 26.142 ms, p95 93.618 ms, maximum
166.825 ms. Model verification and worker/dictionary startup took 4026.854 ms.
Peak whole-process RSS was 819,101,696 bytes (781.16 MiB), exceeding the 768 MiB
engineering budget in this Dart JIT development run. The GGUF is 82,756,896
bytes; the report does not treat that as the entire model-pack size.

Repeated grammatical sentence controls contain 61, 126 and 256 WordPieces.
Their p95 complete-check times were 166.825, 441.333 and 820.010 ms. They are
structural scaling probes, not representative long-document language tests.

## Exact Dart reference replay

`original-logit-replay.json` authenticates the original bundle and all saved
raw head tensors. All 30 cases / 40 passes match exact input IDs, masks,
first-subword alignment, words, selected tags, edited words, final corrected
text and UTF-16 suggestions. Largest selected-label probability drift from
Dart double versus NumPy float32 intermediates is 2.7512629274806244e-7;
largest detection drift is 6.107278971434482e-8. No decision differs.

The replay is unguarded and does not measure neural inference latency.
`pubspec.lock` preserves the resolved workspace dependencies used by both runs.
No model weights or raw logits are committed. No hosted CI was launched or awaited.

## Retained compiled execution

`provider-aot-v1.json` preserves the completed product-mode AOT run from the
previous checkpoint, byte for byte. All 30 case statuses, corrected strings and
findings match the JIT receipt. All eight integration controls and all three
long-input structural controls pass. The same 62 source/dependency files were
sealed before and after execution. The runner now records the actual Dart
runtime and AOT entrypoint sizes and SHA-256 values, and accepts an explicit
`--source-root` for compiled execution outside the repository.

| Complete guarded measurement | JIT | AOT |
| --- | ---: | ---: |
| Warm median, up to 64 WordPieces | 26.142 ms | 21.910 ms |
| Warm p95, up to 64 WordPieces | 93.618 ms | 62.017 ms |
| Startup including verification and dictionary | 4026.854 ms | 3384.501 ms |
| Peak whole-process RSS | 781.16 MiB | 295.50 MiB |
| 61-token structural control p95 | 166.825 ms | 165.940 ms |
| 126-token structural control p95 | 441.333 ms | 481.249 ms |
| 256-token structural control p95 | 820.010 ms | 636.641 ms |

The AOT run passes the provisional short-input latency and process-memory
budgets on this local host. The 256-token measurement remains above 500 ms;
the short-input budget is not a guarantee for long paragraphs. The 78.92 MiB
GGUF size excludes sidecars and native packaging. Intended desktop hardware,
representative language quality and rendered-editor responsiveness remain
separate acceptance work.

The retained AOT has SHA-256
`7fe62b6c387ea44e5b2be754b5dbdccb614380df9455e52e45f208643e177dca`;
the recorded `dartaotruntime` has SHA-256
`3599c987228070f342c80d29353f496c8efc72c620c75fc4d59e5671666b2f72`.
Both were independently rehashed during recovery. This original run records
source and binary identities at execution; it does not contain a separate
before/after compilation receipt. Preserve its original scope and all samples.

Operational success means the requested cases and controls ran correctly. It
is not a linguistic nonregression gate. The guarded v1 baseline retains five
of the nine unguarded expected fixes and leaves all ten supported clean
controls unchanged. Later guard changes must compare against this frozen
baseline without replacing either original JIT or AOT observation.

## Later guarded continuation

The [subsequent compiled run](../2026-11-17-continuation/README.md) preserves
these original receipts and adds an independently source-bound AOT build,
verified complete development pack and frozen guarded nonregression check.
It recovers the `Wir ist` correction (6/18 expected fixes, ten clean controls
unchanged). The original v1 values above remain unchanged historical evidence.
