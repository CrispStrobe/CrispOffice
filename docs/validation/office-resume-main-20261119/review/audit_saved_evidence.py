#!/usr/bin/env python3
"""Independently recount historical saved reporters and bind their original sources.

This does not execute application tests or validate a later integration commit.
Archive bytes were independently checked before this script extracts observations.
"""
import collections
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess

ROOT = Path('/workspace/scratch/261cd76b2166')
REPO = ROOT / 'quds_office_suite'
DATA = ROOT / 'evidence-review'


def check(value, detail):
    if not value:
        raise AssertionError(detail)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def read(path):
    return json.loads(path.read_bytes())


def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])


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


def phase(label, relative):
    base = DATA / label / 'accepted' / relative
    receipt = read(base / 'verification.json')
    source = receipt['source_commit']
    check(git('rev-parse', source + '^{tree}').decode().strip() == receipt['source_tree'], 'Source tree mismatch')
    plan_raw = git('show', source + ':' + receipt['plan'])
    check(digest(plan_raw) == receipt['plan_sha256'], 'Plan hash mismatch')
    plan = json.loads(plan_raw)
    check(plan['groups'] == receipt['planned_groups'], 'Receipt/committed plan groups mismatch')
    check(plan['analysis'] == receipt['analysis_files'] and plan['format'] == receipt['formatted_files'], 'Static plan mismatch')
    check(receipt['success'] is True and receipt['failed'] == receipt['skipped'] == 0, 'Receipt rejects run')
    check(receipt['github_actions_queried_or_awaited'] is False, 'Actions use declared')
    for name, sha in receipt['manifest_sha256'].items():
        check(digest((base / name).read_bytes()) == sha, 'Manifest hash mismatch')
    for prefix in ('source', 'environment'):
        check((base / (prefix+'-before.json')).read_bytes() == (base / (prefix+'-after.json')).read_bytes(), 'Recorded inventory changed')
    bound = source_binding(source, read(base / 'source-before.json'))
    check(bound['records'] == receipt['source_input_count'], 'Source count mismatch')
    check(len(read(base/'environment-before.json')) == receipt['runtime_input_count'], 'Runtime count mismatch')
    original_repo = str(PurePosixPath(receipt['package_config']).parent.parent)
    groups = {g['name']:g for g in plan['groups']}
    allcases = []
    group_results = []
    static = []
    for run in receipt['runs']:
        check(run['exit_code'] == 0 and run['accepted'] is True, 'Rejected/nonzero run: ' + run['name'])
        for key, hashkey in [('log','log_sha256'), ('compressed_log','compressed_log_sha256'), ('cases_file','cases_sha256'), ('errors_file','errors_sha256')]:
            if key in run:
                check(digest((base/run[key]).read_bytes()) == run[hashkey], 'Run file hash mismatch: '+run[key])
        raw = (base/run['log']).read_bytes()
        check(gzip.decompress((base/run['compressed_log']).read_bytes()) == raw, 'Compressed/raw mismatch')
        if run['name'] in groups:
            group = groups.pop(run['name'])
            requested = [(PurePosixPath(group['cwd'])/p).as_posix() for p in group['tests']]
            cases, counted = events_recount(raw, group['cwd'], original_repo, requested)
            check(len(cases) == run['passed'], 'Run passed count mismatch')
            saved = read(base/run['cases_file'])
            saved_ids = [(normalized(c['suite'], group['cwd'], original_repo), c['name']) for c in saved]
            check(set(saved_ids) == set(cases) and len(saved_ids) == len(cases), 'Saved/raw case mismatch')
            check(read(base/run['errors_file']) == [], 'Saved error list is nonempty')
            check(all(c['result']=='success' and c['skipped'] is False for c in saved), 'Saved failed/skipped case')
            allcases.extend(cases)
            group_results.append({'name':run['name'], **counted})
        else:
            static.append(run['name'])
            if run['name'] == 'analysis':
                check('--fatal-infos' in run['command'] and '--fatal-warnings' in run['command'], 'Non-strict analysis')
                check('No issues found!' in raw.decode(), 'Analysis log lacks success')
            if run['name'] == 'format':
                check('--set-exit-if-changed' in run['command'] and b'0 changed' in raw, 'Formatting not clean')
    check(not groups and len(allcases) == receipt['passed'], 'Missing planned groups or total mismatch')
    check(len(allcases) == len(set(allcases)), 'Duplicate case across groups')
    return {'phase':relative, 'source_commit':source, 'source_tree':receipt['source_tree'], 'started_at_utc':receipt['started_at_utc'], 'finished_at_utc':receipt['finished_at_utc'], 'passed_executions':len(allcases), 'suite_count':len({c[0] for c in allcases}), 'groups':group_results, 'analysis_paths':len(receipt['analysis_files']), 'format_paths':len(receipt['formatted_files']), 'static_runs':static, 'source_binding':bound, 'runtime_inventory_records':receipt['runtime_input_count'], 'recorded_before_after_source_and_runtime_identical':True, 'passed':True}, set(allcases)


