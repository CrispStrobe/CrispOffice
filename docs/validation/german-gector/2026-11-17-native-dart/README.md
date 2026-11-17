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

Compiled execution is measured separately; its receipt will be added without
replacing the JIT observation or changing the engineering budgets.
