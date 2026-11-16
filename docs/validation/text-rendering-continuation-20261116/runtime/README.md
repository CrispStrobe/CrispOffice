# Local Dart and Flutter runtime restoration

The final runtime is ready. `runtime.json` and the two final logs record successful
official Flutter artifact installation and the actual version report. This is
runtime setup evidence; the parent qualification harness owns application tests.

## Source and native artifacts

The Flutter framework is an unmodified checkout of the official `3.47.8` tag,
commit `737ba8f885dc774b53b442759999a312c9461e4e`. The local branch is `stable` at
that exact commit. This restores normal stable-channel behavior: Flutter's
`--version` command fetches every Git tag when invoked from a detached checkout,
but skips that fetch on a stable branch. No tracked SDK source was changed.

The complete Dart SDK and Linux engine archives came from the official Flutter
artifact URLs recorded in `archive-integrity.json`. Their complete payloads match
the MD5 checksums supplied by Google's artifact responses; SHA-256 values are
recorded for subsequent identification. Every ZIP entry passed its CRC check.
The installed Dart executable and `flutter_tester` also exactly match the
SHA-256 values in the previous qualification:

| Executable | SHA-256 |
| --- | --- |
| Dart | `01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb` |
| Flutter tester | `800f4ca182df7dd2fb46a42dea5d76277b9dbc5e8cd2915e02bcbc978681b45f` |

The actual runtime reports Flutter 3.47.8 and Dart 3.13.7. The additional universal
artifacts and their content hashes are recorded in `flutter-assets-receipt.json`.
All 162 pinned Pub archives were fetched and checked against their recorded
SHA-256 values. `pub-cache-receipt.json` records that dependency set; the official
Flutter CLI package uses 101 of the resolved dependencies. Its actual lockfile
is `sdk-tools-pubspec.lock`.

## Offline Flutter launcher

Use `flutter_cli.sh` for Flutter commands in this workspace. It runs the official
CLI, compiled to a Dart kernel file from the unchanged framework source, using
the official Dart executable. The native Dart and Flutter engine binaries were
not rebuilt. The kernel hash and build command are recorded in `runtime.json`.

The CLI's real Pub configuration was produced with `dart pub get --offline`.
The actual compilation command was:

```sh
dart compile kernel \
  --packages=toolchain/flutter-runtime/packages/flutter_tools/.dart_tool/package_config.json \
  toolchain/flutter-runtime/packages/flutter_tools/bin/flutter_tools.dart \
  --output=toolchain/flutter_tools.dill
```

This launcher avoids the SDK shell wrapper's first-time online `pub upgrade`.
It passes `--no-version-check`; application test invocations should also use
`--no-pub` after the already completed workspace resolution. It does not alter
the Flutter implementation, substitute a renderer, or fabricate a package
configuration or a version file.

The official CLI generated Flutter's version metadata and installed its cache
from verified local copies of the official archives. A temporary loopback HTTP
server supplied those exact archives through Flutter's normal storage-base
override. `finalize_flutter_cache.py` documents that installation; the server is
stopped after installation and is not required for tests.

## Workspace resolution

The real workspace resolved with:

```sh
source /workspace/scratch/796b63b8623e/toolchain/env.sh
dart pub get --offline --enforce-lockfile
```

The observed successful command exited zero and printed `Got dependencies!`.
The workspace has 108 packages. Its pinned lock remains SHA-256
`344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.
No production package manifest was edited for runtime setup. The baseline workspace was independently resolved with the same verified SDK and lock before its regression probes.

## Retained setup failures and corrections

These are setup failures, not application test results:

- The initial full 1.58 GB Flutter distribution stream was stopped when the
  connection repeatedly ended early. That incomplete distribution was not
  represented as hash-verified or used for final qualification. The smaller
  official component archives were then downloaded completely with resumable
  byte ranges.
- The temporary package-cache writer initially appended a newline to Pub's hash
  metadata. Offline resolution succeeded, but online Pub compared that metadata
  literally and attempted to redownload the packages. The metadata was corrected
  to Pub's canonical format; all 162 package archives remained hash-verified.
- A direct Dart workspace resolution before Flutter generated its version cache
  failed to recognize the Flutter SDK. The failure and unchanged-lock receipt are
  retained. The official CLI subsequently generated genuine version metadata,
  after which the same real workspace resolve with lock enforcement succeeded.
- The detached tag caused Flutter's version command to fetch tags. The local
  checkout was put on the stable branch at the verified release commit.
- Initial precache selections requested irrelevant platforms. The final
  `--informative` selection keeps normal host filtering while also including
  universal defaults. The required font-subset artifact was added to the verified
  mirror, and the final precache exited zero.

Compressed logs and receipts for those attempts are under `attempts/`. None of
this setup used or waited for GitHub Actions.
