import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
from datetime import datetime, timezone

ROOT = Path('/workspace/scratch/209f165653d7')
REPO = ROOT / 'quds_office_suite'
OUTPUT = ROOT / 'validation/quds-word-followup'
WRAPPER = ROOT / 'toolchain/run'
DART = ROOT / 'toolchain/flutter/bin/cache/dart-sdk/bin/dart'

ENGINE = [
    'bookmark_fidelity_test.dart',
    'word_block_bookmark_import_test.dart',
    'word_import_tolerance_test.dart',
    'word_bookmark_fidelity_test.dart',
    'word_bookmark_copy_test.dart',
    'word_note_bookmark_edit_test.dart',
    'content_control_fidelity_test.dart',
    'word_content_control_fidelity_test.dart',
    'word_auxiliary_content_control_test.dart',
]
EDITOR = [
    'sheet_style_history_test.dart',
    'sheet_grid_history_test.dart',
    'sheet_view_history_test.dart',
    'sheet_fill_intent_history_test.dart',
    'sheet_font_color_intent_test.dart',
    'sheet_explicit_style_history_test.dart',
    'sheet_cell_state_history_test.dart',
    'pending_edit_save_test.dart',
    'sheet_sort_history_test.dart',
    'slide_notes_history_test.dart',
]
ANALYSIS = [
    'packages/quds_office_engine/lib/src/word/model/wml_document.dart',
    'packages/quds_office_engine/lib/src/word/model/word_bookmarks.dart',
    'packages/quds_office_engine/lib/src/word/model/word_content_controls.dart',
    'packages/quds_office_engine/lib/src/word/serial/word_deserializer.dart',
    *['packages/quds_office_engine/test/' + name for name in ENGINE],
    'packages/quds_office_editor/lib/src/embed/office_controller.dart',
    'packages/quds_office_editor/test/sheet_sort_history_test.dart',
]

name = sys.argv[1]
if name == 'engine-word':
    cwd = REPO / 'packages/quds_office_engine'
    args = [str(DART), 'test', '--concurrency=1', '--reporter=json', *['test/' + p for p in ENGINE]]
elif name == 'editor-history':
    cwd = REPO / 'packages/quds_office_editor'
    args = ['flutter', 'test', '--no-pub', '--concurrency=1', '--reporter=json', *['test/' + p for p in EDITOR]]
elif name == 'strict-analysis':
    cwd = REPO
    args = ['dart', 'analyze', '--fatal-infos', *ANALYSIS]
else:
    raise SystemExit('Unknown gate')

command = [str(WRAPPER), *args]
log = OUTPUT / (name + ('.log' if name == 'strict-analysis' else '.jsonl'))
start = datetime.now(timezone.utc).isoformat()
clock = time.monotonic()
with log.open('wb') as stream:
    result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
elapsed = time.monotonic() - clock
receipt = {
    'gate': name,
    'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip(),
    'source_tree': subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=REPO, text=True).strip(),
    'command': command,
    'working_directory': str(cwd.relative_to(REPO)),
    'started_at': start,
    'completed_at': datetime.now(timezone.utc).isoformat(),
    'wall_seconds': elapsed,
    'exit_code': result.returncode,
    'log': log.name,
    'log_sha256': hashlib.sha256(log.read_bytes()).hexdigest(),
    'log_bytes': log.stat().st_size,
    'input_manifest': 'inputs-before.json.gz',
}
if name != 'strict-analysis':
    suites, tests, outcomes = {}, {}, {}
    errors, done = [], None
    for line in log.read_text(errors='replace').splitlines():
        try:
            event = json.loads(line)
        except (ValueError, TypeError):
            continue
        if not isinstance(event, dict):
            continue
        if event.get('type') == 'suite':
            suites[event['suite']['id']] = event['suite']
        elif event.get('type') == 'testStart':
            tests[event['test']['id']] = event['test']
        elif event.get('type') == 'testDone':
            outcomes[event['testID']] = event
        elif event.get('type') == 'error':
            errors.append(event)
        elif event.get('type') == 'done':
            done = event
    counts = {'passed': 0, 'failed': 0, 'skipped': 0}
    by_suite = {}
    for test_id, event in outcomes.items():
        if event.get('hidden') or tests.get(test_id, {}).get('name', '').startswith('loading '):
            continue
        key = 'skipped' if event.get('skipped') else 'passed' if event.get('result') == 'success' else 'failed'
        counts[key] += 1
        suite = Path(suites.get(tests.get(test_id, {}).get('suiteID'), {}).get('path', 'unknown')).name
        by_suite.setdefault(suite, {'passed': 0, 'failed': 0, 'skipped': 0})[key] += 1
    receipt.update(counts)
    receipt.update({'tests_by_suite': by_suite, 'errors': errors, 'done_event': done})
(OUTPUT / (name + '-receipt.json')).write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt, indent=2))
raise SystemExit(result.returncode)
