import hashlib
import json
from pathlib import Path
import runpy
import subprocess

root = Path('/workspace/scratch/9c3338a48b2c')
repo = root / 'crispoffice'
out = root / 'validation/layout-theme'
extract = runpy.run_path(str(out / 'extract_cases.py'))['extract_log']
editor = 'packages/quds_office_editor/'
example = editor + 'example/'
unpublished_files = subprocess.check_output(
    ['git', 'diff', 'HEAD', '--name-only'], cwd=repo, text=True).splitlines()
unpublished_source = [path for path in unpublished_files if path.endswith('.dart')
                      or path.endswith('pubspec.yaml') or path.endswith('pubspec.lock')]
assert not unpublished_source, ('Publish the already-tested source before final acceptance binding.', unpublished_source)

# Each selected test file has exactly one accepted run per platform.
# Earlier attempts stay on disk and are listed separately, not counted again.
selection = [
    ('core_theme_and_page_layout', 'core-focused', [editor + 'test/office_dark_document_test.dart']),
    ('core_theme_and_page_layout', 'main-language-core', [editor + 'test/word_page_layout_test.dart']),
    ('core_theme_and_page_layout', 'final-ruler-slide-2', [editor + 'test/office_chrome_theme_test.dart']),
    ('slide_theme', 'final-ruler-slide-2', [editor + 'test/office_dark_slide_test.dart']),
    ('paragraph_dialog', 'main-language-example', [example + 'test/studio_paragraph_dialog_test.dart']),
    ('page_layout_dialog', 'main-language-example', [example + 'test/studio_page_layout_dialog_test.dart']),
    ('layout_workspace', 'main-language-example', [example + 'test/studio_layout_theme_test.dart']),
    ('sheet_slide_menus', 'dialogs-workspace-2', [example + 'test/studio_slide_sheet_menus_test.dart']),
    ('existing_gui_regressions', 'gui-regressions', [example + 'test/' + name for name in ['studio_zotero_shortcuts_test.dart', 'studio_comment_review_test.dart', 'studio_comment_keyboard_review_test.dart', 'studio_review_pane_test.dart', 'studio_ribbon_preferences_test.dart', 'widget_test.dart']]),
    ('existing_gui_regressions', 'main-language-example', [example + 'test/studio_ribbon_customization_test.dart']),
    ('language_downloads', 'main-language-example', [example + 'test/studio_downloads_manager_test.dart']),
    ('proofing_controls_and_review', 'main-language-core', [editor + 'test/word_text_proofing_controls_test.dart', editor + 'test/word_text_proofing_pane_test.dart', editor + 'test/word_review_pane_test.dart']),
    ('native_ner_removal', 'main-language-ner-removal', None),
    ('vba_vm', 'incoming-vba-vm', None),
    ('mail_vm', 'incoming-resume-native-2', None),
    ('mail_node', 'incoming-resume-portable', None),
    ('mail_studio', 'incoming-resume-studio', None),
    ('embed_host', 'incoming-embed-host-fixture', None),
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def record(path):
    return {'path': str(path.relative_to(out)), 'sha256': digest(path)}


def verify_receipt(name, receipt):
    assert receipt['log_sha256'] == digest(out / (name + '.log')), name
    manifest = receipt.get('source_before')
    if manifest:
        assert digest(Path(manifest['path'])) == manifest['sha256'], name


reports, receipts, cases, seen = {}, {}, [], set()
for cohort, name, files in selection:
    if name not in reports:
        receipt_path = out / (name + '.json')
        if name == 'core-focused':
            receipt_path = out / 'core-original-gate-comparison.json'
            receipt = json.loads(receipt_path.read_text())
            cwd, exit_code = repo / editor, 0
            # Owner reported exit zero; original terminal log is preserved.
        else:
            receipt = json.loads(receipt_path.read_text())
            cwd, exit_code = receipt['cwd'], receipt['exit_code']
            assert not receipt.get('source_changed_during_run'), name
            verify_receipt(name, receipt)
        report = extract(out / (name + '.log'), platform='vm', repo_root=repo,
                         cwd=cwd, exit_code=exit_code)
        assert report['usable_pass_evidence'], (name, report['status'], report['ambiguities'], report['errors'])
        reports[name], receipts[name] = report, receipt
        (out / (name + '.extracted.json')).write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    rows = [row for row in reports[name]['cases'] if files is None or row['file'] in files]
    if files:
        assert set(row['file'] for row in rows) == set(files), (name, files)
    for row in rows:
        key = (row['file'], row['name'], row['platform'])
        assert key not in seen, key
        seen.add(key)
        assert row['result'] == 'passed', row
        cases.append({
            'cohort': cohort, 'file': row['file'], 'name': row['name'],
            'platform': row['platform'], 'result': row['result'],
            'log': name + '.log',
            'receipt': 'core-original-gate-comparison.json' if name == 'core-focused' else name + '.json',
            'source_sha256': digest(repo / row['file']),
        })

cohorts = []
for cohort in dict.fromkeys(row['cohort'] for row in cases):
    rows = [row for row in cases if row['cohort'] == cohort]
    per_file = []
    for file in sorted(set(row['file'] for row in rows)):
        file_rows = [row for row in rows if row['file'] == file]
        per_file.append({'file': file, 'cases': len(file_rows),
                         'platforms': sorted(set(row['platform'] for row in file_rows)),
                         'accepted_logs': sorted(set(row['log'] for row in file_rows)),
                         'source_sha256': digest(repo / file)})
    cohorts.append({'cohort': cohort, 'case_platform_executions': len(rows),
                    'distinct_source_cases': len(set((row['file'], row['name']) for row in rows)),
                    'files': per_file})
gui_names = {'core_theme_and_page_layout', 'slide_theme', 'paragraph_dialog',
             'page_layout_dialog', 'layout_workspace', 'sheet_slide_menus',
             'existing_gui_regressions'}
assert sum(item['case_platform_executions'] for item in cohorts if item['cohort'] in gui_names) == 144

accepted_names = list(reports)
analysis_names = ['example-analysis-2', 'tabs-analysis', 'final-ruler-slide-analysis',
                  'final-slide-test-analysis', 'incoming-vba-scoped-analysis',
                  'incoming-resume-scoped-analysis-2', 'main-language-analysis']
for name in analysis_names:
    receipt = json.loads((out / (name + '.json')).read_text())
    assert receipt['exit_code'] == 0 and not receipt.get('source_changed_during_run'), name
    verify_receipt(name, receipt)

source_paths = set(repo.glob('packages/*/lib/**/*.dart'))
source_paths.update(repo.glob('packages/*/example/lib/**/*.dart'))
source_paths.update(repo.glob('packages/*/tool/**/*.dart'))
source_paths.update(repo.glob('packages/*/example/macros/**/*.bas'))
source_paths.update(repo.glob('packages/*/example/macros/**/*.json'))
source_paths.update(repo.glob('packages/*/test/support/**/*.dart'))
source_paths.update(repo.glob('packages/*/example/test/support/**/*.dart'))
source_paths.update(repo.glob('packages/*/pubspec.yaml'))
source_paths.update(repo.glob('packages/*/example/pubspec.yaml'))
source_paths.update(repo / value for value in ['.fvmrc', 'pubspec.yaml', 'pubspec.lock'])
source_paths.update(repo / row['file'] for row in cases)
source_hashes = {str(path.relative_to(repo)): digest(path) for path in sorted(source_paths) if path.is_file()}
(out / 'source-hashes-final.json').write_text(json.dumps(source_hashes, sort_keys=True, indent=2) + '\n')
(out / 'accepted-cases.json').write_text(json.dumps(cases, ensure_ascii=False, indent=2) + '\n')

qualified_changes = {}
for name in accepted_names + analysis_names:
    if name == 'core-focused':
        continue
    receipt = json.loads((out / (name + '.json')).read_text())
    source_manifest = receipt.get('source_before')
    if source_manifest:
        before = json.loads(Path(source_manifest['path']).read_text())
    else:
        before = {str((Path(receipt['cwd']) / rel).relative_to(repo)): sha
                  for rel, sha in receipt.get('source_sha256', {}).items()}
    changed = []
    for rel, previous in before.items():
        path = repo / rel
        current = digest(path) if path.is_file() else None
        if previous != current:
            changed.append({'file': rel, 'at_run_sha256': previous, 'final_sha256': current})
    if changed:
        qualified_changes[name] = changed
    tested_files = {row['file'] for row in cases if row['log'] == name + '.log'}
    assert not any(row['file'] in tested_files for row in changed), (name, 'Accepted test source changed after run', changed)
(out / 'accepted-source-comparisons.json').write_text(json.dumps(qualified_changes, indent=2) + '\n')
original_core = json.loads((out / 'core-original-gate-comparison.json').read_text())
core_final = {
    rel: {'checkpoint_sha256': item['checkpoint_sha256'],
          'final_sha256': digest(repo / rel),
          'unchanged': item['checkpoint_sha256'] == digest(repo / rel)}
    for rel, item in original_core['source_comparison'].items()
}
(out / 'core-checkpoint-vs-final.json').write_text(json.dumps(core_final, indent=2) + '\n')
assert core_final[editor + 'test/office_dark_document_test.dart']['unchanged']

smokes = []
for smoke in ['web_vba_arrays_smoke', 'web_vba_control_flow_smoke']:
    checked = out / ('incoming-' + smoke + '-node.assertions.json')
    assertion = json.loads(checked.read_text())
    assert assertion['all_passed'] and all(assertion['assertions'].values()), smoke
    for suffix in ['compile', 'node']:
        receipt = json.loads((out / ('incoming-' + smoke + '-' + suffix + '.json')).read_text())
        assert receipt['exit_code'] == 0 and not receipt.get('source_changed_during_run'), smoke
        verify_receipt('incoming-' + smoke + '-' + suffix, receipt)
    smokes.append(record(checked))

preview_receipt = json.loads((out / 'previews-publication.json').read_text())
assert preview_receipt['exit_code'] == 0 and not preview_receipt['source_changed_during_run']
verify_receipt('previews-publication', preview_receipt)
preview = json.loads((out / 'previews-publication-images.json').read_text())
assert preview['image_count'] == preview['distinct_images'] == 12
for image in preview['screenshots']:
    assert digest(repo / image['path']) == image['sha256']
preview_sources = json.loads(Path(preview_receipt['source_before']['path']).read_text())
preview_source_changes = []
for rel, previous in preview_sources.items():
    if rel == example + 'test/_layout_theme_previews_test.dart':
        assert not (repo / rel).exists(), 'Temporary preview test must be removed.'
        continue
    path = repo / rel
    current = digest(path) if path.is_file() else None
    if current != previous:
        preview_source_changes.append(rel)
assert not preview_source_changes, preview_source_changes

lock_sha = digest(repo / 'pubspec.lock')
assert lock_sha == '72a5a52654a1484f4df646c631b4d1ea47e96025a671beff045eecf2b9e78e82'
format_receipt = json.loads((out / 'final-gui-format.json').read_text())
assert format_receipt['exit_code'] == 0 and not format_receipt['source_changed_during_run']
verify_receipt('final-gui-format', format_receipt)
language_format = json.loads((out / 'main-language-format.json').read_text())
assert language_format['exit_code'] == 0 and not language_format['source_changed_during_run']
verify_receipt('main-language-format', language_format)
vba_receipt = json.loads((out / 'incoming-vba-vm.json').read_text())
vba_changes = subprocess.check_output([
    'git', 'diff', '--name-only', vba_receipt['head'], 'HEAD', '--',
    'packages/quds_office_engine/lib', 'packages/quds_office_engine/test',
    'packages/quds_office_engine/tool', 'packages/quds_office_engine/example/macros',
], cwd=repo, text=True).splitlines()
assert not vba_changes, vba_changes
vba_retention = {'accepted_run_head': vba_receipt['head'],
                 'final_head': subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),
                 'engine_lib_test_tool_macro_changes': vba_changes,
                 'pubspec_lock_sha256': lock_sha,
                 'qualification': 'Mail and language/proofing integrations preserve complete engine lib/test/tool/macro source; VBA395 is retained without rerun. Both web smoke programs ran after the mail integration and remain source-identical through the language integration.'}
