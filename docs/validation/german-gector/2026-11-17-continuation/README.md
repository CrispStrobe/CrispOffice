# German grammar continuation — 17 November 2026

The final integrated implementation is `a15d173ab05d0c569aa0693e33706358fe368da6`.
The compiled **v3** run preserves all prior guarded fixes and adds
`Wir ist zufrieden.` → `Wir sind zufrieden.`. It keeps all ten supported clean
controls unchanged. The source, build, run and comparison receipts are sealed
in [final-validation.json](final-validation.json). All validation was local;
no GitHub Actions run was dispatched, polled or awaited.

## Complete compiled checker

The guarded result improves from **5/18 to 6/18 expected corrections** on the
frozen synthetic panel. The same-number verb-person alias repair admits the
additional `Wir sind` correction from the authenticated verb table. It retains
the existing singular/plural, coordination and sentence-boundary guards. The
other three of the nine unguarded model fixes remain held.

All 30 corpus cases have their expected operational statuses: 28 successful
de-DE checks and two explicitly unsupported de-CH controls. All eight
integration controls and three longer structural probes also pass. Successful
execution does not mean every error was corrected. No v3 case status,
corrected text, finding or span differs from v2. The deterministic German
rules, including the imported genitive corrections, have separate tests;
6/18 is not an accuracy result for the combined Office grammar checker.

[provider-aot-v3-build.json](provider-aot-v3-build.json) binds the actual AOT
compilation to 62 selected runner sources, explicit package configuration,
109 resolved package records covering 4,755 Dart library files, and the
compiler/runtime SDK inputs. Before/after source, dependency and SDK seals
match. The compiled snapshot has SHA-256
`b3e68ff4f3291ceb16baf086ffbf0e19c3a34320eb8f80114085f0d91648126c`.
Its actual bytes, runtime/entrypoint pins and selected-source map match
[provider-aot-v3.json](provider-aot-v3.json).
[guarded-comparison-v3.json](guarded-comparison-v3.json) authenticates the
unchanged v1 baseline and corpus and verifies the guarded result.

An independent review passed 65 evidence checks. It recomputed the metrics,
reconstructed all 74 retained result/warmup outputs from their UTF-16 edits,
verified the source/dependency/SDK and pack files, and checked the captured
branch ancestry. It did not rerun inference or modify artifacts.

| Complete-check measurement | AOT v1 | AOT v2 through pack | Final AOT v3 through pack |
| --- | ---: | ---: | ---: |
| Warm median, up to 64 WordPieces | 21.910 ms | 23.863 ms | 24.020 ms |
| Warm p95, up to 64 WordPieces | 62.017 ms | 98.249 ms | 66.072 ms |
| Peak whole-process RSS | 295.50 MiB | 280.91 MiB | 343.80 MiB |
| Startup with verification and dictionary | 3384.501 ms | 3130.889 ms | 3619.700 ms |
| 61-token structural control p95 | 165.940 ms | 151.724 ms | 165.031 ms |
| 126-token structural control p95 | 481.249 ms | 355.255 ms | 369.813 ms |
| 256-token structural control p95 | 636.641 ms | 717.319 ms | 816.225 ms |

The v3 short-input cohort has 87 timing samples. Its latency and memory pass
the unchanged 500 ms / 768 MiB engineering budgets. Timing samples are retained;
complete per-case outputs are retained for the warmup and first measured run,
so repeated-output stability remains producer-reported. Separate local runs
cannot attribute timing differences solely to source changes.

The 256-token probe exceeds 500 ms; that budget applies to the short-input
cohort. Inputs beyond 512 tokens still fail explicitly rather than being
silently truncated. Repeated-sentence probes do not establish representative
long-document language quality. These observations do not qualify intended
end-user hardware or establish general German precision/recall.

## Incoming work integrated

The first inventory covered 381 branches across Quds, CrispEmbed,
onnx_runtime_dart and fastembed-rs. Quds had newer main, morphology, Office
fidelity, annotation and continuation work. The other three grammar branches
and their relevant base histories were already current. Integration commit
`aa6c50ed3736cea2c871f4bed7ae18a60e0cbb8b` preserves the captured Quds histories,
including byte-verified section histories equivalent to main.
[integration.json](integration.json) records those inputs and conflict choices;
`incoming-refs.json.gz` retains the full first branch/PR inventory.

A second fixed snapshot, captured at **2026-11-17 14:54:15 UTC**, is integrated
in `a15d173ab05d0c569aa0693e33706358fe368da6`. All **128 captured Quds branch
tips** are ancestors of that commit. The exact parents, tree, ancestry checks
and conflict decisions are retained in
[second-integration.json](second-integration.json).

