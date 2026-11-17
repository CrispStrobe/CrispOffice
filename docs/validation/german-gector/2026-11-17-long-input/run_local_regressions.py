import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

WORK = Path('/home/agent/.codex/skills/remote-skills/.quds-gector-work')
REPO = WORK / 'worktrees/quds_office_suite'
OUT = Path(__file__).resolve().parent
DART = WORK / 'runtime/flutter-sdk/bin/cache/dart-sdk/bin/dart'
FLUTTER = WORK / 'runtime/flutter-sdk/bin/cache/flutter_tools.snapshot'
ENGINE = REPO / 'packages/quds_office_engine'

ODT = [
    'test/odf_annotation_extraction_test.dart',
    'test/odf_covered_cell_extraction_test.dart',
    'test/odf_export_text_fidelity_test.dart',
    'test/odf_frame_extraction_test.dart',
    'test/odt_comment_fidelity_test.dart',
    'test/odt_document_writer_test.dart',
    'test/odt_header_footer_fidelity_test.dart',
    'test/odt_list_fidelity_test.dart',
    'test/odt_note_fidelity_test.dart',
    'test/odt_paragraph_properties_test.dart',
    'test/odt_section_fidelity_test.dart',
    'test/odt_section_integration_test.dart',
    'test/odt_structure_fidelity_test.dart',
    'test/odt_table_merge_test.dart',
]
GERMAN = [
    'test/proofing/german_genitive_noun_test.dart',
    'test/proofing/german_morphology_grammar_test.dart',
    'test/proofing/german_agreement_context_test.dart',
]
EDITOR = [
    'packages/quds_office_editor/test/word_manual_proofing_test.dart',
    'packages/quds_office_editor/test/word_proofing_correction_test.dart',
    'packages/quds_office_editor/test/word_proofing_dialog_test.dart',
    'packages/quds_office_editor/test/word_proofing_session_test.dart',
]
ANALYZE = [
    'lib/src/odf/odf_text.dart',
    'lib/src/extract/office_text_extractor.dart',
    'lib/src/extract/office_search_text.dart',
    'test/odf_frame_extraction_test.dart',
    'lib/src/proofing/german_spelling.dart',
    'lib/src/proofing/office_proofing.dart',
    'lib/src/slide/serial/odp_presentation_writer.dart',
    'test/proofing/proofing_report_merge_test.dart',
    'test/odp_presentation_writer_test.dart',
    'test/odp_transform_fidelity_test.dart',
    'test/odt_section_integration_test.dart',
    'test/odt_paragraph_properties_test.dart',
    'lib/src/word/serial/odt_document_writer.dart',
    'test/odt_list_fidelity_test.dart',
    'test/odt_section_fidelity_test.dart',
]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO, text=True).strip()

def source_map():
    paths = git('ls-files', 'packages/quds_office_engine',
                'packages/quds_office_editor', 'packages/quds_proofing_gector',
                'tools/proofing/german_model', 'pubspec.yaml', 'pubspec.lock').splitlines()
    result = {p: digest(REPO / p) for p in paths if (REPO / p).is_file()}
    result['.dart_tool/package_config.json'] = digest(REPO / '.dart_tool/package_config.json')
    return result

