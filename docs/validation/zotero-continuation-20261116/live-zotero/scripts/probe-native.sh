#!/usr/bin/env bash
set -euo pipefail
task_acceptance=/workspace/scratch/7b8555dd0115/zotero-native-acceptance
curl -sS --noproxy '*' --max-time 10 \
  -D "$task_acceptance/logs/catalog-headers.txt" \
  -H 'Zotero-API-Version: 3' -H 'Zotero-Allowed-Request: 1' \
  'http://localhost:23119/api/users/0/items/top?format=json' \
  -o "$task_acceptance/logs/catalog-response.json"
printf 'Native catalog response saved.\n'
