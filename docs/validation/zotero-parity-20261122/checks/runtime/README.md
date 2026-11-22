# Local runtime setup

- Official Flutter **3.47.8** / bundled Dart **3.13.7**, Linux x64.
- SDK release metadata: <https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json>.
- Archive: <https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.8-stable.tar.xz>.
- Archive SHA-256 matched official release metadata: `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
- Framework revision: `737ba8f885dc774b53b442759999a312c9461e4e`.
- Workspace dependency resolution used **`dart pub get --enforce-lockfile`** with `FLUTTER_ROOT` set to that official SDK. All 22 captured repository manifests and the root lock remained unchanged. The resolved workspace has 166 packages.
- Flutter tooling dependencies were then resolved with the same command inside the SDK's `packages/flutter_tools`, without changing repository dependencies.
- No GitHub Actions, checks or status queue were queried or awaited.

## Environment and commands

The installed SDK is outside the repository under `toolchains/flutter`; caches and temporary files are also task-local. The default `/tmp` directory is absent in this executor, so `TMPDIR` must point to an existing writable directory. For a different checkout, substitute its absolute task paths below.

```bash
export TMPDIR=/workspace/scratch/0bc03d5773e3/toolchains/tmp
export PUB_CACHE=/workspace/scratch/0bc03d5773e3/toolchains/pub-cache
export FLUTTER_ROOT=/workspace/scratch/0bc03d5773e3/toolchains/flutter
export DART_SUPPRESS_ANALYTICS=true
export FLUTTER_SUPPRESS_ANALYTICS=true

# Root workspace, preserving exact locked dependencies:
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" pub get --enforce-lockfile

# SDK tooling setup (needed on this fresh extraction):
cd "$FLUTTER_ROOT/packages/flutter_tools"
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" pub get --enforce-lockfile

# From the engine package; Dart test has no --no-pub option:
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" test --reporter json test/word_zotero_writing_position_test.dart

# From the editor package:
"$FLUTTER_ROOT/bin/flutter" --no-version-check --suppress-analytics test --no-pub --reporter json test/word_zotero_writing_position_test.dart
```

## Setup attempts and limits

Initial Flutter entrypoint dependency attempts were interrupted before emitting dependency/test output. They are not test results. The first direct Dart Pub attempt resolved dependencies but failed extracting archives because `/tmp` did not exist; its failure is retained in `pub-get-direct.log`. The successful retry used the task-local `TMPDIR`, with genuine package downloads and enforced lockfile resolution. The accepted workspace and SDK tooling logs are retained separately. No dependency version constraints, packages, test imports or implementation were substituted.

This setup supports Dart/Flutter source and widget testing. It does not establish installed Zotero/Word/LibreOffice interoperability or a native release build. Test outcomes belong to their own source-bound receipts.
