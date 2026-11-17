"""Read-only independent audit of the published November 17 evidence."""

from __future__ import annotations

import copy
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'docs/validation/german-proofing-next-20261117'
OUT = Path(__file__).with_name('recovered-evidence-audit.json')
ISSUES: list[str] = []


def check(value: bool, label: str) -> None:
    if not value:
        ISSUES.append(label)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read(name: str) -> dict:
    data = (BASE / name).read_bytes()
    return json.loads(gzip.decompress(data) if name.endswith('.gz') else data)


index = read('evidence-index.json')
archive = BASE / index['archive']['path']
archive_bytes = archive.read_bytes()
check(sha(archive_bytes) == index['archive']['sha256'], 'archive SHA-256')
check(len(archive_bytes) == index['archive']['bytes'], 'archive byte count')
verification = read('verification.json')
raw_test_counts = []


def parse_events(data: bytes) -> dict:
    ends = []
    starts = set()
    errors = []
    done = None
    for line in data.decode().splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        kind = event.get('type')
        if kind == 'testStart':
            starts.add(event['test']['id'])
        elif kind == 'testDone':
            ends.append(event)
        elif kind == 'error':
            errors.append(event)
        elif kind == 'done':
            done = event
    visible = [e for e in ends if not e.get('hidden', False)]
    return {
        'passed': sum(e['result'] == 'success' and not e['skipped'] for e in visible),
        'skipped': sum(e['skipped'] for e in visible),
        'failed': sum(e['result'] != 'success' and not e['skipped'] for e in visible),
        'unfinished': len(starts - {e['testID'] for e in ends}),
        'error_count': len(errors),
        'done_success': done is not None and done['success'],
    }


with tarfile.open(archive, 'r:xz') as tf:
    members = tf.getmembers()
    names = [m.name for m in members]
    check(len(names) == len(set(names)), 'archive unique member paths')
    check(set(names) == set(index['members']), 'archive member path set')
    check(len(names) == index['member_count'], 'archive member count')
    check(sum(m.size for m in members) == index['uncompressed_member_bytes'], 'archive uncompressed bytes')
    for member in members:
        check(member.isfile(), 'regular archive member ' + member.name)
        check(not member.name.startswith('/') and '..' not in Path(member.name).parts, 'safe archive member ' + member.name)
        if not member.isfile() or member.name not in index['members']:
            continue
        data = tf.extractfile(member).read()
        expected = index['members'][member.name]
        check(len(data) == expected['bytes'], 'size ' + member.name)
        check(sha(data) == expected['sha256'], 'SHA-256 ' + member.name)

    for item in verification['tests']:
        path = item['evidence']['archive_member']
        data = tf.extractfile(path).read()
        check(sha(data) == item['evidence']['sha256'], 'receipt hash ' + path)
        receipt = json.loads(data)
        source = receipt.get('source_head', receipt.get('source_commit'))
        check(source == item['tested_source'], 'receipt source ' + path)
        base = Path(path).parent
        if 'log' in receipt:
            counts = parse_events(tf.extractfile(str(base / receipt['log'])).read())
        elif 'commands' in receipt:
            counts = {'passed': 0, 'skipped': 0, 'failed': 0, 'unfinished': 0, 'error_count': 0, 'done_success': True}
            for command in receipt['commands']:
                if 'tests' not in command:
                    continue
                c = parse_events(tf.extractfile(str(base / command['log'])).read())
                for k in counts:
                    if k == 'done_success':
                        counts[k] = counts[k] and c[k]
                    else:
                        counts[k] += c[k]
        else:
            # The unittest receipt records all console lines; its terminal summary
            # is separately checked rather than misread as Dart JSON events.
            tail = receipt['tail']
            check('Ran 108 tests in 1.318s' in tail and 'OK (skipped=1)' in tail, 'Python unittest summary')
            counts = {'passed': 107, 'skipped': 1, 'failed': 0, 'done_success': receipt['passed']}
        for k in ('passed', 'skipped', 'failed'):
            check(counts[k] == item[k], f'{path}: independent {k}')
        check(counts['done_success'], 'test done success ' + path)
        check(not counts.get('unfinished', 0) and not counts.get('error_count', 0), 'test operational completion ' + path)
        raw_test_counts.append({'name': item['name'], 'source': source, **counts})


