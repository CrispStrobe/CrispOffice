# Completed rendering continuation

## Final result

Local qualification is complete: **626 tests passed**, with no failures, errors
or skips. Strict analysis and formatting passed for all three cohorts.

| Cohort | Tests | Files | Unchanged recorded inputs |
| --- | ---: | ---: | ---: |
| Engine | 407 | 27 | 411 |
| Actual Flutter editor | 196 | 17 | 482 |
| Harper adapter/source contracts | 23 | 3 | 392 |

The [final report](README.md), [source qualification](source-qualification.json)
and `qualified-engine/`, `qualified-editor/`, `qualified-harper/` receipts retain
commands, exact input hashes, captured runners, compressed logs and artifacts.
The independent verifier recomputes test summaries, verifies log integrity and
binds every tracked input to the checked commit. Runtime-only lock/configuration
inputs are identified separately.

## Saved source and incoming work

The combined production/test source is
`c6aab884eb478672d36da5c03cd20873d7e8c42c`. Later checkpoints are evidence only.
All **185 pinned refs / 126 distinct commit SHAs** at
**2026-11-16 20:10:54.959 UTC** are included by ancestry. Five real Git merges
completed cleanly: pinned main `63194d8e` and the English, German, Zotero-recovery
and en-de/Harper tips. Later arrivals remain outside the frozen cutoff.

The integration adds ODS page setup/header-footer work, English automatic
hyphenation, German advisory proofing refinements and Harper source projection.
Nine incoming Dart files received formatter-only normalization, with the exact
diff retained. See `integration-185/` for snapshots, reviews, duplicate-patch
proof and local/remote ancestry receipts.

Work was saved incrementally: recovered evidence `6a07cb8`, earlier engine
`f23675a`, earlier editor/runtime `bc195165`, combined source `c6aab884`, final
Harper evidence `8825ef58`, and final engine evidence `a725f9cf`. The final report
and editor evidence are preserved by this documentation checkpoint. All new
checkpoints use `[skip ci]`. GitHub Actions were not queried, polled, awaited
or rerun.

## Rendering evidence and scope

Distinct Unicode scalars now receive independent PDF CIDs, explicit glyph
mapping and correct ToUnicode ownership. TrueType subsets retain valid glyph
alignment, complete records, bounded composite dependencies and font metadata.
Existing contextual measurement, embedded-font identity and supplementary
Unicode fixes remain included.

Three real Flutter font-rendering tests passed. PDF-reopened and identical
Unicode subset controls have zero differing pixels and exact scalar extraction.
The independent Poppler comparison also has zero differing pixels; final engine
PDF fixture bytes match its already rendered inputs exactly. These synthetic
Latin-outline aliases do not demonstrate real emoji/CJK coverage. The separate
cross-cmap Latin reference differs by 559 pixels and is not claimed equivalent.

The negative baseline remains separately attributed: 20 probes at `0d19b16`
produced 10 assertion failures, nine errors and one success, demonstrating the
old defects. Earlier overlapping passing counts are not added to the final 626.
Historical evidence recovered through `5ed98a` remains under `editor/` and
`runtime/`; its 66 tests retain their original source attribution.

## Licenses and remaining architecture

The scoped reviews preserve the MIT FontTools notice and identify new GB English
patterns as MIT and US patterns as LicenseRef-Kuiken-permissive. Full source and
generated notices remain present; the restricted OUP word list is not shipped.
The reviewed deltas add no GPL/LGPL dependency, native shaping backend or font
binary. Existing font notices and dependency manifests are unchanged.

Harper's fresh tests use injected transport, so they do not constitute fresh
native/Wasm acceptance. Shared editor/headless positioned-glyph shaping remains
future work. Complete Unicode/platform conformance, original-font raster parity
and performance gains are outside these scoped results.
