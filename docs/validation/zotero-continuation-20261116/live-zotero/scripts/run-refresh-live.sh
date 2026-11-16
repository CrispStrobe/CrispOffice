#!/usr/bin/env bash
set -euo pipefail
source /workspace/scratch/7b8555dd0115/zotero-toolchain/env.sh
task_acceptance=/workspace/scratch/7b8555dd0115/zotero-native-acceptance
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" --packages=/workspace/scratch/7b8555dd0115/zotero-toolchain/harness/quds_office_studio/.dart_tool/package_config.json "$task_acceptance/refresh-live.dart" > "$task_acceptance/logs/refresh-client-run.log" 2>&1
