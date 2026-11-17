# Retaining Quds integration work around the historical AOT backend

17 November 2026. The user clarified the separation: keep our integration work;
exclude the incompletely documented/licensed AOT/RML implementation and data.
The native spaCy implementation belongs to a separate agent session. This note
does not implement its model contract, shared types or runtime.

## What remains reusable

Our adapter, lifecycle, source-safety and editor work does not have to be thrown
away because its original backend was AOT. Keep its history and reuse the
backend-independent behavior with the new backend's actual capabilities.
Existing integration already retained on main includes:

- `OfficeProofingRequest`, finding validation and deterministic-first report
  merging in `packages/quds_office_engine/lib/src/proofing/office_proofing.dart`.
- `WordProofingSession` manual-only provider configuration, immutable paragraph
  snapshots, revision checks, protected ranges, ignore/restore and source-safe
  correction in `packages/quds_office_editor/lib/src/proofing/word_proofing.dart`.
- The existing controller, review dialogs and command-based correction/undo
  path; these are independent of any analyzer implementation.
- The optional GECToR package's worker-isolate, request identity, bounded queue,
  stale-result, native ownership and shutdown patterns. Its particular model,
  runtime and numerical graph are separate from these reusable patterns.

Additional first-party integration source and tests remain recoverable at the
immutable historical Quds commit
[`e37ccdb47c047f6a0250585cf5cb20efc17573b4`](https://github.com/CrispStrobe/quds_office_suite/tree/e37ccdb47c047f6a0250585cf5cb20efc17573b4),
branch `codex/aot-daemon-free-20261117`:

| Historical source | Reusable work | Boundary when carrying it forward |
| --- | --- | --- |
| `packages/quds_office_editor/example/lib/studio_aot.dart` | Explicit selected-text/body capture; lazy dialog sessions; stale/cancel/close handling; navigation and readable results | Separate backend configuration and AOT-specific views. Preserve story/block identities and exact original offsets; the old flattened display snapshot is not a ready-to-edit spaCy source map. |
| `packages/quds_office_editor/example/test/studio_aot_test.dart` | Selection, Unicode, revision, cancellation and late-result regression scenarios | Adapt the tests to neutral or real replacement-backend fixtures; a synthetic backend proves UI/protocol behavior only. |
| `packages/quds_proofing_aot/lib/src/client.dart` | Request lifecycle, bounded caches and disposal behavior authored for the Quds adapter | Do not bring along HTTP/process transports or an automatic backend fallback. |
| `packages/quds_proofing_aot/lib/src/provider.dart` | Mapping explicit provider statuses and guarded proposals into manual review | Use the new analyzer's real capabilities and current deterministic baseline. Do not imply full AOT paradigms or parse alternatives. |
| `packages/quds_proofing_aot/test/` | Quds-authored protocol, mapping, cache and lifecycle scenarios | Keep upstream morphology fixtures and engine-derived outputs separate from independently authored fixtures; do not silently import dictionaries through tests. |

This is a reuse map, not blanket approval to merge the historical package. The
AOT-shaped DTOs, grammar-label decoding and paradigm-dependent rules need
backend-specific replacement. Preserve their original source history while
adapting only the independent integration behavior that is still useful.

## What stays excluded from the app

Do not restore AOT/RML/nlp_base libraries, dictionaries, syntax resources,
transitive code with unresolved grants, installed resource trees, native build
outputs or their dependency registration. Do not restore the old process/pipe
or HTTP analyzer transports. A historical C++ wrapper/build recipe may itself
be our source, but compiling it against excluded upstream inputs does not make
those inputs acceptable.

The existing historical receipts document experiments; they are not a shipped
analyzer or redistribution clearance. User acceptance of LGPL in principle
supersedes the former blanket restriction, but does not resolve the specific
missing AOT/RML provenance. There is no new categorical LGPL ban.

## Separate native implementation ownership

The [native spaCy handoff](native-spacy/README.md) remains authoritative for
that work: C++/ggml, the exact German model, a separately optional Dart package,
and a frozen reference/model contract before graph implementation. Its owner
controls the new ABI and analysis DTOs. Reuse our surrounding work without
preemptively creating conflicting APIs here. Qualified linguistic analysis is
useful independently; model grammar must show incremental benefit against the
current rules, with source-safe review/undo and explicit false-positive results.
