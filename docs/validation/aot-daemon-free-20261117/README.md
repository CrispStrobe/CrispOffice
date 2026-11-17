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

Studio always exposes Review → AOT analysis. Opening it does not start an
engine. One private analyzer serves subsequent syntax and morphology requests,
and is reset on cancellation, close, stale text, language change, or failure.
Standalone Word forms supports German, Russian and English. Local processing
and explicit HTTP service mode have distinct labels. Explicit local settings
also enable manual F7/document grammar checks; ordinary typing proofing remains
independent. The CLI adds bounded stdin/file input, worker/resource selection,
timeout configuration, structured errors and a synthetic `doctor` command.

Native syntax preserves exact original UTF-16 source spans separately from the
analyzer's normalized surface. The worker retains original graphan tokens,
verifies source spans, and Dart independently verifies substrings, coverage,
ordering and grapheme boundaries. Both previously failing infinitive examples
now have complete exact coverage. Normalized token contexts remain excluded
from grammar corrections; unrelated exact clauses can still be checked.

The three conservative grammar families remain personal-pronoun/verb agreement,
selected fixed-preposition case, and article/adjective/noun agreement, for de-DE.
German/Russian syntax and German/Russian/English morphology do not imply grammar
checking for every language or German regional locale.

## Real native build and upstream repairs

The headless build uses AOT `0d591d972c7bb2729f4764d3bc32611ea6fd142a` and
nlp_base `244b3d1f9a09e4a81e75ea83c3b55b209c663503`. It builds real dictionaries,
assembles an approximately 106 MB runtime, verifies that installed layout, and
only then replaces an existing installation. Resources are discovered beside
the worker; custom paths remain supported. No generated engine binaries or
language dictionaries are committed to Quds.

Three exact, validated patches are applied to generated source copies:

1. Remove the unconditional `input.lem` document dump in `SimpleGrammarLib/Parser.cpp`.
2. Copy temporary phrase descriptions into RapidJSON-owned storage, fixing
   corrupted descriptions observed in actual multi-clause output.
3. Remove `_DEBUG` `before.lem`/`after.lem` document dumps in `SynanLib/SyntaxHolder.cpp`.

The pinned upstream checkout remains unchanged. Manifest entries record all
three generated-source hashes. A negative-control `_DEBUG` compilation proves
that the original object contains both diagnostic filenames and the write
call, while the patched object contains neither. The third patch leaves the
qualified Release executable byte-for-byte unchanged.

Qualified worker SHA-256:
`d20a7a707736c05fb0e2143aa517769f0136a459cfef9c113af5ecfd375a0d0f`.
See `evidence/native-runtime-manifest.json`, `native-build-toolchain.json`,
`native-build.log.gz`, `native-smoke.json`, and `native-debug-dump-proof.json`.

## Incoming source reconciliation

The initial checkpoint includes all **269** captured fork branch, fork PR,
upstream branch and upstream PR references by ancestry. It incorporates AOT
#117, Office #113/#116, German #114, GECToR continuation, and latest-at-start main
`388bd745`, with original feature/vendor ancestry behind squash merges #115/#118.
`incoming.json` records every fixed SHA and the published integration tree.

The final refresh freezes **277** references in `incoming-final.json`. Later
arrivals include main `edd023c3`, ODT multi-column export #119, ODP chart data as
tables #121, additional Office tab/row/cell fidelity fixes, bounded German scans,
and GECToR request-local prediction reuse and irregular-participle precedence.
All 277 exact captured references are preserved by ancestry in published checkpoint
`940148b0`; no reference is missing. The final follow-up column repair preserves
that ancestry. `evidence/published-ancestry.json` records the verification.

Initial conflict decisions retain consolidated ODF frame/namespace/hidden-story
extraction, separate structured table ownership, the compatibility paragraph
entry point, hyperlink assertions once, the empty-document invariant, and both
AOT and incoming proofing documentation. Repeated squash feature bodies are
retained once while all original commits remain ancestors. Final decisions are
recorded in `final-integration.md`.

During initial integration, output-based tests exposed an inherited tab-style
cache collision. Five new tests failed on the original writer and passed after
including tab positions/alignment/leaders in the style identity. Late-arriving
parallel tab fixes are reconciled with that invariant and their broader fidelity
coverage, not used to discard it.

## Local validation

No GitHub Actions, workflow/check runs, or commit-status endpoints were queried
or awaited. Checkpoints use `[skip ci]`. Flutter 3.47.8 / Dart 3.13.7 and existing
offline dependencies were used locally.

| Cohort | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| Full AOT package — Dart VM | 153 | 0 | 0 |
| Portable AOT package — JavaScript/Node | 129 | 0 | 0 |
| Studio configuration/lifecycle/Word forms | 25 | 0 | 0 |
| Word proofing widgets/controllers | 139 | 0 | 0 |
| Initial affected ODF/search tests | 424 | 0 | 0 |
| Final affected ODF/search tests after source refresh and column repair | 502 | 0 | 0 |
| Final engine proofing | 699 | 0 | 0 |
| Final GECToR package | 212 | 0 | 1 |
| Python admission/comparison guards | 36 | 0 | 0 |

