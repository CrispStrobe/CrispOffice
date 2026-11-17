#!/usr/bin/env python3
"""Report reviewed decisions separately from an unchanged literal gold score.

The ordinary VM/Node qualifier remains the inference runner. This reporter
cannot replace its original exact score. Explicit, text-bound adjudications
may accept an alternative correction or preserve an independently valid
reading. All other error cases still require the historical expected output.
"""
import argparse
import hashlib
import json
from pathlib import Path


def evaluate(corpus_path, review, result):
    raw = corpus_path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != review['corpus_sha256']:
        raise ValueError('Review is not bound to this exact historical corpus')
    cases = json.loads(raw)['cases']
    by_id = {row['id']: row for row in cases}
    if len(by_id) != len(cases):
        raise ValueError('Duplicate historical case ID')
    overrides = {}
    for row in review['cases']:
        original = by_id[row['id']]
        if (row['id'] in overrides or original['kind'] != 'error'
                or row['text'] != original['text']
                or row['original_expected'] != original['expected']):
            raise ValueError('Adjudication does not match its historical case')
        accepted = row['accepted_outputs']
        if not accepted or not all(isinstance(s, str) and s for s in accepted):
            raise ValueError('Accepted outputs must be explicit nonempty strings')
        if row['disposition'] == 'valid-reading':
            if accepted != [original['text']]:
                raise ValueError('A valid-reading decision must preserve the source')
        elif row['disposition'] == 'alternative-repair':
            if original['expected'] not in accepted or original['text'] in accepted:
                raise ValueError('Alternative repairs retain the original correction')
        else:
            raise ValueError('Unknown review disposition')
        overrides[row['id']] = row
    base = [row for row in result['results'] if row['variant'] == 'base']
    if len(base) != len(cases) or {r['id'] for r in base} != set(by_id):
        raise ValueError('Incomplete or duplicate base results')
    failures = []
    repaired = preserved = accepted_count = 0
    for row in base:
        original = by_id[row['id']]
        if (row['text'], row['expected'], row['kind']) != (
                original['text'], original['expected'], original['kind']):
            raise ValueError('Inference result changed historical input/gold/label')
        if original['kind'] != 'error':
            continue
        decision = overrides.get(row['id'])
        allowed = decision['accepted_outputs'] if decision else [original['expected']]
        preservation = decision and decision['disposition'] == 'valid-reading'
        ok = (row['complete'] and row['can_apply_nonoverlapping']
              and row['applied'] in allowed
              and (not row['findings'] if preservation else bool(row['findings'])))
        if ok:
            accepted_count += 1
            if preservation:
                preserved += 1
            else:
                repaired += 1
        else:
            failures.append({'id': row['id'], 'text': row['text'],
                             'applied': row['applied'], 'accepted': allowed})
    controls = [r for r in result['results'] if r['kind'] == 'control']
    control_failures = sum(not r['complete'] or not r['clean'] for r in controls)
    safety = {k: result['summary'][k] for k in (
        'operational_failures', 'protection_failures', 'ignore_failures', 'recheck_failures')}
    return {'historical_literal_summary': result['summary'],
            'historical_error_labels': sum(c['kind'] == 'error' for c in cases),
            'accepted_reviewed_decisions': accepted_count,
            'necessary_corrections': repaired, 'valid_readings_preserved': preserved,
            'false_positive_controls_across_variants': control_failures,
            'safety_failures': safety, 'unhandled': failures,
            'status': 'passed' if not failures and not control_failures and not any(safety.values()) else 'failed'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--corpus', type=Path, required=True)
    parser.add_argument('--review', type=Path, required=True)
    parser.add_argument('--results', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = evaluate(args.corpus, json.loads(args.review.read_text()), json.loads(args.results.read_text()))
    report['review_sha256'] = hashlib.sha256(args.review.read_bytes()).hexdigest()
    report['results_sha256'] = hashlib.sha256(args.results.read_bytes()).hexdigest()
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if report['status'] != 'passed':
        raise SystemExit(1)


if __name__ == '__main__':
    main()
