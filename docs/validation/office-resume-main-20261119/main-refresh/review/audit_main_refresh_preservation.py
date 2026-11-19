#!/usr/bin/env python3
"""Read-only preservation audit of the bounded 76fe761f main reconciliation.

Reads staged blobs by default, or immutable --target when supplied. Never writes
an index/tree or fetches objects. This is source/evidence verification, not a
product-test run or a claim that earlier receipts qualify the merged source.
"""
import argparse
import datetime
import hashlib
import io
import json
import pathlib
import re
import subprocess
import tarfile

MAIN = "76fe761f1c97c31ca8d8add405aa54c436a336aa"
QUALIFIED = "0bd53e3e2b0d75ae48a4d7807dcddd123ab477f9"
PUBLISHED = "fb402a5d18e588753744e533c2c96609afd73d94"
PREPARED = "9c9f580c193bab32594697f44f141d5f1269c622"
EVIDENCE = "docs/validation/office-resume-main-20261119/"
REFRESH = EVIDENCE + "main-refresh/"
MORPH = "packages/quds_arabic_morph/"
EDITOR = "packages/quds_office_editor/"
EXAMPLE = EDITOR + "example/"
EXPECTED = {
    MORPH + "lib/src/morph_analysis.dart": "qualified portable numeric decoder",
    MORPH + "test/arabic_morph_unit_test.dart": "qualified numeric controls",
    EXAMPLE + "lib/studio_mail_native.dart": "confirmed submission cleanup branch",
    EXAMPLE + "lib/studio_strings.dart": "Dart formatter layout only",
    EXAMPLE + "test/studio_mail_test.dart": "one confirmed submission regression",
    EXAMPLE + "test/studio_review_status_test.dart": "13-case footer coverage union",
    EDITOR + "lib/src/embed/office_controller.dart": "qualified active-slot API documentation",
    EDITOR + "test/word_text_proofing_controls_test.dart": "qualified stronger inactive-slot assertions",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def dart_tokens(data, comments=True):
    pattern = (r"r?'''[\s\S]*?'''|r?\"\"\"[\s\S]*?\"\"\"|"
               r"r?'(?:\\.|[^'\\])*'|r?\"(?:\\.|[^\"\\])*\"|"
               r"//[^\n]*|/\*[\s\S]*?\*/|[A-Za-z_]\w*|\d+(?:\.\d+)?|[^\s]")
    values = re.findall(pattern, data.decode())
    return [value for i, value in enumerate(values)
            if (comments or not value.startswith(("//", "/*")))
            and not (value == ',' and i + 1 < len(values)
                     and values[i + 1] in (')', ']', '}'))]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True)
    parser.add_argument('--target')
    parser.add_argument('--prepared-tree', default=PREPARED)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    repo = pathlib.Path(args.repo)

    def git(*values):
        return subprocess.check_output(
            ['git', '--no-lazy-fetch', '-C', str(repo), *values])

    def tree(rev):
        result = {}
        for row in git('ls-tree', '-r', '-z', rev).split(b'\0'):
            if not row:
                continue
            header, path = row.split(b'\t', 1)
            mode, kind, oid = header.decode().split()
            result[path.decode()] = [mode, kind, oid]
        return result

    def index():
        result = {}
        for row in git('ls-files', '--stage', '-z').split(b'\0'):
            if not row:
                continue
            header, path = row.split(b'\t', 1)
            mode, oid, stage = header.decode().split()
            if stage != '0':
                raise ValueError('Unmerged index entry: ' + path.decode())
            result[path.decode()] = [mode, 'commit' if mode == '160000' else 'blob', oid]
        return result

    def body(mapping, path):
        return git('cat-file', 'blob', mapping[path][2])

    def differences(before, after, predicate=lambda _: True):
        return [{'path': p, 'before': before.get(p), 'after': after.get(p)}
                for p in sorted(set(before) | set(after))
                if predicate(p) and before.get(p) != after.get(p)]

    def product(p):
        return p.startswith(('packages/', 'third_party/'))

    def evidence(p):
        return p.startswith(('docs/validation/', 'docs/evidence/'))

    def fingerprint(mapping):
        return sha(json.dumps(mapping, sort_keys=True, separators=(',', ':')).encode())

    incoming = tree(MAIN)
    qualified = tree(QUALIFIED)
    published = tree(PUBLISHED)
    prepared = tree(args.prepared_tree)
    current = tree(args.target) if args.target else index()
    changes = differences(incoming, current, product)
    checks = []

    def check(name, passed, **detail):
        checks.append({'name': name, 'passed': bool(passed), **detail})

    check('source_equals_prepared_tree', current == prepared)
    check('exact_eight_product_exceptions',
          {r['path'] for r in changes} == set(EXPECTED), actual=changes)
    for path in (MORPH + 'lib/src/morph_analysis.dart',
                 MORPH + 'test/arabic_morph_unit_test.dart',
                 EDITOR + 'test/word_text_proofing_controls_test.dart'):
        check('qualified_blob_retained:' + path, current.get(path) == qualified.get(path))

    path = EXAMPLE + 'lib/studio_strings.dart'
    check('studio_strings_format_only', dart_tokens(body(incoming, path)) ==
          dart_tokens(body(current, path)))
    path = EDITOR + 'lib/src/embed/office_controller.dart'
    check('incoming_controller_code_retained', dart_tokens(body(incoming, path), False) ==
          dart_tokens(body(current, path), False))
    doc_start = b'  /// Changes the proofing language of exactly [target].'
    doc_end = b'  bool setTextProofingLanguage('
    current_body = body(current, path)
    qualified_body = body(qualified, path)
    check('qualified_active_slot_documentation_retained',
          current_body[current_body.index(doc_start):current_body.index(doc_end)] ==
          qualified_body[qualified_body.index(doc_start):qualified_body.index(doc_end)])

    path = EXAMPLE + 'lib/studio_mail_native.dart'
    old = body(incoming, path)
    new = body(current, path)
    begin = new.index(b'    } on mail.MailSendPostSubmissionException {')
    end = new.index(b'    } on Object {', begin)
    branch = new[begin:end]
    check('mail_native_only_typed_outcome_branch_added', new[:begin] + new[end:] == old)
    check('mail_confirmed_outcome_clears_draft_and_uncertainty', all(s in branch for s in [
        b'_currentSession(client, generation)', b'_busy = false;', b'_draft = null;',
        b'_submissionUncertain = false;', b'_notice = widget.strings.mailSubmissionAccepted;',
    ]) and b'mailSubmissionUncertain' not in branch)

    path = EXAMPLE + 'test/studio_mail_test.dart'
    old = body(incoming, path)
    new = body(current, path)
    marker = b"  testWidgets(\n    'confirmed submission clears the draft when outgoing cleanup fails',"
    begin = new.index(marker)
    end = new.index(b'  for (final fail in [false, true]) {', begin)
    regression = new[begin:end]
    check('mail_test_only_one_regression_added', new[:begin] + new[end:] == old)
    check('mail_regression_checks_accepted_no_retry_and_empty_draft', all(s in regression for s in [
        b'MailSendPostSubmissionException', b'cleanupError:',
        b'mailSubmissionAccepted', b'mailSubmissionUncertain', b'mailRetryAcknowledgement',
        b'private outgoing cleanup details', b'client.sent, hasLength(1)',
        b'_strings.to', b'_strings.subject', b'find.byType(QudsWordEditor)', b'isEmpty',
    ]))

    path = EXAMPLE + 'test/studio_review_status_test.dart'
    old = body(qualified, path)
    new = body(current, path)
    incoming_footer = body(incoming, path)
    check('qualified_footer_fixture_and_ten_cases_retained_verbatim',
          old.endswith(b'}\n') and new.startswith(old[:-2]))
    marker = b'  for (final language in ['
    incoming_block = incoming_footer[incoming_footer.rindex(marker):-2]
    new_block = new[new.rindex(marker):-2]
    check('incoming_three_locale_footer_controls_retained',
          dart_tokens(incoming_block) == dart_tokens(new_block))

    path = 'packages/quds_office_engine/lib/src/proofing/arabic_extended_rules.dart'
    check('arabic_incoming_source_exact', current.get(path) == incoming.get(path))
    check('arabic_qualified_code_tokens_equal', dart_tokens(body(current, path), False) ==
          dart_tokens(body(qualified, path), False))
    path = 'packages/quds_office_engine/test/proofing/arabic_extended_rules_test.dart'
    check('arabic_tests_exact_both_parents', current.get(path) == incoming.get(path) == qualified.get(path))

    relocations = {
        EVIDENCE + 'README.md': REFRESH + 'incoming-overview-76fe761f.md',
        EVIDENCE + 'final/plan.json': REFRESH + 'incoming-final-plan-76fe761f.json',
    }
    old_evidence = {p: v for p, v in incoming.items() if evidence(p)}
    changed_evidence = [r for r in differences(incoming, current, evidence) if r['before'] is not None]
    check('only_two_incoming_evidence_paths_relocated',
          {r['path'] for r in changed_evidence} == set(relocations), actual=changed_evidence)
    for original, replacement in relocations.items():
        check('incoming_evidence_exact_copy:' + original,
              incoming.get(original) == current.get(replacement), destination=replacement)
    qualified_final = {p: v for p, v in qualified.items() if p.startswith(EVIDENCE + 'final/')}
    check('qualified_final_evidence_exact',
          all(current.get(p) == v for p, v in qualified_final.items()),
          records=len(qualified_final))
    published_final = {p: v for p, v in published.items() if p.startswith(EVIDENCE + 'final/')}
    current_final = {p: v for p, v in current.items() if p.startswith(EVIDENCE + 'final/')}
    check('all_published_qualified_receipts_retained_exact',
          current_final == published_final, records=len(published_final))
    for path in ('pubspec.lock', 'pubspec.yaml'):
        check('root_dependency_manifest_exact_both_parents:' + path,
              current.get(path) == incoming.get(path) == qualified.get(path))

    plans = {}
    for name, count in [('native-plan.json', 25), ('node-plan.json', 4)]:
        plan = json.loads(body(current, REFRESH + name))
        suites = [group['cwd'] + '/' + test for group in plan['groups'] for test in group['tests']]
        check('plan_suite_count:' + name, len(suites) == count and len(set(suites)) == count,
              suites=len(suites), unique_suites=len(set(suites)))
        check('plan_references_existing_tests:' + name, all(p in current for p in suites))
        plans[name] = {'groups': len(plan['groups']), 'suites': suites,
                       'analysis_paths': plan['analysis'], 'format_paths': plan['format'],
                       'sha256': sha(body(current, REFRESH + name))}
    check('native_static_scope_45_paths',
          len(plans['native-plan.json']['analysis_paths']) == 45 and
          len(plans['native-plan.json']['format_paths']) == 45)

    archive_path = REFRESH + 'development-evidence.tar.xz'
    archive = body(current, archive_path)
    archive_index = json.loads(body(current, REFRESH + 'development-evidence.index.json'))
    check('development_archive_hash_and_size',
          sha(archive) == archive_index['sha256'] and len(archive) == archive_index['bytes'])
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:xz') as tar:
        members = {m.name: tar.extractfile(m).read() for m in tar if m.isfile()}
    expected_members = {m['path']: m for m in archive_index['members']}
    check('development_archive_exact_62_members',
          len(members) == archive_index['member_count'] == 62 and set(members) == set(expected_members))
    check('development_archive_member_hashes', all(
        len(data) == expected_members[name]['bytes'] and sha(data) == expected_members[name]['sha256']
        for name, data in members.items()))
    development = {}
    for color, expected_success in [('red', False), ('green', True)]:
        path = 'diagnostics/main-refresh/confirmed-send-' + color + '.jsonl'
        events = [json.loads(line) for line in members[path].splitlines() if line.strip()]
        terminals = [row for row in events if row.get('type') == 'done']
        starts = [row for row in events if row.get('type') == 'testStart' and
                  'confirmed submission clears the draft when outgoing cleanup fails' in row['test']['name']]
        ids = {row['test']['id'] for row in starts}
        results = [row for row in events if row.get('type') == 'testDone' and row['testID'] in ids]
        check('retained_confirmed_send_' + color + '_outcome',
              len(terminals) == 1 and terminals[0]['success'] is expected_success and
              len(starts) == len(results) == 1 and results[0]['result'] ==
              ('success' if expected_success else 'error'))
        if color == 'red':
            messages = '\n'.join(row.get('message', '') for row in events if row.get('type') == 'print')
            check('red_is_missing_accepted_notice_assertion',
                  'TestFailure' in messages and 'Found 0 widgets with text' in messages and
                  'The sending server accepted the message.' in messages)
        development[color] = {'selected_case_starts': len(starts), 'selected_case_completions': len(results),
                              'result': results[0]['result'] if results else None,
                              'terminal': terminals}

    observed = tree(args.target) if args.target else index()
    check('observed_source_snapshot_stable', current == observed)
    output = {
        'status': 'pass' if all(c['passed'] for c in checks) else 'fail',
        'observed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'target': args.target or 'staged-index',
        'prepared_tree': args.prepared_tree,
        'incoming_main': MAIN,
        'qualified_source': QUALIFIED,
        'qualified_publication': PUBLISHED,
        'qualified_publication_final_records_preserved': len(published_final),
        'qualified_source_receipts_are_not_merged_source_qualification': True,
        'entry_map_sha256': fingerprint(current),
        'product_entry_map_sha256': fingerprint({p: v for p, v in current.items() if product(p)}),
        'incoming_product_records': sum(product(p) for p in incoming),
        'incoming_product_records_exact': sum(product(p) and current.get(p) == v for p, v in incoming.items()),
        'product_exceptions': [{**row, 'disposition': EXPECTED.get(row['path'])} for row in changes],
        'incoming_evidence_records': len(old_evidence),
        'incoming_evidence_records_exact_at_original_path': sum(current.get(p) == v for p, v in old_evidence.items()),
        'incoming_evidence_relocations': relocations,
        'development_archive': {'path': archive_path, 'sha256': sha(archive), 'members': len(members),
                                'focused_red_green_receipts': development},
        'plans': plans,
        'checks': checks,
        'limitations': ['No product tests launched by this audit.',
                       'No Git index/tree writes, fetch, or Actions access.',
                       'Development RED/GREEN receipts are retained focused evidence, not final qualification.',
                       'Runtime package-config/graph preservation is recorded by the root run, not independently established by this Git-only comparison.'],
    }
    if args.target:
        output['actual_tree'] = git('rev-parse', args.target + '^{tree}').decode().strip()
        output['actual_parents'] = git('show', '-s', '--format=%P', args.target).decode().strip().split()
    pathlib.Path(args.output).write_text(json.dumps(output, indent=2) + '\n')
    print(json.dumps({k: v for k, v in output.items() if k in [
        'status', 'target', 'prepared_tree', 'actual_tree', 'actual_parents',
        'incoming_product_records', 'incoming_product_records_exact',
        'incoming_evidence_records', 'incoming_evidence_records_exact_at_original_path']}))
    print(json.dumps({'failed_checks': [c for c in checks if not c['passed']],
                      'checks': len(checks), 'report': args.output}))
    raise SystemExit(0 if output['status'] == 'pass' else 1)


if __name__ == '__main__':
    main()
