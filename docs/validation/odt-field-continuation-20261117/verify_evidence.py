"""Recount fresh recovered-source qualification and verify its exact inputs."""
import collections
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

FOLDER = Path(__file__).resolve().parent
REPO = FOLDER.parents[2]
EVIDENCE = FOLDER / 'evidence'
BASE = 'e3a38789359adaa33b2da1345c952fa1c2d8aebb'
SOURCE = '5afff4b86523250c93d949eb6c010e49d9fabd82'
CHANGED = {
    'packages/quds_office_engine/lib/src/word/serial/odt_document_writer.dart',
    'packages/quds_office_engine/lib/src/word/serial/word_deserializer.dart',
}
EXPECTED = {
    'recovered-baseline': {'failure': 24, 'success': 31},
    'recovered-vm': {'success': 620},
    'recovered-node': {'success': 165},
    'recovered-analysis': {},
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def metadata(data):
    return {'bytes': len(data), 'sha256': sha(data)}


cache = {}


def source_metadata(revision, path):
    key = (revision, path)
    if key not in cache:
        cache[key] = metadata(subprocess.check_output(
            ['git', 'show', revision + ':' + path], cwd=REPO,
        ))
    return cache[key]


manifests = {}
outcomes = {}
runtime = json.loads((FOLDER / 'runtime.json').read_text())
for label, expected_counts in EXPECTED.items():
    receipt_file = EVIDENCE / (label + '.json')
    receipt = json.loads(receipt_file.read_text())
    assert receipt['head'] == SOURCE, label
    assert receipt['passed'], label
    assert receipt['packageConfigStable'] and not receipt['changedInputs'], label
    assert receipt['packageConfigSha256'] == runtime['packageConfigSha256'], label
    assert receipt['packageConfigBeforeSha256'] == receipt['packageConfigSha256'], label
    assert receipt['dartExecutableSha256'] == runtime['dartExecutableSha256'], label
    assert receipt['harnessSha256'] == sha((FOLDER / 'run_logged.py').read_bytes()), label
    packed = (EVIDENCE / receipt['inputManifest']).read_bytes()
    assert sha(packed) == receipt['inputManifestSha256'], label
    manifest = json.loads(gzip.decompress(packed))
    assert manifest['before'] == manifest['after'] and not manifest['changed'], label
    assert len(manifest['before']) == receipt['sourceInputCount'], label
    for path, recorded in manifest['before'].items():
        if path == 'docs/validation/odt-field-continuation-20261117/resolved-pubspec.lock':
            actual = metadata((FOLDER / 'resolved-pubspec.lock').read_bytes())
        else:
            revision = BASE if label == 'recovered-baseline' and path in CHANGED else SOURCE
            actual = source_metadata(revision, path)
        assert recorded == actual, (label, path)
    streams = {}
    for name, info in receipt['outputs'].items():
        packed = (EVIDENCE / info['path']).read_bytes()
        plain = gzip.decompress(packed)
        assert sha(packed) == info['compressedSha256'], (label, name)
        assert sha(plain) == info['uncompressedSha256'], (label, name)
        assert len(plain) == info['uncompressedBytes'], (label, name)
        streams[name] = plain
    suites, tests, completions, terminal = {}, {}, {}, []
    for line in streams['stdout'].decode().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not isinstance(event, dict):
            continue
        kind = event.get('type')
        if kind == 'suite':
            suites[event['suite']['id']] = event['suite']['path']
        elif kind == 'testStart':
            tests[event['test']['id']] = event['test']
        elif kind == 'testDone':
            completions[event['testID']] = event
        elif kind == 'done':
            terminal.append(event)
    counts = collections.Counter()
    by_file = collections.defaultdict(collections.Counter)
    for identity, event in completions.items():
        if event.get('hidden'):
            continue
        result = 'skipped' if event.get('skipped') else event['result']
        counts[result] += 1
        by_file[suites[tests[identity]['suiteID']]][result] += 1
    assert dict(counts) == expected_counts == receipt['substantiveTestCounts'], label
    assert terminal == receipt['terminalEvents'], label
    if label != 'recovered-analysis':
        assert len(terminal) == 1, label
        assert terminal[0]['success'] == (label != 'recovered-baseline'), label
    else:
        assert b'No issues found!' in streams['stdout'], label
    assert receipt['exitCode'] == (1 if label == 'recovered-baseline' else 0), label
    if label != 'recovered-baseline':
        assert not receipt['testErrors'], label
    manifests[label] = manifest['before']
    outcomes[label] = {
        'receiptSha256': sha(receipt_file.read_bytes()),
        'recordedHead': receipt['head'],
        'counts': dict(counts),
        'byFile': {path: dict(count) for path, count in sorted(by_file.items())},
        'sourceInputs': len(manifest['before']),
        'sourceAndRuntimeBindingsVerified': True,
        'logsAndTerminalEventsVerified': True,
    }

before = manifests['recovered-baseline']
after = manifests['recovered-vm']
common = before.keys() & after.keys()
changed = sorted(path for path in common if before[path] != after[path])
assert changed == sorted(CHANGED)
focused = {
    'test/odt_page_field_fidelity_test.dart': 34,
    'test/odt_imported_field_fidelity_test.dart': 21,
    'test/odt_inline_field_fidelity_test.dart': 23,
}
for label in ['recovered-vm', 'recovered-node']:
    for path, count in focused.items():
        assert outcomes[label]['byFile'][path] == {'success': count}
result = {
    'schemaVersion': 1,
    'qualifiedPublishedSource': SOURCE,
    'originalProductBaseline': BASE,
    'receipts': outcomes,
    'pairedRegression': {
        'commonInputs': len(common),
        'changedInputs': changed,
        'identicalFinalRegressionFiles': True,
        'note': 'Baseline receipt HEAD is the published source; its two product-file input hashes bind to the exact original baseline. The substitution was restored before the passing runs.',
    },
    'focusedPassingSubset': focused,
    'focusedPassingSubsetTotal': sum(focused.values()),
    'limits': 'Fresh reruns after recovery; test cohorts overlap. Lost unpublished prior logs were not reconstructed.',
    'passed': True,
}
(FOLDER / 'verification.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
print(json.dumps({'passed': True, 'acceptedReceipts': len(outcomes), 'counts': EXPECTED}, indent=2))
