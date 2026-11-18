#!/bin/bash
set -eu
source /workspace/scratch/5e1b9c2fa60d/native-consumers/native-qualification-runtime/native-env.sh
export FLUTTER_ROOT=/workspace/scratch/5e1b9c2fa60d/toolchains/flutter
export PUB_CACHE=/workspace/scratch/5e1b9c2fa60d/toolchains/pub-cache
export TMPDIR=/workspace/scratch/5e1b9c2fa60d/flutter-qualification/workspace/tmp
export XDG_CONFIG_HOME=/workspace/scratch/5e1b9c2fa60d/flutter-qualification/workspace/config
export CI=true DART_SUPPRESS_ANALYTICS=true FLUTTER_SUPPRESS_ANALYTICS=true DASH__SUPPRESS_ANALYTICS=true PYTHONDONTWRITEBYTECODE=1
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export PATH=/workspace/scratch/5e1b9c2fa60d/toolchains/flutter/bin/cache/dart-sdk/bin:$PATH
exec "$QUALIFICATION_PYTHON" -u /workspace/scratch/5e1b9c2fa60d/quds_office_suite/docs/validation/office-reconciled-20261117/qualification/run_qualification.py \
  --repo /workspace/scratch/5e1b9c2fa60d/quds_office_suite \
  --source-commit "${1:?frozen source commit required}" \
  --flutter-root "$FLUTTER_ROOT" \
  --workspace /workspace/scratch/5e1b9c2fa60d/flutter-qualification/workspace \
  --output "${2:?new output directory required}"
