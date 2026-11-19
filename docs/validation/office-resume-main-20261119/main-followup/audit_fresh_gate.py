#!/usr/bin/env python3
"""Independently audit completed fresh native/Node qualification receipts.

Reads frozen Git objects, committed plans, raw reporters and live bound runtime
files. Does not run application tests, fetch objects, write refs/index/source,
or accept incomplete receipts. Counts are reconstructed from raw events.
"""
import argparse
import collections
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess

REPO = None
RUNTIME = None
SOURCE = None
LIVE_SOURCE = True
FILE_HASHES = {}
RUNNER = 'docs/validation/document-review-notes-20261118/run_checks.py'

def check(value, detail):
    if not value:
        raise AssertionError(detail)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def read(path):
    return json.loads(path.read_bytes())


def git(*args):
    return subprocess.check_output(['git', '--no-lazy-fetch', '-C', str(REPO), *args], env={**os.environ, 'GIT_OPTIONAL_LOCKS':'0'})


def tree(commit):
    rows = {}
    for item in git('ls-tree', '-r', '-z', commit).split(b'\0'):
        if not item:
            continue
        meta, path = item.decode().split('\t', 1)
        mode, kind, sha = meta.split()
        rows[path] = (mode, kind, sha)
    return rows


HASH_CACHE = {}


