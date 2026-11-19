from pathlib import Path
import hashlib
import json
import shutil
import subprocess

ROOT = Path('/workspace/scratch/f0520e768bc8')
REPO = ROOT / 'quds_office_suite'
STAGE = ROOT / 'publication-tls/stage/tls-review'
COMMIT = '5569c055a021c893e941fc54d40499ad9d96a5db'
TREE = '9d2c815eda61378fbc4b234124e8e7c9cfeacb5b'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO)


def save(name, data):
    target = STAGE / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)


def copy(source, destination):
    save(destination, source.read_bytes())


def outcomes(path):
    events = [json.loads(line) for line in path.read_text().splitlines() if line]
    tests = {event['test']['id']: event['test'] for event in events if event['type'] == 'testStart'}
    suites = {event['suite']['id']: event['suite']['path'] for event in events if event['type'] == 'suite'}
    ends = [event for event in events if event['type'] == 'testDone' and not event.get('hidden')]
    count = {result: sum(event.get('result') == result for event in ends)
             for result in ('success', 'failure', 'error')}
    count['skipped'] = sum(bool(event.get('skipped')) for event in ends)
    count['reporter_errors'] = sum(event['type'] == 'error' for event in events)
    by_file = {}
    for event in ends:
        name = suites[tests[event['testID']]['suiteID']]
        if name.startswith(str(REPO) + '/'):
            name = name[len(str(REPO)) + 1:]
        by_file[name] = by_file.get(name, 0) + 1
    return {'results': count, 'files': by_file,
            'terminal': [event for event in events if event['type'] == 'done']}


assert git('rev-parse', COMMIT + '^{tree}').decode().strip() == TREE
incoming = json.loads((ROOT / 'review/TLS/incoming-tls-review.json').read_text())
original = json.loads((ROOT / 'review/TLS/tls-test-review.json').read_text())
fetch = json.loads((ROOT / 'review/FETCH-delimiter/final-fetch-review.json').read_text())
expected = dict(incoming['development_source_hashes'])
for entry in original['files']:
    expected[entry['path']] = entry['sha256']
expected.update(fetch['source_sha256'])
fixed_paths = [
    'third_party/enough_mail/test/src/imap/raw_fetch_parser_test.dart',
    'packages/quds_mail_transport/test/native_provider_test.dart',
    'packages/quds_mail_transport/test/native_tls_cancellation_test.dart',
    'packages/quds_mail_transport/test/native_tls_round_trip_test.dart',
    'packages/quds_mail_transport/test/native_tls_test.dart',
    'third_party/enough_mail/test/mail/mail_client_pop_test.dart',
    'third_party/enough_mail/test/mail/mail_client_starttls_test.dart',
    'third_party/enough_mail/test/mail/mail_client_oauth_test.dart',
    'third_party/enough_mail/test/mail/mail_client_delete_test.dart',
    'third_party/enough_mail/test/mail/mail_client_reconnect_test.dart',
    'third_party/enough_mail/test/mail/mail_client_send_test.dart',
]
supporting_paths = [
    'third_party/enough_mail/lib/src/private/imap/imap_response.dart',
    'third_party/enough_mail/lib/src/private/imap/imap_response_line.dart',
    'third_party/enough_mail/lib/src/private/imap/imap_response_reader.dart',
    'third_party/enough_mail/lib/src/imap/imap_client.dart',
    'packages/quds_mail_transport/lib/src/native/provider.dart',
]
proofs = []
source_hashes = {}
for name in sorted(set(expected) | set(fixed_paths) | set(supporting_paths)):
    content = git('show', COMMIT + ':' + name)
    actual = digest(content)
    if name in expected:
        assert actual == expected[name], ('Reviewed source changed', name)
    assert (REPO / name).read_bytes() == content, ('Working/committed bytes differ', name)
    if name in supporting_paths:
        assert git('show', '54c36e40daa7b17d73801dac1fd12f110b24017f:' + name) == content
    source_hashes[name] = actual
    proofs.append({'path': name, 'sha256': actual, 'bytes': len(content),
                   'git_blob': git('rev-parse', COMMIT + ':' + name).decode().strip(),
                   'matches_captured_development_manifest': name in expected})
    save('source/fixed/' + name, content)

