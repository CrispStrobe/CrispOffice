#!/usr/bin/env python3
"""Seal closed local qualification records; never runs tests or contacts CI.

Usage: python3 build_evidence.py --runtime /path/to/runtime
The final forty-suite recheck must have a closed successful summary first.
"""
import argparse
from collections import Counter
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import tarfile

parser = argparse.ArgumentParser()
parser.add_argument('--runtime', required=True, type=Path)
args = parser.parse_args()
runtime = args.runtime.resolve()
destination = Path(__file__).resolve().parent
validation = destination.parent


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    return json.loads(path.read_text())


def encoded(value):
    # Invalid-surrogate rejection tests deliberately include those UTF-16 values
    # in their names. JSON escapes preserve the exact deduplication keys.
    return (json.dumps(value, ensure_ascii=True, indent=2) + '\n').encode()


def event_log(path):
    events = []
    for line in path.read_text().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if isinstance(event, dict):
            events.append(event)
    suites = {event['suite']['id']: event['suite']['path']
              for event in events if event.get('type') == 'suite'}
    tests = {event['test']['id']: event['test']
             for event in events if event.get('type') == 'testStart'}
    finished = {event['testID']: event for event in events
                if event.get('type') == 'testDone'}
    errors = [event for event in events if event.get('type') == 'error']
    ends = [event for event in events if event.get('type') == 'done']
    assert ends, f'Log is not closed: {path}'
    bad = {suites[tests[event['testID']]['suiteID']] for event in errors}
    keys = set()
    key_occurrences = Counter()
    results = Counter()
    for test_id, result in finished.items():
        test = tests[test_id]
        suite = suites[test['suiteID']]
        if result['result'] != 'success' or result.get('skipped'):
            bad.add(suite)
        if not result.get('hidden'):
            results['skipped' if result.get('skipped') else result['result']] += 1
            if result['result'] == 'success' and not result.get('skipped'):
                keys.add((suite, test['name']))
                key_occurrences[(suite, test['name'])] += 1
    return {'suites': set(suites.values()), 'bad': bad, 'keys': keys,
            'keyOccurrences': key_occurrences,
            'results': results, 'errors': errors, 'tests': tests,
            'success': ends[-1].get('success') is True}


initial_dir = runtime / 'final-word-validation'
recheck_dir = runtime / 'final-word-recheck'
initial_summary = read_json(initial_dir / 'summary.json')
recheck_summary = read_json(recheck_dir / 'summary.json')
assert recheck_summary['runnerSuccessful'] is True
assert not recheck_summary['changedInputs']
assert all(gate['exitCode'] == 0 for gate in recheck_summary['gates'].values())
assert initial_summary['counts'] == {
    'passed': 6213, 'failed': 46, 'skipped': 0, 'hiddenErrors': 0,
}
assert not initial_summary['changedInputs']
initial = event_log(initial_dir / 'macro-regressions.stdout')
assert len(initial['suites']) == 141 and len(initial['bad']) == 40
assert initial['results'] == Counter({'success': 6213, 'error': 46})
categories = Counter()
for error in initial['errors']:
    message = error.get('error', '')
    if 'No space left on device' in message or 'errno = 28' in message:
        categories['ENOSPC'] += 1
    elif 'LateInitializationError' in message:
        categories['dependentTeardown'] += 1
    elif 'expected' in message.lower() and 'column' in message.lower():
        categories['positionDiagnostic'] += 1
    else:
        categories['other'] += 1
assert categories == Counter({'ENOSPC': 43, 'dependentTeardown': 5,
                              'positionDiagnostic': 3})

rechecked_suites = set()
rechecked_keys = set()
rechecked_occurrences = Counter()
for receipt_path in sorted(recheck_dir.glob('macro-batch-*.json')):
    receipt = read_json(receipt_path)
    assert receipt['exitCode'] == 0
    batch = event_log(receipt_path.with_suffix('.stdout'))
    assert batch['success'] and not batch['bad'] and not batch['errors']
    assert not (rechecked_suites & batch['suites']), 'A suite was rechecked twice'
    rechecked_suites.update(batch['suites'])
    rechecked_keys.update(batch['keys'])
    rechecked_occurrences.update(batch['keyOccurrences'])
