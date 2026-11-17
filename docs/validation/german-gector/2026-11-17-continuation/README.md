# German grammar continuation — 17 November 2026

## Remote synchronization

The continuation started from provider checkpoint `216d9a4`. The captured
inventory covers 381 branches in the four cooperating repositories. Quds had
new main, morphology, Office fidelity, annotation and continuation work; the
other three grammar branches and their relevant base histories were current.
No GitHub Actions run was dispatched, polled or awaited.

Integration commit `aa6c50ed3736cea2c871f4bed7ae18a60e0cbb8b` retains every
captured Quds branch tip as an ancestor, including the two byte-verified section
histories equivalent to main. All source changes are preserved through merge
parents; no incoming feature branch was reset or rewritten. `integration.json`
records exact inputs, the final tree, conflict decisions and checks.
`incoming-refs.json.gz` contains the complete captured branch/PR inventory.

The ODT writer conflicts were resolved around the newer bounded comment and
note implementation, keeping main's section layout styles. Independent source
comparison checked GECToR preservation, ODP transforms/tables, annotation
exclusion, complete note regression coverage and section support.

Six focused engine test files covered 119 distinct tests. The first invocation
passed 118 and failed one fixture lookup because it was run from the repository
root. Running that eight-test file from the engine package passed all eight.
Both logs are retained; no product test assertion or fixture was changed to
resolve the invocation error.

## Recovered compiled baseline

The previous completed AOT receipt is preserved unchanged in the
[provider evidence](../2026-11-17-native-dart/README.md). Its source/runtime
identities and all case outputs were independently rechecked before new guard
work. Keep this v1 baseline and its JIT comparison immutable.

## Complete compiled run through the verified pack

`provider-aot-v2-build.json` binds one real AOT compilation to 62 selected runner
sources, explicit package configuration, 109 resolved package records / 4,755
Dart library files, and the actual compiler/runtime SDK inputs. Before/after
source, dependency and SDK seals all match. The produced snapshot has SHA-256
`d65a179fe4e5635c133b2862d72582b9444e262563b4f55a73baf805ce842c40`.
The build's runtime/entrypoint pins and selected-source map agree exactly with
`provider-aot-v2.json` and the actual snapshot bytes.

The complete checker ran from the assembled development pack. All 30 corpus
cases have their expected statuses (28 successful de-DE checks and two
unsupported de-CH controls); all eight integration controls and three longer
structural probes pass. The independently validated comparison in
`guarded-comparison-v2.json` authenticates the unchanged v1 AOT baseline and
corpus. Its sole output change is:

- `Wir ist zufrieden.` -> `Wir sind zufrieden.`

The guarded result therefore moves from **5/18 to 6/18 expected corrections**.
All five previous fixes and all ten unchanged supported clean controls are
preserved. No other case status, corrected text, finding or span changes.
The fix recognizes same-number person aliases from the authenticated verb table;
it does not relax singular/plural, coordination or sentence-boundary guards.
The three other previously held baseline fixes remain held.

| Complete-check measurement | AOT v1 | AOT v2 through pack |
| --- | ---: | ---: |
| Warm median, up to 64 WordPieces | 21.910 ms | 23.863 ms |
| Warm p95, up to 64 WordPieces | 62.017 ms | 98.249 ms |
| Peak whole-process RSS | 295.50 MiB | 280.91 MiB |
| Startup with verification and dictionary | 3384.501 ms | 3130.889 ms |
| 61-token structural control p95 | 165.940 ms | 151.724 ms |
| 126-token structural control p95 | 481.249 ms | 355.255 ms |
| 256-token structural control p95 | 636.641 ms | 717.319 ms |

The current short-input latency and memory observations pass the unchanged
500 ms / 768 MiB engineering budgets. All samples are retained; separate local
runs cannot attribute timing differences solely to the guard change. The
256-token probe exceeds 500 ms, and inputs beyond 512 tokens still fail
explicitly rather than being silently truncated. These repeated-sentence
probes do not establish representative long-document language quality.

## Reproducible local development pack

The pack builder/verifier is pinned to the qualified mixed GGUF, all twelve
frozen sidecars, the measured native library, installed ABI header, source
license notices and archived qualification/build receipts. It uses immutable
content-addressed paths and refuses existing or racing output destinations.
The real pack verified independently at **23 files / 86,356,331 bytes**
(**82.36 MiB**, including the 9,315-byte manifest). Its deterministic manifest
is retained as `development-pack-manifest.json`, SHA-256
`70187da9248c829ab511f566ba4db9093a0ec5a9c922ad4438d63db372880841`.

`development-pack-verification.json` records the assembly/verification step,
which itself performs no inference. The separate complete-check receipt above
records the subsequent real inference run using those pack paths. The pack is
for this qualified Linux x86_64 development binary; its ISA and unbundled system
runtime license requirements remain explicit. This is not a published release
or approval of another platform/toolchain.

## Local regression checks and remaining work

- 98 GECToR package tests pass, including the live pinned native adapter; none
  were skipped in this run.
- 45 new Python tooling checks pass: 27 guarded comparison, 11 immutable pack,
  and seven AOT build/provenance controls.
- The 119 distinct engine integration checks are recorded above. The focused
  guard tests and analysis also pass; those tests are included in the package
  total rather than added again.

`validation.json` seals the build, provider, comparison, pack and compressed
logs together. The [local reproduction guide](../../../../tools/proofing/german_model/LOCAL_PROVIDER.md)
provides build/run/compare commands without a hosted-CI dependency.

Representative held-out German quality, incremental benefit over existing
rules, longer-paragraph segmentation, intended-device/editor responsiveness,
de-AT/de-CH policy and exact distribution/platform acceptance remain open.
The model stays an explicit manual/F7 provider. Native inference cannot be
interrupted mid-call; existing cancellation discards obsolete results between
passes. No default promotion, release or main-branch merge is claimed here.
