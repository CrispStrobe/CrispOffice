#!/usr/bin/env python3
"""Re-run the fixed bounded Office cohort with before/after source evidence."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

FILES = """
bookmark_fidelity_test.dart
odf_annotation_extraction_test.dart
odf_covered_cell_extraction_test.dart
odf_export_text_fidelity_test.dart
odf_frame_extraction_test.dart
odf_revision_extraction_test.dart
odf_text_box_extraction_test.dart
odp_presentation_writer_test.dart
ods_text_story_import_test.dart
odt_bookmark_end_fidelity_test.dart
odt_bookmark_name_ambiguity_test.dart
odt_bookmark_range_fidelity_test.dart
odt_column_break_style_fidelity_test.dart
odt_columns_breaks_fidelity_test.dart
odt_columns_schema_fidelity_test.dart
odt_comment_fidelity_test.dart
odt_complex_field_fidelity_test.dart
odt_document_writer_test.dart
odt_header_footer_fidelity_test.dart
odt_header_variant_comment_fidelity_test.dart
odt_header_variant_order_test.dart
odt_inline_column_break_fidelity_test.dart
odt_inline_field_fidelity_test.dart
odt_list_fidelity_test.dart
odt_note_fidelity_test.dart
odt_page_field_fidelity_test.dart
odt_page_marker_column_break_test.dart
odt_paragraph_break_style_test.dart
odt_paragraph_decoration_fidelity_test.dart
odt_paragraph_decoration_resume_test.dart
odt_paragraph_decoration_test.dart
odt_paragraph_properties_test.dart
odt_section_columns_test.dart
odt_section_continuation_test.dart
odt_section_fidelity_test.dart
odt_section_integration_test.dart
odt_story_visual_fidelity_test.dart
odt_structure_fidelity_test.dart
odt_tab_stop_fidelity_test.dart
odt_tab_style_cache_test.dart
odt_tab_style_fidelity_test.dart
odt_table_merge_test.dart
odt_table_tab_consolidation_test.dart
odt_table_tab_fidelity_test.dart
odt_table_tab_gector_fidelity_test.dart
odt_table_tab_qualification_test.dart
odt_table_tab_resume_test.dart
word_block_bookmark_import_test.dart
word_bookmark_copy_test.dart
word_bookmark_fidelity_test.dart
word_note_bookmark_edit_test.dart
""".split()

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--engine', type=Path, required=True)
parser.add_argument('--source-repo', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--dart', default=shutil.which('dart'))
parser.add_argument('--expected-count', type=int, default=703)
args = parser.parse_args()
engine = args.engine.resolve()
repo = args.source_repo.resolve()
output = args.output.resolve()
if not args.dart:
    raise SystemExit('Missing Dart executable')
if output.exists():
    raise SystemExit('Output must be fresh; do not overwrite prior evidence')
if len(FILES) != 51 or len(set(FILES)) != 51:
    raise SystemExit('Cohort inventory is not exactly 51 distinct files')
for name in FILES:
    if not (engine / 'test' / name).is_file():
        raise SystemExit('Missing cohort file: ' + name)
output.mkdir(parents=True)

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write(name, value):
    (output / name).write_text(json.dumps(value, indent=2) + '\n')

def seals():
    files = list((engine / 'lib').rglob('*.dart'))
    files += [engine / 'test' / name for name in FILES]
    legacy = engine.parent / 'legacy_doc_parser'
    files += list((legacy / 'lib').rglob('*.dart'))
    for path in [engine / 'pubspec.yaml', legacy / 'pubspec.yaml',
                 engine.parent.parent / 'pubspec.yaml',
                 engine.parent.parent / 'pubspec.lock',
                 engine.parent.parent / '.dart_tool/package_config.json',
                 Path(__file__).resolve()]:
        if path.is_file():
            files.append(path)
    return {str(path): sha(path) for path in sorted(set(files))}

# If a lean shadow workspace is used, bind the tested engine/lib + selected
# tests + parser/lib back to the reviewed source checkout before execution.
bindings = []
for package in ['quds_office_engine', 'legacy_doc_parser']:
    actual = engine if package == 'quds_office_engine' else engine.parent / package
    for path in (actual / 'lib').rglob('*.dart'):
        relative = path.relative_to(actual)
        source = repo / 'packages' / package / relative
        if not source.is_file() or sha(path) != sha(source):
            raise SystemExit('Runtime source differs from checkout: ' + str(path))
        bindings.append({'runtime': str(path), 'source': str(source), 'sha256': sha(path)})
for name in FILES:
    actual = engine / 'test' / name
    source = repo / 'packages/quds_office_engine/test' / name
    if not source.is_file() or sha(actual) != sha(source):
        raise SystemExit('Runtime test differs from checkout: ' + name)
    bindings.append({'runtime': str(actual), 'source': str(source), 'sha256': sha(actual)})
write('source-bindings.json', bindings)
before = seals()
started = now()
head = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=repo, capture_output=True, text=True)
version = subprocess.run([args.dart, '--version'], capture_output=True, text=True)
command = [args.dart, 'test', *['test/' + name for name in FILES], '--reporter=json']
identity = {'started_at_utc': started, 'head': head.stdout.strip(),
            'command': command, 'cwd': str(engine), 'cohort_files': FILES,
            'expected_visible_cases': args.expected_count, 'dart': str(Path(args.dart).resolve()),
            'dart_sha256': sha(Path(args.dart).resolve()),
            'dart_version_stdout': version.stdout, 'dart_version_stderr': version.stderr,
            'files': before, 'reconstruction': 'New post-reset run; does not recreate lost raw streams.'}
write('inputs.json', identity)
with (output / 'events.jsonl').open('w') as stdout, (output / 'stderr.log').open('w') as stderr:
    completed = subprocess.run(command, cwd=engine, stdout=stdout, stderr=stderr)
after = seals()
write('inputs-after.json', after)
events, non_json = [], []
for line in (output / 'events.jsonl').read_text().splitlines():
    try:
        events.append(json.loads(line))
    except json.JSONDecodeError:
        non_json.append(line)
starts = {r['test']['id']: r['test'] for r in events if r.get('type') == 'testStart'}
done = [r for r in events if r.get('type') == 'testDone' and not r.get('hidden', False)
        and r['testID'] in starts and not starts[r['testID']]['name'].startswith('loading ')]
failures = [{'test': starts[r['testID']], 'completion': r}
            for r in done if r['result'] != 'success' or r.get('skipped', False)]
summary = {'started_at_utc': started, 'completed_at_utc': now(), 'exit_code': completed.returncode,
           'files': len(FILES), 'visible_cases': len(done),
           'passed': sum(r['result'] == 'success' and not r.get('skipped', False) for r in done),
           'skipped': sum(bool(r.get('skipped', False)) for r in done),
           'failures': failures, 'source_inputs_unchanged': before == after,
           'expected_visible_cases': args.expected_count, 'non_json_stdout': non_json,
           'done_events': [r for r in events if r.get('type') == 'done']}
write('summary.json', summary)
print(json.dumps(summary, indent=2), flush=True)
sys.exit(0 if completed.returncode == 0 and before == after and not failures
         and len(done) == args.expected_count else 1)