assert rechecked_suites == initial['bad']
original_good = initial['suites'] - initial['bad']
assert len(original_good) == 101
initial_keys = {key for key in initial['keys'] if key[0] in original_good}
initial_occurrences = Counter({key: count for key, count in initial['keyOccurrences'].items()
                               if key[0] in original_good})
assert not (initial_keys & rechecked_keys)
accepted_keys = initial_keys | rechecked_keys
accepted_occurrences = initial_occurrences + rechecked_occurrences
assert {suite for suite, _ in accepted_keys} == initial['suites']

first_inputs = read_json(initial_dir / 'inputs-after.json')
last_inputs = read_json(recheck_dir / 'inputs-before.json')
changed_between = sorted(key for key in first_inputs.keys() | last_inputs.keys()
                         if first_inputs.get(key) != last_inputs.get(key))
engine_production_changes = [key for key in changed_between
                            if key.startswith('packages/quds_office_engine/lib/')]
assert not engine_production_changes
fixture_correction = 'packages/quds_office_engine/test/fixtures/vba_conformance/word_cell_paragraphs_v1.json'
assert changed_between == [fixture_correction], changed_between

coverage = {
    'schemaVersion': 1,
    'method': 'Select every nonhidden successful test from the 101 wholly passing original suites, and every nonhidden successful test from the complete final reruns of the other 40 suites. Deduplicate by suite path plus full test name. Never retain partial results from an originally failing suite.',
    'originalRun': {
        'sourceCommit': initial_summary['sourceCommit'], 'suiteCount': 141,
        'passed': 6213, 'failed': 46, 'skipped': 0,
        'errorEvents': dict(categories), 'errorEventCount': 51,
        'wholePassingSuites': 101, 'wholeFailingSuites': 40,
        'selectedUniqueTestKeys': len(initial_keys),
        'selectedPassingExecutions': sum(initial_occurrences.values()),
        'excludedPartialPassingExecutions': sum(initial['keyOccurrences'].values()) - sum(initial_occurrences.values()),
        'acceptedAsWholeRun': False,
        'formatExitCode': initial_summary['gates']['format']['exitCode'],
        'analysisExitCode': initial_summary['gates']['analysis']['exitCode'],
    },
    'finalRecheck': {
        'sourceCommit': recheck_summary['sourceCommit'], 'suiteCount': 40,
        'uniqueTestKeys': len(rechecked_keys),
        'passingExecutions': sum(rechecked_occurrences.values()),
        'counts': recheck_summary['counts'],
        'allBatchesSucceeded': True, 'inputsStable': True,
        'analysisExitCode': recheck_summary['gates']['analysis']['exitCode'],
        'formatExitCode': recheck_summary['gates']['format']['exitCode'],
    },
    'betweenRuns': {
        'engineProductionUnchanged': True, 'changedInputs': changed_between,
        'fixtureCorrection': {
            'path': fixture_correction,
            'changes': [
                {'id': 'projected-insertafter-refused', 'columnBefore': 3, 'columnAfter': 65},
                {'id': 'inactive-unsafe-projection-refused', 'columnBefore': 5, 'columnAfter': 67},
            ],
            'scope': 'Position columns only; source, error codes, behavior expectations and test counts retained. Its entire containing suite was rechecked.',
        },
        'resourceRecovery': 'The full failing files were rerun in bounded batches after temporary storage cleanup. The original ENOSPC and dependent teardown events are preserved, not reclassified as passes.',
    },
    'acceptedCoverage': {
        'suiteCount': 141, 'uniqueTestKeys': len(accepted_keys),
        'passingExecutions': sum(accepted_occurrences.values()),
        'duplicateNameExecutions': sum(accepted_occurrences.values()) - len(accepted_keys),
        'failures': 0, 'skips': 0, 'runnerErrors': 0,
        'doesNotClaimOneCleanMonolithicRun': True,
        'testKeySha256': sha(encoded(sorted(accepted_keys))),
        'suites': [{
            'path': suite,
            'source': 'initial-wholly-passing-suite' if suite in original_good else 'final-whole-file-recheck',
            'testCount': sum(key[0] == suite for key in accepted_keys),
        } for suite in sorted(initial['suites'])],
    },
    'acceptedTestKeys': [{'suite': suite, 'name': name}
                         for suite, name in sorted(accepted_keys)],
    'repeatedTestNames': [{'suite': suite, 'name': name, 'executions': count}
                          for (suite, name), count in sorted(accepted_occurrences.items())
                          if count > 1],
}

