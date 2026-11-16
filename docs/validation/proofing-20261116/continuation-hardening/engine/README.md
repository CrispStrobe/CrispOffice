# Frozen-source engine integration verification

**Passed against `8b93e866b4661d19f4bbad4e1069c0a609441ebb`.** The local run
finished on **16 November 2026 at 16:06:33 UTC / 17:06:33 CET**. Git HEAD and
the tracked working tree remained unchanged throughout the run.

This run uses the actual resolved **108-package Flutter workspace**, with
Flutter **3.47.8** and Dart **3.13.7**. It does not use the isolated pure-Dart
dependency harness from the earlier handoff. The direct Dart executable and
resolved `package:test` runner use the repository's exact package configuration.
No package downloads, native/Wasm Harper rebuilds, or GitHub Actions queries
were performed.

## Results

| Scope | Result | Evidence |
| --- | --- | --- |
| Hyphenation, bidi, Word layout, DOCX/PDF, contextual run metrics, invisible break controls and fragment fallback; 26 test files | **295 passed**, no failures or skips | [Log](hyphenation-layout-export-tests.log), [events](hyphenation-layout-export-tests.events.jsonl) |
| Incoming ODS reader/writer, Zotero and comment/proofing style regressions; 22 test files | **503 passed**, no failures or skips | [Log](incoming-ods-zotero-tests.log), [events](incoming-ods-zotero-tests.events.jsonl) |
| Harper provider contract | **8 passed**, no failures or skips | [Log](harper-provider-tests.log), [events](harper-provider-tests.events.jsonl) |
| Harper native worker lifecycle guards | **3 passed**, **1 real-library test skipped** | [Log](harper-native-guards.log), [events](harper-native-guards.events.jsonl) |

The real-library test explicitly requires `QUDS_HARPER_TEST_LIBRARY` to point to
a built native library. It was not configured, so this run makes no fresh
real-native Harper acceptance claim. The native guards verified missing-library
and disposal behavior. No real mobile dictionaries or browser interactions
were exercised.

These groups overlap, including the Zotero bibliography layout file; do not add
their results into a unique repository-wide test total. Test counts come from
the retained machine events and exclude hidden suite-loading records.

## Source and dependency integrity

The [receipt](receipt.json) records every command, working directory, timestamp,
exit code, duration, test summary and log/event digest. Before and after hashes
match for all recorded inputs:

- **4,291 tracked repository inputs**, excluding historical and newly written
  `docs/validation/**` evidence.
- **8,097 dependency Dart/configuration/lock files** from the actual resolved
  non-workspace packages. Extensions are `.dart`, `.yaml`, `.json` and `.lock`;
  generated cache/build/version-control directories are excluded.
- **40 runtime/configuration inputs**, including the Dart executables,
  snapshots, internal SDK kernels, root lock/configuration, runtime identity,
  Python executable and this validation runner.

The compressed manifests preserve the complete path-to-SHA-256 maps:
[source before](source-before.json.gz), [source after](source-after.json.gz),
[dependencies before](dependencies-before.json.gz),
[dependencies after](dependencies-after.json.gz),
[runtime before](runtime-before.json.gz), [runtime after](runtime-after.json.gz).
The actual [resolved lock](resolved-pubspec.lock),
[package configuration](resolved-package-config.json),
[workspace pubspec](workspace-pubspec.yaml) and
[package roots](package-roots.json) are retained.

## Reproduction

Check out the exact source commit and resolve its real Flutter workspace using
the retained runtime version and dependency lock. Set the intended `PUB_CACHE`
and `TMPDIR` before invoking the runner. Use a new output directory:

```sh
python3 run-validation.py \
  --repo /path/to/quds_office_suite \
  --runtime /path/to/runtime \
  --expected-source 8b93e866b4661d19f4bbad4e1069c0a609441ebb \
  --output /path/to/new-engine-validation
```

The runtime root contains `flutter/` with its Dart SDK. The runner discovers
`package:test` from the repository package configuration and asserts that the
engine, Harper and Flutter package roots match the chosen workspace/runtime.
It runs from each package directory so relative font and fixture paths resolve
as authored. The complete reproduction script is [run-validation.py](run-validation.py).

## Preserved initial attempt

[initial-attempt-731d370/](initial-attempt-731d370/) contains the original runner,
preflight manifests, runtime version receipt and incomplete first test-group
logs from source `731d3708513d00fde9ac32dcb32bac1d39631214`. That attempt was
interrupted with exit 130 when the editor analysis gate found two test-only
lint issues: an unused ODS writer test binding and an unnecessary Flutter
services import. The final source includes those corrections.

The initial attempt completed no test group and is not counted as a passing
validation run. Its [interruption record](initial-attempt-731d370/interruption.json)
states the exact boundary. Every group reported above completed against the
final frozen source.
