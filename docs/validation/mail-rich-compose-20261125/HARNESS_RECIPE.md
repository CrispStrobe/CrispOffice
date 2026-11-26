# Reproducing the pure-Dart qualification

Use Linux x64, the full official Dart **3.13.7** SDK (the Dart version associated
with this repository's Flutter **3.47.8** pin), Python with PyYAML, and a clean
checkout of source commit `46645673bc944d1bb518703108234ba6836afc91`
(or a descendant with identical qualified source fingerprints). The recipe does not edit that checkout.
It links genuine runtime source into a separate minimal workspace and copies only
selected tests. No Flutter implementation or runtime dependency is stubbed.

```bash
python create_validation_harness.py \
  --repo /absolute/path/to/quds_office_suite \
  --output /absolute/path/to/mail-validation
cd /absolute/path/to/mail-validation

mail_validation_root="$PWD"
export PUB_CACHE="$mail_validation_root/pub-cache"
export TMPDIR="$PWD/tmp"
export XDG_CONFIG_HOME="$PWD/config"
export DART_SUPPRESS_ANALYTICS=true
mkdir -p "$PUB_CACHE" "$TMPDIR" "$XDG_CONFIG_HOME"

dart --version
dart pub get
```

The harness starts with the repository lockfile. Verify that dependency versions
have not changed before qualifying results:

```bash
python - /absolute/path/to/quds_office_suite/pubspec.lock <<'PY'
import sys, yaml
original = yaml.safe_load(open(sys.argv[1]))['packages']
resolved = yaml.safe_load(open('pubspec.lock'))['packages']
assert all(name in original and value['version'] == original[name]['version']
           for name, value in resolved.items() if value['source'] == 'hosted')
print('All resolved dependency versions match the repository lockfile.')
PY
```

Build and identify the real SQLite native asset with its package's build hook.
The qualified binary reports SQLite **3.54.1**, SHA-256
`0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b`.

```bash
dart run sqlite_smoke.dart
sha256sum .dart_tool/lib/libsqlite3.so
export LD_PRELOAD="$PWD/.dart_tool/lib/libsqlite3.so${LD_PRELOAD:+:$LD_PRELOAD}"

cd "$mail_validation_root/packages/quds_office_engine"
dart --packages="$mail_validation_root/.dart_tool/package_config.json" \
  "$PUB_CACHE/hosted/pub.dev/test-1.31.1/bin/test.dart" \
  --compiler=source --concurrency=1 --reporter=expanded \
  "$mail_validation_root/test"

cd "$mail_validation_root"
dart analyze --fatal-infos analysis
```

The twelve selected test files cover the rich model, Word conversion, bounded
preview projection, MIME/submission, real SQLite draft/Outbox recovery, existing
submission and Outbox privacy behavior, and incoming main-branch paragraph marks,
XML parsing, core Outbox state, store codec, and cache invalidation. The original
Liberation Sans fixture is copied byte-for-byte. Running from the harness engine
package directory preserves its test's original relative font path.

The supported source compiler avoids accumulating large test kernel files.
Preloading the exact package-generated binary enables native FFI symbol lookup
in source isolates without substituting the SQLite backend. Test adaptations are
limited to `flutter_test` → `package:test`, the real `package:test/fake.dart`
export, and equivalent synchronous `expect` assertions. Original and copied
SHA-256 values are recorded in `test-transforms.json`.

The analysis overlay copies production bytes exactly, including the complete
relative import closure. This avoids analyzer context switching through source
symlinks into the original Flutter workspace. The selected test logic is analyzed
with the same documented test API adaptation. The current generator also includes
the exact XML reader source and its unchanged test file, qualifying the final
main-branch namespace-scope update.

This establishes pure-Dart model, conversion, MIME, Outbox and real SQLite
behavior. It does not execute Flutter widget tests, path_provider, installed-app
packaging, browser runtime, or live provider delivery. Separate source-only
Flutter analysis is a different check and must be recorded separately.

During this session the disk limit required omitting nonruntime SDK/devtools and
dependency fixture/docs files from a task-owned cache. Analyzer and Drift runtime
source was extracted from official archives only after verifying their lockfile
SHA-256. Those space-saving steps are unnecessary with adequate disk capacity.
