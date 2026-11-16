# Native Zotero session scaling benchmark

This local engine microbenchmark compares the native Zotero document adapter
before and after the lookup and note-position changes. It contains no GitHub
Actions dependency and makes no request to Zotero or a remote library.

## Comparison boundary and source identity

The comparison deliberately substitutes **one source file**:

`packages/quds_office_engine/lib/src/word/model/word_zotero_citing.dart`

| Input | Source |
| --- | --- |
| Baseline target file | `428679a33381f943a8ae63117d4207f01dd15462` |
| Common engine tree and optimized target file | `91c725feb5517db3c5f686e80662e2cb4f77f0d4` |
| Baseline target SHA-256 | `a18893904d03f1e8a5b02f65653e6a981a87cb18451a6195da00ee82ad73d416` |
| Optimized target SHA-256 | `ea9288994003cb32bccfbfc7ab6a4ced541858c849324a8d8816ca5151113492` |
| Fixture SHA-256 | `fe835a1f0c7255e4aef8f628f32bd4d73be33ea3b4a727252337bbd10d9f4e53` |
| Engine harness lock SHA-256 | `3b55c7eb8535653c0733db7abc99934bf3f23fdf3835eb5fb673c1044a848379` |

The original baseline was a copy of the current engine library with the older
target file substituted. The retained baseline tree was subsequently compared
with the optimized checkpoint: **all 264 other engine library files match**.
This isolates the native-session implementation; it does not compare two full
historical repository checkouts. The `baseline_commit` label in the original
`summary.json` refers only to that substituted target file.

The later delivery checkpoint `0dd09811b1c02514c32c33bd13744dadb202e7af`
reformats two expressions in `assertUnchanged` (line wrapping and trailing
commas). Its target-file SHA-256 is
`fd89825b3628fbaf897404b1e4f0405367a0f90fee312915bcc9509c1e8f42ef`.
These saved timings retain their original measured source identity at
`91c725f`; they have not been reattributed to the later formatting checkpoint.

`engine-lib-sha256.json` records every engine library file in both inputs.
`legacy-parser-lib-sha256.json` records the local path dependency. Exact source,
fixture, dependency-input and result hashes are in `source-provenance.json`.
`inputs/package-config.json` retains the original resolved graph and its
historical scratch paths as provenance. The reproduction runner resolves the
supplied harness on the current machine instead of reusing those paths.

## Method

The run used **Dart 3.13.7 stable on Linux x64**, in separate JIT processes for
the baseline and optimized input. Each process first warms up three times with
80 groups. Measured sizes contain 100, 400 and 800 groups, with five repetitions
per size. Each group contains one inline citation, one footnote citation and
one endnote citation. Note storage order and numeric IDs are intentionally
different from reading order.

The fixture records session construction, one `Document.getFields` call, a
full `assertUnchanged` check and five passes selecting every field by ID.
Fixture construction is outside the timed sections. Raw results retain all
five measurements in microseconds; the tables below report medians.

The SHA-256 of the complete JSON field response is calculated for every
repetition. The baseline and optimized output hashes agree at every size:

| Fields | Notes | Identical protocol snapshot SHA-256 |
| ---: | ---: | --- |
| 300 | 200 | `c310f30f13ae76e397a6f8215e796795f91123548376f45640c9fcb6db933caa` |
| 1,200 | 800 | `d7bd142ba44545d449e7dc9c46db726351bcb0097bb106387bba8e7d12453120` |
| 2,400 | 1,600 | `28e7e2b7282d69cadd9465ef14f6a42dce7d01bd8f63484f638e80a3c0d527d1` |

## Results

Every metric is shown, including setup and full validation, which did not show
the same speedups as field enumeration and ID lookup.