(out / 'vba-post-integration-retention.json').write_text(json.dumps(vba_retention,indent=2)+'\n')
mail_changes = subprocess.check_output([
    'git', 'diff', '--name-only', 'ba51c40abc664758df3cfc846625bdeb81e3ac13', 'HEAD', '--',
    'packages/quds_mail_store/lib', 'packages/quds_mail_store/test',
], cwd=repo, text=True).splitlines()
assert not mail_changes, mail_changes
language_retention = {
    'accepted_previous_source_commit': 'ba51c40abc664758df3cfc846625bdeb81e3ac13',
    'integrated_main_commit': '9f41e0427734d815b19149eba5eabef202f78ba6',
    'integration_commit': 'a93c78032b043c35edd2632ba3ab7a058299926a',
    'final_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
    'mail_lib_test_changes': mail_changes,
    'vba_source_retention': 'vba-post-integration-retention.json',
    'accepted_new_gate_receipts': ['main-language-analysis.json', 'main-language-example.json',
                                  'main-language-core.json', 'main-language-ner-removal.json'],
    'publication_preview_source_changes_after_run': preview_source_changes,
}
(out / 'main-language-source-retention.json').write_text(json.dumps(language_retention, indent=2) + '\n')
failed_restore = json.loads((out / 'incoming-resume-native.source-before.json').read_text())
fixed_restore = json.loads((out / 'incoming-resume-native-2.source-before.json').read_text())
repair_changes = [rel for rel in sorted(failed_restore.keys() & fixed_restore.keys())
                  if failed_restore[rel] != fixed_restore[rel]]
