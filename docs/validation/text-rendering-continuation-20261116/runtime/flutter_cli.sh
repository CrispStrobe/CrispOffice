#!/usr/bin/env bash
set -euo pipefail
export FLUTTER_ROOT=/workspace/scratch/796b63b8623e/toolchain/flutter-runtime
export PUB_CACHE=/workspace/scratch/796b63b8623e/toolchain/pub-cache
export TMPDIR=/workspace/scratch/796b63b8623e/toolchain/tmp
export DART_SUPPRESS_ANALYTICS=true
export FLUTTER_SUPPRESS_ANALYTICS=true
export CI=true
exec "$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" --disable-dart-dev /workspace/scratch/796b63b8623e/toolchain/flutter_tools.dill --no-version-check "$@"