def main():
    result = {'checked_at_utc':datetime.now(timezone.utc).isoformat(), 'scope':'Independent integrity and raw-event recount of historical saved evidence only. No application execution, current-source acceptance, installed OS/browser acceptance, or current external runtime readback is claimed.', 'archive_integrity':read(DATA/'archive-audit.json'), 'qualifications':{}}
    for label, phases in [('host',['main','node']), ('sync',['raw/native','raw/node'])]:
        rows = []; identities = set(); executions = 0; suite_runs = 0
        for relative in phases:
            row, cases = phase(label,relative)
            rows.append(row); identities |= cases; executions += row['passed_executions']; suite_runs += row['suite_count']
        result['qualifications'][label] = {'phases':rows, 'passed_executions':executions, 'distinct_cases':len(identities), 'suite_platform_runs':suite_runs, 'distinct_suite_paths':len({x[0] for x in identities}), 'passed':True}
    outer = DATA/'sync'/'accepted'/'raw'; execution=read(outer/'execution.json'); source=execution['source_commit']
    check(execution['status']=='PASS' and execution['source_tree']==git('rev-parse',source+'^{tree}').decode().strip(),'Outer source/status mismatch')
    for prefix in ('source','runtime'):
        check((outer/(prefix+'-before.json')).read_bytes()==(outer/(prefix+'-after.json')).read_bytes(),'Outer inventories changed')
    binding=source_binding(source,read(outer/'source-before.json'))
    controls={}
    for run in execution['runs']:
        check(run['exit_code']==0 and run['accepted'] is True,'Outer run failed')
        raw=(outer/run['log']).read_bytes();check(digest(raw)==run['log_sha256'],'Outer log mismatch')
        if run['name'] in ('bundle-controls','packaging-controls'):
            text=raw.decode(); m=re.search(r'Ran (\d+) tests? in ',text)
            check(m and re.search(r'^OK\s*$',text,re.M),'Python controls not accepted')
            controls[run['name']]=int(m.group(1))
    result['qualifications']['sync']['outer']={'source_binding':binding,'runtime_records':len(read(outer/'runtime-before.json')),'python_controls':controls,'python_controls_total':sum(controls.values()),'prior_application_cases_added_to_delta':execution['prior_application_cases_added_to_delta'],'rejected_attempts_added_to_delta':execution['rejected_attempts_added_to_delta'],'all_outer_logs_hash_verified':True}
    result['all_passed']=result['archive_integrity']['all_passed'] and all(x['passed'] for x in result['qualifications'].values())
    result['script_sha256']=digest(Path(__file__).read_bytes())
    path=ROOT/'saved-evidence-independent-audit.json';path.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'all_passed':result['all_passed'],'archives':result['archive_integrity']['archive_count'],'archive_members':result['archive_integrity']['member_count'],'qualifications':{k:{n:v for n,v in x.items() if n!='phases'} for k,x in result['qualifications'].items()},'output':str(path)},indent=2))


if __name__=='__main__':
    main()
