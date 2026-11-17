# Native spaCy Dart/editor continuation — 17 November 2026

## Checkpoint and scope

This lane continues the accepted native German CPU/F32 analyzer through a new
optional [Dart package](../../../packages/quds_proofing_spacy/README.md). The
exact accepted native library and model are reused without rebuilding or
changing any native source, acceptance input, original annotation or tolerance.
Quds main `16e2477ff93f7a1ec5c6ed78491f2716ce4d1658` was merged and saved at
`4471324a612853946fd5c3b2e7077f570abbc10e` before implementation. All fork/upstream
branches and PR heads were fetched; no upstream main commit is missing. Other
in-progress Office/GECToR branches remain separately owned.

The current checkpoint implements a strict counted-string C ABI binding and a
persistent isolate worker. Its manual editor analysis view is under integration
and does not have a completed UI qualification receipt yet. No grammar provider
is registered. Existing deterministic proofreading, correction and undo paths
remain authoritative. The native gate remains default off; no app release,
consumer pin, native/model publication or platform promotion follows.

## Recovered runtime

[runtime-restoration.json](runtime-restoration.json) binds the original candidate
archive, all 15 installed files, six resolved dependency binaries, all five
model bundle files, original model wheel and pinned developer tooling. The
native binary SHA-256 is
`ea89842ebf22c08508aff1cfbf18d78a107118af320523009616ff62b6e42977`.
The bundle manifest is
`d599768375de3dc56abcca5cf1d49da0015857f9d3a10640aebb5317ef5d427e`.
The native target remains Linux x86-64/AVX2 with PCRE2 10.46.

Flutter 3.47.8 / Dart 3.13.7 and all 162 original Pub archives were authenticated;
the initial restored workspace resolves offline with its unchanged lock.
[All 21 existing actual-model API groups](restored-api-controls.json) pass after
restoration. The original eight-case acceptance was not rerun. Sanitized setup
logs are retained in [runtime-logs](runtime-logs).

## Dart binding evidence

[The corrected direct-FFI replay](dart-development-final.json) matches all 16
existing development documents, 113 tokens, 22 sentences and 2,571 exposed-field
comparisons, with zero differences, plus ten authored adverse/ownership controls.
Requests use a nonzero UTF-16 origin; embedded NUL, supplementary characters and
decomposed text retain the original source coordinates. Immutable copied results
remain valid after repeated context disposal. Unsupported locales, malformed
UTF-16, input/token limits and disposed contexts produce explicit failures.

[The first adapter result](dart-development-first.json) is retained. It exposed
a Dart-only overly strict root-label assumption: the unchanged original spaCy
whitespace-only sentence has a self-headed root labeled `dep`. The adapter now
validates the actual structural contract (one self-headed root, same-sentence
heads and no cycles) without inventing a required label. The original native
candidate and oracle were unchanged. The initial report-path sanitizer also
replaced a relative dot too broadly; future reports use absolute-path matches.
These initial receipts collect source identities after execution; subsequent
qualification seals source bytes before and after execution.

## Worker contract and remaining checks

The worker sends at most one full request to its isolate at a time, bounds
waiting callers, coalesces obsolete snapshots and authenticates replies against
the exact request/runtime identity. Cancellation and timeout settle callers
immediately, but only the actual native reply releases the physical slot.
Shutdown joins context cleanup after an active call returns; it never kills an
isolate to simulate native cancellation. Prompt interruption of native compute
is not claimed by this Dart adapter.

Twelve model-free tests exercise the actual isolate protocol, including 200
replacements, queue saturation, invalid replacement admission, timeout,
cancellation, unexpected exit, snapshot/runtime mismatch and delayed-startup
cleanup. These synthetic backend controls do not substitute for the explicit
actual-model worker replay or editor tests, which remain the next checkpoint.
The initial convenience `dart test` command stalled on implicit package setup;
the explicit offline Flutter and cached test runners completed successfully.

Continue with actual-worker replay, editor snapshot/lifecycle/widget checks,
portable web-import validation, and a source-bound final evidence index. Keep
grammar benefit, mobile/device packaging and release distribution separate.
Every checkpoint uses `[skip ci]` and a verified remote tree. No GitHub Actions
endpoint was queried, polled, awaited or rerun.
