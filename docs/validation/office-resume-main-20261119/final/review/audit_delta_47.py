#!/usr/bin/env python3
"""Read-only source-delta and retained-failure review for checkpoint 47ce5f72."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import io
import json
from pathlib import Path
import re
import tarfile

from audit_recovery import Audit, sha256

BASE = '911d8f43c420bd0d2bea1b9844f3f59f61d46dcf'
HEAD = '47ce5f726f1a0b1f213b926162528533dc0a3aab'
MAIN = 'b070e228a749e22cc8ce2098029a76ab5fb8eccb'
TREE = '97cad8c95409bee4af74b57c8e0e90cd4fc43585'
FINAL = 'docs/validation/office-resume-main-20261119/final/'
ARABIC = 'packages/quds_office_engine/lib/src/proofing/arabic_extended_rules.dart'
ARABIC_TEST = 'packages/quds_office_engine/test/proofing/arabic_extended_rules_test.dart'
CONTROLLER = 'packages/quds_office_editor/lib/src/embed/office_controller.dart'
LANGUAGE_TEST = 'packages/quds_office_editor/test/word_text_proofing_controls_test.dart'
FOOTER_TEST = 'packages/quds_office_editor/example/test/studio_review_status_test.dart'


def unpack(audit, name):
    stem = FINAL + name + '-evidence'
    data = audit.blob(HEAD, stem + '.tar.xz')
    index = json.loads(audit.blob(HEAD, stem + '.index.json'))
    audit.check(len(data) == index['bytes'] and sha256(data) == index['sha256'], name + ' archive identity')
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:xz') as tar:
        members = tar.getmembers()
        audit.check(all(m.isfile() for m in members), name + ' regular members')
        contents = {m.name: tar.extractfile(m).read() for m in members}
    expected = {m['path']: m for m in index['members']}
    audit.check(len(contents) == len(members) == len(expected) == index['member_count'], name + ' member counts')
    audit.check(set(contents) == set(expected), name + ' exact member coverage')
    for path, entry in expected.items():
        raw = contents[path]
        audit.check(len(raw) == entry['bytes'] and sha256(raw) == entry['sha256'], name + ' member hash: ' + path)
    return contents, {'name': name, 'bytes': len(data), 'sha256': sha256(data), 'members': len(members), 'status': index.get('status', index.get('kind'))}


def events(audit, raw, label):
    starts, done, suites = {}, {}, {}
    kinds = Counter()
    terminal = []
    for line in raw.decode().splitlines():
        event = json.loads(line)
        kind = event['type']
        kinds[kind] += 1
        if kind == 'suite':
            suites[event['suite']['id']] = event['suite']['path']
        elif kind == 'testStart':
            test = event['test']
            audit.check(test['id'] not in starts, label + ' duplicate start')
            starts[test['id']] = test
        elif kind == 'testDone':
            test_id = event['testID']
            audit.check(test_id in starts and test_id not in done, label + ' completion lifecycle')
            done[test_id] = event
        elif kind == 'done':
            terminal.append(event['success'])
    audit.check(kinds['start'] == kinds['done'] == 1 and set(starts) == set(done), label + ' complete reporter lifecycle')
    cases = []
    for test_id, completion in done.items():
        if completion.get('hidden', False):
            audit.check(completion['result'] == 'success' and not completion['skipped'], label + ' failed hidden setup')
            continue
        test = starts[test_id]
        cases.append({'suite': suites[test['suiteID']], 'name': test['name'],
                      'result': completion['result'], 'skipped': completion['skipped']})
    audit.check(len(cases) == len({(c['suite'], c['name']) for c in cases}), label + ' distinct case identities')
    return {'cases': cases, 'counts': dict(Counter(c['result'] for c in cases)),
            'suites': sorted(suites.values()), 'terminal_success': terminal[0] if len(terminal) == 1 else None,
            'reporter_errors': kinds['error'], 'skipped': sum(c['skipped'] for c in cases)}


def dart_tokens(data):
    """Preserve literals/comments; ignore layout and optional closing commas."""
    pattern = (r'''r?\x27\x27\x27[\s\S]*?\x27\x27\x27|r?\x22\x22\x22[\s\S]*?\x22\x22\x22|'''
               r'''r?'(?:\\.|[^'\\])*'|r?"(?:\\.|[^"\\])*"|'''
               r'''//[^\n]*|/\*[\s\S]*?\*/|[A-Za-z_]\w*|\d+(?:\.\d+)?|[^\s]''')
    tokens = re.findall(pattern, data.decode())
    return [token for i, token in enumerate(tokens)
            if not (token == ',' and i + 1 < len(tokens) and tokens[i + 1] in (')', ']', '}'))]


def static_constants(data):
    tokens = dart_tokens(data)
    declarations = {}
    for start in range(len(tokens) - 1):
        if tokens[start:start + 2] != ['static', 'const']:
            continue
        end = tokens.index(';', start)
        assignment = tokens.index('=', start, end)
        declarations[tokens[assignment - 1]] = tokens[start:end + 1]
    return declarations


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    audit = Audit(args.repo)
    audit.check(audit.text('rev-parse', HEAD + '^') == BASE, 'Expected source parent')
    audit.check(audit.text('rev-parse', HEAD + '^{tree}') == TREE, 'Expected source tree')
    paths = audit.text('diff', '--name-only', BASE, HEAD).splitlines()
    expected = {
        FINAL + 'development-evidence.index.json', FINAL + 'development-evidence.tar.xz',
        FINAL + 'first-attempt-evidence.index.json', FINAL + 'first-attempt-evidence.tar.xz',
        FINAL + 'first-attempt.md', FINAL + 'plan.json',
        ARABIC, ARABIC_TEST, CONTROLLER, LANGUAGE_TEST, FOOTER_TEST,
    }
    audit.check(set(paths) == expected, 'Exact bounded source/evidence delta')
    before = {p: audit.blob(BASE, p) for p in [ARABIC, ARABIC_TEST, CONTROLLER, LANGUAGE_TEST, FOOTER_TEST]}
    after = {p: audit.blob(HEAD, p) for p in before}
    controller_implementation = lambda data: b'\n'.join(line for line in data.splitlines() if not line.lstrip().startswith(b'///'))
    doc_only = controller_implementation(before[CONTROLLER]) == controller_implementation(after[CONTROLLER])
    audit.check(doc_only, 'Controller implementation unchanged')

    marker = b'  // ---------------------- word tables (S9 frozen, L3, L4, L7, S10)'
    table_sections = {}
    for commit in [MAIN, BASE, HEAD]:
        text = audit.blob(commit, ARABIC)
        section = text[text.index(marker):]
        table_sections[commit] = {'bytes': len(section), 'sha256': sha256(section)}
    audit.check(len({x['sha256'] for x in table_sections.values()}) == 1, 'Broad Arabic word-table bytes unchanged')
    constants = {commit: static_constants(audit.blob(commit, ARABIC)) for commit in [MAIN, BASE, HEAD]}
    prior_constant_checks = [
        {'name': name, 'tokens_unchanged': constants[MAIN].get(name) == tokens == constants[HEAD].get(name),
         'token_sha256': sha256(json.dumps(tokens, ensure_ascii=False).encode())}
        for name, tokens in constants[BASE].items()
    ]
    audit.check(all(row['tokens_unchanged'] for row in prior_constant_checks), 'All preexisting Arabic static constants/tables unchanged')
    audit.check(set(constants[HEAD]) - set(constants[BASE]) == {'_tokenContinuation'}, 'Only shared boundary constant added')
    stable_paths = [
        'packages/quds_office_engine/lib/src/proofing/arabic_grammar_rules.dart',
        'packages/quds_office_engine/lib/src/proofing/arabic_morphology.dart',
        'packages/quds_office_engine/lib/src/proofing/arabic_writing_rules.dart',
        'packages/quds_arabic_morph/',
    ]
    stable = {commit: audit.tree(commit, stable_paths) for commit in [MAIN, BASE, HEAD]}
    stable_same = stable[MAIN] == stable[BASE] == stable[HEAD]
    audit.check(stable_same, 'Arabic base/T2/morphology files unchanged from captured main')
    mapping_start = b'final class _ArabicBareText {'
    mapping_end = b'enum _PhraseSpan {'
    sections = [text[text.index(mapping_start):text.index(mapping_end)] for text in [before[ARABIC], after[ARABIC]]]
    audit.check(sections[0] == sections[1], 'Semantic-mark/UTF-16 mapping unchanged')
    old_tests = before[ARABIC_TEST].decode()
    new_tests = after[ARABIC_TEST].decode()
    block_start = new_tests.index("  group('integration token boundaries',")
    block_end = new_tests.index("  group('word lists',", block_start)
    audit.check(new_tests[:block_start] + new_tests[block_end:] == old_tests, 'Existing Arabic tests retained byte-for-byte')
    boundary_block = new_tests[block_start:block_end]
    controls = re.findall(r"^      '([^']*)',$", boundary_block, re.M)
    audit.check(len(controls) == 11, 'Eleven added boundary controls')

    old_footer = before[FOOTER_TEST].decode()
    new_footer = after[FOOTER_TEST].decode()
    old_main_body = old_footer[old_footer.index('void main() {'):].rstrip()[:-1].rstrip()
    added_start = new_footer.index("  testWidgets('compact footer exposes partial status")
    prior_main_body = new_footer[new_footer.index('void main() {'):added_start].rstrip()
    audit.check(old_main_body == prior_main_body, 'All prior footer test bodies retained verbatim')
    added_footer_cases = re.findall(r"testWidgets\(\s*'([^']+)'", new_footer[added_start:])
    audit.check(len(added_footer_cases) == 3, 'Three explicit compact-footer controls')
    required_metrics = ['tester.view.devicePixelRatio = 1;', 'tester.view.physicalSize = viewport;',
                        'tester.view.resetPhysicalSize();', 'tester.view.resetDevicePixelRatio();',
                        'MediaQuery.sizeOf(tester.element(find.byType(QudsWordEditor)))']
    audit.check(all(fragment in new_footer for fragment in required_metrics), 'Viewport geometry and teardown are explicit')
    old_plan = json.loads(audit.blob(BASE, FINAL + 'plan.json'))
    new_plan = json.loads(audit.blob(HEAD, FINAL + 'plan.json'))
    audit.check(old_plan['groups'] == new_plan['groups'], 'Qualification suite selection unchanged')
    for key in ['analysis', 'format']:
        audit.check(set(new_plan[key]) == set(old_plan[key]) | {LANGUAGE_TEST}, 'Updated static target set: ' + key)

    rejected, rejected_archive = unpack(audit, 'first-attempt')
    prefix = 'qualification-main/'
    receipt = json.loads(rejected[prefix + 'verification.json'])
    audit.check(receipt['source_commit'] == BASE and receipt['success'] is False, 'Original failed receipt retained')
    for path, digest in receipt['manifest_sha256'].items():
        audit.check(sha256(rejected[prefix + path]) == digest, 'Rejected manifest hash: ' + path)
    source = json.loads(rejected[prefix + 'source-before.json'])
    runtime = json.loads(rejected[prefix + 'environment-before.json'])
    audit.check(source == json.loads(rejected[prefix + 'source-after.json']), 'Rejected source stable')
    audit.check(runtime == json.loads(rejected[prefix + 'environment-after.json']), 'Rejected runtime stable')
    original_source = audit.source_hashes(source, BASE)
    rejected_cases, rejected_groups = [], []
    for run in receipt['runs']:
        raw = rejected[prefix + run['log']]
        audit.check(sha256(raw) == run['log_sha256'], 'Rejected log hash: ' + run['name'])
        compressed = rejected[prefix + run['compressed_log']]
        audit.check(sha256(compressed) == run['compressed_log_sha256'] and gzip.decompress(compressed) == raw,
                    'Rejected compressed log: ' + run['name'])
        if 'cases_file' not in run:
            audit.check(run['exit_code'] == 0, 'Rejected static check succeeded: ' + run['name'])
            continue
        parsed = events(audit, raw, 'Rejected ' + run['name'])
        audit.check(parsed['counts'].get('success', 0) == run['passed'] and
                    parsed['counts'].get('failure', 0) + parsed['counts'].get('error', 0) == run['failed'],
                    'Rejected raw/receipt counts: ' + run['name'])
        group = next(g for g in old_plan['groups'] if g['name'] == run['name'])
        def canonical(path):
            if '/quds_office_suite/' in path:
                return path.split('/quds_office_suite/', 1)[1]
            return path if path.startswith('packages/') else group['cwd'] + '/' + path
        requested = {group['cwd'] + '/' + p for p in group['tests']}
        audit.check({canonical(p) for p in parsed['suites']} == requested, 'Rejected exact suite coverage: ' + run['name'])
        for case in parsed['cases']:
            case['suite'] = canonical(case['suite'])
        rejected_cases.extend(parsed.pop('cases'))
        rejected_groups.append({'name': run['name'], **parsed})
    counts = dict(Counter(c['result'] for c in rejected_cases))
    audit.check(len(rejected_cases) == len({(c['suite'], c['name']) for c in rejected_cases}), 'Rejected unique identities')
    failed_or_error = counts.get('failure', 0) + counts.get('error', 0)
    audit.check(counts.get('success', 0) == receipt['passed'] and failed_or_error == receipt['failed'] and not any(c['skipped'] for c in rejected_cases), 'Rejected complete totals')

    development, development_archive = unpack(audit, 'development')
    red_receipt = json.loads(development['diagnostics/arabic-boundary/red-receipt.json'])
    red_log = development['diagnostics/arabic-boundary/red.jsonl']
    audit.check(red_receipt['base'] == BASE and red_receipt['exit_code'] == 1, 'Arabic RED receipt attribution')
    audit.check(sha256(red_log) == red_receipt['stdout_sha256'], 'Arabic RED log hash')
    audit.check(red_receipt['source_sha256'][ARABIC] == sha256(before[ARABIC]) and
                red_receipt['source_sha256'][ARABIC_TEST] == sha256(after[ARABIC_TEST]), 'Arabic RED controlled source/test inputs')
    red = events(audit, red_log, 'Arabic boundary RED')
    audit.check(len(red['cases']) == 11 and red['counts'] == {'failure': 9, 'success': 2}, 'Arabic RED counts')
    development_results = []
    for item in json.loads(development['diagnostics/corrected-preflight/receipts.json']):
        name = item['name']
        raw = development['diagnostics/corrected-preflight/' + name + '.jsonl']
        audit.check(item['exit_code'] == 0 and sha256(raw) == item['.jsonl_sha256'], 'GREEN receipt/log: ' + name)
        for path, digest in item['selected_test_sha256'].items():
            audit.check(sha256(audit.blob(HEAD, item['cwd'] + '/' + path)) == digest, 'GREEN selected source: ' + path)
        parsed = events(audit, raw, name)
        audit.check(parsed['terminal_success'] is True and parsed['reporter_errors'] == parsed['skipped'] == 0 and set(parsed['counts']) == {'success'}, 'GREEN complete pass: ' + name)
        if name == 'arabic-extended-green':
            red_names = {c['name'] for c in red['cases']}
            matching = [c for c in parsed['cases'] if c['name'] in red_names]
            audit.check(len(matching) == 11 and all(c['result'] == 'success' for c in matching), 'Identical eleven RED/GREEN identities')
        parsed.pop('cases')
        development_results.append({'name': name, **parsed})
    snapshot_checks = []
    for snapshot, source_path in [('audit-studio/studio_review_status_test.patched.dart', FOOTER_TEST),
                                  ('audit-studio/word_text_proofing_controls_test.patched.dart', LANGUAGE_TEST)]:
        reviewed = development[snapshot]
        committed = after[source_path]
        same_tokens = dart_tokens(reviewed) == dart_tokens(committed)
        audit.check(same_tokens, 'Saved review source snapshot tokens: ' + source_path)
        snapshot_checks.append({'snapshot': snapshot, 'target': source_path,
                                'snapshot_sha256': sha256(reviewed), 'committed_sha256': sha256(committed),
                                'byte_identical': reviewed == committed,
                                'tokens_identical_ignoring_layout_and_optional_trailing_commas': same_tokens})

    report = {
        'schema': 1, 'audited_at_utc': datetime.now(timezone.utc).isoformat(),
        'source': HEAD, 'tree': TREE, 'parent': BASE, 'captured_main': MAIN,
        'auditor_sha256': sha256(Path(__file__).read_bytes()),
        'exact_changed_paths': paths,
        'application_logic_changes': [ARABIC],
        'controller_documentation_only': doc_only,
        'arabic_table_sections': table_sections,
        'existing_arabic_static_constants': prior_constant_checks,
        'unchanged_arabic_base_grammar_morphology': {'records': len(stable[HEAD]), 'identical_from_main': stable_same, 'entries': stable[HEAD]},
        'semantic_mark_and_utf16_mapping_unchanged': sections[0] == sections[1],
        'arabic_boundary_control_count': len(controls),
        'existing_arabic_cases_retained_verbatim': new_tests[:block_start] + new_tests[block_end:] == old_tests,
        'prior_footer_test_bodies_retained_verbatim': old_main_body == prior_main_body,
        'new_compact_footer_cases': added_footer_cases,
        'review_findings': [
            'Arabic phrase/date/implausible-year/double-future patterns now use the existing Unicode letter/mark/number/connector/joiner continuation class, preserving semantic marks and original offset mapping.',
            'Word language code is unchanged in this delta. Reconciled tests assert active-slot changes while retaining inactive Latin/complex-script/East-Asian metadata, style, formatting, undo/redo and DOCX serialization.',
            'Footer production code is unchanged. Test view metrics now agree with the requested RenderView geometry; all prior test bodies remain intact and three compact-state controls cover partial, paused and waiting states.',
        ],
        'new_archives': [rejected_archive, development_archive],
        'rejected_run': {'source': BASE, 'success': False, 'case_executions': len(rejected_cases),
                         'counts': counts, 'failed_or_error_cases': failed_or_error,
                         'suites': len({c['suite'] for c in rejected_cases}),
                         'source_records': len(source), 'runtime_records': len(runtime),
                         'source_hash_verification': original_source,
                         'failures': [c for c in rejected_cases if c['result'] != 'success'],
                         'groups': rejected_groups, 'contribution_to_accepted_totals': 0},
        'development': {'arabic_red_counts': red['counts'], 'green': development_results,
                        'reviewed_source_snapshots': snapshot_checks,
                        'contribution_to_accepted_totals': 0},
        'fresh_test_executions_by_auditor': 0, 'repository_mutations_by_auditor': 0,
        'github_actions_calls': 0, 'errors': audit.errors, 'passed': not audit.errors,
        'scope': 'Independent immutable source/evidence preservation review. Fresh qualification on this source is performed separately by the owning session.'}
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({k: report[k] for k in ['source','tree','application_logic_changes','controller_documentation_only','arabic_boundary_control_count','errors','passed']}))
    print(json.dumps({'rejected': counts, 'rejected_suites': report['rejected_run']['suites'],
                      'unchanged_arabic_records': len(stable[HEAD]), 'new_archives': len(report['new_archives'])}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