expected_repair = ['packages/quds_mail_store/lib/src/archive_restore_checkpoints.dart',
                   'packages/quds_mail_store/lib/src/archive_restore_native.dart']
assert repair_changes == expected_repair, repair_changes
repair_tests = {row['file']: {'failed_run_sha256': failed_restore[row['file']],
                            'accepted_run_sha256': fixed_restore[row['file']]}
                for row in cases if row['cohort'] == 'mail_vm'}
assert all(item['failed_run_sha256'] == item['accepted_run_sha256'] for item in repair_tests.values())
repair_record = {'changed_product_files': repair_changes, 'all_original_test_files_unchanged': True,
                 'test_source_comparison': repair_tests,
                 'failed_receipt': 'incoming-resume-native.json',
                 'accepted_receipt': 'incoming-resume-native-2.json',
                 'published_source_commit': 'ba51c40abc664758df3cfc846625bdeb81e3ac13',
                 'published_source_tree': 'e3b0c194fc9b0ccbdcc16b052daffc6646d216cc'}
(out / 'restore-repair-source-proof.json').write_text(json.dumps(repair_record,indent=2)+'\n')
summary = {
    'schema_version': 1,
    'scope': 'Layout/theme/Paragraph continuation, integrated VBA/mail restoration gates and final main language/downloads qualification; excludes the earlier634-case GUI phase.',
    'final_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
    'published_final_source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
    'published_final_source_tree': subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=repo, text=True).strip(),
    'all_selected_tests_passed': True,
    'totals': {
        'case_platform_executions_without_reruns': len(cases),
        'distinct_source_cases': len(set((row['file'], row['name']) for row in cases)),
        'test_files': len(set(row['file'] for row in cases)),
        'gui_continuation_cases': 144,
        'prior_pre_language_cases': 848,
        'additional_language_downloads_proofing_cases': len(cases) - 848,
        'preview_tests_separate': 1,
        'preview_images': 12,
        'web_smoke_programs_separate': 2,
    },
    'cohorts': cohorts,
    'accepted_test_evidence': [{'run': name,
        'log': record(out / (name + '.log')),
        'receipt': record(out / ('core-original-gate-comparison.json' if name == 'core-focused' else name + '.json')),
        'extracted_cases': record(out / (name + '.extracted.json')),
    } for name in accepted_names],
    'accepted_analysis_receipts': [record(out / (name + '.json')) for name in analysis_names],
    'original_core_analysis': record(out / 'core-analysis.log'),
    'source_comparison_qualifications': {
        'details': record(out / 'accepted-source-comparisons.json'),
        'original_core_checkpoint_to_final': record(out / 'core-checkpoint-vs-final.json'),
        'early_core17': 'Earlier core gate had no at-run manifest. Source checkpoint4fd010fc comparison is retained. Its3 unchanged Word/Sheet rendering cases remain accepted;4 ruler cases were rerun after explicit theme-font selection, and10 Page Layout cases were rerun after the final controller/proofing merge.',
        'early_gui84': 'Six customization cases are replaced by the final main-integration rerun. Other78 behavior cases remain accepted. Later tab ink/height, ruler font, Settings/downloads and proofing hooks are covered by focused workspace/customization/dialog/proofing tests and final screenshots.',
        'older_dialog_and_menu_runs': 'Paragraph18, Page Layout9, workspace7 and customization6 are replaced by main-language-example. Sheet/Slide3 retains unchanged source; later shared host changes have concrete workspace/customization/downloads coverage. VBA parser changes have separate incoming gates.',
        'final_mail_integration': 'Final cutoff changes13 mail-specific product paths and their tests/embedding fixtures. GUI product sources and engine lib/test/tool are retained exactly. Fresh mail VM/Node/Studio/embedding gates cover the final source.',
        'retained_vba_proof': record(out / 'vba-post-integration-retention.json'),
        'final_main_language_integration': 'Main9f was merged into accepted ba51 as a93. Changed proofing/controller callbacks, Settings/downloads routes and native NER deletion have dedicated analysis/tests. Existing848-case coverage is retained with latest rerun mappings, and genuinely new cases are added once. Mail and engine source trees are unchanged by this merge.',
        'main_language_source_proof': record(out / 'main-language-source-retention.json'),
    },
    'source_manifest': record(out / 'source-hashes-final.json'),
    'accepted_case_map': record(out / 'accepted-cases.json'),
    'pubspec_lock': {'sha256': lock_sha, 'unchanged': True},
    'nonmutating_gui_format': record(out / 'final-gui-format.json'),
    'nonmutating_restore_repair_format': record(out / 'restore-repair-format.json'),
    'main_language_format_no_files_changed': record(out / 'main-language-format.json'),
    'restore_repair_source_proof': record(out / 'restore-repair-source-proof.json'),
    'native_runtime': record(out / 'native-runtime-receipt.json'),
    'web_smoke_assertions': smokes,
    'preview': {'receipt': record(out / 'previews-publication.json'), 'images': record(out / 'previews-publication-images.json'),
                'preserved_earlier_capture': {'receipt': record(out / 'previews-3.json'), 'images': record(out / 'previews-images-final.json')}},
    'failed_or_superseded_attempts': [
        {'run': 'example-analysis-1', 'reason': 'Nullable generic inference and style diagnostics fixed before accepted strict analysis.'},
        {'run': 'dialogs-1', 'reason': 'Paragraph18 was replaced after removal of unsupported Keep lines UI; both Paragraph18 and Page Layout9 now use the final main-language-example run.'},
        {'run': 'dialogs-workspace-2', 'reason': 'Sheet/Slide3 retained; Paragraph18 and expanded workspace7 now use the final main-language-example run.'},
        {'run': 'tabs-workspace-customization', 'reason': 'All13 passed; workspace7 and customization6 now use the final main-language-example run after shared Settings/downloads integration.'},
        {'run': 'slide-workspace-analysis', 'reason': 'One new multiline-if brace diagnostic fixed; later scoped analysis clean.'},
        {'run': 'workspace-final', 'reason': 'Seven passed, then rerun with final tab color/height assertions.'},
        {'run': 'slide-core', 'reason': 'Exact-RGB pixel count underrepresented small anti-aliased table glyphs; meaningful contrast and unchanged-pixel assertions passed later.'},
        {'run': 'final-ruler-slide', 'reason': 'Nine passed; first Slide case assumed existing table reader round-tripped explicit black. Render-only test now checks source ink and actual serialized XML; all10 passed subsequently.'},
        {'run': 'previews', 'reason': 'Generation passed but Paragraph image was captured before its route paint; dark-tab contrast/clipping found during visual review.'},
        {'run': 'previews-2', 'reason': 'Preview-only font alias did not override raw default Ahem; rejected by explicit assertion and removed. Production ruler now selects registered theme font; final preview passed.'},
        {'run': 'incoming-resume-native', 'reason': '178 passed and3 original adversarial cases failed. Two product files restored diagnostic operation compatibility and separated per-message codec failures from fatal destination-receipt corruption; original tests remained byte-identical and the full native gate was rerun.'},
    ],
    'limitations': ['Local Linux Flutter/widget/native-VM/Node validation. Native macOS/Windows application packaging and GitHub Actions were not run for this continuation.'],
}
for attempt in summary['failed_or_superseded_attempts']:
    for kind, suffix in [('log', '.log'), ('receipt', '.json')]:
        path = out / (attempt['run'] + suffix)
        if path.is_file():
            attempt[kind] = record(path)
(out / 'acceptance-summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'summary': str(out / 'acceptance-summary.json'), 'totals': summary['totals'],
                  'cohorts': {item['cohort']: item['case_platform_executions'] for item in cohorts},
                  'source_manifest_files': len(source_hashes)}, indent=2))