members = {}
manifest = []


def add(path, arcname, category):
    assert path.is_file(), path
    assert arcname not in members
    assert not any(arcname.endswith(ext) for ext in ('.js', '.map', '.deps'))
    data = path.read_bytes()
    assert data == path.read_bytes(), f'File changed while archiving: {path}'
    members[arcname] = data
    manifest.append({'path': arcname, 'sha256': sha(data), 'bytes': len(data),
                     'category': category})


def add_dir(directory, prefix, category):
    for path in sorted(directory.rglob('*')):
        if not path.is_file() or path.suffix in ('.js', '.map', '.deps', '.gz'):
            continue
        add(path, prefix + '/' + str(path.relative_to(directory)), category)


def generated(arcname, value, category):
    data = encoded(value)
    assert arcname not in members
    members[arcname] = data
    manifest.append({'path': arcname, 'sha256': sha(data), 'bytes': len(data),
                     'category': category})


add(validation / 'intake.json', 'intake/initial.json', 'intake')
add(destination / 'remote-intake-refresh.json', 'intake/refresh.json', 'intake')
add_dir(initial_dir, 'initial-failed-word-run', 'failed-historical-run')
add_dir(recheck_dir, 'accepted-word-recheck', 'accepted-recheck')
generated('accepted-word-coverage.json', coverage, 'deduplicated-coverage')

for filename in [
    'native-cell-suffix-tests.log', 'native-cell-suffix-analysis.log',
    'suffix-source-integration-tests.log', 'word-cell-alias-graph-tests.log',
    'word-cell-alias-graph-analysis.log', 'engine-analysis.log',
    'word-cell-suffix-conformance.jsonl', 'word-cell-suffix-conformance.stderr',
]:
    add(runtime / 'logs' / filename, 'checkpoint-logs/' + filename, 'completed-checkpoint')
checkpoint_corpus = event_log(runtime / 'logs/word-cell-suffix-conformance.jsonl')
assert checkpoint_corpus['success'] and not checkpoint_corpus['errors']

for label in ['initial-failures', 'repeat-initial-failures']:
    path = runtime / 'logs' / ('word-cell-suffix-conformance.' + label + '.jsonl')
    failed = event_log(path)
    assert failed['success'] is False
    for extension in ['jsonl', 'stderr']:
        filename = 'word-cell-suffix-conformance.' + label + '.' + extension
        add(runtime / 'logs' / filename, 'initial-failed-corpus/' + filename,
            'failed-historical-run')
for extension in ['jsonl', 'stderr']:
    filename = 'word-cell-suffix-conformance.initial-no-env.' + extension
    add(runtime / 'logs' / filename, 'initial-failed-corpus/' + filename,
        'interrupted-no-test-events')
generated('initial-failed-corpus/attempt-accounting.json', {
    'initialNoEnvironmentAttempt': {'exitCode': 130, 'testEvents': 0,
                                   'accepted': False},
    'completedInitialAttempts': {'attempts': 2, 'accepted': False,
        'observedIssues': ['Reserved local variable names in the independently authored fixture',
                           'A rooted direct-cell alias cycle was unnecessarily refused',
                           'Empty/Null runtime type-error locations were anchored at the member',
                           'Two proposed aggregate-size accepted cases instead exceeded the existing work budget'],
        'resolution': 'Reserved fixture names and positioned diagnostics were corrected after source review; the rooted alias-cycle success oracle was retained and the compiler graph proof fixed; budget tests were rewritten to exercise reachable independent bounds.'},
}, 'historical-accounting')

