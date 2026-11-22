#!/usr/bin/env python3
"""Run the local note-formatting acceptance cohorts with retained JSON evidence.

Use the repository-pinned Flutter SDK and locked package resolution first.
Example: python3 run_checks.py --cohort engine --output /absolute/evidence/path
The script does not install dependencies or query GitHub Actions.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
from urllib.parse import unquote, urlparse


ROOT = Path(__file__).resolve().parents[3]
ENGINE = [
    'word_directional_paragraph_io_test.dart',
    'word_zotero_paragraph_format_test.dart',
    'zotero_note_color_test.dart',
    'word_zotero_blockquote_test.dart',
    'word_zotero_add_note_test.dart',
    'word_zotero_note_list_test.dart',
    'word_zotero_note_table_test.dart',
    'word_zotero_nested_table_test.dart',
    'word_zotero_note_insertion_test.dart',
    'word_zotero_note_images_integration_test.dart',
    'word_zotero_table_cell_replacement_test.dart',
    'word_zotero_research_target_test.dart',
    'word_zotero_citing_test.dart',
    'word_zotero_rich_edit_test.dart',
    'word_zotero_formatted_bibliography_test.dart',
    'zotero_formatted_text_test.dart',
    'zotero_paragraph_runs_test.dart',
    'zotero_all_caps_test.dart',
    'zotero_add_note_protocol_test.dart',
    'word_layout_test.dart',
    'style_cascade_test.dart',
    'word_package_preservation_test.dart',
    'word_paragraph_style_identity_test.dart',
    'word_paragraph_style_assignment_test.dart',
    'word_style_introduction_test.dart',
    'word_table_cell_paragraph_formatting_test.dart',
    'word_styles_layout_test.dart',
    'word_referenced_styles_and_breaks_test.dart',
    'word_table_direction_test.dart',
    'word_table_style_import_regression_test.dart',
    'word_table_style_precedence_test.dart',
    'word_paragraph_mark_layout_test.dart',
    'word_footnote_separator_docx_test.dart',
    'office_vba_word_paragraph_layout_test.dart',
    'office_vba_word_paragraph_layout_integration_test.dart',
    'word_empty_formatted_run_test.dart',
    'word_pdf_test.dart',
    'odt_paragraph_properties_test.dart',
    'odt_zotero_writer_test.dart',
    'odt_zotero_image_lifecycle_test.dart',
    'office_macro_word_font_colors_test.dart',
    'office_vba_word_font_colors_test.dart',
]
EDITOR = [
    'word_ruler_directional_indent_test.dart',
    'word_ruler_cell_margin_test.dart',
    'word_zotero_paragraph_format_controller_test.dart',
    'word_zotero_note_color_controller_test.dart',
    'word_zotero_note_color_render_test.dart',
    'word_empty_paragraph_direction_test.dart',
    'word_zotero_blockquote_controller_test.dart',
    'word_zotero_add_note_controller_test.dart',
    'word_zotero_rich_controller_test.dart',
    'word_zotero_note_image_controller_test.dart',
    'word_zotero_notes_pane_test.dart',
    'word_zotero_nested_table_controller_test.dart',
    'word_zotero_vertical_table_controller_test.dart',
    'word_zotero_format_test.dart',
    'word_plain_text_insertion_test.dart',
    'office_direction_chord_test.dart',
    'office_dark_document_test.dart',
]
STUDIO = [
    'studio_zotero_citing_transport_test.dart',
    'studio_zotero_shortcuts_test.dart',
    'studio_zotero_odt_export_test.dart',
]
INCOMING_WORD = [
    'office_vba_mid_assignment_test.dart',
    'office_vba_mid_assignment_conformance_test.dart',
    'office_vba_word_mid_assignment_integration_test.dart',
    'office_vba_word_mid_assignment_cli_test.dart',
    'office_vba_string_intrinsics_test.dart',
    'office_vba_string_intrinsics_integration_test.dart',
    'office_vba_arrays_test.dart',
    'office_vba_arrays_integration_test.dart',
    'office_vba_arrays_boundaries_test.dart',
    'office_vba_text_intrinsics_test.dart',
    'office_vba_string_constants_test.dart',
]
INCOMING_MAIL = [
    'studio_mail_journal_host_test.dart',
    'studio_mail_message_loader_test.dart',
    'studio_mail_organization_dialog_test.dart',
]
COHORTS = {
    'engine': ('packages/quds_office_engine', ENGINE, False),
    'editor': ('packages/quds_office_editor', EDITOR, True),
    'studio': ('packages/quds_office_editor/example', STUDIO, True),
    'incoming-word': ('packages/quds_office_engine', INCOMING_WORD, False),
    'incoming-mail': ('packages/quds_office_editor/example', INCOMING_MAIL, True),
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT).decode().strip()


def inputs():
    names = subprocess.check_output(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'],
        cwd=ROOT,
    ).decode().split('\0')
    selected = {}
    extensions = {'.dart', '.yaml', '.lock', '.json', '.docx', '.odt', '.png', '.ttf', '.otf'}
    for name in names:
        if not name:
            continue
        path = ROOT / name
        relevant = name.startswith(('packages/', 'apps/', 'third_party/')) and path.suffix in extensions
        if path.is_file() and (relevant or name in {'pubspec.yaml', 'pubspec.lock', '.fvmrc', 'analysis_options.yaml'}):
            selected[name] = sha256(path)
    for name in ['.dart_tool/package_config.json', '.dart_tool/package_graph.json']:
        path = ROOT / name
        if path.is_file():
            selected[name] = sha256(path)
    return dict(sorted(selected.items()))


def reporter(path):
    starts, ends, errors, done, suites = {}, {}, [], [], {}
    non_json = []
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip():
            continue
        try:
            item = json.loads(line)
        except ValueError:
            non_json.append({'line': number, 'text': line[:300]})
            continue
        kind = item.get('type')
        if kind == 'testStart':
            starts[item['test']['id']] = item['test']
        elif kind == 'testDone':
            ends[item['testID']] = item
        elif kind == 'suite':
            suites[item['suite']['id']] = item['suite']
        elif kind == 'error':
            errors.append(item)
        elif kind == 'done':
            done.append(item)
    visible = [item for item in ends.values() if not item.get('hidden', False)]
    return {
        'suites': list(suites.values()),
        'passed': sum(item.get('result') == 'success' and not item.get('skipped', False) for item in visible),
        'failed': sum(item.get('result') != 'success' for item in visible),
        'skipped': sum(item.get('skipped', False) for item in visible),
        'errors': errors,
        'unfinished': [value for key, value in starts.items() if key not in ends],
        'done': done,
        'non_json_output': non_json,
        'cases': [{**starts[item['testID']], **item} for item in visible],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cohort', choices=COHORTS, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    package, names, flutter = COHORTS[args.cohort]
    cwd = ROOT / package
    for name in names:
        if not (cwd / 'test' / name).is_file():
            raise FileNotFoundError(cwd / 'test' / name)
    if flutter:
        command = [shutil.which('flutter'), 'test', '--no-pub']
    else:
        configuration = ROOT / '.dart_tool/package_config.json'
        config = json.loads(configuration.read_text())
        test = next(item for item in config['packages'] if item['name'] == 'test')
        test_root = Path(unquote(urlparse(test['rootUri']).path))
        if not test_root.is_absolute():
            test_root = configuration.parent / test_root
        command = [shutil.which('dart'), f'--packages={configuration}', str(test_root / 'bin/test.dart')]
    if command[0] is None:
        raise RuntimeError('Activate the pinned Flutter/Dart SDK before running checks')
    command += [f'test/{name}' for name in names] + ['--concurrency=2', '--reporter=json']
    prefix = output / args.cohort
    before = inputs()
    before_path = prefix.with_suffix('.inputs-before.json')
    before_path.write_text(json.dumps(before, indent=2) + '\n')
    receipt = {
        'cohort': args.cohort,
        'source_commit': git('rev-parse', 'HEAD'),
        'source_tree': git('rev-parse', 'HEAD^{tree}'),
        'working_tree': git('status', '--porcelain'),
        'command': command,
        'cwd': str(cwd),
        'started_at_unix': time.time(),
    }
    stdout_path, stderr_path = prefix.with_suffix('.jsonl'), prefix.with_suffix('.stderr')
    with stdout_path.open('w') as stdout, stderr_path.open('w') as stderr:
        try:
            result = subprocess.run(command, cwd=cwd, stdout=stdout, stderr=stderr, timeout=600)
            receipt['exit_code'] = result.returncode
        except subprocess.TimeoutExpired:
            receipt['exit_code'] = 124
            receipt['timed_out'] = True
    after = inputs()
    prefix.with_suffix('.inputs-after.json').write_text(json.dumps(after, indent=2) + '\n')
    parsed = reporter(stdout_path)
    prefix.with_suffix('.cases.json').write_text(json.dumps(parsed.pop('cases'), indent=2) + '\n')
    changed = [name for name in sorted(before.keys() | after.keys()) if before.get(name) != after.get(name)]
    receipt.update(parsed)
    receipt.update({
        'finished_at_unix': time.time(),
        'input_count': len(before),
        'changed_inputs': changed,
        'reporter_sha256': sha256(stdout_path),
        'stderr_sha256': sha256(stderr_path),
    })
    receipt['accepted'] = (
        receipt['exit_code'] == 0 and not changed and not parsed['errors']
        and not parsed['unfinished'] and parsed['failed'] == 0
        and parsed['skipped'] == 0 and parsed['done']
        and parsed['done'][-1].get('success') is True
    )
    prefix.with_suffix('.receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({key: receipt[key] for key in ['cohort', 'source_commit', 'exit_code', 'passed', 'failed', 'skipped', 'input_count', 'changed_inputs', 'accepted']}), flush=True)
    return 0 if receipt['accepted'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
