#!/usr/bin/env bash
set -euo pipefail
source /workspace/scratch/7b8555dd0115/zotero-toolchain/env.sh
task_acceptance=/workspace/scratch/7b8555dd0115/zotero-native-acceptance/first-insertion
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" "$task_acceptance/first-insertion.dill" > "$task_acceptance/client-run.log" 2>&1