selected_tls = [
    'tls-lifecycle-review.json', 'tls-test-review.json', 'incoming-tls-review.json',
    'committed-source-verification.json', 'baseline-reproduction.json', 'baseline-source.txt',
    'baseline-package-config.json', 'baseline-stalled-handshake.jsonl',
    'baseline-stalled-handshake.stderr',
    'final-development-tls-nine.jsonl', 'final-development-tls-nine.stderr',
    'native-provider-after-raw-helper.jsonl', 'native-provider-after-raw-helper.stderr',
    'mail-loopback-after-raw-helper.jsonl', 'mail-loopback-after-raw-helper.stderr',
    'final-development-analysis.log', 'final-development-format.log',
    'development-tls-tests.jsonl', 'development-tls-tests-env.jsonl',
    'development-tls-tests-repository.jsonl', 'development-tls-idle-producer.jsonl',
    'development-incoming-tls-adapted.jsonl', 'development-direct-abort-baseline.jsonl',
    'development-direct-abort-baseline-inputs.json',
    'development-incoming-tls-adapted-final.jsonl',
    'final-union-focused-development.jsonl', 'final-union-focused-development.stderr',
    'final-union-analysis.log', 'final-union-format.log', 'test-design-report.json',
]
for name in selected_tls:
    copy(ROOT / 'review/TLS' / name, 'review/TLS/' + name)
selected_fetch = [
    'baseline.jsonl', 'baseline.stderr', 'baseline-inputs.json', 'baseline-package-config.json',
    'final-fetch-review.json', 'raw_fetch_parser-final.patch',
    'raw_fetch_parser_test-final.patch', 'native_provider_test-final.patch',
    'imap_fixture-final.patch',
]
for name in selected_fetch:
    copy(ROOT / 'review/FETCH-delimiter' / name, 'review/FETCH-delimiter/' + name)
copy(ROOT / 'review/TLS/original-client_base-c634f494.dart',
     'source/baseline/client_base-c634f494.dart')
copy(ROOT / 'review/TLS/direct-abort-baseline-client_base.dart',
     'source/baseline/client_base-before-abort-signal.dart')
copy(ROOT / 'review/FETCH-delimiter/baseline-raw-fetch-parser.dart',
     'source/baseline/raw_fetch_parser-99dd7307.dart')
copy(ROOT / 'review/TLS/native_tls_cancellation_baseline_test.dart',
     'replay/native_tls_cancellation_baseline_test.dart')
copy(ROOT / 'review/TLS/pubspec.yaml', 'replay/original-external-pubspec.yaml')
copy(ROOT / 'review/TLS/analysis_options.yaml', 'replay/original-external-analysis_options.yaml')

