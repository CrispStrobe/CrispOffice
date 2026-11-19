#!/usr/bin/env python3
"""Independently audit frozen Dart/Flutter run_checks evidence, without executing tests.

Repeat --plan and --output-dir in matching order to combine native and Node runs.
All cases are reconstructed from reporter events; no expected case count is used.
The audit reads the live bound runtime. Regenerated runs at new locations require
new truthful receipts. It never edits the raw evidence directory or repository.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urljoin, urlsplit

import yaml

SOURCE_PREFIXES = ('packages/', 'apps/', 'third_party/')
RUNNER = 'docs/validation/document-review-notes-20261118/run_checks.py'
DIAGNOSTICS = re.compile(
    r'A Render\w+ overflowed|overflowed by \d+(?:\.\d+)? pixels|'
    r'RenderBox was not laid out|setState\(\) called after dispose|'
    r'A Timer is still pending|pending timers|EXCEPTION CAUGHT BY|'
    r'would not hit test|would not hit-test|missed.?tap|'
    r'derived an Offset that would not hit test|'
    r'warning:.*(?:tap|hit.?test)|unhandled exception|fatal error',
    re.I,
)
SHA256 = re.compile(r'^[0-9a-f]{64}$')


class AuditError(Exception):
    pass


def unique_json_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise AuditError('Duplicate JSON key: ' + str(key))
        result[key] = value
    return result


def decode(data):
    return json.loads(data, object_pairs_hook=unique_json_keys,
                      parse_constant=lambda value: (_ for _ in ()).throw(
                          AuditError('Non-finite JSON number: ' + value)))


def sha(data):
    return hashlib.sha256(data).hexdigest()


def checked_relative(name):
    if not isinstance(name, str) or not name or Path(name).is_absolute() or '..' in Path(name).parts:
        raise AuditError('Expected bounded relative path: ' + repr(name))
    if Path(name).as_posix() != name:
        raise AuditError('Noncanonical relative path: ' + name)
    return name


def file_uri(uri, base):
    if not isinstance(uri, str):
        raise AuditError('Local URI must be a string')
    parsed = urlsplit(urljoin(base.as_uri(), uri))
    if parsed.scheme != 'file' or parsed.netloc or parsed.query or parsed.fragment:
        raise AuditError('Expected local file URI: ' + uri)
    return Path(unquote(parsed.path)).resolve()


def repo_suite(path, repo, cwd):
    if not isinstance(path, str) or not path:
        raise AuditError('Suite path must be nonempty text')
    if path.startswith('file:'):
        full = file_uri(path, repo / 'placeholder')
    else:
        full = Path(path)
        if not full.is_absolute():
            full = repo / cwd / full
        full = full.resolve()
    try:
        return full.relative_to(repo).as_posix()
    except ValueError as error:
        raise AuditError('Suite escapes source checkout: ' + path) from error


def outcome_counts(cases):
    """Count visible completions by their recorded outcome, independent of acceptance."""
    counts = dict(executions=0, passed=0, failed=0, skipped=0)
    for case in cases:
        counts['executions'] += 1
        if case.get('skipped') is True:
            counts['skipped'] += 1
        elif case.get('result') == 'success':
            counts['passed'] += 1
        else:
            counts['failed'] += 1
    return counts


def reported_outcomes_match(record, reconstructed):
    """An honestly reported failed run has matching counts but is not accepted."""
    return all(type(record.get(kind)) is int and record[kind] == reconstructed[kind]
               for kind in ('passed', 'failed', 'skipped'))


def reparse_events(data, repo, cwd, requested, platform):
    """Build an independent lifecycle ledger directly from JSON events."""
    issues = []
    suites, groups, tests, completions = {}, {}, {}, {}
    event_counts = Counter()
    cases = []
    diagnostic_messages = []
    printed_messages = []
    error_events = []
    global_ids = set()
    all_suites_counts = []
    done_values = []
    previous_time = -1
    terminal_seen = False

    def demand(ok, text):
        if not ok:
            issues.append(text)

    def register(identifier, label):
        if type(identifier) is not int or identifier < 0 or identifier in global_ids:
            raise AuditError('Invalid/repeated global ' + label + ' ID: ' + repr(identifier))
        global_ids.add(identifier)

    lines = data.decode('utf-8', errors='strict').splitlines()
    for line_no, line in enumerate(lines, 1):
        try:
            if not line.strip():
                raise AuditError('Blank/non-event stdout line')
            event = decode(line)
            if not isinstance(event, dict) or not isinstance(event.get('type'), str):
                raise AuditError('Reporter event must have a string type')
            kind = event['type']
            event_counts[kind] += 1
            demand(not terminal_seen, f'Event after terminal success at line {line_no}')
            stamp = event.get('time')
            if type(stamp) is not int or stamp < previous_time:
                raise AuditError('Missing, negative or nonmonotonic reporter time')
            previous_time = stamp
            if line_no == 1:
                demand(kind == 'start', 'Reporter does not begin with start')
            if kind != 'start':
                demand(event_counts['start'] == 1, 'Event outside one runner start')
            if kind == 'start':
                demand(event_counts['start'] == 1 and line_no == 1, 'Repeated/late runner start')
                demand(isinstance(event.get('protocolVersion'), str), 'No reporter protocol version')
            elif kind == 'suite':
                suite = event['suite']
                identifier = suite['id']; register(identifier, 'suite')
                name = repo_suite(suite['path'], repo, cwd)
                demand(name in requested, 'Unexpected suite: ' + name)
                demand(name not in {s['path'] for s in suites.values()}, 'Suite announced twice: ' + name)
                demand(suite.get('platform') == platform, 'Wrong suite platform: ' + name)
                suites[identifier] = dict(path=name, platform=suite.get('platform'))
            elif kind == 'allSuites':
                all_suites_counts.append(event.get('count'))
                demand(type(event.get('count')) is int and event['count'] == len(requested),
                       'Declared suite count differs from exact selection')
            elif kind == 'group':
                group = event['group']; identifier = group['id']; register(identifier, 'group')
                demand(group.get('suiteID') in suites, 'Group references unknown suite')
                parent = group.get('parentID')
                demand(parent is None or (parent in groups and groups[parent]['suiteID'] == group['suiteID']),
                       'Group parent absent or belongs to another suite')
                demand(group.get('metadata', {}).get('skip') is False, 'Skipped group metadata')
                groups[identifier] = group
            elif kind == 'testStart':
                test = event['test']; identifier = test['id']; register(identifier, 'test')
                demand(test.get('suiteID') in suites, 'Started test references unknown suite')
                demand(isinstance(test.get('name'), str) and bool(test['name']), 'Empty test name')
                demand(test.get('metadata', {}).get('skip') is False, 'Skipped test metadata')
                group_ids = test.get('groupIDs')
                demand(isinstance(group_ids, list), 'Invalid group membership')
                if isinstance(group_ids, list):
                    demand(len(set(group_ids)) == len(group_ids), 'Repeated group membership')
                    for group_id in group_ids:
                        demand(group_id in groups and groups[group_id]['suiteID'] == test.get('suiteID'),
                               'Test references unknown/foreign group')
                tests[identifier] = test
            elif kind == 'testDone':
                identifier = event.get('testID')
                if identifier not in tests:
                    raise AuditError('Completion without start: ' + repr(identifier))
                if identifier in completions:
                    raise AuditError('Second completion for one start: ' + repr(identifier))
                completions[identifier] = event
                test = tests[identifier]
                demand(event.get('result') in {'success', 'failure', 'error'}, 'Invalid result value: ' + test['name'])
                demand(type(event.get('skipped')) is bool, 'Invalid skipped marker: ' + test['name'])
                demand(event.get('result') == 'success', 'Unsuccessful test: ' + test['name'])
                demand(event.get('skipped') is False, 'Skipped completion: ' + test['name'])
                hidden = event.get('hidden')
                demand(type(hidden) is bool, 'Missing visibility marker: ' + test['name'])
                infrastructure = (test['name'].startswith('loading ') or
                                  re.search(r'\((?:setUpAll|tearDownAll)\)$', test['name']) is not None)
                if hidden is True:
                    demand(infrastructure, 'A non-infrastructure case was hidden: ' + test['name'])
                elif hidden is False:
                    demand(not test['name'].startswith('loading '), 'Visible loader event')
                    suite = suites.get(test.get('suiteID'), {})
                    cases.append(dict(id=identifier, suite=suite.get('path'), name=test['name'],
                                      platform=platform, result=event.get('result'), skipped=event.get('skipped')))
            elif kind == 'print':
                demand(event.get('testID') in tests, 'Print references unknown test')
                message = event.get('message')
                demand(isinstance(message, str), 'Print message is not text')
                demand(event.get('messageType') == 'print', 'Unexpected print message category')
                if isinstance(message, str):
                    printed_messages.append(message)
                    if DIAGNOSTICS.search(message):
                        diagnostic_messages.append(message)
            elif kind == 'error':
                error_events.append(event)
                issues.append('Reporter error event: ' + str(event.get('error', event))[:1200])
            elif kind == 'done':
                done_values.append(event.get('success')); terminal_seen = True
                demand(event.get('success') is True, 'Reporter terminal result is not success')
            else:
                raise AuditError('Unexpected reporter event: ' + kind)
        except (KeyError, TypeError, ValueError, AuditError) as error:
            issues.append(f'Line {line_no}: {error}')

    demand(event_counts['start'] == 1, 'Expected exactly one runner start')
    demand(len(done_values) == 1 and done_values == [True], 'Expected exactly one successful terminal event')
    demand(len(all_suites_counts) == 1, 'Expected exactly one allSuites declaration')
    demand(set(tests) == set(completions), 'Started events without exactly one completion: ' +
           repr(sorted(set(tests) - set(completions))))
    seen_suites = {entry['path'] for entry in suites.values()}
    demand(seen_suites == requested, 'Exact suite set mismatch: missing=' +
           repr(sorted(requested - seen_suites)) + '; unexpected=' + repr(sorted(seen_suites - requested)))
    by_suite = Counter(case['suite'] for case in cases)
    demand(set(by_suite) == requested and all(by_suite.get(name, 0) > 0 for name in requested),
           'One or more selected suites have no visible completed cases')
    identities = [(case['suite'], case['name']) for case in cases]
    demand(len(identities) == len(set(identities)), 'Duplicate visible suite/name identities')
    demand(not diagnostic_messages, 'Layout/tap/disposal diagnostics were printed')
    outcomes = outcome_counts(cases)
    per_suite_outcomes = {path: {key: value for key, value in outcome_counts(
        [case for case in cases if case['suite'] == path]).items() if key != 'executions'}
        for path in sorted(by_suite)}
    hidden_outcomes = outcome_counts([event for event in completions.values() if event.get('hidden') is True])
    return dict(valid=not issues, issues=issues, cases=cases, events=dict(event_counts),
                outcomes=outcomes, per_suite_outcomes=per_suite_outcomes, hidden_outcomes=hidden_outcomes,
                error_events=error_events,
                started=len(tests), completed=len(completions),
                visible_cases=len(cases), hidden_cases=len(completions)-len(cases),
                suites=dict(sorted(by_suite.items())), diagnostic_messages=diagnostic_messages,
                print_event_count=len(printed_messages), terminal_success=done_values == [True])


class Auditor:
    def __init__(self, repo, source, publication=None):
        self.repo = repo.resolve(); self.failures = []; self.phase_reports = []; self.cases = []
        self.source = self.git('rev-parse', source).decode().strip()
        self.source_tree = self.git('rev-parse', self.source+'^{tree}').decode().strip()
        self.publication = self.git('rev-parse', publication).decode().strip() if publication else None
        self.tree = self.read_tree(self.source)
        self.publication_tree = self.read_tree(self.publication) if self.publication else None
        self.file_cache = {}
        self.source_manifests = []; self.runtime_manifests = []

    def git(self, *args):
        return subprocess.check_output(['git','-C',str(self.repo),*args])

    def read_tree(self, ref):
        result={}
        for entry in self.git('ls-tree','-rz',ref).split(b'\0'):
            if entry:
                meta,name=entry.split(b'\t',1); mode,kind,oid=meta.decode().split()
                result[name.decode()]=dict(mode=mode,kind=kind,git_blob=oid)
        return result

    def check(self, condition, message):
        if not condition:
            self.failures.append(message)

    def file_hashes(self, path):
        path=Path(path)
        st=path.stat()
        key=(str(path),st.st_size,st.st_mtime_ns)
        if key not in self.file_cache:
            h=hashlib.sha256(); g=hashlib.sha1(b'blob '+str(st.st_size).encode()+b'\0')
            with path.open('rb') as stream:
                while block:=stream.read(1024*1024): h.update(block); g.update(block)
            self.file_cache[key]=(h.hexdigest(),g.hexdigest(),st.st_size)
        return self.file_cache[key]

    def load(self,path):
        return decode(Path(path).read_bytes())

    def selected(self,tree,plan,plan_name):
        selected={name for name in tree if name.startswith(SOURCE_PREFIXES) or
                  ('/' not in name and Path(name).suffix in {'.yaml','.lock'})}
        selected.update([RUNNER,plan_name,'tools/mail/check_store.py','tools/mail/check_reader.py'])
        for group in plan['groups']:
            selected.update((Path(group['cwd'])/checked_relative(path)).as_posix() for path in group['tests'])
        for kind in ['analysis','format','extra_inputs']:
            paths=plan.get(kind,[])
            if not isinstance(paths,list): raise AuditError('Audit requires explicit '+kind+' paths')
            selected.update(checked_relative(path) for path in paths)
        selected.update(checked_relative(row['path']) for row in plan.get('whitespace_preserved_inputs',[]))
        return selected

    def verify_sources(self,before,after,plan,plan_name,receipt):
        self.check(before==after,'Source inventory changed during run')
        selected=self.selected(self.tree,plan,plan_name)
        self.check(set(before)==selected,'Source manifest is not the complete declared product/harness/plan selection')
        self.check(receipt.get('source_input_count')==len(before),'Receipt source count differs from inventory')
        materialized=0
        for name,record in before.items():
            checked_relative(name)
            expected=self.tree.get(name)
            self.check(expected is not None,'Manifest input absent from frozen source: '+name)
            if not expected: continue
            self.check(record.get('mode')==expected['mode'] and record.get('git_blob')==expected['git_blob'],
                       'Source Git identity differs: '+name)
            path=self.repo/name
            if record.get('materialized') is not True:
                self.check(record.get('sparse_omission') is True and record.get('sha256') is None,
                           'Invalid sparse source record: '+name)
                self.check(not name.endswith(('.dart','.yaml','.lock')),'Executable/config input omitted: '+name)
                continue
            materialized+=1
            self.check(record.get('sparse_omission') is False,'Materialized input marked sparse: '+name)
            if not path.is_file():
                self.check(False,'Live materialized source is missing: '+name); continue
            content_hash,blob,size=self.file_hashes(path)
            self.check(record.get('sha256')==content_hash,'Live source bytes differ: '+name)
            if expected['mode']=='120000':
                self.check(path.is_symlink(),'Git symlink is not a symlink: '+name)
                link=os.readlink(path).encode();blob=hashlib.sha1(b'blob '+str(len(link)).encode()+b'\0'+link).hexdigest()
            else:
                self.check(not path.is_symlink(),'Source regular file redirected by symlink: '+name)
                mode='100755' if path.stat().st_mode & 0o111 else '100644'
                self.check(mode==expected['mode'],'Live source mode differs: '+name)
            self.check(blob==expected['git_blob'],'Live source is not frozen Git blob: '+name)
        self.check(receipt.get('materialized_source_inputs')==materialized,'Materialized source count mismatch')
        if self.publication_tree is not None:
            self.check(self.selected(self.publication_tree,plan,plan_name)==selected,
                       'Publication adds/removes selected application inputs')
            for name in selected:
                self.check(self.publication_tree.get(name)==self.tree.get(name),'Publication mutates tested input: '+name)
        self.source_manifests.append(before)
        return dict(records=len(before),materialized=materialized,sparse=len(before)-materialized,
                    live_readback=True,publication_checked=self.publication)

    def verify_runtime(self,before,after,plan,receipt):
        self.check(before==after,'Runtime inventory changed during run')
        self.check(receipt.get('runtime_input_count')==len(before),'Receipt runtime count differs')
        sdk=Path(receipt['runtime']['flutterRoot']).resolve();runtime=sdk.parent
        package_config=self.repo/'.dart_tool/package_config.json'
        self.check(Path(receipt['package_config']).resolve()==package_config,'Package config path differs')
        runtime_receipt=self.load(runtime/'runtime.json')
        self.check(self.file_hashes(runtime/'runtime.json')[0]==receipt['runtime_receipt_sha256'],
                   'Runtime receipt hash differs')
        self.check(runtime_receipt.get('status')=='ready' and runtime_receipt.get('archive',{}).get('verified') is True,
                   'Runtime not restored and verified')
        self.check(Path(runtime_receipt['sdk']).resolve()==sdk,'Runtime SDK routing differs')
        lock_hash=self.file_hashes(self.repo/'pubspec.lock')[0]
        self.check(receipt['workspace_lock_sha256']==runtime_receipt['workspace_lock_sha256']==lock_hash,
                   'Workspace lock differs from runtime/run binding')
        retained=self.load(runtime/'retained-inputs.json')
        mappings={}
        for name,record in retained.items():
            checked_relative(name);mappings['runtime/'+name]=runtime/name
            self.check(before.get('runtime/'+name)==record.get('sha256'),'Retained hash absent/different: '+name)
            self.check(self.file_hashes(runtime/name)[2]==record['bytes'],'Retained size differs: '+name)
        for name in ['runtime.json','retained-inputs.json','pub-cache-receipt.json','cache-omissions.json',
                     'archive-members.json','env.sh','bin/dart','bin/flutter']:
            mappings['runtime/'+name]=runtime/name
        mappings.update({'workspace/pubspec.lock':self.repo/'pubspec.lock',
                         'workspace/package_config.json':package_config,
                         'sdk/flutter_tools/package_config.json':sdk/'packages/flutter_tools/.dart_tool/package_config.json',
                         'workspace/native_assets.yaml':self.repo/'.dart_tool/native_assets.yaml'})
        additional=runtime_receipt.get('additional_inputs',{})
        self.check(receipt.get('additional_runtime_inputs')==additional,'Run additional runtime bindings differ')
        for name,expected in additional.items():
            self.check(Path(name).is_absolute() and SHA256.fullmatch(expected) is not None,
                       'Invalid additional runtime binding')
            mappings['additional/'+name]=Path(name)
        optional={'workspace/native_assets.yaml'}
        for group in plan['groups']:
            directory=(self.repo/group['cwd']).resolve();directory.relative_to(self.repo)
            while directory!=self.repo:
                path=directory/'.dart_tool/native_assets.yaml'
                key='workspace/'+path.relative_to(self.repo).as_posix();mappings[key]=path;optional.add(key)
                self.check(not path.exists() and not path.is_symlink(),'Nearer native mapping shadows workspace: '+str(path))
                directory=directory.parent
        self.check(set(mappings)==set(before),'Runtime manifest path set differs from complete bounded bindings')
        for key,path in mappings.items():
            expected=before.get(key)
            if expected is None:
                self.check(key in optional and not path.exists() and not path.is_symlink(),'Missing required runtime file: '+key)
            else:
                self.check(SHA256.fullmatch(expected) is not None,'Invalid runtime digest: '+key)
                self.check(path.is_file() and self.file_hashes(path)[0]==expected,'Live runtime bytes changed: '+key)
        for path,expected in runtime_receipt['executables_sha256'].items():
            self.check(self.file_hashes(path)[0]==expected,'Pinned executable changed: '+path)
        mapping=self.repo/'.dart_tool/native_assets.yaml'
        native_count=0
        if mapping.exists():
            self.check(str(mapping) in additional,'Native mapping not in additional inputs')
            native=yaml.safe_load(mapping.read_text())['native-assets']
            for assets in native.values():
                for asset in assets.values():
                    self.check(isinstance(asset,list) and len(asset)==2 and asset[0]=='absolute'
                               and asset[1] in additional,'Native asset path is not explicitly bound')
                    native_count+=1
        if any(group.get('platform','vm')=='node' for group in plan['groups']):
            node=runtime_receipt.get('node_runtime',{})
            self.check(node.get('path') in additional and node.get('sha256')==additional.get(node.get('path')),
                       'Node runtime lacks explicit matching binding')
        dependency_report=self.verify_packages(package_config,runtime,sdk,retained)
        self.runtime_manifests.append(before)
        return dict(records=len(before),retained_files=len(retained),additional_files=len(additional),
                    native_assets=native_count,runtime_root=str(runtime),receipt_sha256=receipt['runtime_receipt_sha256'],
                    dependency_report=dependency_report,scope='Recorded bounded inputs and current byte readback; not an OS/container snapshot')

    def verify_packages(self,config_path,runtime,sdk,retained):
        root=yaml.safe_load((self.repo/'pubspec.yaml').read_text())
        lock=yaml.safe_load((self.repo/'pubspec.lock').read_text())['packages']
        workspace={root['name']:self.repo}
        for name in root.get('workspace',[]):
            path=(self.repo/checked_relative(name)).resolve();path.relative_to(self.repo)
            manifest=yaml.safe_load((path/'pubspec.yaml').read_text())
            self.check(manifest['name'] not in workspace,'Duplicate workspace package')
            workspace[manifest['name']]=path
        packages=self.load(config_path)['packages']
        names=[row['name'] for row in packages]
        self.check(len(names)==len(set(names)),'Duplicate resolved package names')
        self.check(set(names)==set(lock)|set(workspace),'Resolved package set differs from lock/workspace')
        archives=self.load(runtime/'pub-cache-receipt.json')
        archive_map={}
        for item in archives:
            key=(item['name'],item['version'])
            self.check(key not in archive_map and item.get('verified') is True,'Duplicate/unverified hosted archive receipt')
            archive_map[key]=item
        expected_archives={}
        for locked in [lock,yaml.safe_load((sdk/'packages/flutter_tools/pubspec.lock').read_text())['packages']]:
            for name,item in locked.items():
                if item['source']=='hosted':
                    self.check(item['description']['url']=='https://pub.dev','Unexpected hosted package registry')
                    expected_archives[(name,item['version'])]=item['description']['sha256']
        self.check(set(archive_map)==set(expected_archives),'Hosted archive receipt set differs from locked union')
        for key,expected in expected_archives.items():
            item=archive_map.get(key,{})
            self.check(item.get('sha256')==expected,'Hosted archive digest differs from lock: '+repr(key))
        launcher=None
        for item in packages:
            name=item['name'];path=file_uri(item['rootUri'],config_path)
            self.check(item.get('packageUri')=='lib/','Unexpected package URI: '+name)
            if name in workspace:
                self.check(path==workspace[name],'Workspace package root redirected: '+name)
            elif name in lock:
                spec=lock[name]
                if spec['source']=='hosted':
                    self.check(path==runtime/'pub-cache/hosted/pub.dev'/f"{name}-{spec['version']}",
                               'Hosted package root redirected: '+name)
                elif spec['source']=='path':
                    expected=(self.repo/spec['description']['path']).resolve()
                    expected.relative_to(self.repo)
                    self.check(path==expected,'Path dependency root redirected: '+name)
                elif spec['source']=='sdk':
                    self.check(path.is_relative_to(sdk),'SDK package outside pinned SDK: '+name)
                else: self.check(False,'Unsupported dependency source: '+spec['source'])
            manifest=yaml.safe_load((path/'pubspec.yaml').read_text())
            self.check(manifest['name']==name,'Package manifest name differs: '+name)
            if name=='test': launcher=path/'bin/test.dart'
        if launcher is None: raise AuditError('No test launcher in resolved packages')
        launcher_key=launcher.relative_to(runtime).as_posix()
        self.check(launcher_key in retained,'Test launcher not in retained files')
        return dict(resolved_packages=len(packages),workspace_packages=len(workspace),
                    hosted_archive_receipts=len(archives),test_launcher=str(launcher),
                    package_config_sha256=self.file_hashes(config_path)[0])

    def checked_log(self,base,row,path_key,hash_key):
        relative=checked_relative(row[path_key]);path=base/relative
        data=path.read_bytes()
        self.check(sha(data)==row[hash_key],'Log/artifact hash differs: '+str(path))
        return data

    def audit_phase(self,plan_arg,output):
        start_errors=len(self.failures)
        plan_path=Path(plan_arg)
        if not plan_path.is_absolute():plan_path=self.repo/plan_path
        plan_path=plan_path.resolve();plan_name=plan_path.relative_to(self.repo).as_posix()
        output=output.resolve();raw=output/'verification.json';receipt=self.load(raw);plan=self.load(plan_path)
        self.check(receipt.get('source_commit')==self.source,'Receipt belongs to different source')
        self.check(receipt.get('source_tree')==self.source_tree,'Receipt source tree differs')
        self.check(receipt.get('plan')==plan_name and receipt.get('plan_sha256')==sha(plan_path.read_bytes()),'Plan receipt binding differs')
        for flag in ['tracked_worktree_clean_before','tracked_worktree_clean_after','source_unchanged','environment_unchanged',
                     'source_head_unchanged','source_index_unchanged','success']:
            self.check(receipt.get(flag) is True,'Receipt gate flag failed/missing: '+flag)
        self.check(receipt.get('github_actions_queried_or_awaited') is False,'Actions policy not recorded as false')
        for key in ['source_mismatches','environment_mismatches','unexpected_native_mappings_after']:
            self.check(receipt.get(key)==[],'Receipt reports '+key)
        self.check(not receipt.get('runner_error'),'Runner error recorded')
        self.check(isinstance(receipt.get('finished_at_utc'),str),'Receipt is unfinished')
        self.check(receipt.get('planned_groups')==plan['groups'],'Receipt group selection differs')
        self.check(receipt.get('analysis_files')==plan.get('analysis',[]),'Analysis target selection differs')
        self.check(receipt.get('formatted_files')==plan.get('format',[]),'Format target selection differs')
        manifests={}
        for name in ['source-before.json','source-after.json','environment-before.json','environment-after.json']:
            data=(output/name).read_bytes();self.check(sha(data)==receipt['manifest_sha256'].get(name),'Manifest hash differs: '+name)
            manifests[name]=decode(data)
        source_report=self.verify_sources(manifests['source-before.json'],manifests['source-after.json'],plan,plan_name,receipt)
        runtime_report=self.verify_runtime(manifests['environment-before.json'],manifests['environment-after.json'],plan,receipt)
        group_names=[group['name'] for group in plan['groups']]
        self.check(len(group_names)==len(set(group_names)),'Duplicate planned group names')
        required_names=group_names+(['analysis'] if plan.get('analysis') else [])+(['format'] if plan.get('format') else [])+['whitespace']
        self.check([row.get('name') for row in receipt['runs']]==required_names,'Run order/set differs from exact plan')
        expected_paths=set();phase_cases=[];groups=[];static=[]
        group_map={group['name']:group for group in plan['groups']}
        runtime=Path(runtime_report['runtime_root']);launcher=runtime_report['dependency_report']['test_launcher']
        self.check(receipt['test_launcher']==launcher,'Recorded launcher is not verified package:test entrypoint')
        for row in receipt['runs']:
            name=row['name'];self.check(row.get('exit_code')==0 and row.get('accepted') is True,'Command failed/rejected: '+name)
            self.check(not row.get('runner_error'),'Per-command runner error: '+name)
            log=self.checked_log(output,row,'log','log_sha256')
            compressed=self.checked_log(output,row,'compressed_log','compressed_log_sha256')
            self.check(gzip.decompress(compressed)==log,'Compressed/raw log mismatch: '+name)
            if name in group_map:
                group=group_map[name];platform=group.get('platform','vm');cwd=group['cwd']
                requested={repo_suite(path,self.repo,cwd) for path in group['tests']}
                self.check(len(requested)==len(group['tests']) and not(expected_paths & requested),'Repeated planned suite')
                expected_paths.update(requested)
                self.check(row.get('cwd')==cwd,'Recorded working directory differs: '+name)
                prefix=([str(runtime/'bin/flutter'),'test','--no-pub'] if group['runner']=='flutter' else
                        [str(runtime/'bin/dart'),'--disable-dart-dev','--packages='+str(self.repo/'.dart_tool/package_config.json'),
                         launcher,'--compiler=kernel' if platform=='vm' else '--platform=node'])
                command=prefix+['--concurrency=1','--reporter=json',*group['tests']]
                self.check(row['command']==command,'Test launch differs or contains selection filters: '+name)
                stderr=self.checked_log(output,row,'stderr_log','stderr_log_sha256')
                stderr_gz=self.checked_log(output,row,'stderr_compressed_log','stderr_compressed_log_sha256')
                self.check(gzip.decompress(stderr_gz)==stderr,'Compressed/raw stderr mismatch: '+name)
                self.check(not DIAGNOSTICS.search(stderr.decode(errors='replace')),'Native stderr contains prohibited diagnostics: '+name)
                parsed=reparse_events(log,self.repo,cwd,requested,platform)
                self.check(parsed['valid'],'Reporter audit failed '+name+': '+json.dumps(parsed['issues'],ensure_ascii=False))
                saved_cases=decode(self.checked_log(output,row,'cases_file','cases_sha256'))
                saved_errors=decode(self.checked_log(output,row,'errors_file','errors_sha256'))
                self.check(saved_errors==parsed['error_events'],'Saved error records differ from raw events: '+name)
                normalized=[dict(id=case['id'],suite=repo_suite(case['suite'],self.repo,cwd),name=case['name'],
                                 result=case['result'],skipped=case['skipped']) for case in saved_cases]
                raw_cases=[{key:case[key] for key in ['id','suite','name','result','skipped']} for case in parsed['cases']]
                self.check(normalized==raw_cases,'Saved cases differ from raw lifecycle reconstruction: '+name)
                self.check(reported_outcomes_match(row,parsed['outcomes']),
                           'Reported outcome totals differ from raw events: '+name)
                saved_suite={repo_suite(path,self.repo,cwd):values for path,values in row.get('per_suite',{}).items()}
                wanted=parsed['per_suite_outcomes']
                self.check(saved_suite==wanted,'Per-suite receipt differs from raw counts: '+name)
                for key in ['missing_requested_suites','unexpected_suites','empty_requested_suites','unfinished_reporter_events','protocol_anomalies']:
                    self.check(row.get(key)==[],'Runner reported '+key+': '+name)
                self.check(row.get('reporter_error_count')==len(parsed['error_events']),
                           'Reporter error count differs from raw events: '+name)
                self.check(row.get('reporter_success') is parsed['terminal_success'],
                           'Reporter terminal receipt differs from raw events: '+name)
                groups.append(dict(name=name,platform=platform,suites=len(requested),cases=parsed['visible_cases'],
                                   **parsed['outcomes'],per_suite_outcomes=parsed['per_suite_outcomes'],
                                   hidden_outcomes=parsed['hidden_outcomes'],error_events=len(parsed['error_events']),
                                   started_events=parsed['started'],completed_events=parsed['completed'],hidden_events=parsed['hidden_cases'],
                                   event_types=parsed['events'],per_suite=parsed['suites'],stderr_bytes=len(stderr),
                                   print_events=parsed['print_event_count'],raw_log_sha256=sha(log)))
                for case in parsed['cases']:
                    case.update(group=name,phase=plan_name);phase_cases.append(case)
            else:
                text=log.decode('utf-8')
                self.check(row.get('cwd')=='.','Static command working directory differs')
                if name=='analysis':
                    self.check(row['command']==[str(runtime/'bin/dart'),'analyze','--fatal-infos','--fatal-warnings',*plan['analysis']],
                               'Strict analysis command differs')
                    self.check('No issues found' in text,'Analysis did not explicitly report no issues')
                elif name=='format':
                    self.check(row['command']==[str(runtime/'bin/dart'),'format','--output=none','--set-exit-if-changed',*plan['format']],
                               'Format command differs')
                    found=re.search(r'Formatted (\d+) files? \(0 changed\)',text)
                    self.check(found is not None and int(found.group(1))==len(plan['format']),'Format count/unchanged result differs')
                elif name=='whitespace':
                    expected=['git','diff','--check',receipt['source_base'],self.source,'--','.',
                              *[':(exclude)'+item['path'] for item in plan.get('whitespace_preserved_inputs',[])]]
                    self.check(row['command']==expected and not text.strip(),'Whitespace check differs or emitted findings')
                else:self.check(False,'Unexpected command: '+name)
                static.append(dict(name=name,passed=row.get('exit_code')==0,log_sha256=sha(log)))
        phase_outcomes=outcome_counts(phase_cases)
        self.check(reported_outcomes_match(receipt,phase_outcomes),
                   'Receipt overall outcome counts differ from independent reconstruction')
        self.cases.extend(phase_cases)
        report=dict(plan=plan_name,output_dir=str(output),receipt_sha256=sha(raw.read_bytes()),
                    started_at_utc=receipt.get('started_at_utc'),finished_at_utc=receipt.get('finished_at_utc'),
                    accepted=len(self.failures)==start_errors,application_case_executions=len(phase_cases),
                    **phase_outcomes,
                    distinct_suites=len(expected_paths),groups=groups,static_checks=static,
                    source=source_report,runtime=runtime_report)
        self.phase_reports.append(report)

    def finish(self):
        if self.source_manifests:
            self.check(all(value==self.source_manifests[0] for value in self.source_manifests),
                       'Combined phases do not bind identical full source inventories')
        overlap={}
        for manifest in self.runtime_manifests:
            for name,value in manifest.items():
                self.check(name not in overlap or overlap[name]==value,'Runtime binding differs across phases: '+name)
                overlap[name]=value
        identities=Counter((case['suite'],case['name']) for case in self.cases)
        platform_ids=Counter((case['platform'],case['suite'],case['name']) for case in self.cases)
        self.check(all(value==1 for value in platform_ids.values()),'Case repeated on same platform across phases')
        native_ids={(case['suite'],case['name']) for case in self.cases if case['platform']=='vm'}
        node_ids={(case['suite'],case['name']) for case in self.cases if case['platform']=='node'}
        outcomes=outcome_counts(self.cases)
        return dict(schema=2,accepted=not self.failures,audited_at_utc=datetime.now(timezone.utc).isoformat(),
                    source_commit=self.source,source_tree=self.source_tree,publication_commit=self.publication,
                    method='Independent raw-event lifecycle ledger; exact committed plan/command selection; Git mode/blob/content readback; complete recorded before/after source and bounded runtime mappings. No product tests executed by auditor.',
                    issues=self.failures,application_case_executions=len(self.cases),**outcomes,
                    distinct_case_identities=len(identities),cross_platform_repeated_executions=len(self.cases)-len(identities),
                    distinct_suite_paths=len({case['suite'] for case in self.cases}),
                    suite_platform_executions=len({(case['suite'],case['platform']) for case in self.cases}),
                    node_only_identities=[dict(suite=suite,name=name) for suite,name in sorted(node_ids-native_ids)],
                    phases=self.phase_reports,source_inventory_records=len(self.source_manifests[0]) if self.source_manifests else 0,
                    runtime_union_records=len(overlap),historical_cases_added=0,
                    github_actions='NOT QUERIED OR AWAITED',
                    audit_script_sha256=sha(Path(__file__).read_bytes()))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True);parser.add_argument('--source',required=True)
    parser.add_argument('--plan',type=Path,action='append',required=True)
    parser.add_argument('--output-dir',type=Path,action='append',required=True)
    parser.add_argument('--publication')
    parser.add_argument('--report',type=Path,default=Path(__file__).with_name('qualification-audit.json'))
    args=parser.parse_args()
    if len(args.plan)!=len(args.output_dir):parser.error('Pass one --output-dir for each --plan')
    auditor=Auditor(args.repo,args.source,args.publication)
    for plan,output in zip(args.plan,args.output_dir):
        try:auditor.audit_phase(plan,output)
        except Exception as error:auditor.failures.append(f'{output}: {type(error).__name__}: {error}')
    report=auditor.finish()
    report['requested_phase_count']=len(args.plan)
    if len(auditor.phase_reports)!=len(args.plan):
        report['accepted']=False;report['issues'].append('Not every requested phase completed audit')
    cases_path=args.report.with_name(args.report.stem+'-cases.json')
    args.report.parent.mkdir(parents=True,exist_ok=True)
    cases_bytes=(json.dumps(auditor.cases,indent=2,ensure_ascii=False)+'\n').encode()
    cases_path.write_bytes(cases_bytes)
    report['case_inventory']=dict(path=str(cases_path),sha256=sha(cases_bytes),records=len(auditor.cases))
    args.report.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps({key:report[key] for key in ['accepted','source_commit','application_case_executions','passed','failed','skipped',
                                                'distinct_case_identities','distinct_suite_paths','suite_platform_executions','issues']},ensure_ascii=False))
    raise SystemExit(0 if report['accepted'] else 1)

if __name__=='__main__':main()