Native process tests require the VM and are intentionally absent from the Node
cohort. Node repeats portable contracts; it is not 129 additional unique cases.
The focused process/client cohort (47 VM / 23 Node) and initial source-mapping
cohort are subsets/repeats of the full package suites and are not added again.
Post-refresh tests repeat affected coverage on the reconciled source.

Real-engine checks use only synthetic text:

| Native pathway | Checks | Scope |
| --- | ---: | --- |
| Worker protocol directly | 22 | Languages, forms, exact source spans, description ownership, bounds, errors, missing data and no working-directory writes |
| Production Dart client/provider | 17 | Three expected corrections, seven clean/guard controls, four syntax examples, three language morphology checks and cache identity |
| Compiled production CLI | 23 | Doctor, all grammar examples, clean/infinitive controls, morphology languages, source metadata, input/backend errors and no working-directory writes |

These pathways overlap linguistically and are not a count of independent
accuracy examples. Expected suggestions include `Ich geht → Ich gehe`,
`mit den Hund → mit dem Hund`, and `Der kleines Hund → Der kleine Hund`.
Infinitive controls now return complete successful analyses rather than an
alignment failure. Raw JSON, hashes, commands and reproducible runners are kept
under `evidence/`.

Changed AOT, Studio, ODF writers/tests, engine proofing and GECToR sources report
no static-analysis issues. The full Word cohort was repeated after incoming
integration and again passed 139 tests. The final native-offset fixture was
repeated on VM (15 passing cases) after its JavaScript numeric-representation
correction. AOT source/tests and the shared proofing contract remain unchanged
by the late integration.

A final source review also repaired the incoming ODT column style: `style:columns`
now nests within `style:section-properties` and owns the column-count/gap
attributes, as required by ODF 1.3 sections 17.11–17.12. A parsed, namespace-aware
regression failed before the fix. The adjacent ODP chart table placement was
checked against the specification and required no change.

The single optional skip is the separately configured real GECToR dual-head
model probe: its pinned fixture environment variables were absent. It does not
qualify native GECToR model inference and does not concern the real AOT checks.
The initial GECToR invocation from the repository root hit package-relative
fixture paths; the full package-directory rerun passed without code changes.
Those initial harness errors are retained separately and not counted as final
passes or as implementation failures.

## Development observations retained separately

- Flutter's initial offline bootstrap was blocked by automatic approval review
  because its bot detector attempted a cloud metadata probe. Inspection located
  the code path; supported `BOT=true`/`CI=true` settings prevent that probe.
  Offline resolution then completed. No blocked metadata access was retried.
- The environment initially lacked `/tmp`; tests use an explicit writable scratch
  `TMPDIR`. The setup failure is retained separately from code results.
- Five tab-cache tests intentionally failed before the fix, providing a negative
  control. Those failures are not part of the final passing cohort.
- A first Studio test used `pumpAndSettle` against a blinking caret; a bounded
  animation pump fixes the harness and all 25 widget tests pass.
- One native-offset fixture initially used `0.0` as an invalid integer. JavaScript
  represents it identically to `0`; the fixture now uses `0.5` to verify actual
  fractional-offset rejection. The initial Node log and final passing log are
  both retained. No production implementation changed for that test correction.

## Scope and use

The native Release binary and headless setup are qualified on Linux x86-64.
macOS and Windows paths/build support are supplied in source but are not
qualified by this Linux run. Browsers and mobile hosts explicitly report native
worker unavailability. HTTP is available only through explicit configuration.
The engine/data remain a build/install dependency, with their upstream notices
and licensing obligations; daemon-free does not mean the native runtime is
included in the pure Dart package.

Read [package setup and API](../../../packages/quds_proofing_aot/README.md) and
[native build/protocol](../../../packages/quds_proofing_aot/native/README.md).
The synthetic panels do not establish broad grammar accuracy, arbitrary-document
coverage, or performance on every target device.

## Incremental remote preservation

| Checkpoint | Purpose |
| --- | --- |
| `48634dce` | Initial integration of all 269 captured references |
| `42083c99` | Managed process transport, native build scaffold and ODT tab-cache repair |
| `0b4c0107` | Local client default, bounded cache, exact source spans and doctor CLI |
| `9297f077` | Qualified real native runtime, reusable Studio workflow and local evidence |
| `940148b0` | Final 277-reference integration, debug dump removal and retained incoming features |
| Current final branch head | Column XML repair, final revalidation and complete source/evidence index |

GitHub plugin-created commit trees were checked against the local Git tree SHA.
All ref updates use an expected-head lease and preserve original branch history.
The final local branch is synchronized to the published checkpoint.
