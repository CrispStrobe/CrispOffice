#!/usr/bin/env python3
"""Independently recount final validation logs and verify their recorded inputs.

No validation runner is imported and no tests or analyzers are executed.
Usage: python audit_validation.py --repo CLONE --evidence FINAL_VALIDATION
       --final-head SHA --output REPORT.json
"""
import argparse
from collections import Counter
import functools
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urljoin, urlparse


FLUTTER = ('mail-host', 'editor-rendering', 'editor-zotero-materials', 'studio-spacy')
PURE = ('engine-rendering', 'spacy-package', 'engine-macro-serialization')
OPTIONAL_NATIVE = (
    'packages/quds_proofing_spacy/test/macho_code_identity_test.dart',
    'the qualified macOS library has the recorded code digest',
    'set QUDS_SPACY_MACOS_LIBRARY to the qualified library',
)
DELTA_PATHS = {
    'packages/quds_proofing_spacy/tool/evaluate_grammar_v2.dart',
    'packages/quds_office_engine/test/office_pdf_export_test.dart',
}
SPECS = {
    'engine-rendering': ('packages/quds_office_engine', ['slide*_test.dart'],
                         ['office_pdf_export_test.dart', 'word_small_caps_test.dart']),
    'spacy-package': ('packages/quds_proofing_spacy', ['**/*_test.dart'], []),
    'engine-macro-serialization': ('packages/quds_office_engine', [],
                                  ['office_macro_cli_test.dart', 'office_macro_language_test.dart', 'office_macro_runtime_test.dart']),
    'editor-rendering': ('packages/quds_office_editor', ['slide*_test.dart'],
                         ['office_dark_slide_test.dart', 'paint_run_text_unicode_test.dart', 'word_small_caps_test.dart', 'word_tab_stops_editor_test.dart']),
    'editor-zotero-materials': ('packages/quds_office_editor', [],
                               ['word_zotero_children_dialog_test.dart', 'word_zotero_children_test.dart', 'word_zotero_note_preview_test.dart']),
    'studio-spacy': ('packages/quds_office_editor/example', [], ['studio_spacy_setup_test.dart', 'studio_spacy_pin_test.dart']),
    'mail-host': ('packages/quds_office_editor/example', [], [
        'studio_mail_attachment_test.dart', 'studio_mail_attachment_loader_test.dart',
        'studio_mail_attachment_compose_test.dart', 'studio_mail_cloud_test.dart',
        'studio_mail_ews_test.dart', 'studio_mail_session_test.dart', 'studio_mail_compose_test.dart',
        'studio_mail_recipients_test.dart', 'studio_mail_reply_test.dart',
        'studio_mail_threading_test.dart', 'studio_mail_test.dart']),
}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def read_json(path):
    raw = path.read_bytes()
    return json.loads(gzip.decompress(raw) if path.suffix == '.gz' else raw)


@functools.lru_cache(maxsize=None)
def cached_record(name, size, mtime):
    path = Path(name)
    sha, blob = hashlib.sha256(), hashlib.sha1(f'blob {size}\0'.encode())
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            sha.update(chunk)
            blob.update(chunk)
    after = path.stat()
    if (after.st_size, after.st_mtime_ns) != (size, mtime):
        raise RuntimeError(f'File changed during independent hashing: {path}')
    return {'bytes': size, 'sha256': sha.hexdigest(), 'git_blob_sha1': blob.hexdigest()}