portable = read_json(runtime / 'logs/final-portable-qualification/receipt.json')
assert portable['status'] == 'passed' and portable['source_stable'] and portable['runtime_stable']
add_dir(runtime / 'logs/final-portable-qualification', 'accepted-portable/qualification', 'accepted-portable')
add_dir(runtime / 'logs/word-cell-suffix-portable', 'accepted-portable/actual-bas', 'accepted-portable')
for filename in [
    'word-cell-suffix-portability.json', 'word-cell-suffix-conformance.vm.json',
    'word-cell-suffix-conformance.node.json', 'word-cell-suffix-conformance-vm.stderr',
    'word-cell-suffix-conformance-node.stderr', 'word-cell-suffix-conformance-js-compile.stderr',
    'word-cell-suffix-conformance.js-compile.log',
    'word-cell-suffix-conformance-final-driver.log', 'word-cell-suffix-portable-driver.log',
    'final-portable-qualification-driver.log',
]:
    add(runtime / 'logs' / filename, 'accepted-portable/corpus/' + filename, 'accepted-portable')
add_dir(runtime / 'logs/prior-portable', 'historical-portable', 'superseded-portable-checkpoint')

zotero_results = []
for label in ['engine', 'editor', 'studio', 'analysis']:
    prefix = 'incoming-zotero-' + label
    result = read_json(runtime / 'logs' / (prefix + '.receipt.json'))
    assert result['accepted'] and result['sourceStable'] and result['exitCode'] == 0
    for path in sorted((runtime / 'logs').glob(prefix + '.*')):
        add(path, 'incoming-zotero/' + path.name, 'accepted-incoming-zotero')
    zotero_results.append({
        'scope': label, 'sourceCommit': result['gitHeadBefore'],
        'passed': result.get('passed'), 'failed': result.get('failed', 0),
        'skipped': result.get('skipped', 0), 'exitCode': result['exitCode'],
        'inputCount': len(result['sourceHashesBefore']), 'inputsStable': True,
        'receipt': 'incoming-zotero/' + prefix + '.receipt.json',
    })

for filename in ['run_suffix_portability.py', 'run_cell_suffix_portable.py',
                 'run_incoming_zotero.py']:
    add(runtime / filename, 'reproduction/' + filename, 'reproduction')
add(validation / 'run_local.py', 'reproduction/run_local.py', 'reproduction')
add(Path(__file__), 'reproduction/build_evidence.py', 'reproduction')

checkpoint_results = []
for filename in ['native-cell-suffix-tests.log', 'suffix-source-integration-tests.log',
                 'word-cell-alias-graph-tests.log']:
    text = (runtime / 'logs' / filename).read_text()
    matches = re.findall(r'\+(\d+): All tests passed!', text)
    assert matches, filename
    checkpoint_results.append({'log': 'checkpoint-logs/' + filename,
        'terminalPassedCount': int(matches[-1]),
        'scopeFromLog': sorted(set(re.findall(r'test/[A-Za-z0-9_]+_test\.dart', text))),
        'commandProvenance': 'Standalone terminal log; exact launcher and input manifest are not independently recorded in this file.',
        'includedInAggregate': False})

archive = destination / 'local-qualification.tar.gz'
with archive.open('wb') as raw:
    with gzip.GzipFile(fileobj=raw, filename='', mode='wb', mtime=0, compresslevel=9) as compressed:
        with tarfile.open(fileobj=compressed, mode='w', format=tarfile.PAX_FORMAT) as tar:
            for name, data in sorted(members.items()):
                entry = tarfile.TarInfo(name)
                entry.size = len(data)
                entry.mtime = 0
                entry.uid = entry.gid = 0
                entry.uname = entry.gname = ''
                entry.mode = 0o644
                tar.addfile(entry, io.BytesIO(data))