def hash_blobs(oids):
    need = sorted(set(oids) - HASH_CACHE.keys())
    if not need:
        return
    proc = subprocess.Popen(['git', '--no-lazy-fetch', '-C', str(REPO), 'cat-file', '--batch'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    for oid in need:
        proc.stdin.write((oid + '\n').encode())
        proc.stdin.flush()
        fields = proc.stdout.readline().decode().strip().split()
        check(len(fields) == 3 and fields[0] == oid and fields[1] == 'blob', 'Missing or nonblob object: ' + oid)
        size = int(fields[2])
        raw = proc.stdout.read(size)
        check(len(raw) == size and proc.stdout.read(1) == b'\n', 'Bad cat-file body')
        HASH_CACHE[oid] = digest(raw)
    proc.stdin.close()
    check(proc.wait() == 0, 'cat-file failed')


def source_binding(commit, source):
    entries = tree(commit)
    oids = []
    for path, value in source.items():
        check(path in entries, 'Untracked bound source: ' + path)
        mode, kind, oid = entries[path]
        check(kind == 'blob', 'Nonblob source: ' + path)
        if isinstance(value, dict):
            check(mode == value['mode'] and oid == value['git_blob'], 'Git identity mismatch: ' + path)
            check(value.get('materialized') is True and not value.get('sparse_omission'), 'Unmaterialized source: ' + path)
        oids.append(oid)
    hash_blobs(oids)
    for path, value in source.items():
        want = value['sha256'] if isinstance(value, dict) else value
        check(HASH_CACHE[entries[path][2]] == want, 'Source content hash mismatch: ' + path)
    return {'records': len(source), 'all_git_entries_and_content_hashes_match': True}


def normalized(path, cwd, original_repo):
    p = PurePosixPath(path)
    if p.is_absolute():
        return p.relative_to(PurePosixPath(original_repo)).as_posix()
    return (PurePosixPath(cwd) / p).as_posix()


def events_recount(raw, cwd, original_repo, requested):
    events = []
    hook_lines = 0
    for line in raw.decode().splitlines():
        line = line.strip()
        while line.startswith(('Running build hooks...', 'Running link hooks...')):
            prefix = next(x for x in ('Running build hooks...', 'Running link hooks...') if line.startswith(x))
            hook_lines += 1
            line = line[len(prefix):].strip()
        if line:
            e = json.loads(line)
            check(isinstance(e, dict) and isinstance(e.get('type'), str), 'Malformed reporter event')
            events.append(e)
    kinds = collections.Counter(e['type'] for e in events)
    check(events[0]['type'] == 'start' and events[-1]['type'] == 'done', 'Invalid reporter boundaries')
    check(kinds['start'] == kinds['done'] == kinds['allSuites'] == 1, 'Duplicate/missing reporter boundaries')
    check(events[-1]['success'] is True, 'Unsuccessful reporter terminal')
    check(set(kinds) <= {'start', 'done', 'allSuites', 'suite', 'group', 'testStart', 'testDone', 'print'}, 'Error/unknown reporter event')
    suites, starts, dones, groups = {}, {}, {}, {}
    for e in events:
        kind = e['type']
        if kind == 'allSuites':
            check(e['count'] == len(requested), 'Suite-count mismatch')
        elif kind == 'suite':
            v = e['suite']; ident = v['id']
            check(ident not in suites, 'Duplicate suite')
            suites[ident] = normalized(v['path'], cwd, original_repo)
        elif kind == 'group':
            v = e['group']; ident = v['id']
            check(ident not in groups and v['suiteID'] in suites, 'Bad group')
            check(not v.get('metadata', {}).get('skip'), 'Skipped group')
            check(v.get('parentID') is None or v['parentID'] in groups, 'Unknown parent group')
            groups[ident] = v
        elif kind == 'testStart':
            v = e['test']; ident = v['id']
            check(ident not in starts and v['suiteID'] in suites, 'Duplicate/invalid start')
            check(not v.get('metadata', {}).get('skip'), 'Skipped test')
            check(all(g in groups for g in v['groupIDs']), 'Unknown group')
            starts[ident] = v
        elif kind == 'testDone':
            ident = e['testID']
            check(ident in starts and ident not in dones, 'Missing start/duplicate completion')
            check(e['result'] == 'success' and e['skipped'] is False, 'Failed/skipped completion, including setup/teardown')
            check(type(e.get('hidden')) is bool, 'Invalid hidden flag')
            dones[ident] = e
        elif kind == 'print':
            check(e['testID'] in starts, 'Unknown print test')
            check(not re.search(r'A Render\w+ overflowed|RenderBox was not laid out|would not hit test|does not receive pointer events|EXCEPTION CAUGHT BY (?:RENDERING|WIDGETS|FLUTTER TEST) LIBRARY|setState\(\) called after dispose\(\)', e['message'], re.I), 'Widget diagnostic')
    check(starts.keys() == dones.keys(), 'Unfinished tests')
    check(set(suites.values()) == set(requested) and len(set(suites.values())) == len(suites), 'Suite coverage mismatch')
    cases = []
    excluded = 0
    for ident, done in dones.items():
        start = starts[ident]
        if done['hidden'] or start['name'].startswith('loading ') or re.search(r'(?:^| )\((?:setUpAll|tearDownAll)\)$', start['name']):
            excluded += 1
        else:
            cases.append((suites[start['suiteID']], start['name']))
    check(len(set(cases)) == len(cases), 'Duplicate case identities')
    check({c[0] for c in cases} == set(requested), 'Empty selected suite')
    return cases, {'passed_executions':len(cases), 'suite_count':len(suites), 'excluded_successful_setup_loading_teardown_events':excluded, 'known_native_hook_prefixes':hook_lines, 'errors_failures_skips_unfinished_duplicate_cases':0, 'exact_suite_coverage':True, 'terminal_success':True}


def filehash(path):
    path = Path(path)
    if path not in FILE_HASHES:
        check(path.is_file(), 'Missing live bound file: ' + str(path))
        with path.open('rb') as stream:
            FILE_HASHES[path] = hashlib.file_digest(stream, 'sha256').hexdigest()
    return FILE_HASHES[path]


def source_expected(plan, plan_path, changed):
    entries = tree(SOURCE)
    selected = {p for p in entries if p.startswith(('packages/', 'apps/', 'third_party/'))}
    selected |= {p for p in entries if '/' not in p and Path(p).suffix in {'.yaml', '.lock'}}
    selected |= {plan_path, RUNNER, 'tools/mail/check_store.py', 'tools/mail/check_reader.py'}
    selected |= set(plan.get('extra_inputs', []))
    selected |= {r['path'] for r in plan.get('whitespace_preserved_inputs', [])}
    for g in plan['groups']:
        selected |= {(PurePosixPath(g['cwd'])/p).as_posix() for p in g['tests']}
    for category in ('analysis', 'format'):
        value = plan.get(category, 'changed')
        selected |= set(changed if value == 'changed' else value)
    return selected


def environment_path(name):
    if name.startswith('runtime/'):
        return RUNTIME/name[len('runtime/'):]
    if name.startswith('additional/'):
        path = Path(name[len('additional/'):])
        check(path.is_absolute(), 'Nonabsolute additional runtime input')
        return path
    fixed = {
        'workspace/pubspec.lock': REPO/'pubspec.lock',
        'workspace/package_config.json': REPO/'.dart_tool/package_config.json',
        'workspace/native_assets.yaml': REPO/'.dart_tool/native_assets.yaml',
        'sdk/flutter_tools/package_config.json': RUNTIME/'flutter/packages/flutter_tools/.dart_tool/package_config.json',
    }
    if name in fixed:
        return fixed[name]
    check(name.startswith('workspace/') and name.endswith('/.dart_tool/native_assets.yaml'), 'Unrecognized environment binding: '+name)
    return REPO/name[len('workspace/'):]


def verify_environment(record, inventory):
    runtime_receipt = read(RUNTIME/'runtime.json')
    check(filehash(RUNTIME/'runtime.json') == record['runtime_receipt_sha256'], 'Runtime receipt changed')
    check(runtime_receipt['status'] == 'ready' and runtime_receipt['archive']['verified'] is True, 'Runtime not ready/verified')
    check(record['runtime'] == runtime_receipt['runtime'], 'Runtime metadata mismatch')
    check(record['additional_runtime_inputs'] == runtime_receipt['additional_inputs'], 'Additional input map mismatch')
    check(record['workspace_lock_sha256'] == runtime_receipt['workspace_lock_sha256'] == filehash(REPO/'pubspec.lock'), 'Dependency lock mismatch')
    retained = read(RUNTIME/'retained-inputs.json')
    for name, value in retained.items():
        check(inventory['runtime/'+name] == value['sha256'], 'Retained runtime fingerprint mismatch')
        check(filehash(RUNTIME/name) == value['sha256'], 'Retained runtime bytes changed')
    absents = []
    for name, expected in inventory.items():
        path = environment_path(name)
        if expected is None:
            check(not path.exists() and not path.is_symlink(), 'Unexpected nearer native-assets mapping')
            absents.append(name)
        else:
            check(filehash(path) == expected, 'Live runtime digest mismatch: '+name)
    for path, expected in runtime_receipt['executables_sha256'].items():
        check(filehash(path) == expected, 'SDK executable mismatch')
    launcher=Path(record['test_launcher'])
    check(launcher.is_relative_to(RUNTIME/'pub-cache/hosted/pub.dev'), 'Launcher outside hosted cache')
    key=launcher.relative_to(RUNTIME).as_posix()
    check(retained[key]['sha256'] == filehash(launcher), 'Unbound launcher')
    return {'inventory_records':len(inventory),'retained_runtime_files':len(retained),'observed_absent_native_mappings':absents,'all_present_inputs_rehashed':True,'runtime_receipt_sha256':filehash(RUNTIME/'runtime.json')}


def audit_phase(base, label):
    record = read(base/'verification.json')
    check(record.get('finished_at_utc') and record.get('success') is True, 'Incomplete or rejected gate: '+label)
    check(record['source_commit'] == SOURCE, 'Wrong qualified source')
    check(record['source_tree'] == git('rev-parse', SOURCE+'^{tree}').decode().strip(), 'Wrong qualified tree')
    for name in ('tracked_worktree_clean_before','tracked_worktree_clean_after','source_unchanged','environment_unchanged','source_head_unchanged','source_index_unchanged'):
        check(record.get(name) is True, 'Source/environment invariant failed: '+name)
    check(record['github_actions_queried_or_awaited'] is False, 'Actions usage declared')
    for name in ('failed','skipped','source_mismatches','environment_mismatches','unexpected_native_mappings_after'):
        check(not record[name], 'Nonempty failure field: '+name)
    plan_raw = git('show',SOURCE+':'+record['plan'])
    check(digest(plan_raw) == record['plan_sha256'], 'Committed plan hash mismatch')
    if LIVE_SOURCE:
        check(filehash(REPO/record['plan']) == record['plan_sha256'], 'Working plan changed')
    plan=json.loads(plan_raw)
    check(plan['groups']==record['planned_groups'], 'Plan group mismatch')
    changed=[p for p in git('diff','--name-only','--diff-filter=ACMRT','-z',record['source_base'],SOURCE).decode().split('\0') if p.endswith('.dart') and p.startswith(('packages/','apps/'))]
    for category,field in [('analysis','analysis_files'),('format','formatted_files')]:
        selection=plan.get(category,'changed')
        check((changed if selection=='changed' else selection)==record[field], 'Static-check selection mismatch')
    for name,sha in record['manifest_sha256'].items():
        check(filehash(base/name)==sha,'Inventory/receipt hash mismatch')
    for kind in ('source','environment'):
        check((base/(kind+'-before.json')).read_bytes()==(base/(kind+'-after.json')).read_bytes(),'Before/after inventory changed')
    sources=read(base/'source-before.json')
    check(set(sources)==source_expected(plan,record['plan'],changed),'Bound source set differs from independently reconstructed selection')
    source_result=source_binding(SOURCE,sources)
    check(len(sources)==record['source_input_count']==record['materialized_source_inputs'],'Missing source inputs')
    check(record['sparse_source_omissions']==[],'Sparse inputs omitted')
    if LIVE_SOURCE:
        for path,entry in sources.items():
            check(filehash(REPO/path)==entry['sha256'],'Live bound source bytes changed: '+path)
    environment=read(base/'environment-before.json')
    check(len(environment)==record['runtime_input_count'],'Environment count mismatch')
    environment_result=verify_environment(record,environment)
    groups={g['name']:g for g in plan['groups']};cases=[];cohorts=[];static=[];run_names=[]
    for run in record['runs']:
        run_names.append(run['name'])
        check(run['exit_code']==0 and run['accepted'] is True,'Rejected/nonzero child process')
        for key,hashkey in [('log','log_sha256'),('compressed_log','compressed_log_sha256'),('cases_file','cases_sha256'),('errors_file','errors_sha256'),('stderr_log','stderr_log_sha256'),('stderr_compressed_log','stderr_compressed_log_sha256')]:
            if key in run:
                check(filehash(base/run[key])==run[hashkey],'Saved run hash mismatch: '+run[key])
        raw=(base/run['log']).read_bytes()
        check(gzip.decompress((base/run['compressed_log']).read_bytes())==raw,'Raw/compressed log mismatch')
        if 'stderr_log' in run:
            stderr=(base/run['stderr_log']).read_bytes()
            check(gzip.decompress((base/run['stderr_compressed_log']).read_bytes())==stderr,'Raw/compressed stderr mismatch')
            check(not re.search(r'A Render\w+ overflowed|RenderBox was not laid out|would not hit test|EXCEPTION CAUGHT BY (?:RENDERING|WIDGETS|FLUTTER TEST) LIBRARY|setState\(\) called after dispose\(\)',stderr.decode(),re.I),'Widget diagnostic on stderr')
        if run['name'] in groups:
            group=groups.pop(run['name'])
            requested=[(PurePosixPath(group['cwd'])/p).as_posix() for p in group['tests']]
            recount,counts=events_recount(raw,group['cwd'],str(REPO),requested)
            check(run['cwd']==group['cwd'],'Group working directory mismatch')
            check('--reporter=json' in run['command'],'Non-JSON test command')
            check(all(t in run['command'] for t in group['tests']),'Command misses committed suite')
            if group.get('platform')=='node':
                check(any(x in run['command'] for x in ['--platform=node','node']),'Node platform command mismatch')
            check(len(recount)==run['passed'] and not run['failed'] and not run['skipped'],'Receipt/recount mismatch')
            saved=read(base/run['cases_file'])
            identities=[(normalized(c['suite'],group['cwd'],str(REPO)),c['name']) for c in saved]
            check(set(identities)==set(recount) and len(identities)==len(recount),'Saved case list/recount mismatch')
            check(all(c['result']=='success' and c['skipped'] is False for c in saved),'Saved unsuccessful case')
            check(read(base/run['errors_file'])==[],'Saved errors present')
            check(run.get('strict_event_accounting',{}).get('valid') is True,'Runner rejected reporter protocol')
            cases.extend(recount);cohorts.append({'name':run['name'],'platform':group.get('platform','vm'),**counts})
        else:
            check(run['name'] in {'analysis','format','whitespace'},'Unexpected validation run')
            text=raw.decode();static.append(run['name'])
            if run['name']=='analysis':
                check('--fatal-infos' in run['command'] and '--fatal-warnings' in run['command'],'Non-strict analysis')
                check('No issues found!' in text and not re.search(r'^\s*(?:error|warning|info)\s*[•-]',text,re.I|re.M),'Analysis diagnostic')
            elif run['name']=='format':
                check('--set-exit-if-changed' in run['command'] and '0 changed' in text,'Formatting changed')
            else:
                check(raw==b'','Whitespace diagnostics')
    check(len(run_names)==len(set(run_names)) and not groups,'Duplicate/missing run')
    check(len(cases)==len(set(cases))==record['passed'],'Duplicate case or wrong total')
    check(('analysis' in static)==bool(record['analysis_files']) and ('format' in static)==bool(record['formatted_files']) and 'whitespace' in static,'Static gate missing')
    return {'phase':label,'source_commit':SOURCE,'source_tree':record['source_tree'],'source_base':record['source_base'],'plan':record['plan'],'plan_sha256':record['plan_sha256'],'verification_sha256':filehash(base/'verification.json'),'started_at_utc':record['started_at_utc'],'finished_at_utc':record['finished_at_utc'],'groups':cohorts,'passed_executions':len(cases),'suite_count':len({p for p,n in cases}),'analysis_paths':len(record['analysis_files']),'formatted_paths':len(record['formatted_files']),'source_binding':source_result,'runtime_binding':environment_result,'recorded_source_and_environment_before_after_identical':True,'passed':True},set(cases),sources,environment


def audit_fixtures(fixtures):
    path=fixtures/'fixture-build.json';receipt=read(path)
    runtime_receipt=read(RUNTIME/'runtime.json')
    declaration=runtime_receipt['synthetic_hunspell_fixtures']
    check(Path(declaration['receipt'])==path and declaration['sha256']==filehash(path),'Fixture/runtime binding mismatch')
    check(declaration['environment']==receipt['environment'],'Fixture environment mismatch')
    check(filehash(fixtures/'env.sh')==receipt['environment_script_sha256'],'Fixture environment script mismatch')
    compiler=Path(receipt['compiler']['path'])
    check(filehash(compiler)==receipt['compiler']['sha256'],'Compiler bytes changed')
    implementation='docs/validation/office-resume-main-20261119/prepare_native_fixtures.py'
    check(digest(git('show',SOURCE+':'+implementation))==receipt['implementation_sha256'],'Fixture builder/source binding mismatch')
    check(len(receipt['builds'])==3,'Expected three synthetic fixtures')
    libraries=[]
    for build in receipt['builds']:
        check(build['exit_code']==0,'Fixture build failed')
        check(digest(git('show',SOURCE+':'+build['source']))==build['source_sha256'],'Fixture native source mismatch')
        check(filehash(fixtures/build['log'])==build['log_sha256'],'Fixture build log mismatch')
        library=Path(build['library'])
        check(library.stat().st_size==build['bytes'] and filehash(library)==build['sha256'],'Compiled fixture mismatch')
        check(runtime_receipt['additional_inputs'][str(library)]==build['sha256'],'Fixture library not bound in runtime')
        check(str(library) in receipt['environment'].values(),'Fixture has no environment selection')
        libraries.append({'source':build['source'],'source_sha256':build['source_sha256'],'library':str(library),'sha256':build['sha256'],'bytes':build['bytes']})
    return {'scope':receipt['scope'],'receipt_sha256':filehash(path),'compiler_sha256':filehash(compiler),'libraries':libraries,'all_bound_native_builds_verified':True}


def main():
    global REPO,RUNTIME,SOURCE,LIVE_SOURCE
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--runtime',type=Path,required=True)
    parser.add_argument('--fixtures',type=Path,required=True)
    parser.add_argument('--source',required=True)
    parser.add_argument('--native',type=Path,required=True)
    parser.add_argument('--node',type=Path)
    parser.add_argument('--historical-source',action='store_true',help='Audit a completed prior source through pinned Git objects and receipts; do not claim current worktree source identity.')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();REPO=args.repo.resolve();RUNTIME=args.runtime.resolve();SOURCE=args.source;LIVE_SOURCE=not args.historical_source
    if LIVE_SOURCE:
        check(git('rev-parse','HEAD').decode().strip()==SOURCE,'Current checkout is no longer the frozen source')
    rows=[];identities=set();all_sources={};envs=[];phase_cases={}
    selected_phases=[('native',args.native)]+([('node',args.node)] if args.node else [])
    for label,path in selected_phases:
        row,cases,sources,environment=audit_phase(path.resolve(),label)
        rows.append(row);identities|=cases;phase_cases[label]=cases;envs.append(environment)
        for name,value in sources.items():
            check(name not in all_sources or all_sources[name]==value,'Source differs between native and Node')
            all_sources[name]=value
    overlap=set(envs[0]) if len(envs)==1 else set(envs[0])&set(envs[1])
    if len(envs)>1:
        check(all(envs[0][p]==envs[1][p] for p in overlap),'Shared runtime differs between phases')
    fixture_result=audit_fixtures(args.fixtures.resolve())
    if LIVE_SOURCE:
        check(git('rev-parse','HEAD').decode().strip()==SOURCE,'Head moved during audit')
        check(not git('diff','--name-only',SOURCE,'--'),'Tracked worktree/index changed during audit')
    case_path=args.output.with_name(args.output.stem+'-cases.json')
    case_rows=[{'phase':phase,'suite':s,'name':n} for phase in sorted(phase_cases) for s,n in sorted(phase_cases[phase])]
    case_path.write_text(json.dumps(case_rows,ensure_ascii=False,indent=2)+'\n')
    result={'checked_at_utc':datetime.now(timezone.utc).isoformat(),'source_commit':SOURCE,'source_tree':git('rev-parse',SOURCE+'^{tree}').decode().strip(),'scope':'Independent raw-reporter acceptance for the explicitly named completed source and included committed native/Node plans only. Synthetic native C ABI fixtures, controlled Mail and Flutter widgets do not establish actual browser, installed OS, live external accounts, real dictionaries or linguistic acceptance. Other sources and rejected attempts contribute zero.','historical_source_mode':not LIVE_SOURCE,'live_source_bytes_verified':LIVE_SOURCE,'node_phase_included':bool(args.node),'phases':rows,'passed_executions':sum(r['passed_executions'] for r in rows),'distinct_cases':len(identities),'suite_platform_runs':sum(r['suite_count'] for r in rows),'distinct_suite_paths':len({p for p,n in identities}),'node_cases_repeating_native':len(phase_cases['native']&phase_cases.get('node',set())),'source_union_records':len(all_sources),'shared_runtime_records':len(overlap),'shared_runtime_identical':True,'fixture_binding':fixture_result,'case_inventory':{'file':case_path.name,'sha256':filehash(case_path),'records':len(case_rows)},'live_file_hashes_checked':len(FILE_HASHES),'script_sha256':digest(Path(__file__).read_bytes()),'other_source_or_rejected_case_contribution':0,'application_tests_executed_by_auditor':0,'github_actions_calls':0,'git_lazy_fetch_disabled':True,'repository_mutations_performed':0,'passed':True}
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:result[k] for k in ('source_commit','passed_executions','distinct_cases','suite_platform_runs','distinct_suite_paths','source_union_records','shared_runtime_records','passed')},indent=2))


if __name__=='__main__':
    main()