def record(path):
    stat = path.stat()
    return cached_record(str(path.resolve()), stat.st_size, stat.st_mtime_ns)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repo', type=Path, required=True)
    p.add_argument('--evidence', type=Path, required=True)
    p.add_argument('--final-head', required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    repo, root = args.repo.resolve(), args.evidence.resolve()
    issues, pending, rows, all_cases, input_audits, static_audits = [], [], [], [], [], []
    checked_artifacts = {}
    captured_source_paths = set()

    def git(*argv):
        return subprocess.check_output(['git', '-C', str(repo), *argv])

    @functools.lru_cache(maxsize=None)
    def tree_entries(head):
        entries = {}
        for raw in git('ls-tree', '-r', '-z', head).split(b'\0'):
            if raw:
                meta, path = raw.split(b'\t', 1)
                mode, kind, oid = meta.decode().split()
                entries[path.decode()] = {'mode': mode, 'type': kind, 'oid': oid}
        return entries

    def check(condition, message):
        if not condition:
            issues.append(message)
        return condition

    def check_file(path, expected, label):
        if not check(path.is_file(), f'{label}: missing {path}'):
            return False
        actual = record(path)
        valid = all(actual[k] == v for k, v in expected.items() if k in actual)
        check(valid, f'{label}: artifact/input hash mismatch for {path}')
        return valid

    def audit_artifacts(folder, receipt):
        for name, expected in receipt.get('artifacts', {}).items():
            path = folder / name
            check_file(path, expected, folder.name)
            if path.exists():
                checked_artifacts[str(path.relative_to(root))] = record(path)
        for name in ('validation_runner',):
            data = receipt.get(name)
            if data and 'path' in data:
                check_file(Path(data['path']), data, folder.name + ':' + name)
        adapter = receipt.get('selection_adapter')
        if adapter:
            check(adapter['code_before'] == adapter['code_after'], folder.name + ': selection adapter changed')
            for name, data in adapter['code_before'].items():
                check_file(Path(data['path']), data, folder.name + ':' + name)

    def relative_suite(path, cwd):
        if path.startswith('file:'):
            value = Path(unquote(urlparse(path).path))
        else:
            value = Path(path)
            if not value.is_absolute():
                value = cwd / value
        return str(value.resolve().relative_to(repo))

    def recount(path, cwd, expected, cohort):
        raw = path.read_bytes()
        decoded = gzip.decompress(raw) if path.suffix == '.gz' else raw
        events, parse_errors, notifications = [], [], []
        # JSONL framing is LF only. Unicode NEL/line/paragraph separators are
        # valid JSON string data in the unsafe-filename regression names.
        for line_no, line in enumerate(decoded.decode().split('\n'), 1):
            if not line.strip():
                continue
            try:
                item = json.loads(line)
                if isinstance(item, dict) and isinstance(item.get('type'), str):
                    events.append(item)
                elif isinstance(item, list) and all(isinstance(x, dict) and str(x.get('event', '')).startswith('test.') for x in item):
                    notifications.extend(item)
                else:
                    parse_errors.append({'line': line_no, 'value': item})
            except (ValueError, TypeError) as error:
                parse_errors.append({'line': line_no, 'error': str(error), 'text': line[:300]})
        start_rows = [e['test'] for e in events if e['type'] == 'testStart']
        end_rows = [e for e in events if e['type'] == 'testDone']
        suite_rows = [e['suite'] for e in events if e['type'] == 'suite']
        starts = {t['id']: t for t in start_rows}
        suites = {s['id']: s for s in suite_rows}
        starts_count = Counter(t['id'] for t in start_rows)
        ends_count = Counter(e['testID'] for e in end_rows)
        errors = [e for e in events if e['type'] == 'error']
        final = [e for e in events if e['type'] == 'done']
        observed = [relative_suite(s['path'], cwd) for s in suite_rows]
        excluded, cases = [], []
        for end in end_rows:
            test = starts.get(end['testID'])
            if test is None:
                continue
            name = test.get('name', '')
            if end.get('hidden') or (name.startswith('loading ') and test.get('url') is None) or name.endswith(('(setUpAll)', '(tearDownAll)')):
                excluded.append({'name': name, 'result': end['result'], 'skipped': end.get('skipped', False)})
                continue
            suite = suites.get(test.get('suiteID'))
            if suite is None:
                issues.append(f'{cohort}: test without known suite: {name}')
                continue
            metadata = test.get('metadata', {})
            skipped = bool(end.get('skipped') or metadata.get('skip'))
            case = {'cohort': cohort, 'file': relative_suite(suite['path'], cwd),
                    'platform': suite.get('platform'), 'name': name,
                    'result': 'not_run' if skipped else 'passed' if end['result'] == 'success' else 'failed',
                    'skipReason': metadata.get('skipReason') if skipped else None}
            cases.append(case)
        case_keys = [(c['file'], c['platform'], c['name']) for c in cases]
        duplicates = [k for k, n in Counter(case_keys).items() if n > 1]
        failure_events = [e for e in end_rows if e.get('result') != 'success']
        not_run = [c for c in cases if c['result'] == 'not_run']
        expected_optional = cohort == 'spacy-package' and len(not_run) == 1 and (
            not_run[0]['file'], not_run[0]['name'], not_run[0]['skipReason']) == OPTIONAL_NATIVE
        guards = {
            'strict_json_parse': not parse_errors,
            'no_error_events': not errors,
            'no_failed_completion_including_hidden': not failure_events,
            'every_start_and_completion_once': set(starts_count) == set(ends_count) and
                all(n == 1 for n in starts_count.values()) and all(n == 1 for n in ends_count.values()),
            'suite_ids_unique': len(suite_rows) == len(suites),
            'selected_files_exactly_once': Counter(observed) == Counter(expected) and len(expected) == len(set(expected)),
            'application_case_names_unique': not duplicates,
            'one_successful_final_event': len(final) == 1 and final[0].get('success') is True,
            'skip_scope_explicit': not not_run or expected_optional,
            'no_flutter_error_notification': not any('error' in str(n.get('event', '')).lower() for n in notifications),
        }
        for key, value in guards.items():
            check(value, f'{cohort}: raw-event guard failed: {key}')
        counts = {'passed': sum(c['result'] == 'passed' for c in cases),
                  'failed': sum(c['result'] == 'failed' for c in cases), 'not_run': len(not_run)}
        return {'counts': counts, 'suite_count': len(observed), 'selected_files': expected,
                'observed_files': observed, 'hidden_or_lifecycle_excluded': len(excluded),
                'start_events': len(start_rows), 'completion_events': len(end_rows),
                'guards': guards, 'errors': errors, 'parse_errors': parse_errors,
                'duplicate_cases': duplicates, 'not_run_cases': not_run,
                'event_file_sha256': hashlib.sha256(raw).hexdigest(),
                'events_uncompressed_sha256': hashlib.sha256(decoded).hexdigest(),
                'accepted_events': all(guards.values())}, cases

    def expected_paths(name):
        package, patterns, additional = SPECS[name]
        directory = repo / package / 'test'
        paths = {directory / item for item in additional}
        for pattern in patterns:
            paths.update(directory.glob(pattern))
        return sorted(str(path.relative_to(repo)) for path in paths)

    def input_file(path, expected, label, source_head=None, source_path=None):
        if source_head is None:
            return check_file(path, expected, label)
        saved_blob = tree_entries(source_head).get(source_path, {}).get('oid')
        check(saved_blob is not None, f'{label}: source path absent from claimed commit: {source_path}')
        if 'git_blob_sha1' in expected:
            check(saved_blob == expected['git_blob_sha1'], f'{label}: saved blob differs from claimed commit: {source_path}')
        actual = record(path)
        if all(actual[k] == v for k, v in expected.items() if k in actual):
            check(actual['git_blob_sha1'] == saved_blob, f'{label}: source bytes differ from claimed commit: {source_path}')
            return True
        data = git('show', source_head + ':' + source_path)
        historic = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                    'git_blob_sha1': hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest()}
        return check(all(historic[k] == v for k, v in expected.items() if k in historic),
                     f'{label}: retained source record does not match historical bytes: {source_path}')

    def audit_inputs(folder, receipt):
        data = read_json(folder / 'inputs.json.gz')['before']
        fingerprint = receipt['fingerprints']
        check(read_json(folder / 'input-check.json') == fingerprint, folder.name + ': input-check differs from receipt')
        for area, records in data.items():
            computed = digest(records)
            check(computed == fingerprint['before_sha256'][area], folder.name + ':' + area + ' before digest mismatch')
            check(computed == fingerprint['after_sha256'][area], folder.name + ':' + area + ' after digest mismatch')
            check(not fingerprint['changed_paths'][area], folder.name + ':' + area + ' changed during run')
        source_head = receipt['source_head_at_start']
        captured_source_paths.update(data['source'])
        changed_to_final = []
        for path, expected in data['source'].items():
            input_file(repo / path, expected, folder.name, source_head, path)
            if tree_entries(args.final_head).get(path, {}).get('oid') != expected['git_blob_sha1']:
                changed_to_final.append(path)
        for path, expected in data['workspace'].items():
            input_file(repo / path, expected, folder.name)
        for package, manifest in data['dependencies'].items():
            check(manifest['file_count'] == len(manifest['files']), folder.name + ':' + package + ' dependency count mismatch')
            check(manifest['inventory_sha256'] == digest(manifest['files']), folder.name + ':' + package + ' dependency digest mismatch')
            for path, expected in manifest['files'].items():
                input_file(Path(manifest['root']) / path, expected, folder.name)
        sdk = Path(receipt.get('runtime', {}).get('flutter_root', root.parent / 'runtime/flutter'))
        for path, expected in data['runtime'].items():
            input_file(sdk / path, expected, folder.name)
        for path, expected in data.get('host_fonts', {}).items():
            check(Path(path).is_file() == expected['present'], folder.name + ': host font presence changed')
            if expected['present']:
                input_file(Path(path), expected, folder.name)
        check(receipt.get('source_file_count') == len(data['source']), folder.name + ': source inventory count mismatch')
        report = {'cohort': folder.name, 'source_head': source_head,
                  'source_files_verified': len(data['source']),
                  'dependency_files_verified': sum(len(v['files']) for v in data['dependencies'].values()),
                  'runtime_files_verified': len(data['runtime']),
                  'source_differences_to_final_head': sorted(changed_to_final),
                  'input_manifest_sha256': record(folder / 'inputs.json.gz')['sha256'],
                  'all_before_and_after_area_digests_recomputed': True}
        input_audits.append(report)
        return report

    # Seven mail cohorts use the older flat-manifest envelope.
    mail = root / 'mail-packages'
    receipt = read_json(mail / 'receipt.json')
    selection = read_json(mail / 'selection.json')
    selected = {c['name']: c for c in selection['cohorts']}
    sdk = root.parent / 'runtime/flutter'
    configs = {'workspace': repo / '.dart_tool/package_config.json',
               'flutter-tools': sdk / 'packages/flutter_tools/.dart_tool/package_config.json'}
    package_roots = {origin: {
        item['name']: Path(unquote(urlparse(urljoin(config.as_uri(), item['rootUri'])).path))
        for item in read_json(config)['packages']
    } for origin, config in configs.items()}
    for area, key in [('source', 'source_digest'), ('dependencies', 'dependency_digest'), ('runtime', 'runtime_digest')]:
        before = read_json(mail / f'{area}-before.json.gz')
        after = read_json(mail / f'{area}-after.json.gz')
        check(before == after, 'mail-packages:' + area + ' changed during run')
        check(digest(before) == receipt[key], 'mail-packages:' + area + ' digest mismatch')
        for path, expected in before.items():
            if area == 'source':
                input_file(repo / path, expected, 'mail-packages', receipt['source_head_before'], path)
                check(record(repo / path)['sha256'] == expected['sha256'], 'mail source changed since accepted run: ' + path)
            elif area == 'runtime':
                input_file(Path(path), expected, 'mail-packages')
            else:
                origin, package, relative = path.split('/', 2)
                input_file(package_roots[origin][package] / relative, expected, 'mail-packages')
        input_audits.append({'cohort': 'mail-packages', 'area': area,
                             'files_verified': len(before), 'before_after_equal': before == after,
                             'recomputed_digest': digest(before)})
    mail_union = []
    for step in receipt['steps']:
        name = step['name']; folder = mail / name; chosen = selected[name]
        expected = sorted(chosen['package'] + '/' + f for f in chosen['files'])
        check(sorted(step['expected_test_files']) == expected, name + ': selection differs from receipt')
        if name != 'vendor-mime':
            derived = []
            for path in (repo / chosen['package'] / 'test').rglob('*_test.dart'):
                match = re.search(r"@TestOn\(['\"]([^'\"]+)['\"]\)", path.read_text()[:4000])
                platform = 'node' if match and match.group(1) in ('js', 'node') else 'vm'
                if platform == chosen['platform']:
                    derived.append(str(path.relative_to(repo)))
            check(sorted(derived) == expected, name + ': declared mail test inventory differs')
        audit, cases = recount(folder / 'events.jsonl', Path(step['cwd']), expected, name)
        for filename, field in [('events.jsonl', 'stdout_sha256'), ('stderr.log', 'stderr_sha256'), ('test-cases.json.gz', 'test_cases_sha256')]:
            check_file(folder / filename, {'sha256': step[field]}, name)
            checked_artifacts[str((folder / filename).relative_to(root))] = record(folder / filename)
        check(step == read_json(folder / 'result.json'), name + ': nested and standalone result differ')
        for key in ('passed', 'failed'):
            check(audit['counts'][key] == step['counts'][key], name + ':' + key + ' recount mismatch')
        check(audit['counts']['not_run'] == step['counts']['skipped'], name + ': skip recount mismatch')
        check(step['exit_code'] == 0 and step['accepted'], name + ': process not accepted')
        rows.append({'cohort': name, 'source_head': receipt['source_head_before'], **audit})
        all_cases.extend(cases); mail_union.extend(expected)
    check(len(mail_union) == len(set(mail_union)), 'mail cohorts overlap in selected files')
    mail_counts = Counter(c['result'] for c in all_cases)
    check(mail_counts['passed'] == receipt['counts']['passed'], 'mail aggregate pass count mismatch')
    check(receipt['accepted'] and receipt['inputs_stable'], 'mail aggregate receipt not accepted')

    # Four Flutter and three pure-Dart cohorts use the newer receipt envelope.
    for name in (*FLUTTER, *PURE):
        folder = root / 'flutter-cohorts' / name if name in FLUTTER else root / name
        path = folder / 'receipt.json'
        if not path.exists() or read_json(path).get('status') == 'running':
            pending.append(name)
            continue
        receipt = read_json(path)
        audit_artifacts(folder, receipt)
        expected = expected_paths(name)
        check(receipt['selected_repository_paths'] == expected, name + ': advertised selected files differ from independent inventory')
        audit, cases = recount(folder / 'events.jsonl.gz', Path(receipt['cwd']), expected, name)
        for key in ('passed', 'failed'):
            check(audit['counts'][key] == receipt['tests'][key], name + ':' + key + ' recount mismatch')
        check(audit['counts']['not_run'] == receipt['tests']['skipped'], name + ': skip recount mismatch')
        check(receipt['exit_code'] == 0 and not receipt['timed_out'], name + ': process failed or timed out')
        if name == 'spacy-package' and audit['counts']['not_run'] == 1:
            controlled = folder / 'controlled-suite-receipt.json'
            check(controlled.exists(), name + ': missing explicit controlled skip receipt')
            if controlled.exists():
                checked_artifacts[str(controlled.relative_to(root))] = record(controlled)
                allowed = read_json(controlled)
                check(all(allowed['checks'].values()), name + ': controlled skip checks failed')
                check(allowed['raw_receipt_sha256'] == record(path)['sha256'], name + ': controlled receipt is not bound to raw receipt')
                check(allowed['passed'] == audit['counts']['passed'] and allowed['skipped'] == 1 and allowed['failed'] == 0,
                      name + ': controlled counts differ from independent recount')
                check(allowed['source_fingerprints'] == receipt['fingerprints'], name + ': controlled input binding differs')
            check(all(v for k, v in receipt['guards'].items() if k != 'no_failures_skips_or_errors'), name + ': other strict guards failed')
        else:
            check(receipt['status'] == 'passed' and all(receipt['guards'].values()), name + ': strict receipt rejected')
        inputs = audit_inputs(folder, receipt)
        if inputs['source_differences_to_final_head']:
            check(name in FLUTTER and set(inputs['source_differences_to_final_head']) == DELTA_PATHS,
                  name + ': unreviewed source drift to final head')
        rows.append({'cohort': name, 'source_head': receipt['source_head_at_start'], **audit})
        all_cases.extend(cases)

    # Original Flutter receipt hashes and the final-source binding are distinct
    # evidence; they never add new cases to the accepted total.
    flutter_summary = read_json(root / 'flutter-cohorts/summary.json')
    for item in flutter_summary['cohorts']:
        check_file(root / 'flutter-cohorts' / item['receipt'], {'sha256': item['receipt_sha256']}, 'Flutter summary')
    binding_path = root / 'flutter-final-input-audit-58c6962/receipt.json'
    if not binding_path.exists():
        pending.append('final-Flutter-source-binding')
    else:
        binding = read_json(binding_path)
        check(binding['status'] == 'passed' and binding['final_source_head'] == args.final_head,
              'Flutter final-source binding does not match final head')
        check(binding['application_cases_retained'] == sum(r['counts']['passed'] for r in rows if r['cohort'] in FLUTTER),
              'Flutter final-source binding case count differs')
        changed = set(git('diff', '--name-only', binding['accepted_source_head'], args.final_head).decode().splitlines())
        check(changed == DELTA_PATHS, 'Final source delta is not the two reviewed unexecuted files')
        selected_flutter = {f for r in rows if r['cohort'] in FLUTTER for f in r['selected_files']}
        check(not changed & selected_flutter, 'A changed final-source file was a selected Flutter entry point')
        check_file(binding_path.parent / 'final-source-delta.patch', binding['diff'], 'Final Flutter source delta')
        check_file(root / 'audit_flutter_final_inputs.py', binding['audit_script'], 'Final Flutter source auditor')
        check_file(repo / 'docs/validation/zotero-research-materials-20261120/run_validation.py',
                   binding['inherited_runner'], 'Final Flutter inherited runner')
        current_inputs = read_json(binding_path.parent / 'current-inputs.json.gz')
        for cohort in binding['cohorts']:
            check(record(root / 'flutter-cohorts' / cohort['cohort'] / 'receipt.json')['sha256'] == cohort['original_receipt_sha256'],
                  'Final Flutter binding original receipt hash differs: ' + cohort['cohort'])
            check({area: digest(records) for area, records in current_inputs[cohort['cohort']].items()} == cohort['final_area_sha256'],
                  'Final Flutter binding current manifest digest differs: ' + cohort['cohort'])
        tool = 'packages/quds_proofing_spacy/tool/evaluate_grammar_v2.dart'
        old = git('show', binding['accepted_source_head'] + ':' + tool).decode()
        new = git('show', args.final_head + ':' + tool).decode()
        original = '  if (value is List)\n    return [for (final v in value) _normalizeLibrary(v, library)];\n'
        braced = '  if (value is List) {\n    return [for (final v in value) _normalizeLibrary(v, library)];\n  }\n'
        check(old.count(original) == 1 and old.replace(original, braced) == new, 'Evaluator tool delta exceeds the exact bracing change')
        references = []
        for source in sorted(captured_source_paths):
            if source.endswith('.dart') and source not in DELTA_PATHS:
                content = (repo / source).read_text()
                references.extend({'source': source, 'target': target} for target in DELTA_PATHS
                                  if Path(target).stem in content)
        check(not references, 'Unexecuted final delta has a reference from another captured Dart source')
        checked_artifacts[str(binding_path.relative_to(root))] = record(binding_path)

    # Analysis and format receipts are reported separately, never as tests.
    static = root / 'changed-static'
    if (static / 'receipt.json').exists():
        receipt = read_json(static / 'receipt.json')
        check(receipt['source_before'] == receipt['source_after'], 'Changed-file static inputs changed during execution')
        check(set(receipt['selected_files']) == set(receipt['source_before']), 'Changed-file static selection and hashes differ')
        for path, expected in receipt['source_before'].items():
            input_file(repo / path, {'sha256': expected}, 'changed-static', receipt['head_before'], path)
        for step in receipt['steps']:
            check_file(static / step['log'], {'sha256': step['sha256']}, 'changed-static')
            check(step['exit_code'] == 0, 'Changed-file static command failed: ' + step['name'])
            check(sorted(x for x in step['command'] if x.endswith('.dart')) == sorted(receipt['selected_files']),
                  'Changed-file static command target mismatch: ' + step['name'])
        check(receipt['accepted'], 'Changed-file static receipt rejected')
        static_audits.append({'cohort': 'changed-static', 'selected_file_count': len(receipt['selected_files']),
                              'source_head': receipt['head_before'], 'accepted': receipt['accepted'],
                              'selected_files_different_at_final_head': [path for path in receipt['selected_files']
                                  if tree_entries(receipt['head_before']).get(path) != tree_entries(args.final_head).get(path)]})
    analysis = root / 'engine-spacy-analysis'
    if not (analysis / 'receipt.json').exists() or read_json(analysis / 'receipt.json').get('status') == 'running':
        pending.append('engine-spacy-analysis')
    else:
        receipt = read_json(analysis / 'receipt.json')
        audit_artifacts(analysis, receipt)
        audit_inputs(analysis, receipt)
        check(receipt['status'] == 'passed' and receipt['exit_code'] == 0 and all(receipt['guards'].values()),
              'Final engine/spaCy analysis failed')
        check(receipt['targets'] == read_json(root / 'pure-dart-plan.json')['analysis_targets'],
              'Final targeted analysis scope differs from plan')
        check(receipt['command'][2:4] == ['--fatal-infos', '--fatal-warnings'], 'Analysis is not strict')
        check('No issues found!' in (analysis / 'stdout.log').read_text(), 'Final targeted analyzer log lacks clean completion')
        static_audits.append({'cohort': 'engine-spacy-analysis', 'targets': receipt['targets'],
                              'source_head': receipt['source_head_at_start'], 'accepted': receipt['status'] == 'passed'})

    identities = Counter((c['file'], c['platform'], c['name']) for c in all_cases)
    duplicates = [identity for identity, count in identities.items() if count > 1]
    check(not duplicates, 'Substantive case identities overlap across accepted final cohorts')
    selected_files = [f for row in rows for f in row['selected_files']]
    check(len(selected_files) == len(set(selected_files)), 'Selected files overlap across final cohorts')
    accepted_rows = [r for r in rows if r['accepted_events']]
    accepted_cases = [c for c in all_cases if c['cohort'] in {r['cohort'] for r in accepted_rows}]
    counts = Counter(c['result'] for c in accepted_cases)
    excluded = sorted(p.name for p in root.iterdir() if p.is_dir() and (
        'preliminary' in p.name or p.name in ('slide-background', 'changed-static-before-tool-braces', 'reconciliation') or
        p.name.startswith('flutter-final-input-audit')))
    report = {
        'schema': 'quds.mail.attachments.independent-validation-audit.v1',
        'status': 'failed' if issues else 'pending' if pending else 'passed',
        'final_source_head': args.final_head,
        'final_source_tree': git('rev-parse', args.final_head + '^{tree}').decode().strip(),
        'auditor': record(Path(__file__)),
        'summary': {'distinct_passed_application_cases': counts['passed'],
                    'explicit_not_run_cases': counts['not_run'], 'accepted_final_cohorts': len(accepted_rows),
                    'distinct_selected_files': len(set(selected_files)),
                    'hidden_loading_lifecycle_cases_excluded': sum(r['hidden_or_lifecycle_excluded'] for r in rows),
                    'duplicate_case_identities': duplicates},
        'cohorts': rows, 'input_audits': input_audits, 'static_checks': static_audits,
        'checked_artifacts': checked_artifacts, 'issues': issues, 'pending': pending,
        'not_run': [c for c in all_cases if c['result'] == 'not_run'],
        'excluded_from_totals': excluded,
        'scope_notes': [
            'Only the explicitly selected final cohort directories are counted once. Development, diagnostic, preliminary and repeated repair checks add no cases.',
            'Case identity is repository test path, platform and full substantive name; hidden loading/setup/teardown events never count as passes, but any such failure rejects the run.',
            'Every start/completion and selected suite must occur exactly once; raw error events, unfinished cases, duplicates and failed completion events are rejected.',
            'The one declared native Mach-O check is NOT RUN. Portable parser/model tests do not qualify execution of the installed macOS library.',
            'Artifact hashes, complete captured before-manifest digests, reported after digests, current dependency/runtime bytes and claimed source-commit objects are checked independently.',
            'Raw after-manifests are not retained by the inherited runner. Its unchanged after digests are cross-checked against the full before manifest and independently hashed available bytes.',
            'No tests, analyzers, builds or remote status checks were executed by this audit.',
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    case_path = args.output.with_name(args.output.stem + '-cases.json.gz')
    case_path.write_bytes(gzip.compress(canonical(all_cases) + b'\n', mtime=0))
    print(json.dumps({'status': report['status'], **report['summary'], 'issues': issues, 'pending': pending}, indent=2))
    return 1 if issues else 2 if pending else 0


if __name__ == '__main__':
    raise SystemExit(main())