| Fields / notes | Operation | Baseline median | Optimized median | Baseline ÷ optimized |
| --- | --- | ---: | ---: | ---: |
| 300 / 200 | Construct session | 22.064 ms | 22.802 ms | 0.97× |
| 300 / 200 | Enumerate fields | 2.726 ms | 0.436 ms | 6.25× |
| 300 / 200 | Validate original document | 7.057 ms | 7.629 ms | 0.93× |
| 300 / 200 | Select every field, five passes | 2.359 ms | 0.168 ms | 14.04× |
| 1,200 / 800 | Construct session | 89.082 ms | 85.573 ms | 1.04× |
| 1,200 / 800 | Enumerate fields | 53.254 ms | 1.273 ms | 41.83× |
| 1,200 / 800 | Validate original document | 41.605 ms | 31.097 ms | 1.34× |
| 1,200 / 800 | Select every field, five passes | 37.443 ms | 0.667 ms | 56.14× |
| 2,400 / 1,600 | Construct session | 165.762 ms | 179.471 ms | 0.92× |
| 2,400 / 1,600 | Enumerate fields | 228.704 ms | 1.773 ms | 128.99× |
| 2,400 / 1,600 | Validate original document | 83.643 ms | 79.806 ms | 1.05× |
| 2,400 / 1,600 | Select every field, five passes | 115.496 ms | 1.639 ms | 70.47× |

Computing note positions once per field response and using indexed field IDs
improves the measured operations substantially for larger documents. Full
validation still parses the document, and construction includes parsing and
copying citation results. Those costs remain visible in the results.

This is a synthetic, engine-only, local JIT microbenchmark. It does **not**
measure HTTP round trips, the Zotero processor, its native picker, Flutter
rendering, save/export time or an end-to-end compiled application. JIT warmup,
garbage collection, process order and concurrent machine activity can affect
the timings. These ratios are not universal application speedups. No timing
threshold is used as a regression gate; semantic regression coverage is in
`packages/quds_office_engine/test/word_zotero_scaling_test.dart` and the existing
native citing suites.

## Reproduce with an existing engine validation harness

Use a checkout containing both recorded commit objects and the resolved engine
harness used by the local qualification. The runner requires the exact copied
`inputs/pubspec.yaml` and `inputs/pubspec.lock` bytes and verifies the local
legacy parser source manifest. Resolve that harness with the recorded SDK and
`dart pub get --enforce-lockfile` before running. The dependency cache must be
available; the runner itself never resolves or downloads dependencies.

```bash
python3 docs/validation/zotero-optimization-20261116/benchmark/run-benchmark.py \
  --repo /absolute/path/to/quds_office_suite \
  --engine-harness /absolute/path/to/harness/quds_office_engine \
  --dart /absolute/path/to/flutter/bin/cache/dart-sdk/bin/dart \
  --output /absolute/path/to/new-scratch-benchmark-output
```

The output directory must be new. The runner extracts the common engine tree
from the recorded optimized commit into scratch, copies it and replaces only
the baseline target file. It compares both source manifests with this record,
then writes separate package configurations pointing at the isolated sources.
It does not change the checkout, tracked dependency inputs, or the supplied
harness configuration. Baseline and optimized processes run sequentially.

`--prepare-only` verifies inputs and materializes the isolated sources and
configs without executing the timing fixture. This mode was used to sanity
check the reproduction runner after preserving the original measurements; no
additional performance run was needed.

For a new standalone engine harness, copy `inputs/pubspec.yaml` and
`inputs/pubspec.lock` into its `quds_office_engine` directory. Add a sibling
`legacy_doc_parser` package with the recorded parser source and its original
package manifest, omitting only the copied manifest's
`resolution: workspace` declaration. Link the harness engine's `lib` to the
engine source and the copied parser's `lib` to the matching parser source.
This is the same standalone-package adaptation used by local qualification;
leave the repository manifests unchanged. Then resolve with
`dart pub get --enforce-lockfile`. Keep the two sibling package names because
the locked path dependency is `../legacy_doc_parser`.

The fresh output contains raw timings, normalized package configurations,
source provenance and a recomputed `summary.json`. The runner rejects a
protocol snapshot mismatch and reports every timing metric, including slower
or unchanged measurements.

## Recorded files

- `native-benchmark.dart`: the exact fixture used for the saved measurements.
- `baseline.json`, `optimized.json`: original raw timing and wire-hash output.
- `summary.json`: original median calculations and scope statement.
- `source-provenance.json`: source and artifact integrity receipt.
- `engine-lib-sha256.json`, `legacy-parser-lib-sha256.json`: source manifests.
- `inputs/`: exact standalone engine package inputs and resolved graph.
- `run-benchmark.py`: portable source-isolation, execution and comparison runner.
- `reproduction-check.json`: successful source/config preparation and saved-result verification without another timing run.
