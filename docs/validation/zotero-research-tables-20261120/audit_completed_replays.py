"""Audit package:test NDJSON using only literal LF record boundaries."""
from pathlib import Path
import json, hashlib, collections, sys

def audit(path):
    raw = Path(path).read_bytes()
    lines = raw.decode('utf-8').split('\n')
    events = []
    malformed = []
    progress = []
    for number, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except ValueError as error:
            entry = {'line': number, 'text': line, 'error': str(error)}
            (malformed if line.lstrip().startswith(('{', '[')) else progress).append(entry)
            continue
        if not isinstance(value, dict) or not isinstance(value.get('type'), str):
            malformed.append({'line': number, 'value': value, 'error': 'Expected event object with type'})
            continue
        events.append(value)
    starts = [e for e in events if e['type'] == 'start']
    terminal = [e for e in events if e['type'] == 'done']
    test_starts = [e['test'] for e in events if e['type'] == 'testStart']
    test_dones = [e for e in events if e['type'] == 'testDone']
    started = collections.Counter(e['id'] for e in test_starts)
    completed = collections.Counter(e['testID'] for e in test_dones)
    duplicates = {'start': sorted(k for k,v in started.items() if v != 1), 'done': sorted(k for k,v in completed.items() if v != 1)}
    incomplete = sorted(started.keys() - completed.keys())
    unstarted = sorted(completed.keys() - started.keys())
    errors = [e for e in events if e['type'] == 'error']
    visible = [e for e in test_dones if not e.get('hidden')]
    counts = dict(collections.Counter('skip' if e.get('skipped') else e['result'] for e in visible))
    failures = [e for e in test_dones if e['result'] != 'success']
    by_id = {e['id']: e for e in test_starts}
    suites = {e['suite']['id']: e['suite']['path'] for e in events if e['type'] == 'suite'}
    per_suite = {}
    for e in visible:
        test = by_id.get(e['testID'], {})
        name = suites.get(test.get('suiteID'), '<unknown>')
        counts_for = per_suite.setdefault(name, {})
        result = 'skip' if e.get('skipped') else e['result']
        counts_for[result] = counts_for.get(result, 0) + 1
    unicode_names = [{'id':e['id'], 'name':e['name']} for e in test_starts if any(c in e['name'] for c in '\u0085\u2028\u2029')]
    protocol_complete = (len(starts) == 1 and len(terminal) == 1 and events[-1]['type'] == 'done' and not malformed and not incomplete and not unstarted and not any(duplicates.values()))
    return {'rawSha256':hashlib.sha256(raw).hexdigest(), 'rawBytes':len(raw), 'framing':'UTF-8 NDJSON split on literal U+000A only', 'startCount':len(starts), 'terminalCount':len(terminal), 'terminalSuccess':terminal[0].get('success') if len(terminal) == 1 else None, 'eventCount':len(events), 'startedCount':sum(started.values()), 'completedCount':sum(completed.values()), 'duplicateIds':duplicates, 'incompleteIds':incomplete, 'unstartedIds':unstarted, 'malformedJsonLines':malformed, 'nonJsonProgressLines':progress, 'errorEvents':errors, 'failedCompletions':failures, 'visibleCounts':counts, 'perOriginalSuite':per_suite, 'unicodeSeparatorNames':unicode_names, 'protocolComplete':protocol_complete, 'acceptedProtocol':protocol_complete and terminal[0].get('success') is True and not errors and not failures}

if __name__ == '__main__':
    root = Path(sys.argv[1])
    results = {}
    for receipt_path in sorted(root.glob('*/receipt.json')):
        receipt = json.loads(receipt_path.read_text())
        if not receipt['accepted']:
            continue
        result = audit(receipt_path.parent/'tests.jsonl')
        result.update({'processExit':receipt['exit'], 'source':receipt['source'], 'sourceHashesUnchanged':receipt['sourceHashesUnchanged'], 'matchesPublishedCounts':result['visibleCounts'] == receipt['counts']})
        result['accepted'] = result['acceptedProtocol'] and receipt['exit'] == 0 and receipt['sourceHashesUnchanged'] and result['matchesPublishedCounts']
        results[receipt_path.parent.name] = result
    total = collections.Counter()
    for result in results.values():
        total.update(result['visibleCounts'])
    summary = {'purpose':'Independent literal-LF re-audit of closed, unchanged raw streams; no SDK test rerun', 'accepted':all(r['accepted'] for r in results.values()) and len(results) == 6, 'gateCount':len(results), 'visibleCounts':dict(total), 'gates':results}
    target = root.parent/'231bd-literal-lf-reaudit.json'
    target.write_text(json.dumps(summary, indent=2))
    print(json.dumps({'output':str(target), 'accepted':summary['accepted'], 'gateCount':len(results), 'visibleCounts':dict(total), 'malformedLines':sum(len(r['malformedJsonLines']) for r in results.values()), 'progressLines':sum(len(r['nonJsonProgressLines']) for r in results.values()), 'unicodeSeparatorNames':sum(len(r['unicodeSeparatorNames']) for r in results.values())}))
    if not summary['accepted']:
        sys.exit(1)
