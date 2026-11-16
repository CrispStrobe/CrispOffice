#!/usr/bin/env bash
set -euo pipefail
task_acceptance=/workspace/scratch/7b8555dd0115/zotero-native-acceptance
exec "$task_acceptance/binary/Zotero_linux-x86_64/zotero" -no-remote -profile "$task_acceptance/profile" -datadir "$task_acceptance/data" -debug-text > "$task_acceptance/first-insertion/zotero-native.log" 2>&1
