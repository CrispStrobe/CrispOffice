# Local mail validation checkpoints — 2026-11-20

These are completed local development checks for the durable-draft increment.
GitHub Actions were not consulted or awaited. This record separates successful
checkpoints from the final host acceptance run, which is recorded separately.

## Final combined acceptance

The [source-bound final acceptance record](final-mail/README.md) qualifies
combined source `793dae7de10848b5a1ec0762e0fc4b55b70296f3`, Git tree
`59fc3e06df00a73e53c46f4f2591231c19eef06a`, with **1,245 successful test
executions represented, 0 failed and 0 skipped**. It comprises 54 core, 562 store,
3 store Node boundary, and 626 Studio cases across 59 selected and loaded suites.

The initial frozen-source checkpoint `81b0d762` passed all eight local gates:
formatting, strict core/store/changed-Studio analysis, and the four test cohorts.
After the incoming Office changes, all 29 Studio mail suites were rerun on the
combined source and passed. That follow-up captured identical before/after
hashes for 4,424 product files and seven pinned inputs; aggregate SHA-256:
`90c40feb38c37e022471f06912f517881b31a80c289047ef0cf3a70f72619fdc`.

The original 619 core/store/Node executions retain their original receipt. A
separate [reuse proof](final-mail/reused-core-store-inputs.json) establishes
unchanged relevant source/tests/manifests, seven runtime/configuration pins and
the declared resolution of 60 transitive packages. Studio's repeated 626 cases
replace its earlier contribution. The development counts below are historical
checkpoints and are not added to the final accepted set. Exact commands,
selections, raw runner events and before/after manifests are included in the
final acceptance directory.

## Completed checks

| Scope | Passed test executions | Failed | Skipped | Result |
| --- | ---: | ---: | ---: | --- |
| `quds_mail_core`, complete VM test directory | 54 | 0 | 0 | Exit 0; runner completed successfully |
| `quds_mail_mime`, complete VM test directory | 84 | 0 | 0 | Exit 0; runner completed successfully |
| `quds_mail_store`, complete VM test directory | 562 | 0 | 0 | Exit 0; includes actual SQLite crash/recovery cases |
| `quds_mail_transport`, complete VM test directory | 373 | 0 | 0 | Exit 0; runner completed successfully |
| Transport portable boundaries, Node | 13 | 0 | 0 | Exit 0; four explicit test files |
| `quds_mail_ui`, complete widget test directory | 33 | 0 | 0 | Exit 0; runner completed successfully |
| Four pure mail packages: `dart analyze --fatal-infos` | — | — | — | All four exited 0 |
| Mail UI: `flutter analyze --no-pub` | — | — | — | Exit 0, “No issues found!” |

The completed checkpoint contains **1,073 VM executions, 13 Node executions,
and 33 mail UI widget executions**. Reruns and incomplete attempts are not added
to these counts. Each counted test run emitted the real JSON runner's successful
`done` event, with no failed or skipped non-hidden test events.

### Source scope

The first checkpoint began at 07:34:58 UTC with HEAD
`2cfeca15d197110a65a1cbe7601e763ee281fc9d` (reference Git tree
`59231205a420d41aae09f8b715e11c4ebfbd1dbf`). Core draft state, store codec,
repository, composer and draft adapter changes were already being edited in the
shared checkout. The second checkpoint began at 07:36:19 UTC on the same HEAD;
HEAD advanced to `5b072494af4f142aa03654884856c5a9359dc968` (reference tree
`3a9adef8a74f93d29174499b99b8e76c01cd6c39`) during the transport run.

These commit/tree identifiers record ancestry and checkout context. They do
**not** assert a frozen byte-for-byte snapshot of concurrent edits. The checks
establish the working mail baseline; final changed-source tests and host
acceptance must accompany the final integration commit. The obsolete full
Studio run was intentionally interrupted after it exposed composer lifecycle
regressions and host fixtures needing an injected draft store. That run is not
counted as a pass. The identified failures were sent to the implementation owner.

## Commands and runner setup

The session environment was loaded from
`/workspace/scratch/70953f0172ce/toolchains/env.sh`. It selected the pinned SDK,
a workspace-owned `PUB_CACHE` and temporary directory, and suppressed analytics
for these commands without changing telemetry consent.

Workspace dependencies and Flutter tools were resolved with:

```sh
dart pub get --offline --enforce-lockfile
```

