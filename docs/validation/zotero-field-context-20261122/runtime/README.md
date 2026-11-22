# Local runtime setup

The task uses the repository-pinned **Flutter 3.47.8**, bundled **Dart 3.13.7**,
and framework revision `737ba8f885dc774b53b442759999a312c9461e4e` on Linux x64.
The SDK was downloaded freshly from the official Flutter archive. Its
1,581,444,364 bytes match the SHA-256 in freshly retrieved official release
metadata: `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
See [flutter-provenance.json](flutter-provenance.json).

- Release metadata: <https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json>
- Archive: <https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.8-stable.tar.xz>

## Environment

The SDK and caches are outside the Git checkout. The executor has no `/tmp`, so
all commands use an existing task-local temporary directory.

```bash
export TMPDIR=/workspace/scratch/2437eaf6f35d/toolchains/tmp
export PUB_CACHE=/workspace/scratch/2437eaf6f35d/toolchains/pub-cache
export FLUTTER_ROOT=/workspace/scratch/2437eaf6f35d/toolchains/flutter
export DART_SUPPRESS_ANALYTICS=true
export FLUTTER_SUPPRESS_ANALYTICS=true
export CI=true
export PATH="$FLUTTER_ROOT/bin:$FLUTTER_ROOT/bin/cache/dart-sdk/bin:$PATH"
```

These exports are also available at
`/workspace/scratch/2437eaf6f35d/toolchains/env.sh`. Dependency resolution is
performed directly through Dart to avoid implicit Flutter startup resolution:

```bash
# From the repository root:
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" pub get --enforce-lockfile

# From "$FLUTTER_ROOT/packages/flutter_tools":
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" pub get --enforce-lockfile

# Check the installed framework/engine/Dart versions:
"$FLUTTER_ROOT/bin/flutter" --no-version-check --suppress-analytics --version --machine
```

[setup-commands.json](setup-commands.json) records exact commands, directories,
start/end times, exit codes and log hashes. The corresponding logs are retained
alongside it. [workspace-resolution.json](workspace-resolution.json) records
resolved package count and dependency integrity. The manifest hash files cover
all repository `pubspec.yaml` files, `pubspec.lock` and `.fvmrc`, including
retained evidence manifests; they are compared before and after setup.

The native Flutter test runner's required shared libraries resolve on this
host. No application tests are claimed by runtime installation. No dependency
constraints, lock entries or product source were changed for setup. No GitHub
Actions or queue wait is part of this local workflow. This runtime supports
source and widget checks; installed Zotero, Word and LibreOffice acceptance is
separate.

## Setup outcome

Both locked dependency resolutions completed successfully. The workspace
resolves 166 packages; all 28 captured manifests/lock/FVM files are unchanged.
The actual Flutter version output is in
[flutter-version-ci.log](flutter-version-ci.log).

The first Flutter version startup was blocked by automatic approval review
because Flutter's environment detection attempted a cloud-instance metadata
request. Read-only inspection of the official, unmodified
`packages/flutter_tools/lib/src/base/bot_detector.dart` showed that its standard
`CI` marker short-circuits that detector before the metadata request. Running
with `CI=true` therefore removes the request entirely. That safer version check
completed successfully; the environment above keeps this setting for subsequent
Flutter commands. The blocked attempt is retained separately and is not counted
as successful setup or as a test. No metadata request was retried, and no SDK or
security policy was modified.
