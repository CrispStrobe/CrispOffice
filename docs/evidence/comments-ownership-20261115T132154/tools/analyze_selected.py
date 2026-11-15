#!/usr/bin/env python3
import json
import subprocess
import sys
paths = [
    'lib/src/sheet/serial/sheet_serial.dart',
    'test/sheet_comments_namespace_test.dart',
    'tool/fidelity/comment_schema_fixture.dart',
]
results = []
for path in paths:
    command = ['dart', 'analyze', '--fatal-infos', '--fatal-warnings', path]
    print(json.dumps({'analyzing': path, 'command': command}), flush=True)
    result = subprocess.run(command, check=False)
    results.append({'path': path, 'returncode': result.returncode})
print(json.dumps({'files': results, 'success': all(r['returncode'] == 0 for r in results)}), flush=True)
sys.exit(0 if all(r['returncode'] == 0 for r in results) else 1)
