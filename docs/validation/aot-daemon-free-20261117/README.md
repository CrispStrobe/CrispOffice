# Daemon-free AOT integration — 17 November 2026

Branch: `codex/aot-daemon-free-20261117`. Review: [PR #120](https://github.com/CrispStrobe/quds_office_suite/pull/120).

## Delivered behavior

`AotClient()` and the JSON CLI now default to the real AOT engine in a managed
local worker. SynanDaemon, Qt, an HTTP listener, and a persistent background
service are unnecessary. The explicit build script installs pinned engine/data
sources; runtime analysis performs no download or remote fallback.

The client starts the worker lazily, reuses its per-language dictionaries, and
terminates it on cancellation, disposal, active timeout, or a fatal protocol
failure. Text travels through bounded stdin JSON lines, never shell arguments.
A bounded LRU cache retains successful word morphology by exact word, language
and paradigm mode; identical in-flight requests share work. Syntax text and
failures are not cached.

This initial checkpoint preceded daemon-free implementation and local qualification.
GitHub Actions, checks and commit-status endpoints are not used as a gate.

## Captured implementation at `0b4c0107`

This section describes the subsequently saved source
`0b4c0107f6b7651bd77e95670e4f2f4f8b58e038`, captured from the same branch during
the German-proofing recovery on 17 November 2026. The original incoming
inventory and evidence files above retain their historical source and dates.
The recovery's separate reference snapshot does not redefine that earlier
269-reference inventory.

`AotClient()` now selects a managed local process transport. The host must
explicitly install a worker and its language resources; construction starts
nothing, and analysis downloads nothing. `AotClient.local(...)` accepts worker
and resource paths, while `AotClient.http(...)` explicitly selects an HTTP
service. Local requests use bounded JSON lines and a child process owned by the
transport, with cancellation, deadlines and explicit browser/mobile
unavailability. No server or automatic HTTP fallback is introduced.

A reused client coalesces identical morphology lookups and retains successful
immutable results in a bounded LRU cache, keyed by exact surface, language and
paradigm mode. Syntax requests and failures are not cached. The CLI adds bounded
stdin input, local/HTTP selection, explicit installation paths, configurable
deadlines and a `doctor` command using synthetic examples. Worker source and
pinned build tooling are committed; generated binaries and dictionaries are
separately installed. [Current setup and API](../../../packages/quds_proofing_aot/README.md)

The captured Studio example still requires `QUDS_AOT_ENDPOINT` and explicitly
constructs HTTP clients. Each Analyze/morphology action owns and disposes its
client. Local Studio configuration and dialog-wide session/cache reuse are
unfinished in this snapshot.

## Recorded local fixture evidence

The committed logs at `0b4c0107` contain these substantive completed results,
excluding hidden loader/setup/teardown events:

| Historical cohort | Passes | Failures | Skips |
| --- | ---: | ---: | ---: |
| Process/client, Dart VM | 47 | 0 | 0 |
| Portable process/client, JavaScript/Node | 23 | 0 | 0 |
| Native-metadata consumer, grammar rules and provider fixtures | 78 | 0 | 0 |

The [process/client summary](evidence/process-client-summary.json), recorded
at `2026-11-17T17:51:42.023775+00:00`, binds ten source files whose hashes match
the captured commit. Its VM/Node results overlap; they are not additive
language-quality measurements. The mapping log runs `native_source_mapping`,
`german_rules` and `provider` tests and has no equivalent separate source-binding
receipt. [VM events](evidence/process-client-vm.jsonl.gz) ·
[Node events](evidence/process-client-node.jsonl.gz) ·
[Mapping/rule/provider events](evidence/native-mapping-tests.jsonl.gz) ·
[Recorded client/process analysis](evidence/process-client-analyze.txt)

The process tests launch a Dart fixture executable. They do not establish live
AOT dictionary loading, native serialization, deployment or native performance.
Earlier ODF/tab-cache logs retain their own scope and source attribution.

## Native source mapping and qualification boundary

The Dart decoder accepts optional `sourceStart`, `sourceEnd` and `sourceText`
metadata, verifies exact original UTF-16/grapheme spans and sequential coverage,
and preserves a normalized analyzer surface separately as `analysisText`.
Grammar rules abstain on normalized tokens and affected context. Injected
fixtures exercise that consumer contract.

The captured native `worker.cpp` directly returns upstream `BuildJson`, and its
CMake target compiles the upstream serializer unchanged. At the pinned AOT
revision `0d591d972c7bb2729f4764d3bc32611ea6fd142a`,
[`JVisualSynAnParamBuilder.cpp`](https://github.com/sokirko74/aot/blob/0d591d972c7bb2729f4764d3bc32611ea6fd142a/Source/www/SynanDaemon/JVisualSynAnParamBuilder.cpp)
emits token `str` and `homonyms`, with no source-span metadata. Consequently,
live normalized-token mapping is not implemented or qualified by this
snapshot. Without metadata, rewritten surfaces such as `zu-helfen` continue
through exact sequential alignment and can produce incomplete coverage.

The new `tool/qualify_cli.py` expects the completed native mapping path. Its
presence is not a successful live run or evidence that normalized infinitives
already pass. The native build, producer mapping, upstream diagnostics and
serialization behavior, complete local CLI qualification and Studio session
reuse remain unfinished. The earlier HTTP live smoke remains evidence only for
its recorded server, source and synthetic inputs.
