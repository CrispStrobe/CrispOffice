#!/usr/bin/env python3
"""Independently recount retained local evidence; never execute product tests."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import traceback


def sha(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def load(path: Path):
    return json.loads(path.read_text())


def save(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2) + '\n')


def require(condition, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def parse_events(path: Path, cwd: Path, repo: Path, requested: list[str], platform: str) -> dict:
    """Separate substantive cases from reporter loaders and lifecycle controls."""
    suites, starts, completions = {}, {}, {}
    terminal = None
    event_types = Counter()
    expected = {str((cwd / p).resolve()) for p in requested}
    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        line = line.strip()
        while line.startswith(('Running build hooks...', 'Running link hooks...')):
            prefix = next(p for p in ('Running build hooks...', 'Running link hooks...') if line.startswith(p))
            line = line[len(prefix):].lstrip()
        if not line:
            continue
        event = json.loads(line)
        require(isinstance(event, dict), f'{path}:{line_number}: nonobject event')
        kind = event.get('type')
        require(isinstance(kind, str), f'{path}:{line_number}: missing event type')
        require(terminal is None, f'{path}:{line_number}: event after terminal result')
        event_types[kind] += 1
        require(event_types['start'] == 1, f'{path}:{line_number}: missing/duplicate start')
        if kind == 'suite':
            suite = event['suite']
            ident = suite['id']
            require(type(ident) is int and ident not in suites, f'{path}: duplicate/invalid suite')
            require(suite.get('platform') == platform, f'{path}: unexpected platform')
            suites[ident] = str((cwd / suite['path']).resolve())
        elif kind == 'testStart':
            case = event['test']
            ident = case['id']
            require(type(ident) is int and ident not in starts, f'{path}: duplicate/invalid case start')
            require(type(case['suiteID']) is int and isinstance(case['name'], str), f'{path}: malformed case')
            starts[ident] = case
        elif kind == 'testDone':
            ident = event['testID']
            require(type(ident) is int and ident in starts and ident not in completions, f'{path}: unmatched/duplicate completion')
            require(type(event.get('hidden')) is bool and type(event.get('skipped')) is bool, f'{path}: malformed completion flags')
            require(event.get('result') == 'success' and not event['skipped'], f'{path}: unsuccessful/skipped case, including synthetic controls')
            completions[ident] = event
        elif kind == 'error':
            raise AssertionError(f'{path}: reporter error: {event}')
        elif kind == 'done':
            require(event.get('success') is True, f'{path}: unsuccessful terminal')
            terminal = event
    require(event_types['start'] == 1 and event_types['done'] == 1, f'{path}: incomplete runner lifecycle')
    require(set(starts) == set(completions), f'{path}: unfinished test events')
    require(set(suites.values()) == expected, f'{path}: wrong suite set: missing={expected-set(suites.values())}, extra={set(suites.values())-expected}')
    cases, excluded = [], Counter()
    for ident, case in starts.items():
        done = completions[ident]
        name = case['name']
        if done['hidden'] or name.startswith('loading ') or re.search(r'(?:^| )\((?:setUpAll|tearDownAll)\)$', name):
            excluded['hidden' if done['hidden'] else 'loading_or_lifecycle'] += 1
            continue
        require(case['suiteID'] in suites, f'{path}: case references unknown suite')
        suite = Path(suites[case['suiteID']])
        cases.append({'id': ident, 'suite_id': case['suiteID'], 'suite': str(suite.relative_to(repo)),
                      'name': name, 'platform': platform, 'result': done['result'], 'skipped': done['skipped']})
    require(cases, f'{path}: no substantive cases')
    require({str(repo / c['suite']) for c in cases} == expected, f'{path}: empty requested suite')
    identities = [(c['suite'], c['name'], c['platform']) for c in cases]
    require(len(identities) == len(set(identities)), f'{path}: duplicate named cases')
    return {'passed': len(cases), 'suite_count': len(expected), 'excluded': dict(excluded),
            'event_types': dict(event_types), 'cases': cases, 'sha256': sha(path)}


def verify_archive(index_path: Path) -> dict:
    index = load(index_path)
    archive = index_path.parent / index['archive']
    require(sha(archive) == index['sha256'], f'{archive}: archive hash mismatch')
    if 'bytes' in index:
        require(archive.stat().st_size == index['bytes'], f'{archive}: size mismatch')
    records = index['members']
    require(len(records) == len({r['path'] for r in records}), f'{archive}: duplicate index member')
    with tarfile.open(archive) as bundle:
        members = bundle.getmembers()
        require(all(m.isfile() for m in members), f'{archive}: unexpected nonfile member')
        require({m.name for m in members} == {r['path'] for r in records}, f'{archive}: index/member mismatch')
        require(len(members) == len(records), f'{archive}: duplicate archive member')
        for row in records:
            with bundle.extractfile(row['path']) as stream:
                data = stream.read()
            require(len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256'], f'{archive}: member mismatch {row["path"]}')
    return {'archive': str(archive), 'sha256': index['sha256'], 'bytes': archive.stat().st_size, 'members_verified': len(records)}


def python_count(path: Path) -> int:
    text = path.read_text()
    matches = re.findall(r'^Ran (\d+) tests? in [^\n]+$', text, re.M)
    require(len(matches) == 1 and re.search(r'^OK\s*$', text, re.M), f'{path}: missing successful unittest summary')
    require(not re.search(r'^(?:FAILED|ERROR|FAIL:)|^OK \(', text, re.M), f'{path}: failure or skipped unittest result')
    return int(matches[0])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--runtime', required=True, type=Path)
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--remote-commit', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--archive-index', action='append', default=[], type=Path)
    args = parser.parse_args()
    repo, runtime, evidence, output = (p.resolve() for p in (args.repo, args.runtime, args.evidence, args.output))
    require(not output.is_relative_to(repo), 'Audit output must remain outside source')
    output.mkdir(parents=True, exist_ok=True)
    result = {'status': 'RUNNING', 'started_at_utc': datetime.now(timezone.utc).isoformat(),
              'evidence': str(evidence), 'source_repo': str(repo), 'errors': [], 'scope': 'Independent retained-evidence audit; not another product execution'}

    def git(*argv: str) -> str:
        return subprocess.check_output(['git', '-C', str(repo), *argv], text=True).strip()

    try:
        execution = load(evidence / 'execution.json')
        require(execution.get('status') == 'PASS', 'Aggregate execution is not terminal PASS')
        head, tree = execution['source_commit'], execution['source_tree']
        require(git('rev-parse', head+'^{tree}') == tree, 'Source commit/tree mismatch')
        remote = load(args.remote_commit)
        require(remote['sha'] == head and remote['tree']['sha'] == tree, 'Published GitHub commit/tree mismatch')
        for flag in ('source_unchanged', 'runtime_unchanged', 'source_head_unchanged', 'tracked_worktree_clean_after'):
            require(execution.get(flag) is True, 'Aggregate did not preserve '+flag)
        require(not execution.get('untracked_qualification_inputs_after'), 'Untracked final qualification inputs')
        rows = {row['name']: row for row in execution['runs']}
        require(len(rows) == len(execution['runs']) and set(rows) == {'shared-runner-controls','runtime-controls','ayaspell-offline-controls','core-store','native','node'}, 'Wrong aggregate command selection')
        for row in rows.values():
            require(row['exit_code'] == 0 and row.get('accepted') is True, 'Unaccepted aggregate command '+row['name'])
            require(sha(evidence/row['log']) == row['log_sha256'], 'Changed aggregate log '+row['name'])
            if 'receipt' in row:
                require(sha(evidence/row['receipt']) == row['receipt_sha256'], 'Changed child receipt '+row['name'])
        counts_python = {name: python_count(evidence / rows[name]['log']) for name in ('shared-runner-controls','runtime-controls','ayaspell-offline-controls')}
        source_before, source_after = (load(evidence/name) for name in ('source-before.json','source-after.json'))
        runtime_before, runtime_after = (load(evidence/name) for name in ('runtime-before.json','runtime-after.json'))
        require(source_before == source_after and runtime_before == runtime_after, 'Aggregate snapshots differ')
        expected_source = dict(source_before)
        source_git_records = {}
        all_cases, group_results = [], []

        core_dir = evidence/'core-store'
        core = load(core_dir/'receipt.json')
        require(core['status'] == 'PASS' and core['starting_commit'] == head and core['source_unchanged'], 'Wrong core/store source or outcome')
        require(core['source_before'] == core['source_after'], 'Core/store source drift')
        require(core['direct_launcher_inputs_before'] == core['direct_launcher_inputs_after'], 'Core/store launcher/native drift')
        for path, identity in core['source_before'].items():
            require(expected_source.get(path) == identity, 'Core/store source differs from aggregate: '+path)
        core_suites = sorted(str(p.relative_to(repo/'packages/quds_mail_core')) for p in (repo/'packages/quds_mail_core/test').rglob('*_test.dart'))
        store_suites = sorted(str(p.relative_to(repo/'packages/quds_mail_store')) for p in (repo/'packages/quds_mail_store/test').glob('*_test.dart') if p.name != 'browser_problem_test.dart')
        core_selection = {
            'core-vm': ('packages/quds_mail_core','vm',core_suites),
            'core-node': ('packages/quds_mail_core','node',core_suites),
            'store-vm': ('packages/quds_mail_store','vm',store_suites),
            'portable-node': ('packages/quds_mail_store','node',['test/codec_test.dart','test/platform_configuration_test.dart','test/browser_problem_test.dart']),
        }
        core_test_names=[]
        for row in core['checks']:
            require(row['status'] == 'PASS' and row['exit_code'] == 0, 'Unaccepted core check '+row['name'])
            log = core_dir/row['log']
            require(sha(log) == row['log_sha256'], 'Core log hash mismatch '+row['name'])
            if row['name'] == 'runner-regressions':
                counts_python['mail-runner-controls'] = python_count(log)
            if 'tests' not in row:
                continue
            core_test_names.append(row['name'])
            cwd, platform, requested = core_selection[row['name']]
            parsed = parse_events(log, repo/cwd, repo, requested, platform)
            require(row['tests']['passed'] == parsed['passed'], 'Core substantive count mismatch '+row['name'])
            case_record = load(core_dir/row['case_list'])
            require(case_record['passed'] == parsed['passed'], 'Core case record count mismatch')
            emitted = sorted((c['name'], c['suite_id'], c['result'], c['skipped']) for c in parsed['cases'])
            retained = sorted((c['name'], c['suite_id'], c['result'], c['skipped']) for c in case_record['cases'])
            require(emitted == retained, 'Core retained case identities differ')
            all_cases.extend(parsed.pop('cases'))
            group_results.append({'gate':'core-store','group':row['name'],'platform':platform,**parsed})
        require(set(core_test_names) == set(core_selection), 'Missing core/store test cohort')

        for label in ('native','node'):
            directory = evidence/label
            receipt = load(directory/'verification.json')
            require(receipt.get('success') is True and receipt['source_commit'] == head and receipt['source_tree'] == tree, label+' wrong result/source')
            for flag in ('source_unchanged','environment_unchanged','source_head_unchanged','source_index_unchanged','tracked_worktree_clean_after'):
                require(receipt.get(flag) is True, label+' did not preserve '+flag)
            require(not receipt.get('unexpected_native_mappings_after'), label+' unexpected native mapping')
            for name, identity in receipt['manifest_sha256'].items():
                require(sha(directory/name) == identity, label+' manifest hash mismatch '+name)
            before, after = (load(directory/name) for name in ('source-before.json','source-after.json'))
            env_before, env_after = (load(directory/name) for name in ('environment-before.json','environment-after.json'))
            require(before == after and env_before == env_after, label+' snapshot difference')
            for path, row in before.items():
                require(row.get('materialized') and not row.get('sparse_omission'), 'Unexpected sparse source '+path)
                require(path not in expected_source or expected_source[path] == row['sha256'], 'Cross-gate source mismatch '+path)
                expected_source[path] = row['sha256']
                identity = {'blob': row['git_blob'], 'mode': row['mode']}
                require(path not in source_git_records or source_git_records[path] == identity, 'Cross-gate Git identity mismatch '+path)
                source_git_records[path] = identity
            for name, identity in runtime_before.items():
                require(env_before.get(name) == identity, label+' runtime mismatch against aggregate '+name)
            plan = load(repo/receipt['plan'])
            require(sha(repo/receipt['plan']) == receipt['plan_sha256'], label+' changed plan')
            groups = {g['name']:g for g in plan['groups']}
            group_names=[]
            for row in receipt['runs']:
                require(row['exit_code']==0 and row.get('accepted') is True, label+' unaccepted group '+row['name'])
                log=directory/row['log']
                require(sha(log)==row['log_sha256'], label+' raw log hash mismatch '+row['name'])
                compressed=directory/row['compressed_log']
                require(sha(compressed)==row['compressed_log_sha256'] and gzip.decompress(compressed.read_bytes())==log.read_bytes(), label+' compressed/raw disagreement')
                if row['name'] not in groups:
                    require(row['name'] in {'analysis','format','whitespace'}, label+' unexpected command')
                    continue
                group_names.append(row['name'])
                group=groups[row['name']]
                platform=group.get('platform','vm')
                parsed=parse_events(log,repo/group['cwd'],repo,group['tests'],platform)
                require(parsed['passed']==row['passed'], label+' substantive count mismatch '+row['name'])
                cases_path=directory/row['cases_file'];errors_path=directory/row['errors_file']
                require(sha(cases_path)==row['cases_sha256'] and sha(errors_path)==row['errors_sha256'], label+' cases/errors hash mismatch')
                require(load(errors_path)==[], label+' retained reporter errors')
                observed=sorted((str(repo/c['suite']),c['name'],c['result'],c['skipped']) for c in parsed['cases'])
                retained=sorted((c['suite'],c['name'],c['result'],c['skipped']) for c in load(cases_path))
                require(observed==retained,label+' retained cases disagree')
                all_cases.extend(parsed.pop('cases'))
                group_results.append({'gate':label,'group':row['name'],'platform':platform,**parsed})
            require(set(group_names)==set(groups) and len(group_names)==len(groups), label+' wrong test group selection')
            require(receipt['passed']==sum(g['passed'] for g in group_results if g['gate']==label), label+' aggregate count mismatch')

        # Compare materialized execution inputs against immutable published Git blobs.
        tree_bytes=subprocess.check_output(['git','-C',str(repo),'ls-tree','-r','-z',head])
        blobs={}
        for entry in tree_bytes.split(b'\0'):
            if not entry:continue
            metadata,path=entry.split(b'\t',1);mode,kind,blob=metadata.decode().split()
            blobs[path.decode()]={'mode':mode,'type':kind,'blob':blob}
        cache={}
        process=subprocess.Popen(['git','-C',str(repo),'cat-file','--batch'],stdin=subprocess.PIPE,stdout=subprocess.PIPE)
        try:
            for name,expected in sorted(expected_source.items()):
                require(name in blobs and blobs[name]['type']=='blob','Bound source not in published tree '+name)
                if name in source_git_records:
                    require(all(blobs[name][key] == value for key,value in source_git_records[name].items()), 'Recorded Git identity differs from published tree '+name)
                blob=blobs[name]['blob']
                if blob not in cache:
                    process.stdin.write((blob+'\n').encode());process.stdin.flush()
                    header=process.stdout.readline().decode().strip().split()
                    require(len(header)==3 and header[0]==blob and header[1]=='blob','Unexpected Git object header')
                    remaining=int(header[2]);digest=hashlib.sha256()
                    while remaining:
                        data=process.stdout.read(min(remaining,1024*1024))
                        require(data,'Truncated Git blob');digest.update(data);remaining-=len(data)
                    require(process.stdout.read(1)==b'\n','Missing Git object delimiter')
                    cache[blob]=digest.hexdigest()
                require(cache[blob]==expected,'Published source bytes differ from run: '+name)
                require(sha(repo/name)==expected,'Current materialized source changed: '+name)
        finally:
            process.stdin.close();process.stdout.close();process.wait(timeout=30)
        retained=load(runtime/'retained-inputs.json')
        for name,row in retained.items():
            require(runtime_before['runtime/'+name]==row['sha256'] and sha(runtime/name)==row['sha256'],'Runtime source mismatch '+name)
        runtime_receipt=load(runtime/'runtime.json')
        for name,expected in runtime_receipt['additional_inputs'].items():
            require(runtime_before['additional/'+name]==expected and sha(Path(name))==expected,'Additional runtime mismatch '+name)
        for name,expected in runtime_before.items():
            if name.startswith('runtime/'):
                path=runtime/name[len('runtime/'):]
            elif name.startswith('additional/'):
                path=Path(name[len('additional/'):])
            elif name=='workspace/package_config.json':
                path=repo/'.dart_tool/package_config.json'
            elif name=='sdk/flutter_tools/package_config.json':
                path=runtime/'flutter/packages/flutter_tools/.dart_tool/package_config.json'
            else:
                raise AssertionError('Unknown aggregate runtime binding '+name)
            require(sha(path)==expected,'Current runtime/configuration changed '+name)
        execution_keys=[(c['suite'],c['name'],c['platform']) for c in all_cases]
        require(len(execution_keys)==len(set(execution_keys)),'Duplicate named test execution on same platform')
        scenarios={(c['suite'],c['name']) for c in all_cases}
        platforms=defaultdict(set)
        for c in all_cases:platforms[(c['suite'],c['name'])].add(c['platform'])
        result.update(status='PASS',source_commit=head,source_tree=tree,
                      published_commit=remote['url'],published_git_blob_inputs_verified=len(expected_source),
                      distinct_git_blobs_verified=len(cache),retained_runtime_inputs_verified=len(retained),
                      additional_runtime_inputs_verified=len(runtime_receipt['additional_inputs']),
                      passed_executions=len(all_cases),distinct_scenarios=len(scenarios),
                      cross_platform_repetitions=len(all_cases)-len(scenarios),
                      distinct_test_files=len({c['suite'] for c in all_cases}),
                      scenarios_on_both_platforms=sum(len(p)>1 for p in platforms.values()),
                      executions_by_platform=dict(Counter(c['platform'] for c in all_cases)),
                      groups=group_results,python_controls=counts_python,
                      python_controls_total=sum(counts_python.values()),
                      archives=[verify_archive(p.resolve()) for p in args.archive_index],
                      failed=0,skipped=0,unfinished=0,reporter_errors=0)
        save(output/'cases.json',sorted(all_cases,key=lambda c:(c['suite'],c['name'],c['platform'])))
        result['case_inventory_sha256']=sha(output/'cases.json')
    except BaseException as error:
        result.update(status='FAIL',errors=[repr(error)],traceback=traceback.format_exc())
    result['finished_at_utc']=datetime.now(timezone.utc).isoformat()
    save(output/'audit.json',result)
    print(json.dumps({k:result.get(k) for k in ('status','passed_executions','distinct_scenarios','cross_platform_repetitions','distinct_test_files','python_controls_total','errors')},indent=2))
    return 0 if result['status']=='PASS' else 1


if __name__=='__main__':
    sys.exit(main())