archive_data = archive.read_bytes()

index = {
    'schemaVersion': 1,
    'purpose': 'Closed local Word/VBA qualification and incoming Zotero evidence; GitHub Actions was not queried or awaited.',
    'archive': {'path': archive.name, 'sha256': sha(archive_data),
                'bytes': len(archive_data), 'members': len(members),
                'determinism': 'Lexicographic members; UTF-8 payloads unchanged; tar uid/gid/mtime zero and mode0644; gzip filename empty and mtime zero.'},
    'acceptedWordCoverage': {key: value for key, value in coverage['acceptedCoverage'].items()
                             if key != 'suites'},
    'coverageRecord': 'accepted-word-coverage.json inside archive; includes every selected suite and full deduplication key.',
    'commandReceipts': {
        'initialBroadRun': 'initial-failed-word-run/macro-regressions.json',
        'wholeFileRecheck': [
            'accepted-word-recheck/' + path.name
            for path in sorted(recheck_dir.glob('macro-batch-*.json'))
        ],
        'analysis': 'accepted-word-recheck/analysis.json',
        'format': 'accepted-word-recheck/format.json',
        'portable': 'accepted-portable/qualification/receipt.json',
        'zotero': [result['receipt'] for result in zotero_results],
        'note': 'JSON receipts retain exact argv and working-directory provenance; reproduction scripts are included. Historical standalone logs do not invent missing argv or source manifests.',
    },
    'initialWordFailure': coverage['originalRun'],
    'finalWholeFileRecheck': coverage['finalRecheck'],
    'betweenWordRuns': coverage['betweenRuns'],
    'checkpointResults': checkpoint_results,
    'independentSuffixCorpus': {'cases': 73, 'wholeFileTests': 84,
        'nativePlans': 27, 'positionedDiagnostics': 46,
        'portableReceipt': 'accepted-portable/corpus/word-cell-suffix-portability.json',
        'vmAndJavaScriptReceiptsByteIdentical': True,
        'note': 'Checkpoint counts overlap broad Word coverage and are not added to it.'},
    'actualBasPortable': {'sourceCommit': portable['captured_merge'],
        'operations': portable['bas']['driver_result']['operations'],
        'receipt': 'accepted-portable/actual-bas/receipt.json',
        'vmAndJavaScriptReceiptsByteIdentical': portable['bas']['byte_json_equal'],
        'inputsStable': True},
    'incomingZotero': zotero_results,
    'incomingZoteroExecutions': sum(result['passed'] or 0 for result in zotero_results),
    'incomingMail': {'status': 'pending-separate-qualification',
        'note': 'Mail repair tests were still running while this archive was prepared. No Mail qualification is inferred from a passing Zotero host test. The prior Studio receipt remains bound to its recorded store input; later Mail store changes require separate reconciliation.'},
    'limitations': ['Specification-derived VBA cases do not claim an installed Microsoft Word run.',
                    'Local Flutter host tests use test fixtures and mocks; no live Zotero desktop acceptance is claimed.',
                    'The initial broad run failed and remains preserved. Accepted Word coverage combines complete passing files from two runs, not one clean monolithic execution.',
                    'Historical checkpoint logs and portable receipts overlap accepted coverage and are not summed.',
                    'Compiled JavaScript, source maps, SDK bytes, caches and credentials are excluded. Their recorded hashes remain in receipts.'],
    'files': sorted(manifest, key=lambda item: item['path']),
}
(destination / 'evidence-index.json').write_bytes(encoded(index))
with tarfile.open(archive, 'r:gz') as tar:
    found = {member.name: tar.extractfile(member).read() for member in tar.getmembers() if member.isfile()}
assert found == members
print(json.dumps({'archive': index['archive'], 'acceptedWordCoverage': index['acceptedWordCoverage'],
                  'incomingZoteroExecutions': index['incomingZoteroExecutions']}, indent=2))