stages = {
    'original_stalled_handshake_baseline': outcomes(ROOT / 'review/TLS/baseline-stalled-handshake.jsonl'),
    'original_nine_development': outcomes(ROOT / 'review/TLS/final-development-tls-nine.jsonl'),
    'direct_api_abort_baseline': outcomes(ROOT / 'review/TLS/development-direct-abort-baseline.jsonl'),
    'fetch_delimiter_baseline': outcomes(ROOT / 'review/FETCH-delimiter/baseline.jsonl'),
    'final_focused_union_development': outcomes(ROOT / 'review/TLS/final-union-focused-development.jsonl'),
    'adapted_incoming_tls_development': outcomes(ROOT / 'review/TLS/development-incoming-tls-adapted-final.jsonl'),
}
report = {
    'schema': 'quds-independent-tls-fetch-review-v1',
    'status': 'Independent source review complete; no unresolved concrete blocker in the reviewed scope.',
    'source_commit': COMMIT,
    'source_tree': TREE,
    'source_url': 'https://github.com/CrispStrobe/quds_office_suite/commit/' + COMMIT,
    'bounded_reconciliation_cutoff': '2026-11-19T07:15:06Z',
    'source_sha256': source_hashes,
    'source_proofs': proofs,
    'sdk_sha256': json.loads((ROOT / 'review/TLS/tls-lifecycle-review.json').read_text())['sdk_sha256'],
    'baseline_source_sha256': {
        name: digest((STAGE / name).read_bytes())
        for name in ['source/baseline/client_base-c634f494.dart',
                     'source/baseline/client_base-before-abort-signal.dart',
                     'source/baseline/raw_fetch_parser-99dd7307.dart']
    },
    'source_binding': 'Exact published Git blobs match all captured current TLS/parser/test manifests. Supporting reader/client/provider files remain byte-identical to the independently reviewed 54c36e40 source. The original eight TLS files at 54c36e40 were separately verified in committed-source-verification.json.',
    'reviewed_incoming_heads': [incoming['incoming_commit'], incoming['incoming_tls_source_parent'],
                               '99dd7307', '4624218f9468eeeac07f1f100ac0e4bb6b050a17'],
    'findings_and_resolutions': [
        {'id': 'T12', 'finding': 'Default TLS cancellation lost the original socket owner during handshake.',
         'resolution': 'Use public RawSocket ownership through implicit TLS and STARTTLS; cancel pending connection tasks and close the TCP owner on abort.',
         'baseline': 'Four actual ClientHello/peer-close cases fail on exact c634f494 ClientBase; the original nine-case fixed development union passes.'},
        {'id': 'TLS-established-owner', 'finding': 'Secure wrapper closure may defer underlying TCP close while encrypted output is queued.',
         'resolution': 'Retain original TCP after handshake and close it first during hard abort; preserve Socket-returning seams.',
         'evidence': 'Deterministic distinct-owner test verifies TCP close invocation before unresolved synthetic secure close. Real trusted TLS tests cover data exchange and authentication.'},
        {'id': 'TLS-direct-operation-completion', 'finding': 'Physical TCP closure need not settle the SDK handshake future.',
         'resolution': 'Race public connect/upgrade waits with a per-connection abort signal, observing original futures with late-generation disposal. Update secure connection metadata after successful STARTTLS.',
         'baseline': 'Two direct real-loopback API cases fail before signal port; both pass in the adapted 17-case union. Captured pre-port source hash has been reconstructed exactly and is included.'},
        {'id': 'FETCH-delimiter', 'finding': 'Malformed FETCH keyword delimiters bypassed strict parsing and could produce false missing-UID tombstones.',
         'resolution': 'Recognize keyword at response position using IMAP atom delimiters, then enforce strict prefix/root/list/UID/literal checks. Preserve status exclusions, FETCHX and unrelated FLAGS data.',
         'baseline': 'Exact 99dd parser yields 15 expected failures and three passing controls across the finite matrix. Fixed full parser/provider suites contain 26 and 69 passing cases.'},
        {'id': 'incoming-UID-grammar', 'finding': 'Generic integer parsing admits noncanonical signed/hex/leading-zero UID representations.',
         'resolution': 'Retain incoming 99dd canonical decimal UID grammar and its six body/notification regressions.'},
    ],
    'finite_review_conclusion': 'Latest 4624218f cancellation/disconnect/StreamIterator safeguards are already represented by the selected implementation. No further source expansion was required.',
    'primary_protocol_reference': 'https://www.rfc-editor.org/rfc/rfc3501.html#section-9',
    'development_stages': stages,
    'counting_policy': 'All counts in this archive are development or expected-failure reproduction counts and are excluded from final qualification totals. Repeated eight/nine-case runs are not additive. The final focused 119 and adapted 17 runs contain 136 distinct cases across 11 files, but are not substitutes for the parent final gate.',
    'fixed_replay_test_paths': fixed_paths,
    'replay_scope': 'Replay script is supplied and syntax-reviewed, not executed during the final source freeze. It reconstructs isolated library overlays and never runs pub or changes Git/source. Recorded outputs remain original bytes.',
    'limitations': [
        'Physical hard-close guarantee covers the default owned native transport. Arbitrary manually supplied SDK Socket upgrades retain their previous handoff ownership limitation; direct callers now receive explicit abort failure.',
        'Runtime development verification uses Linux with pinned Flutter 3.47.8 / Dart 3.13.7. No external mail server, installed OS app, or other-platform acceptance is claimed.',
        'Certificates and keys are fixed intentionally public test fixtures. No global trust installation or production certificate bypass is used.',
        'Final qualification results are intentionally not asserted here; the parent owns and publishes those results separately.',
    ],
    'excluded_material': ['Full baseline-enough-mail copies', 'Runtime and package cache', 'Git database', 'GitHub Actions/CI status'],
}
save('review/final-source-review.json', (json.dumps(report, indent=2, sort_keys=True) + '\n').encode())
print(json.dumps({'source_commit': COMMIT, 'source_tree': TREE,
                  'source_files_verified': len(proofs), 'captured_manifest_matches': len(expected),
                  'final_focused_cases': stages['final_focused_union_development']['results']['success'],
                  'incoming_cases': stages['adapted_incoming_tls_development']['results']['success']}))
