#!/bin/sh
set -eu
export DART_DISABLE_ANALYTICS=1
export TMPDIR='/workspace/scratch/55ae4c05da4e/runtime/tmp'
export PUB_CACHE='/workspace/scratch/55ae4c05da4e/runtime/pub-cache'
export PATH='/workspace/scratch/55ae4c05da4e/runtime/dart-sdk/bin':"$PATH"
cd '/workspace/scratch/55ae4c05da4e/quds_office_suite/packages/quds_office_engine'
exec '/workspace/scratch/55ae4c05da4e/runtime/dart-sdk/bin/dart' --packages='/workspace/scratch/55ae4c05da4e/quds_office_suite/.dart_tool/package_config.json' '/workspace/scratch/55ae4c05da4e/runtime/pub-cache/hosted/pub.dev/test-1.31.1/bin/test.dart' "$@"