def main():
    suite = sys.argv[1]
    if suite == 'odt':
        cwd, command = ENGINE, [str(DART), 'test', '--reporter', 'expanded', *ODT]
    elif suite == 'odp':
        cwd, command = ENGINE, [str(DART), 'test', '--reporter', 'expanded', 'test/odp_presentation_writer_test.dart', 'test/odp_transform_fidelity_test.dart']
    elif suite == 'report_merge':
        cwd, command = ENGINE, [str(DART), 'test', '--reporter', 'expanded', 'test/proofing/proofing_report_merge_test.dart']
    elif suite == 'gector':
        cwd, command = REPO / 'packages/quds_proofing_gector', [str(DART), 'test', '--reporter', 'expanded']
    elif suite == 'gector_analysis':
        cwd, command = REPO / 'packages/quds_proofing_gector', [str(DART), 'analyze', '--fatal-infos', '--fatal-warnings', 'lib', 'test', 'tool']
    elif suite == 'tool_analysis':
        cwd, command = REPO, [str(DART), 'analyze', '--fatal-infos', '--fatal-warnings', 'tools/proofing/german_model/run_gector_dart.dart', 'tools/proofing/german_model/run_incremental_quality.dart', 'tools/proofing/german_model/incremental_quality.dart']
    elif suite == 'german':
        cwd, command = ENGINE, [str(DART), 'test', '--reporter', 'expanded', *GERMAN]
    elif suite == 'editor':
        cwd, command = REPO, [str(DART), str(FLUTTER), 'test', '--no-pub', '--reporter', 'expanded', *EDITOR]
    elif suite == 'analysis':
        cwd, command = ENGINE, [str(DART), 'analyze', '--fatal-infos', '--fatal-warnings', *ANALYZE]
    else:
        raise ValueError(suite)
    log = OUT / f'{suite}.log'
    receipt = OUT / f'{suite}.json'
    if log.exists() or receipt.exists():
        raise ValueError('Refusing existing output')
    environment = dict(os.environ)
    environment.update({
        'PUB_CACHE': str(WORK / 'runtime/pub-cache'),
        'TMPDIR': str(WORK / 'runtime/tmp'),
        'XDG_CONFIG_HOME': str(WORK / 'runtime/config'),
        'FLUTTER_ROOT': str(WORK / 'runtime/flutter-sdk'),
    })
    if suite == 'gector':
        pack = WORK / 'assets/native-development-pack-v1'
        model_hash = '549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b'
        library_hash = '9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604'
        environment.update({
            'CRISPEMBED_GECTOR': '1',
            'GECTOR_TEST_LIBRARY': str(pack / 'native' / library_hash / 'libcrispembed-gector.so'),
            'GECTOR_TEST_LIBRARY_SHA256': library_hash,
            'GECTOR_TEST_MODEL': str(pack / 'model' / model_hash / 'gector-de-mixed-q4_k.gguf'),
            'GECTOR_TEST_MODEL_SHA256': model_hash,
        })
    start_sources = source_map()
    record = {
        'schema_version': 1,
        'suite': suite,
        'started_utc': datetime.now(timezone.utc).isoformat(),
        'source_commit_at_start': git('rev-parse', 'HEAD'),
        'workdir': str(cwd.relative_to(REPO)),
        'command': ['dart', *(['flutter_tools.snapshot', *command[2:]] if suite == 'editor' else command[1:])],
        'dart_sha256': digest(DART),
        'source_files_before': start_sources,
    }
    if suite == 'editor':
        record['flutter_tools_snapshot_sha256'] = digest(FLUTTER)
    start = time.monotonic()
    with log.open('xb') as output:
        process = subprocess.run(command, cwd=cwd, env=environment,
                                 stdout=output, stderr=subprocess.STDOUT, timeout=600)
    record['duration_seconds'] = round(time.monotonic() - start, 6)
    record['exit_code'] = process.returncode
    text = log.read_text(errors='replace')
    counts = re.findall(r'\+(\d+)', text)
    record['passed_count'] = int(counts[-1]) if counts else None
    record['all_tests_passed_marker'] = 'All tests passed!' in text
    record['no_issues_found_marker'] = 'No issues found!' in text
    record['source_commit_at_end'] = git('rev-parse', 'HEAD')
    record['source_files_after'] = source_map()
    record['source_stable'] = start_sources == record['source_files_after']
    record['log'] = {'file': log.name, 'bytes': log.stat().st_size,
                     'sha256': digest(log)}
    record['completed_utc'] = datetime.now(timezone.utc).isoformat()
    receipt.write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    print(json.dumps({k: v for k, v in record.items()
                      if not k.startswith('source_files')}, indent=2))
    print('LOG TAIL\n' + text[-2200:])
    return process.returncode

if __name__ == '__main__':
    raise SystemExit(main())
