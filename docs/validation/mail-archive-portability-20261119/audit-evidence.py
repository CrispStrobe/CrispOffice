#!/usr/bin/env python3
"""Independent, read-only source/evidence audit; writes only its final receipt."""
import argparse
import collections
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
from urllib.parse import unquote, urlparse

REPO = Path('/workspace/scratch/b1a98f2b2c3b/quds_office_suite')
EVIDENCE = Path('/workspace/scratch/b1a98f2b2c3b/portability-final-evidence-02')
OUTPUT = Path('/workspace/scratch/b1a98f2b2c3b/portability-independent-audit.json')
HEAD = '9bdef4895922ae74f6275e421af5665552d18b4e'
TREE = 'b537d9f6f2c15657b0fc0b70ae825e347be681cd'
DOCS = REPO / 'docs/validation/mail-archive-portability-20261119'

def check(condition, description):
    if not condition:
        raise AssertionError(description)

def filehash(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b''):
            h.update(chunk)
    return h.hexdigest()

def canonicalhash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

def readjson(path):
    return json.loads(Path(path).read_bytes())

def readgzip(path):
    return json.loads(gzip.decompress(Path(path).read_bytes()))

def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO)

def ancestor(left, right):
    return subprocess.run(['git', 'merge-base', '--is-ancestor', left, right], cwd=REPO,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

def resolve_suite(path, cwd):
    parsed = urlparse(path)
    candidate = Path(unquote(parsed.path)) if parsed.scheme == 'file' else Path(path)
    if not candidate.is_absolute():
        candidate = Path(cwd) / candidate
    return str(candidate.resolve().relative_to(REPO))

def audit_tests(path, record, saved):
    suites, starts, finishes, errors, done = {}, {}, {}, [], []
    non_json = []
    for number, line in enumerate(Path(path).read_text().splitlines(), 1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except ValueError:
            non_json.append({'line': number, 'text': line})
            continue
        check(isinstance(event, dict), f'Non-object reporter event in {path}:{number}')
        kind = event.get('type')
        if kind == 'suite':
            suite = event['suite']
            check(suite['id'] not in suites, f'Duplicate suite id in {path}')
            suites[suite['id']] = suite
        elif kind == 'testStart':
            test = event['test']
            check(test['id'] not in starts, f'Duplicate test start in {path}')
            starts[test['id']] = test
        elif kind == 'testDone':
            check(event['testID'] not in finishes, f'Duplicate test finish in {path}')
            finishes[event['testID']] = event
        elif kind == 'error':
            errors.append(event)
        elif kind == 'done':
            done.append(event)
    check(not errors, f'Reporter error events in {path}')
    check(len(done) == 1 and done[0].get('success') is True, f'Bad terminal reporter event in {path}')
    check(starts.keys() == finishes.keys(), f'Incomplete or unstarted test cases in {path}')
    cases, hidden = [], 0
    for ident, finish in finishes.items():
        check(finish.get('result') == 'success', f'Non-success case in {path}: {ident}')
        check(not finish.get('skipped'), f'Skipped case in {path}: {ident}')
        if finish.get('hidden'):
            hidden += 1
            continue
        test = starts[ident]
        check(test.get('suiteID') in suites, f'Unknown suite id in {path}')
        suite = suites[test['suiteID']]
        cases.append({
            'file': resolve_suite(suite['path'], record['cwd']),
            'platform': suite.get('platform'),
            'name': test.get('name'),
            'result': 'success',
            'skipped': False,
        })
    keys = [(c['file'], c['platform'], c['name']) for c in cases]
    check(len(keys) == len(set(keys)), f'Duplicate logical cases in {path}')
    expected = set(record['expected_test_files'])
    observed = {c['file'] for c in cases}
    check(expected == observed, f'File coverage mismatch in {path}: {expected ^ observed}')
    check(cases, f'Empty cohort in {path}')
    expected_counts = {'passed': len(cases), 'failed': 0, 'skipped': 0}
    check(record['test_counts'] == expected_counts, f'Counts differ from raw events in {path}')
    check(saved['accepted'] is True, f'Saved parser rejection for {path}')
    check(all(saved[k] == v for k, v in expected_counts.items()), f'Saved counts differ in {path}')
    check(saved['cases'] == cases, f'Saved case list differs from raw events in {path}')
    check(saved['expected_files'] == sorted(expected), f'Saved expected files differ in {path}')
    for key in ('hidden_failures', 'incomplete', 'error_events', 'missing_files', 'unexpected_files'):
        check(saved[key] == [], f'Saved parser diagnostics in {path}: {key}')
    check(saved['duplicate_case_keys'] == 0, f'Saved duplicate cases in {path}')
    check(saved['non_json_lines'] == len(non_json), f'Non-JSON count differs in {path}')
    # Do not silently accept unparseable event-shaped lines. Non-event tool
    # chatter, if present, is retained in this independent receipt for review.
    check(not any(row['text'].lstrip().startswith(('{', '[')) for row in non_json),
          f'Malformed JSON-looking reporter lines in {path}')
    return {
        'name': record['name'], 'counts': expected_counts,
        'test_files': sorted(observed), 'hidden_successes': hidden,
        'non_json_lines': non_json, 'stdout_sha256': record['stdout_sha256'],
        'stderr_sha256': record['stderr_sha256'],
        'test_cases_sha256': record['test_cases_sha256'],
    }

def audit_steps(receipt, selection):
    names = [step['name'] for step in receipt['steps']]
    check(len(names) == len(set(names)), 'Duplicate gate result names')
    check(set(names) <= set(selection['required_gates']), 'Unexpected executed gate')
    cohorts, gates = [], []
    for step in receipt['steps']:
        directory = EVIDENCE / step['name']
        record = readjson(directory / 'result.json')
        command = readjson(directory / 'command.json')
        check(record == step, f'Result/receipt mismatch: {step["name"]}')
        check(all(record.get(k) == v for k, v in command.items()), f'Command/result mismatch: {step["name"]}')
        check(record['exit_code'] == 0 and record['accepted'] is True, f'Non-passing gate: {step["name"]}')
        for channel in ('stdout', 'stderr'):
            path = directory / (channel + '.log')
            check(filehash(path) == record[channel + '_sha256'], f'Raw {channel} hash mismatch: {step["name"]}')
            check(path.stat().st_size == record[channel + '_bytes'], f'Raw {channel} length mismatch: {step["name"]}')
        gates.append({'name': step['name'], 'kind': step['kind'],
                      'result_sha256': filehash(directory/'result.json'),
                      'command_sha256': filehash(directory/'command.json')})
        if step['kind'] == 'tests':
            cases_path = directory/'test-cases.json.gz'
            check(filehash(cases_path) == record['test_cases_sha256'], f'Case artifact hash mismatch: {step["name"]}')
            cohorts.append(audit_tests(directory/'stdout.log', record, readgzip(cases_path)))
        elif step['kind'] in ('macro-smoke', 'vba-smoke', 'vba-procedures-smoke'):
            value = readjson(directory/'stdout.log')
            expected = {
                'macro-smoke': {'revision': 1, 'A1': 42, 'A2': 84, 'lateFailurePreservedBytes': True, 'mcpInspection': True},
                'vba-smoke': {'language':'vba-excel','revision':2,'A3':42,'B1':84,'fill':'0A141E',
                              'validationPreservedBytes':True,'lateFailurePreservedBytes':True,
                              'mcpCompileAndRun':True,'numericBoundsAndPrecedence':True},
                'vba-procedures-smoke': {'language':'vba-excel','revision':2,'steps':6,'byValCallerAmount':21,
                                         'exitForCounter':4,'formulaTotal':126,'procedureScopesAndExits':True,
                                         'recursionRejected':True,'sharedWorkBudget':True,'numericBounds':True,
                                         'validationPreservedBytes':True,'lateFailurePreservedBytes':True,'mcpCompileAndRun':True},
            }[step['kind']]
            check(value == expected and record['observed'] == expected, f'JavaScript smoke result mismatch: {step["name"]}')
    return gates, cohorts

def source_tree_entries():
    entries = {}
    for item in git('ls-tree', '-r', '-z', HEAD).split(b'\0'):
        if not item:
            continue
        header, path = item.split(b'\t', 1)
        mode, kind, oid = header.decode().split()
        entries[path.decode()] = (mode, kind, oid)
    return entries

def audit_fingerprints(receipt):
    summaries = {}
    snapshots = {}
    for name, singular in [('source','source'), ('dependencies','dependencies'), ('runtime','runtime')]:
        before = readgzip(EVIDENCE/f'{name}-before.json.gz')
        after = readgzip(EVIDENCE/f'{name}-after.json.gz')
        check(before == after, f'{name} inputs changed during run')
        check(canonicalhash(before) == receipt[f'{singular}_before_sha256'], f'{name} before receipt digest mismatch')
        check(canonicalhash(after) == receipt[f'{singular}_after_sha256'], f'{name} after receipt digest mismatch')
        summaries[name] = {'files': len(before), 'bytes': sum(v['bytes'] for v in before.values()),
                           'canonical_sha256': canonicalhash(before),
                           'before_artifact_sha256': filehash(EVIDENCE/f'{name}-before.json.gz'),
                           'after_artifact_sha256': filehash(EVIDENCE/f'{name}-after.json.gz'),
                           'unchanged': True}
        snapshots[name] = before
    check(summaries['source']['files'] == receipt['source_file_count'], 'Source file count differs')
    check(summaries['dependencies']['files'] == receipt['dependency_file_count'], 'Dependency file count differs')
    tree = source_tree_entries()
    for name, metadata in snapshots['source'].items():
        path = REPO/name
        check(name in tree and tree[name][1] == 'blob', f'Source absent from frozen tree: {name}')
        content = path.read_bytes()
        check(len(content) == metadata['bytes'] and hashlib.sha256(content).hexdigest() == metadata['sha256'],
              f'Current source differs from accepted bytes: {name}')
        check(tree[name][0] != '120000', f'Symlink source needs separate qualification: {name}')
        blob = hashlib.sha1(f'blob {len(content)}\0'.encode()+content).hexdigest()
        check(blob == tree[name][2], f'Source differs from exact frozen Git blob: {name}')
    configurations = {
        'workspace': REPO/'.dart_tool/package_config.json',
        'flutter-tools': Path(os.environ['FLUTTER_ROOT'])/'packages/flutter_tools/.dart_tool/package_config.json',
    }
    roots = {}
    for origin, config in configurations.items():
        for package in readjson(config)['packages']:
            parsed = urlparse(package['rootUri'])
            path = Path(unquote(parsed.path)) if parsed.scheme == 'file' else config.parent/unquote(package['rootUri'])
            roots[(origin, package['name'])] = path.resolve()
    verified_paths = {}
    for key, metadata in snapshots['dependencies'].items():
        origin, package, relative = key.split('/', 2)
        path = roots[(origin, package)]/relative
        observed = verified_paths.setdefault(str(path), {'bytes': path.stat().st_size, 'sha256': filehash(path)})
        check(observed == metadata, f'Current dependency bytes changed: {key}')
    for path, metadata in snapshots['runtime'].items():
        check(Path(path).stat().st_size == metadata['bytes'] and filehash(path) == metadata['sha256'],
              f'Current runtime bytes changed: {path}')
    return summaries

def audit_frontier():
    frontier = readjson(DOCS/'remote-frontier.json')
    reconciliation = readjson(DOCS/'reconciliation-refresh.json')
    references = frontier['references']
    check(len(references) == 234, 'Wrong frozen frontier size')
    check(len({(r['source'],r['ref']) for r in references}) == len(references), 'Duplicate captured references')
    check([{k:r[k] for k in ('source','ref','sha')} for r in reconciliation['references']] == references,
          'Replay changed the captured frontier')
    check(filehash(DOCS/'remote-frontier.json') == reconciliation['frontier_source_sha256'], 'Frontier hash differs')
    check(reconciliation['frontier_mode'] == 'retained_capture', 'Wrong replay mode')
    check(reconciliation['incoming_tip'] == '', 'Final replay must have no accepted incoming exception')
    for proof in reconciliation['historical_proofs']:
        original, equivalent = proof['original'], proof['equivalent']
        base = git('merge-base', original, equivalent).decode().strip()
        check(base == proof['common_base'], 'Historical merge base differs')
        paths = [p.decode() for p in git('diff','--name-only','-z',base,original).split(b'\0') if p]
        if proof['method'] == 'exact_complete_tree_identity':
            equal = git('rev-parse', original+'^{tree}') == git('rev-parse', equivalent+'^{tree}')
        else:
            equal = all(git('ls-tree','-z',original,'--',path) == git('ls-tree','-z',equivalent,'--',path)
                        for path in paths)
        check(equal and ancestor(equivalent, HEAD), 'Historical equivalence or ancestry failed')
        check(proof['passed'] and len(paths) == proof['complete_original_delta_paths'], 'Historical proof metadata differs')
    proofs = {p['original']:p for p in reconciliation['historical_proofs']}
    counts = collections.Counter()
    for item in reconciliation['references']:
        if item['classification'] == 'ancestor':
            check(ancestor(item['sha'],HEAD), 'Captured reference is not an ancestor')
        elif item['classification'] == 'historical_equivalent':
            check(item['sha'] in proofs and item['equivalent'] == proofs[item['sha']]['equivalent'],
                  'Historical reference proof missing')
        else:
            raise AssertionError('Unaccounted captured reference')
        counts[item['classification']] += 1
    check(dict(counts) == {'ancestor':211,'historical_equivalent':23}, 'Wrong final reference counts')
    return {'captured_at_utc':frontier['captured_at_utc'],'references':234,'counts':dict(counts),
            'historical_proofs_revalidated':len(proofs), 'frontier_sha256':filehash(DOCS/'remote-frontier.json'),
            'reconciliation_sha256':filehash(DOCS/'reconciliation-refresh.json')}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--final',action='store_true')
    args=parser.parse_args()
    receipt=readjson(EVIDENCE/'receipt.json')
    selection=readjson(EVIDENCE/'selected-plan.json')
    check(receipt['source_head']==HEAD and receipt['source_tree']==TREE,'Wrong tested source identity')
    check(receipt['expected_head']==HEAD,'Wrong expected source identity')
    check(git('rev-parse', HEAD+'^{tree}').decode().strip()==TREE,'Wrong frozen Git tree')
    check(selection['test_file_count']==95 and len(selection['cohorts'])==10,'Wrong selected test scope')
    check(len(selection['required_gates'])==20,'Wrong required gate count')
    check(canonicalhash(selection)==receipt['plan_sha256'],'Selection hash mismatch')
    selected=[c['package']+'/'+f for c in selection['cohorts'] for f in c['files']]
    check(len(set(selected))==95,'Duplicate planned test files')
    gates,cohorts=audit_steps(receipt,selection)
    totals={key:sum(c['counts'][key] for c in cohorts) for key in ('passed','failed','skipped')}
    if not args.final:
        print(json.dumps({'status':'partial_review','receipt_status':receipt['status'],
                          'completed_gates_checked':len(gates),'completed_cohorts_checked':len(cohorts),
                          'completed_test_counts_only':totals,
                          'non_json_lines':{c['name']:c['non_json_lines'] for c in cohorts if c['non_json_lines']}},indent=2))
        return
    check(receipt['status']=='passed','Run is not yet accepted')
    check({g['name'] for g in gates}==set(selection['required_gates']),'Missing required gates')
    check({c['name'] for c in cohorts}=={c['name'] for c in selection['cohorts']},'Missing cohorts')
    check(set(f for c in cohorts for f in c['test_files'])==set(selected),'Final file coverage differs')
    check(receipt['test_totals']==totals,'Final test total differs from raw logs')
    check(receipt['inputs_stable'] is True,'Input instability')
    for key in ('source_changed_paths','dependencies_changed_paths','runtime_changed_paths',
                'tracked_changes_after','untracked_files_after','unexecuted_gates','unexecuted_cohorts'):
        check(receipt[key]==[],f'Nonempty failure evidence: {key}')
    check(receipt['head_after']==HEAD and receipt['tree_after']==TREE,'End identity differs')
    check(git('rev-parse','HEAD').decode().strip()==HEAD,'Current checkout moved before independent audit')
    check(not git('status','--porcelain'),'Current checkout is not clean')
    for name,key in [('pubspec.lock','lock_sha256'),('pubspec.yaml','production_manifest_sha256')]:
        check(filehash(REPO/name)==receipt[key]==receipt[key+'_after'],f'Production manifest changed: {name}')
    check(filehash(EVIDENCE/'run-local-validation.py')==receipt['runner_sha256']==filehash(DOCS/'run-local-validation.py'),
          'Executed harness differs from frozen harness')
    check(filehash(EVIDENCE/'runtime-setup-receipt.json')==receipt['runtime_receipt_sha256'],'Setup receipt copy differs')
    check(filehash(EVIDENCE/'runtime-readiness-receipt.json')==receipt['readiness_receipt_sha256'],'Readiness receipt copy differs')
    for name,key in [('macro-web-smoke.js','macro_javascript_sha256'),('vba-web-smoke.js','vba_javascript_sha256'),
                     ('vba-procedures-web-smoke.js','vba_procedures_javascript_sha256')]:
        check(filehash(EVIDENCE/name)==receipt[key],f'Compiled JavaScript identity differs: {name}')
    fingerprints=audit_fingerprints(receipt)
    frontier=audit_frontier()
    compact=readjson(EVIDENCE/'compact-receipt.json')
    check(compact['receipt_sha256']==filehash(EVIDENCE/'receipt.json'),'Compact receipt digest differs')
    for key,value in receipt.items():
        if key!='steps':check(compact[key]==value,f'Compact receipt metadata differs: {key}')
    first=readjson(EVIDENCE.parent/'portability-final-evidence/receipt.json')
    check(first['status']=='failed','First attempted run was not retained as failed')
    check(first['test_totals']=={'passed':0,'failed':0,'skipped':0},'First attempt unexpectedly contains tests')
    report={'schema':1,'status':'passed','audited_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'audit_script_sha256':filehash(__file__),'method':'Independent raw reporter parse, exact case/file/gate comparison, raw artifact hashing, before/after and current file checks, frozen Git blob binding, and historical frontier revalidation.',
            'evidence_directory':str(EVIDENCE),'receipt_sha256':filehash(EVIDENCE/'receipt.json'),
            'source_head':HEAD,'source_tree':TREE,'test_totals':totals,'test_file_count':95,
            'cohort_count':10,'gate_count':20,'format_target_count':len(selection['format_files']),
            'analysis_target_count':len(selection['analysis_files']),'cohorts':cohorts,'gates':gates,
            'fingerprints':fingerprints,'frozen_frontier':frontier,
            'excluded_files':selection['excluded_files'],
            'retained_prior_dart_evidence':selection['retained_prior_dart_evidence'],
            'acceptance_limits':selection['acceptance_limits'],
            'prior_attempt':{'directory':'portability-final-evidence','status':first['status'],
                             'receipt_sha256':filehash(EVIDENCE.parent/'portability-final-evidence/receipt.json'),
                             'test_totals':first['test_totals'],'included_in_final_totals':False},
            'findings':[]}
    OUTPUT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps({'status':'passed','audit':str(OUTPUT),'test_totals':totals,'test_files':95,'gates':20,
                      'non_json_lines':{c['name']:c['non_json_lines'] for c in cohorts if c['non_json_lines']}},indent=2))

if __name__=='__main__':main()
