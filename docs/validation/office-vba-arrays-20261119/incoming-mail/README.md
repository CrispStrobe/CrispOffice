# Incoming mail archive restore — independent qualification

19 November 2026. Tested the mail core/store content incorporated from
`37ac6ea8a08225a42098c455deb5375837912eec`, the initial PR #209 head.
All 87 recorded repository mail files also match the later incoming head
`358544a48466c942873a4718a87fa9d1c2be11f7`; its publication does not change
the qualified mail content. GitHub Actions were neither queried nor awaited.

## Results

| Local check | Result |
| --- | --- |
| Full `quds_mail_store/test` selection on Dart VM | **508 distinct tests passed**, zero failures or skips in the executed cases |
| `dart analyze --fatal-infos` in `quds_mail_core` | Passed |
| `dart analyze --fatal-infos` in `quds_mail_store` | Passed |
| Recorded source/shared input stability | **All 168 inputs unchanged** before and after the run |
| Mail files bound to the incoming commit | **All 87 recorded repository mail files match** the incoming Git blobs |
| Native SQLite setup | Default `sqlite3` 3.9.1 hook; empty user defines; mapped library matches the downloaded library |

The executed cases include 15 native restore tests, 15 adversarial restore
tests, nine multi-origin tests, and existing archive, export, search, storage,
migration and crash-recovery regressions. The native restore coverage includes
actual child-process termination and reopening after a committed message.
Counts are extracted from visible `testDone` JSON reporter events; hidden
loading tests are excluded. Platform-specific browser-only tests are outside
this VM selection.

The reduced Dart workspace uses the original live-linked mail sources, test
and tool directories, copied package manifests, the inherited repository
analysis options, and resolved dependencies. Dart 3.13.7 was used. The repository
and reduced workspace manifests, locks, package configuration and graph,
dependency manifests, and Dart executable/version are included in the input
hashes. Native hook configuration and the resolved library hashes were captured
separately after the run in [native-runtime.json](native-runtime.json).

## Review scope

Read the restorer, preview/report models, multi-origin transaction path, and the
new native/adversarial tests. No additional concrete regression was found in
this review. The implementation verifies source length and SHA-256 before
parsing, checks the codec's retained original, rechecks the manifest before
mutation, and commits the original, index and complete provenance together per
message. Duplicate, quota, cancellation and observer paths retain accurate
confirmed-work accounting and use the existing transaction boundary.

The tests cover changed manifests and originals, injected codecs that replace
verified bytes, corrupt existing originals or metadata, duplicate provenance,
quota rollback, source links, concurrent restorers, cancellation and reruns.
The implementation's documented filesystem race boundary remains: portable
path checks do not provide an atomic filesystem snapshot against a hostile
concurrent process. This qualification exercised Linux native storage; Studio
UI qualification is recorded separately by the integration owner.

## Evidence

- [receipt.json](receipt.json): exact commands, controlled environment, exit
  statuses, timings, output hashes, test counts and stability result.
- [test-summary.json](test-summary.json) and
  [suite-counts.json](suite-counts.json): distinct successful test events and
  counts per executed suite.
- [store-tests.stdout.log](store-tests.stdout.log): original JSON test reporter,
  including process-termination output; stderr is retained separately.
- [inputs-before.json](inputs-before.json),
  [inputs-after.json](inputs-after.json), and
  [input-stability.json](input-stability.json): all recorded input hashes.
- [source-binding.json](source-binding.json): exact mail content comparison
  against the incoming commit, reusable when later publications retain it.
- [qualify.py](qualify.py): reproducible qualification runner for this workspace
  layout. It writes only these evidence files and does not edit source files,
  manifests, Git refs or CI state.
