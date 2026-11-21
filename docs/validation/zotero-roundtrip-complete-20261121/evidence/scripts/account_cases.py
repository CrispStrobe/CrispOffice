#!/usr/bin/env python3
"""Independently derive distinct accepted cases from archived raw test events."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile


SOURCES = {
    'engine': ('publication.tar.gz', 'validation/publication-replay/engine/events.jsonl'),
    'editor': ('publication.tar.gz', 'validation/publication/editor/events.jsonl'),
    'renderer': ('renderer-followup.tar.gz', 'validation/final-main/renderer/events.jsonl'),
    'studio_zotero': ('publication.tar.gz', 'validation/publication/studio/events.jsonl'),
    'mail_core': ('mail.tar.gz', 'validation/mail-intake/core-events.jsonl'),
    'mail_store': ('mail.tar.gz', 'validation/mail-intake/store-events.jsonl'),
    'mail_studio': ('mail.tar.gz', 'validation/mail-intake/studio-events.jsonl'),
}


def case_keys(base, source):
    archive_name, member_name = source
    with tarfile.open(base / archive_name, 'r:gz') as archive:
        text = archive.extractfile(member_name).read().decode()
    tests, suites, keys, done = {}, {}, [], []
    for line in text.splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            # Pub's native-hook progress can precede the first JSON start event.
            first = line.find('{')
            if first < 0:
                continue
            event = json.loads(line[first:])
        kind = event.get('type')
        assert kind != 'error', event
        if kind == 'suite':
            suites[event['suite']['id']] = event['suite']['path']
        elif kind == 'testStart':
            tests[event['test']['id']] = event['test']
        elif kind == 'done':
            done.append(event)
        elif kind == 'testDone' and not event.get('hidden'):
            assert event['result'] == 'success' and not event.get('skipped'), event
            test = tests[event['testID']]
            path = suites[test['suiteID']].split('/quds_office_suite/', 1)[-1]
            keys.append((path, test['name']))
    assert done and done[-1].get('success'), archive_name
    assert len(keys) == len(set(keys)), (archive_name, 'duplicate suite/name identity')
    return set(keys)


def derive(base):
    sets = {name: case_keys(base, source) for name, source in SOURCES.items()}
    overlap = sets['editor'] & sets['renderer']
    added = sets['renderer'] - sets['editor']
    scopes = {
        'engine': sets['engine'],
        'editor_distinct': sets['editor'] | sets['renderer'],
        'studio_zotero': sets['studio_zotero'],
        'mail_core': sets['mail_core'],
        'mail_store': sets['mail_store'],
        'mail_studio': sets['mail_studio'],
    }
    all_keys = set()
    for name, keys in scopes.items():
        assert not all_keys & keys, (name, 'overlap between final scopes')
        all_keys |= keys
    hashes = {
        name: hashlib.sha256(json.dumps(sorted(keys), separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()
        for name, keys in scopes.items()
    }
    return {
        'identity': ['repository-relative suite path', 'test name'],
        'editor_publication_cases': len(sets['editor']),
        'renderer_followup_executions': len(sets['renderer']),
        'renderer_repeated_cases': len(overlap),
        'renderer_additional_cases': len(added),
        'distinct_editor_cases': len(scopes['editor_distinct']),
        'repeated_renderer_cases': [{'suite': p, 'name': n} for p, n in sorted(overlap)],
        'additional_renderer_cases': [{'suite': p, 'name': n} for p, n in sorted(added)],
        'final_nonoverlapping_scope_counts': {name: len(keys) for name, keys in scopes.items()},
        'final_scope_identity_sha256': hashes,
        'distinct_accepted_cases': len(all_keys),
        'raw_event_sources': {name: {'archive': source[0], 'member': source[1]} for name, source in SOURCES.items()},
        'not_added': [
            'Historical prepublication3152 executions',
            'Rejected engine partial1703 passes',
            'Initial writer150/1 and first writer108/1',
            'Focused writer109 overlapping full engine suite',
            'Repeated27 final renderer cases',
        ],
    }


def verify_accounting(base):
    expected = json.loads((base / 'case-accounting.json').read_text())
    actual = derive(base)
    assert actual == expected, 'Case accounting differs from raw archived events'
    return actual['distinct_accepted_cases']


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    print(json.dumps(derive(args.evidence), indent=2))