The second integration includes:

- Main through `67482c2`, including PR #106 nested ODT lists and PR #107
  bookmarks and document links.
- Morphology through `c7c92bb`: explicit genitive corrections, bounded worker
  request coalescing and locale-aware omitted manual coverage. Unsupported-only
  documents no longer falsely report a skipped German model check.
- Continuation through `65c5c6e`: continuous, empty, table-first and list-first
  ODT section handling, combined with main's nested-list writer.
- Office-fidelity evidence through `ba1e999`, preserving the existing note,
  annotation, comment-link and covered-cell behavior.
- Equivalent feature/vendor histories as parents after checking their tree or
  patch identity, so their ancestry is retained without replacing newer work.

Two additional tests cover nested ordered/bullet lists at section boundaries,
checking that the outer section style is applied once. The provider runner
keeps the stronger source, runtime and dependency provenance without recording
raw host paths.

A later office-fidelity head, `097475fbda96aa4a6497d92f28d10f1aa5f640b4`, was
observed after the cutoff. It is recorded as the next incoming item and is not
included in the v3 implementation or validation claim. The live branches may
continue moving after this recorded snapshot.

## Reproducible local development pack

The builder/verifier is pinned to the qualified mixed GGUF, all twelve frozen
sidecars, the measured native library, installed ABI header, source license
notices and archived qualification/build receipts. It uses immutable paths
identified by content hashes and refuses existing or racing output destinations.
The real pack verified independently at **23 files / 86,356,331 bytes**
(**82.36 MiB**, including the 9,315-byte manifest). Its deterministic manifest
is retained as [development-pack-manifest.json](development-pack-manifest.json),
SHA-256 `70187da9248c829ab511f566ba4db9093a0ec5a9c922ad4438d63db372880841`.

[development-pack-verification.json](development-pack-verification.json)
records assembly and verification, which perform no inference. The separate
v2/v3 checker receipts record real inference using those pack paths. The pack
is for the qualified Linux x86_64 development binary; its ISA and unbundled
system-runtime license requirements remain explicit. It is not a published
release or approval of another platform/toolchain. Model binaries are not
committed into Git; the builder, exact identities and evidence are retained.

## Local regression checks

| Final suite | Passed | Retained log |
| --- | ---: | --- |
| GECToR package, including live pinned native fixture | 103, none skipped | `gector-package-tests-v3.log.gz` |
| Deterministic German grammar | 268 | `german-grammar-tests-v3.log.gz` |
| Editor proofing and manual/F7 flow | 97 | `editor-proofing-tests-v3.log.gz` |
| ODT import/export and integrated section/list behavior | 148 | `second-odt-tests.log.gz` |
| Python comparison, immutable pack and AOT tooling | 45 | `local-tooling-tests-v3.log.gz` |

[second-test-logs.json](second-test-logs.json) records raw and archived log
hashes. Only known workspace prefixes were removed from the public editor log;
the original raw hash is preserved. The worker tests cover coalescing and
cancellation behavior with a controllable backend. They do not measure the
mailbox of a genuinely blocked native FFI call; the parent-side queue bounds
are enforced by the in-flight/waiting request invariants.

The first integration also ran 119 distinct engine tests. Its initial run
passed 118 and failed one fixture lookup when invoked from the repository root.
Rerunning that eight-test file from the engine package passed all eight. Both
receipts remain retained; no product assertion or fixture was changed to fix
the invocation error. Earlier suite totals are not added to the final totals.

## Preserved evidence and remaining work

The original compiled v1 receipt and JIT memory-budget failure remain unchanged
in the [native Dart evidence](../2026-11-17-native-dart/README.md). The v2 build,
provider, comparison and logs remain here under their original names, sealed by
[validation.json](validation.json). The final v3 files and focused integration
checks are sealed by [final-validation.json](final-validation.json).

The [local reproduction guide](../../../../tools/proofing/german_model/LOCAL_PROVIDER.md)
provides build/run/compare commands; the
[pack guide](../../../../tools/proofing/german_model/NATIVE_PACK.md) documents
assembly and verification without a hosted-CI dependency.

Representative held-out German quality, incremental benefit over existing
rules, longer-paragraph segmentation, intended-device/editor responsiveness,
de-AT/de-CH policy and exact distribution/platform acceptance remain open.
The model stays an explicit manual/F7 provider. Native inference cannot be
interrupted mid-call; cancellation discards obsolete results between passes.
No default promotion, release or main-branch merge is claimed here.