The repository `pubspec.yaml` and `pubspec.lock` hashes were unchanged by setup.
An ordinary `dart test` startup produced no test events and was interrupted.
The completed VM/Node checks used the repository's established direct entry to
the **real pinned package:test runner**, retaining the generated locked package
configuration. No implementation or test source was copied or patched for the
runner:

```sh
QUDS_CHECKOUT=/workspace/scratch/70953f0172ce/quds_office_suite
QUDS_TEST_RUNNER="$PUB_CACHE/hosted/pub.dev/test-1.31.1/bin/test.dart"

# Run separately from each packages/quds_mail_{core,mime,store,transport}.
dart --packages="$QUDS_CHECKOUT/.dart_tool/package_config.json" \
  "$QUDS_TEST_RUNNER" --reporter=json
dart analyze --fatal-infos

# Run from packages/quds_mail_transport.
dart --packages="$QUDS_CHECKOUT/.dart_tool/package_config.json" \
  "$QUDS_TEST_RUNNER" --platform node --reporter=json \
  test/ews_unsupported_test.dart test/ews_configuration_test.dart \
  test/unsupported_test.dart test/cloud_unsupported_test.dart

# Run from packages/quds_mail_ui.
flutter test --no-pub --reporter=json
flutter analyze --no-pub
```

An initial store attempt lacked native SQLite asset registration and was not
counted. The unmodified sqlite3 package's default build hook was then invoked
from `packages/quds_mail_store` using a package-local temporary Dart probe. The
probe opened a real in-memory database, created an FTS5 table, inserted `ready`,
and confirmed that a matching FTS5 query returned exactly one row. Store tests
were restarted after this succeeded. The first UI analyzer attempt found that
the selectively extracted SDK lacked `dev` and `examples`; their exact official
sources were restored from the archive's bundled Git HEAD. The analyzer rerun
then passed. These setup failures remain distinct from passing application runs.

## Targeted autosave follow-up

After review found that a persistent save failure could trap the user in the
composer, the host gained an explicit confirmed **Close without saving** path.
The new regression verifies that a failed ordinary close retains the editor,
Cancel leaves the confirmation without losing work, and a confirmed unsaved
exit returns no send result and cancels a late pending autosave. Previously
saved content is not cleared by this action.

From `packages/quds_office_editor/example`:

```sh
dart format test/studio_mail_draft_autosave_test.dart
flutter test --no-pub --reporter=json test/studio_mail_draft_autosave_test.dart
dart analyze --fatal-infos test/studio_mail_draft_autosave_test.dart
```

The formatter changed no files. The targeted file completed with **10 passed,
0 failed, 0 skipped**, exit 0, and a successful runner `done` event. This
follow-up is separate from the broad checkpoint counts above and is not added
again if the final host selection reruns this file. Its JSON stdout SHA-256 is
`2112f8d136f8bf3cbe5a43cf9874bc69df4895e846d7375a7dcf35a1d6ad7193`.
Strict analysis of the test file also exited 0 with no issues.

## Pinned runtime and dependency provenance

| Item | Verified value |
| --- | --- |
| Flutter | `3.47.8`, framework `737ba8f885dc774b53b442759999a312c9461e4e` |
| Engine | `cf636b1dfb818dd6a3ff16e390e93b1a036969c8` |
| Dart | `3.13.7`, bundled with that Flutter release |
| Official archive | [Flutter Linux 3.47.8 stable](https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.8-stable.tar.xz), 1,581,444,364 bytes |
| Archive SHA-256 | `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2` |
| Dart executable SHA-256 | `01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb` |
| Flutter tester SHA-256 | `800f4ca182df7dd2fb46a42dea5d76277b9dbc5e8cd2915e02bcbc978681b45f` |
| Hosted dependency archives | 195 archives from `pub.dev`, each SHA-256 verified against the workspace or Flutter tools lock |
| Resolved workspace | 157 entries in generated `package_config.json` |
| Workspace lock SHA-256 | `df9ff88b4df699b2420954d0ddc0dd7a1c40dbca8d9e3af3f25bec7e66700e7e` |
| Native sqlite3 | Package `3.9.1`; SQLite `3.54.1`; FTS5 enabled |
| Native library SHA-256 | `0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b` |

No live mailbox credentials or real message submission were used. Protocol
checks used the repository's synthetic provider and loopback fixtures. This is
not a live-provider, installed desktop application, macOS, or Windows test claim.