def projection(case: dict, outcome: dict, label: str) -> str | None:
    if not outcome['complete']:
        # An explicitly unsupported regional model observation has no projected
        # string. It is not a successful unchanged/clean observation.
        check(outcome['corrected'] is None, label + ': incomplete has no projection')
        check(not outcome['changed'] and not outcome['exact_expected'] and not outcome['clean_report'], label + ': incomplete is not success')
        check(not outcome['projected_findings'], label + ': incomplete has no projected findings')
        return None
    source = case['input'].encode('utf-16-le')
    offset = case['start_offset']
    selections = outcome['projected_findings']
    spans = []
    for finding in selections:
        start, end = finding['start'] - offset, finding['end'] - offset
        check(0 <= start <= end <= len(source) // 2, label + ': span bounds')
        check(source[start * 2:end * 2].decode('utf-16-le') == finding['original'], label + ': source span')
        check(finding['replacement_index'] == 0, label + ': first replacement')
        spans.append((start, end, finding['replacements'][0]))
    for start, end, replacement in sorted(spans, reverse=True):
        source = source[:start * 2] + replacement.encode('utf-16-le') + source[end * 2:]
    corrected = source.decode('utf-16-le')
    check(corrected == outcome['corrected'], label + ': projected text')
    check(outcome['changed'] == (corrected != case['input']), label + ': changed')
    check(outcome['flagged'] == bool(outcome['displayed_findings']), label + ': flagged')
    check(outcome['exact_expected'] == (outcome['complete'] and corrected == case['expected']), label + ': exact')
    return corrected


panels = {}
stages = ['baseline', 'after-spelling', 'integrated-quality']
all_cases = {}
for stage in stages:
    all_cases[stage] = {}
    for panel in ('frozen', 'prospective'):
        report = read(f'{stage}/{panel}.json.gz')
        check(report['completed'] and report['operational_passed'] and report['source_stable'], stage + '/' + panel + ': run status')
        cases = report['cases']
        all_cases[stage][panel] = cases
        check(len(cases) == (30 if panel == 'frozen' else 76), stage + '/' + panel + ': case count')
        de = [c for c in cases if c['locale'] == 'de-DE']
        counts = {}
        for lane in ('writing_only', 'deterministic', 'model_only', 'combined'):
            counts[lane] = {'exact_errors': 0, 'clean_flagged': 0, 'clean_changed': 0}
        for case in cases:
            check(case['status_contract_passed'], stage + '/' + panel + '/' + case['id'] + ': status contract')
            for lane, outcome in case['outcomes'].items():
                corrected = projection(case, outcome, stage + '/' + panel + '/' + case['id'] + '/' + lane)
                if case['locale'] != 'de-DE':
                    continue
                check(outcome['complete'], stage + '/' + panel + '/' + case['id'] + '/' + lane + ': supported complete')
                if case['kind'] == 'error':
                    counts[lane]['exact_errors'] += corrected == case['expected']
                elif case['kind'] == 'clean':
                    counts[lane]['clean_flagged'] += bool(outcome['displayed_findings'])
                    counts[lane]['clean_changed'] += corrected != case['input']
        combined = lambda c: c['outcomes']['combined']['complete'] and c['outcomes']['combined']['corrected'] == c['expected']
        deterministic = lambda c: c['outcomes']['deterministic']['complete'] and c['outcomes']['deterministic']['corrected'] == c['expected']
        panels[stage + '/' + panel] = {
            'case_count': len(cases),
            'de_DE_errors': sum(c['kind'] == 'error' for c in de),
            'de_DE_clean': sum(c['kind'] == 'clean' for c in de),
            'lanes': counts,
            'added_exact_ids': [c['id'] for c in de if c['kind'] == 'error' and combined(c) and not deterministic(c)],
            'lost_exact_ids': [c['id'] for c in de if c['kind'] == 'error' and deterministic(c) and not combined(c)],
            'accepted_model_findings': sum(len(c['accepted_model_findings']) for c in de),
            'suppressed_model_findings': sum(len(c['suppressed_model_findings']) for c in de),
        }


comparisons = {}
for before, after in [('baseline', 'after-spelling'), ('after-spelling', 'integrated-quality')]:
    changes = []
    for panel in ('frozen', 'prospective'):
        prior = {c['id']: c for c in all_cases[before][panel]}
        current = {c['id']: c for c in all_cases[after][panel]}
        check(prior.keys() == current.keys(), before + '/' + after + ': case identity')
        for case_id in prior:
            a, b = copy.deepcopy(prior[case_id]), copy.deepcopy(current[case_id])
            for field in ('id', 'input', 'expected', 'locale', 'kind', 'start_offset'):
                check(a[field] == b[field], before + '/' + after + '/' + case_id + ': declaration ' + field)
            a.pop('timing_ms', None)
            b.pop('timing_ms', None)
            if a != b:
                changes.append({'panel': panel, 'case_id': case_id, 'changed_lanes': [k for k in a['outcomes'] if a['outcomes'][k] != b['outcomes'][k]]})
    comparisons[before + ' -> ' + after] = {'case_rows': 106, 'lane_outcomes': 424, 'changes': changes}
check(not comparisons['after-spelling -> integrated-quality']['changes'], 'integrated quality unchanged')

native = read('provider-segmented.json.gz')
samples = native['warm_checks_up_to_64_wordpieces']['samples_ms']
median = statistics.median(samples)
p95 = sorted(samples)[math.ceil(0.95 * len(samples)) - 1]
check(median == 22.886 and p95 == 62.875 and len(samples) == 87, 'native timing statistics')
check(all(c['passed'] for c in native['controls'] + native['segmentation_controls']), 'native operational controls')
check(native['peak_process_rss_bytes'] / 1024**2 == 359.6875, 'native RSS MiB')
source_delta = subprocess.run(['git', 'diff', '--name-only', '6971819edfb53ed40e97fc2b4cd436e89a39a648', 'e67c8090e0bc93eac6b4eb0195461d52e27b7d8e'], cwd=ROOT, check=True, capture_output=True, text=True).stdout.splitlines()
check(all(p.startswith('docs/') or p == 'tools/proofing/german_model/README.md' for p in source_delta), 'publication modifies documentation/evidence only')

result = {
    'kind': 'independent-recovered-evidence-audit',
    'published_commit': 'e67c8090e0bc93eac6b4eb0195461d52e27b7d8e',
    'accepted_historical_source': verification['accepted_product_source'],
    'scope': 'Checks published archive integrity, parses retained test logs, reconstructs UTF-16 diagnostic projections and quality counts, compares all three quality stages, and recalculates retained timing statistics. Does not run product code or qualify future integrated source.',
    'archive': {'sha256': sha(archive_bytes), 'bytes': len(archive_bytes), 'members': len(members), 'uncompressed_bytes': sum(m.size for m in members)},
    'historical_test_counts': raw_test_counts,
    'panels': panels,
    'comparisons': comparisons,
    'native': {'sample_count': len(samples), 'median_ms': median, 'p95_ms': p95, 'peak_rss_mib': native['peak_process_rss_bytes'] / 1024**2, 'operational_controls': len(native['controls']), 'segmented_controls': len(native['segmentation_controls'])},
    'publication_delta_paths': source_delta,
    'issues': ISSUES,
    'passed': not ISSUES,
}
OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'output': str(OUT), 'passed': result['passed'], 'issues': ISSUES, 'archive': result['archive'], 'historical_test_counts': raw_test_counts, 'panels': {k: v for k, v in panels.items() if k.startswith('integrated-quality')}, 'comparisons': comparisons, 'native': result['native']}, ensure_ascii=False, indent=2))
raise SystemExit(bool(ISSUES))
