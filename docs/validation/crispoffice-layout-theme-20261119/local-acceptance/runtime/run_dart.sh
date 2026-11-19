#!/bin/sh
set -eu
. /workspace/scratch/9c3338a48b2c/toolchain/env.sh
exec /workspace/scratch/9c3338a48b2c/toolchain/bin/dart "$@"
