#!/usr/bin/env python3
"""Run the local Zotero converter acceptance cohorts with retained JSON evidence.

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
COHORTS = {'engine': ('packages/quds_office_engine',
            ['odf_zotero_ownership_test.dart',
             'odf_zotero_preferences_test.dart',
             'odf_zotero_reference_marks_test.dart',
             'odf_zotero_resource_test.dart',
             'odt_document_reader_test.dart',
             'odt_image_style_review_test.dart',
             'odt_libreoffice_bibliography_test.dart',
             'odt_libreoffice_fixture_test.dart',
             'odt_libreoffice_note_offsets_test.dart',
             'odt_merged_table_zotero_test.dart',
             'odt_outline_compatibility_test.dart',
             'odt_reader_guards_test.dart',
             'odt_reader_images_test.dart',
             'odt_reader_libreoffice_defaults_test.dart',
             'odt_reader_script_styles_test.dart',
             'odt_reader_styles_test.dart',
             'odt_reader_table_preservation_test.dart',
             'odt_zotero_export_lifecycle_test.dart',
             'odt_zotero_image_lifecycle_test.dart',
             'odt_zotero_note_numbering_test.dart',
             'odt_zotero_position_guard_test.dart',
             'odt_zotero_table_geometry_test.dart',
             'odt_zotero_writer_test.dart',
             'word_empty_formatted_run_test.dart',
             'word_extended_revision_test.dart',
             'word_table_grid_addressing_test.dart',
             'word_field_span_test.dart',
             'word_package_preservation_test.dart',
             'word_zotero_add_note_test.dart',
             'word_zotero_adjacent_citations_test.dart',
             'word_zotero_bibliography_layout_test.dart',
             'word_zotero_bibliography_style_fidelity_test.dart',
             'word_zotero_blockquote_test.dart',
             'word_zotero_boundary_formatting_test.dart',
             'word_zotero_caret_test.dart',
             'word_zotero_citing_test.dart',
             'word_zotero_document_data_test.dart',
             'word_zotero_field_recovery_test.dart',
             'word_zotero_field_selection_test.dart',
             'word_zotero_formatted_bibliography_test.dart',
             'word_zotero_multiparagraph_test.dart',
             'word_zotero_nested_note_tables_test.dart',
             'word_zotero_nested_table_test.dart',
             'word_zotero_nested_tables_integration_test.dart',
             'word_zotero_note_image_test.dart',
             'word_zotero_note_images_integration_test.dart',
             'word_zotero_note_insertion_test.dart',
             'word_zotero_note_list_test.dart',
             'word_zotero_note_table_test.dart',
             'word_zotero_note_tables_integration_test.dart',
             'word_zotero_paragraph_format_test.dart',
             'word_zotero_preference_flow_test.dart',
             'word_zotero_research_target_test.dart',
             'word_zotero_rich_edit_test.dart',
             'word_zotero_scaling_test.dart',
             'word_zotero_simple_field_test.dart',
             'word_zotero_source_identity_test.dart',
             'word_zotero_style_preferences_review_test.dart',
             'word_zotero_table_cell_replacement_test.dart',
             'word_zotero_test.dart',
             'word_zotero_transfer_session_test.dart',
             'word_zotero_transfer_test.dart',
             'word_zotero_writing_position_test.dart'],
            False),
 'editor': ('packages/quds_office_editor',
            ['word_odt_image_load_test.dart',
             'word_odt_load_test.dart',
             'word_odt_merged_table_load_test.dart',
             'word_odt_note_numbering_test.dart',
             'word_zotero_add_note_controller_test.dart',
             'word_zotero_adjacent_citations_controller_test.dart',
             'word_zotero_bibliography_controller_test.dart',
             'word_zotero_blockquote_controller_test.dart',
             'word_zotero_citing_controller_test.dart',
             'word_zotero_controller_test.dart',
             'word_zotero_converter_controller_test.dart',
             'word_zotero_document_actions_test.dart',
             'word_zotero_field_at_caret_test.dart',
             'word_zotero_field_context_controller_test.dart',
             'word_zotero_field_context_dialog_test.dart',
             'word_zotero_field_context_render_test.dart',
             'word_zotero_multiparagraph_controller_test.dart',
             'word_zotero_nested_table_controller_test.dart',
             'word_zotero_note_color_controller_test.dart',
             'word_zotero_note_image_controller_test.dart',
             'word_zotero_paragraph_format_controller_test.dart',
             'word_zotero_recovery_controller_test.dart',
             'word_zotero_recovery_dialog_test.dart',
             'word_zotero_rich_controller_test.dart',
             'word_zotero_transfer_controller_test.dart',
             'word_zotero_unlink_all_test.dart',
             'word_zotero_unlink_recovery_test.dart',
             'word_zotero_vertical_table_controller_test.dart',
             'word_zotero_writing_position_test.dart'],
            True),
 'studio': ('packages/quds_office_editor/example',
            ['studio_zotero_citing_transport_test.dart',
             'studio_zotero_shortcuts_test.dart',
             'studio_zotero_odt_export_test.dart', 'studio_odt_open_test.dart'],
            True),
 'incoming-word': ('packages/quds_office_engine',
                   ['office_vba_conformance_test.dart',
                    'office_vba_string_intrinsics_test.dart',
                    'office_vba_variant_substrings_test.dart',
                    'office_vba_word_cell_paragraphs_test.dart',
                    'office_vba_word_headers_footers_test.dart',
                    'office_vba_word_named_measurements_integration_test.dart',
                    'office_vba_word_named_measurements_test.dart',
                    'office_vba_word_named_selectors_test.dart',
                    'office_vba_word_page_setup_test.dart',
                    'office_vba_word_text_selectors_cli_test.dart',
                    'office_vba_word_text_selectors_conformance_test.dart',
                    'office_vba_word_text_selectors_directional_test.dart',
                    'office_vba_word_text_selectors_integration_test.dart'],
                   False),
 'incoming-mail': ('packages/quds_office_editor/example',
                   ['studio_mail_account_navigation_dialog_test.dart',
                    'studio_mail_account_navigation_native_test.dart',
                    'studio_mail_account_navigation_provider_test.dart',
                    'studio_mail_account_navigation_router_test.dart',
                    'studio_mail_account_navigation_test.dart'],
                   True)}


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
            result = subprocess.run(command, cwd=cwd, stdout=stdout, stderr=stderr, timeout=900)
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
        and not parsed['unfinished'] and not parsed['non_json_output'] and parsed['passed'] > 0 and parsed['failed'] == 0
        and parsed['skipped'] == 0 and parsed['done']
        and len(parsed['done']) == 1 and parsed['done'][-1].get('success') is True and stderr_path.stat().st_size == 0
    )
    prefix.with_suffix('.receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({key: receipt[key] for key in ['cohort', 'source_commit', 'exit_code', 'passed', 'failed', 'skipped', 'input_count', 'changed_inputs', 'accepted']}), flush=True)
    return 0 if receipt['accepted'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
