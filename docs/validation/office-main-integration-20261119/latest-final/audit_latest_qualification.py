#!/usr/bin/env python3
"""Independent raw-event, source and runtime audit of the latest Mail UID/Hunspell/Arabic qualification."""
import argparse,collections,gzip,hashlib,json,re,subprocess,tarfile
from datetime import datetime,timezone
from pathlib import Path,PurePosixPath
ap=argparse.ArgumentParser()
ap.add_argument('--repo',type=Path,required=True)
ap.add_argument('--store',type=Path,required=True)
ap.add_argument('--consumers',type=Path,required=True)
ap.add_argument('--node','--arabic-node',dest='node',type=Path,required=True)
ap.add_argument('--runtime',type=Path,required=True)
ap.add_argument('--source',required=True)
ap.add_argument('--output',type=Path,required=True)
a=ap.parse_args();root=a.repo.resolve();runtime=a.runtime.resolve()
def git(*xs,input=None):return subprocess.check_output(['git','-C',str(root),*xs],input=input)
def read(path):return json.loads(path.read_text())
def digest(data):return hashlib.sha256(data).hexdigest()
def filehash(path):
 with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def tree(ref):
 result={}
 for row in git('ls-tree','-rz','--full-tree',ref).split(b'\0'):
  if not row:continue
  meta,name=row.split(b'\t',1);mode,kind,blob=meta.decode().split();result[name.decode()]={'mode':mode,'kind':kind,'git_blob':blob}
 return result
source=git('rev-parse',a.source).decode().strip();tracked=tree(source)
def verify_sources(values,with_metadata=False,at_source=None):
 selected_tree=tracked if at_source is None or at_source==source else tree(at_source)
 paths=list(values)
 for offset in range(0,len(paths),64):
  selected=paths[offset:offset+64];blobs=[selected_tree[p]['git_blob'] for p in selected]
  raw=git('cat-file','--batch',input=('\n'.join(blobs)+'\n').encode());cursor=0
  for path,blob in zip(selected,blobs):
   end=raw.index(b'\n',cursor);actual,kind,length=raw[cursor:end].decode().split();length=int(length);cursor=end+1;data=raw[cursor:cursor+length];cursor+=length+1
   assert kind=='blob' and actual==blob
   expected=values[path]['sha256'] if with_metadata else values[path]
   assert digest(data)==expected,path
   assert (root/path).is_file() and not (root/path).is_symlink() and filehash(root/path)==expected,path
   if with_metadata:
    x=values[path];assert x['materialized'] is True and x['sparse_omission'] is False
    assert x['mode']==selected_tree[path]['mode'] and x['git_blob']==blob,path
 return len(paths)
records=collections.defaultdict(list);cohort_records={};warnings=[]
def normalize(path,cwd):
 p=Path(path)
 if not p.is_absolute():p=root/cwd/p
 return p.relative_to(root).as_posix()
def events_audit(path,cwd,expected_suites,name,platform):
 events=[];hook_prefixes=0
 for number,line in enumerate(path.read_text().splitlines(),1):
  line=line.strip()
  while line.startswith(('Running build hooks...','Running link hooks...')):
   prefix=next(x for x in ('Running build hooks...','Running link hooks...') if line.startswith(x));line=line[len(prefix):].lstrip();hook_prefixes+=1
  if not line:continue
  event=json.loads(line);assert isinstance(event,dict) and isinstance(event.get('type'),str),(path,number)
  events.append(event)
 assert sum(x['type']=='start' for x in events)==1 and events[0]['type']=='start'
 assert sum(x['type']=='done' for x in events)==1 and events[-1]['type']=='done' and events[-1]['success'] is True
 suites={};starts={};done={};cohort_warnings=[]
 for event in events:
  kind=event['type'];assert kind!='error',(path,event)
  if kind=='suite':
   suite=event['suite'];assert type(suite['id']) is int and suite['id'] not in suites
   suites[suite['id']]=normalize(suite['path'],cwd)
  elif kind=='testStart':
   t=event['test'];assert type(t['id']) is int and t['id'] not in starts
   assert type(t['suiteID']) is int and isinstance(t['name'],str);starts[t['id']]=t
  elif kind=='testDone':
   ident=event['testID'];assert type(ident) is int and ident not in done
   assert type(event['hidden']) is bool and event['skipped'] is False and event['result']=='success'
   done[ident]=event
  elif kind=='print':
   message=event.get('message','')
   if re.search(r'\bwarning\b|\bdeprecated\b',message,re.I):cohort_warnings.append({'test_id':event.get('testID'),'message':message})
 assert set(starts)==set(done)
 assert len(set(suites.values()))==len(suites) and set(suites.values())==set(expected_suites),(name,suites,expected_suites)
 identities=set();per_suite=collections.Counter();excluded=0;simple=[]
 for ident,event in done.items():
  test=starts[ident]
  if event['hidden'] or test['name'].startswith('loading ') or re.search(r'(?:^| )\((?:setUpAll|tearDownAll)\)$',test['name']):excluded+=1;continue
  key=(suites[test['suiteID']],test['name']);assert key not in identities
  identities.add(key);per_suite[key[0]]+=1;records[key].append({'cohort':name,'platform':platform})
  simple.append({'name':test['name'],'suite_id':test['suiteID'],'result':'success','skipped':False,'hidden':False})
 assert all(per_suite[s]>0 for s in expected_suites)
 diagnostic=re.compile(r'A Render\w+ overflowed|RenderBox was not laid out|would not hit test on the specified widget|does not receive pointer events',re.I)
 assert not diagnostic.search(path.read_text()),name
 for item in cohort_warnings:
  t=starts.get(item['test_id']);item['test_name']=t['name'] if t else None
  warnings.append({'cohort':name,**item})
 cohort_records[name]=identities
 return {'name':name,'platform':platform,'suites':len(suites),'passed_executions':len(identities),'failed':0,'skipped':0,'errors':0,'complete_starts_and_completions':True,'exact_suite_coverage':True,'terminal_success':True,'layout_or_tap_diagnostics':0,'excluded_lifecycle_events':excluded,'known_native_hook_prefixes':hook_prefixes,'warning_messages':len(cohort_warnings)},simple,identities
store=read(a.store/'receipt.json');consumer=read(a.consumers/'verification.json')
assert store['status']=='PASS' and store['active_check'] is None and store['source_unchanged'] is True
store_source=git('rev-parse',store['starting_commit']).decode().strip()
assert store_source==source, 'Core/store and focused gates must share the final frozen source'
assert store['source_before']==store['source_after']
store_sources=verify_sources(store['source_before'],at_source=store_source)
assert verify_sources(store['source_before'])==store_sources
assert store['direct_launcher_inputs_before']==store['direct_launcher_inputs_after']
for name,value in store['direct_launcher_inputs_after'].items():
 p=Path(name)
 assert (value is None and not p.exists() and not p.is_symlink()) or (value is not None and p.is_file() and not p.is_symlink() and filehash(p)==value),name
expected_checks=['runtime','runner-regressions','locked-resolution','core-analysis','store-analysis','format','core-vm','core-node','store-vm','portable-node','browser-entry','browser-worker','whitespace']
assert [x['name'] for x in store['checks']]==expected_checks
cohorts=[];compilations=[];python_controls=0
for check in store['checks']:
 assert check['status']=='PASS' and check['exit_code']==0 and not check.get('timed_out')
 log=a.store/check['log'];assert filehash(log)==check['log_sha256']
 name=check['name'];cwd=Path(check['cwd']).relative_to(root).as_posix()
 if 'tests' in check:
  if name.startswith('core-'):suites={p for p in tracked if p.startswith('packages/quds_mail_core/test/') and p.endswith('_test.dart')}
  elif name=='store-vm':suites={p for p in tracked if p.startswith('packages/quds_mail_store/test/') and p.endswith('_test.dart') and len(PurePosixPath(p).parts)==4 and not p.endswith('/browser_problem_test.dart')}
  else:suites={str(PurePosixPath('packages/quds_mail_store/test')/x) for x in ['codec_test.dart','platform_configuration_test.dart','browser_problem_test.dart']}
  platform='node' if name.endswith('node') else 'vm'
  result,simple,_=events_audit(log,cwd,suites,name,platform);assert result['passed_executions']==check['tests']['passed'] and check['tests']['valid'] is True
  saved=read(a.store/check['case_list']);assert sorted(saved['cases'],key=lambda x:(x['suite_id'],x['name']))==sorted(simple,key=lambda x:(x['suite_id'],x['name']))
  cohorts.append(result)
 elif name=='runner-regressions':
  m=re.search(r'Ran (\d+) tests? in ',log.read_text());assert m and re.search(r'\nOK\s*$',log.read_text());python_controls=int(m.group(1))
 elif name in ['browser-entry','browser-worker']:
  command=check['command'];target=Path(command[command.index('-o')+1]);assert target.is_file() and target.stat().st_size>0
  compilations.append({'name':name,'bytes':target.stat().st_size,'sha256':filehash(target),'exit_code':0})
 assert not re.search(r'\bwarning\b|\berror\b',log.read_text(),re.I) if name.endswith('analysis') else True
store_execution_counts={x['name']:x['passed_executions'] for x in cohorts}
store_executions=sum(store_execution_counts.values())
assert '--enforce-lockfile' in store['checks'][2]['command'] and '--offline' in store['checks'][2]['command']
assert consumer['success'] is True and consumer['source_commit']==source and consumer['source_tree']==git('rev-parse',source+'^{tree}').decode().strip()
for key in ['source_unchanged','environment_unchanged','source_head_unchanged','source_index_unchanged','tracked_worktree_clean_before','tracked_worktree_clean_after']:assert consumer[key] is True,key
for key in ['source_mismatches','environment_mismatches','unexpected_native_mappings_after','sparse_source_omissions']:assert not consumer[key]
for name,value in consumer['manifest_sha256'].items():assert filehash(a.consumers/name)==value
src_before=read(a.consumers/'source-before.json');src_after=read(a.consumers/'source-after.json');env_before=read(a.consumers/'environment-before.json');env_after=read(a.consumers/'environment-after.json')
assert src_before==src_after and env_before==env_after
consumer_sources=verify_sources(src_before,True);assert consumer_sources==consumer['source_input_count']
plan_raw=git('show',source+':'+consumer['plan']);assert digest(plan_raw)==consumer['plan_sha256'];plan=json.loads(plan_raw);assert plan['groups']==consumer['planned_groups']
assert consumer['analysis_files']==plan['analysis'] and consumer['formatted_files']==plan['format']
expected_source_inputs={path for path in tracked if path.startswith(('packages/','apps/','third_party/'))}
expected_source_inputs.update(path for path in tracked if '/' not in path and Path(path).suffix in {'.yaml','.lock'})
expected_source_inputs.update([consumer['plan'],'docs/validation/document-review-notes-20261118/run_checks.py','tools/mail/check_store.py','tools/mail/check_reader.py'])
expected_source_inputs.update(str(PurePosixPath(g['cwd'])/t) for g in plan['groups'] for t in g['tests'])
expected_source_inputs.update(plan['analysis']);expected_source_inputs.update(plan['format']);expected_source_inputs.update(plan.get('extra_inputs',[]));expected_source_inputs.update(x['path'] for x in plan.get('whitespace_preserved_inputs',[]))
assert set(src_before)==expected_source_inputs, (sorted(expected_source_inputs-set(src_before)),sorted(set(src_before)-expected_source_inputs))
assert [x['name'] for x in consumer['runs']]==[g['name'] for g in plan['groups']]+['analysis','format','whitespace']
consumer_cases=0
all_requested=[]
for group in plan['groups']:
 all_requested.extend(str(PurePosixPath(group['cwd'])/t) for t in group['tests'])
assert len(all_requested)==len(set(all_requested))
for check in consumer['runs']:
 assert check['accepted'] and check['exit_code']==0
 log=a.consumers/check['log'];assert filehash(log)==check['log_sha256']
 compressed=a.consumers/check['compressed_log'];assert filehash(compressed)==check['compressed_log_sha256'] and gzip.decompress(compressed.read_bytes())==log.read_bytes()
 if 'cases_file' in check:
  group=next(g for g in plan['groups'] if g['name']==check['name']);suites={str(PurePosixPath(group['cwd'])/t) for t in group['tests']}
  assert check['cwd']==group['cwd']
  if group['runner']=='flutter':
   expected_command=[str(runtime/'bin/flutter'),'test','--no-pub']
  else:
   expected_command=[str(runtime/'bin/dart'),'--disable-dart-dev','--packages='+consumer['package_config'],consumer['test_launcher'],'--platform=node' if group.get('platform','vm')=='node' else '--compiler=kernel']
  expected_command+=['--concurrency=1','--reporter=json',*group['tests']]
  assert check['command']==expected_command,(check['name'],check['command'])
  result,_,identities=events_audit(log,group['cwd'],suites,group['name'],group.get('platform','vm'));assert result['passed_executions']==check['passed'];cohorts.append(result);consumer_cases+=result['passed_executions']
  saved=read(a.consumers/check['cases_file']);assert filehash(a.consumers/check['cases_file'])==check['cases_sha256']
  assert len(saved)==len(identities) and {(normalize(x['suite'],group['cwd']),x['name']) for x in saved}==identities
  assert all(x['result']=='success' and x['skipped'] is False for x in saved)
  assert read(a.consumers/check['errors_file'])==[] and filehash(a.consumers/check['errors_file'])==check['errors_sha256']
 else:
  if check['name']=='analysis':assert check['command'][1:4]==['analyze','--fatal-infos','--fatal-warnings'] and check['command'][4:]==consumer['analysis_files']
  if check['name']=='format':assert check['command'][1:4]==['format','--output=none','--set-exit-if-changed'] and check['command'][4:]==consumer['formatted_files']
assert consumer_cases==consumer['passed'] and consumer['failed']==consumer['skipped']==0
assert len({str(PurePosixPath(g['cwd'])/t) for g in plan['groups'] for t in g['tests']})==sum(len(g['tests']) for g in plan['groups'])==23
# Verify every recorded runtime input live, while preserving each run's timing scope.
def env_path(name):
 if name.startswith('runtime/'):return runtime/name[len('runtime/'):]
 if name.startswith('additional/'):return Path(name[len('additional/'):])
 if name=='workspace/pubspec.lock':return root/'pubspec.lock'
 if name=='workspace/package_config.json':return root/'.dart_tool/package_config.json'
 if name=='workspace/native_assets.yaml':return root/'.dart_tool/native_assets.yaml'
 if name.startswith('workspace/'):return root/name[len('workspace/'):]
 if name=='sdk/flutter_tools/package_config.json':return runtime/'flutter/packages/flutter_tools/.dart_tool/package_config.json'
 raise AssertionError(name)
for name,value in env_after.items():
 p=env_path(name)
 if value is None:assert not p.exists() and not p.is_symlink(),name
 else:assert p.is_file() and filehash(p)==value,name
assert len(env_after)==consumer['runtime_input_count']
# Independently audit the third, same-source portable Node receipt. The unchanged
# runner rejects duplicate suite paths within one plan, so this is a separate gate.
node=read(a.node/'verification.json')
assert node['success'] is True and node['source_commit']==source and node['source_tree']==consumer['source_tree']
assert node['source_base']==consumer['source_base']
for key in ['source_unchanged','environment_unchanged','source_head_unchanged','source_index_unchanged','tracked_worktree_clean_before','tracked_worktree_clean_after']:assert node[key] is True,key
for key in ['source_mismatches','environment_mismatches','unexpected_native_mappings_after','sparse_source_omissions']:assert not node[key]
for name,value in node['manifest_sha256'].items():assert filehash(a.node/name)==value
node_src_before=read(a.node/'source-before.json');node_src_after=read(a.node/'source-after.json')
node_env_before=read(a.node/'environment-before.json');node_env_after=read(a.node/'environment-after.json')
assert node_src_before==node_src_after==src_before
assert node_env_before==node_env_after and len(node_env_after)==node['runtime_input_count']
assert node['source_input_count']==consumer_sources
# Every Node runtime binding is also in the main gate, which already verified
# every value against the live file. The extra Flutter bindings remain main-only.
assert set(node_env_after)<=set(env_after)
assert all(value==env_after[name] for name,value in node_env_after.items())
node_plan_raw=git('show',source+':'+node['plan']);assert digest(node_plan_raw)==node['plan_sha256'];node_plan=json.loads(node_plan_raw)
assert node_plan['extra_inputs']==plan['extra_inputs']
assert consumer['plan'] in node_plan['extra_inputs'] and node['plan'] in plan['extra_inputs']
assert node_plan['analysis']==node['analysis_files']==[] and node_plan['format']==node['formatted_files']==[]
expected_node_groups=[{'name': 'mail-configuration-node', 'cwd': 'packages/quds_mail_transport', 'runner': 'dart', 'platform': 'node', 'tests': ['test/configuration_test.dart']}, {'name': 'hunspell-provider-node', 'cwd': 'packages/quds_proofing_hunspell', 'runner': 'dart', 'platform': 'node', 'tests': ['test/hunspell_provider_test.dart']}, {'name': 'arabic-writing-node', 'cwd': 'packages/quds_office_engine', 'runner': 'dart', 'platform': 'node', 'tests': ['test/proofing/arabic_writing_rules_test.dart']}]
assert node_plan['groups']==node['planned_groups']==expected_node_groups
node_requested=[str(PurePosixPath(g['cwd'])/t) for g in node_plan['groups'] for t in g['tests']]
assert len(node_requested)==len(set(node_requested))==3
assert [r['name'] for r in node['runs']]==[g['name'] for g in node_plan['groups']]+['whitespace']
assert node['package_config']==consumer['package_config'] and node['test_launcher']==consumer['test_launcher']
assert node['runtime_receipt_sha256']==consumer['runtime_receipt_sha256'] and node['workspace_lock_sha256']==consumer['workspace_lock_sha256']
node_cases=0
for check in node['runs']:
 assert check['accepted'] and check['exit_code']==0
 log=a.node/check['log'];assert filehash(log)==check['log_sha256']
 compressed=a.node/check['compressed_log'];assert filehash(compressed)==check['compressed_log_sha256'] and gzip.decompress(compressed.read_bytes())==log.read_bytes()
 if 'cases_file' in check:
  group=next(g for g in node_plan['groups'] if g['name']==check['name']);suites={str(PurePosixPath(group['cwd'])/t) for t in group['tests']}
  assert check['name']==group['name'] and check['cwd']==group['cwd']
  command=[str(runtime/'bin/dart'),'--disable-dart-dev','--packages='+node['package_config'],node['test_launcher'],'--platform=node','--concurrency=1','--reporter=json',*group['tests']]
  assert check['command']==command
  result,_,identities=events_audit(log,group['cwd'],suites,group['name'],'node');assert result['passed_executions']==check['passed'];cohorts.append(result);node_cases+=result['passed_executions']
  saved=read(a.node/check['cases_file']);assert filehash(a.node/check['cases_file'])==check['cases_sha256']
  assert len(saved)==len(identities) and {(normalize(x['suite'],group['cwd']),x['name']) for x in saved}==identities
  assert all(x['result']=='success' and x['skipped'] is False for x in saved)
  assert read(a.node/check['errors_file'])==[] and filehash(a.node/check['errors_file'])==check['errors_sha256']
assert node_cases==node['passed'] and node['failed']==node['skipped']==0
assert not node['github_actions_queried_or_awaited']
main_cases_by_suite=collections.defaultdict(set)
for group in plan['groups']:
 for key in cohort_records[group['name']]:main_cases_by_suite[key[0]].add(key)
node_platform_matches=[]
for group in node_plan['groups']:
 actual=cohort_records[group['name']]
 expected=set().union(*(main_cases_by_suite[str(PurePosixPath(group['cwd'])/t)] for t in group['tests']))
 assert actual==expected,group['name']
 node_platform_matches.append({'group':group['name'],'suites':group['tests'],'executions':len(actual),'same_vm_node_case_identities':True,'additional_distinct_cases':0})
arabic_suite='packages/quds_office_engine/test/proofing/arabic_writing_rules_test.dart'
arabic_vm=main_cases_by_suite[arabic_suite]
assert len(arabic_vm)==74
semantic_mark_regressions={'lexical matching preserves U+0653 madda','lexical matching preserves U+0654 hamza above','lexical matching preserves U+0655 hamza below','decomposed letters preserve adjacent correction UTF-16 offsets','semantic combining marks still allow punctuation checks'}
assert semantic_mark_regressions<={name for suite,name in arabic_vm}

retained=read(runtime/'retained-inputs.json')
for name,record in retained.items():assert (runtime/name).is_file() and filehash(runtime/name)==record['sha256'],name
runtime_receipt=read(runtime/'runtime.json');assert filehash(runtime/'runtime.json')==consumer['runtime_receipt_sha256']
assert runtime_receipt['status']=='ready' and runtime_receipt['archive']['verified'] is True
assert filehash(root/'pubspec.lock')==runtime_receipt['workspace_lock_sha256']==consumer['workspace_lock_sha256']
# The native control library is a separately built, instrumented real adapter.
# Its exact bytes and build receipt are bound by both focused runtime intervals.
native_binding_name='docs/validation/office-main-integration-20261119/latest-final/native-runtime-inputs.json'
assert native_binding_name in plan['extra_inputs'] and native_binding_name in node_plan['extra_inputs']
native=read(root/native_binding_name)
assert native['schema']==1 and native['environment']=={'QUDS_HUNSPELL_LIFECYCLE_LIBRARY':native['library']['path']}
assert src_before[native_binding_name]['sha256']==filehash(root/native_binding_name)
native_assets={}
for key in ['library','build_receipt']:
 entry=native[key];p=Path(entry['path'])
 assert p.is_absolute() and p.resolve()==p and p.is_file() and not p.is_symlink()
 p.relative_to(runtime/'local-validation/hunspell')
 assert p.stat().st_size==entry['bytes'] and filehash(p)==entry['sha256'],key
 assert runtime_receipt['additional_inputs'][str(p)]==entry['sha256']
 assert consumer['additional_runtime_inputs'][str(p)]==node['additional_runtime_inputs'][str(p)]==entry['sha256']
 assert env_before['additional/'+str(p)]==env_after['additional/'+str(p)]==entry['sha256']
 assert node_env_before['additional/'+str(p)]==node_env_after['additional/'+str(p)]==entry['sha256']
 native_assets[key]={'path':str(p),'bytes':entry['bytes'],'sha256':entry['sha256'],'main_and_node_before_after_and_live_match':True}
build=read(Path(native['build_receipt']['path']))
assert build['exit_code']==0 and build['output_sha256']==native['library']['sha256']
assert build['adapter_sha256']==native['production_adapter']['sha256']
assert build['instrumented_sha256']==native['instrumented_adapter']['sha256']
assert build['command'][build['command'].index('-o')+1].endswith('/'+Path(native['library']['path']).name)
assert native['instrumented_adapter']['path'] in build['command']
production=native['production_adapter'];assert Path(production['path'])==root/production['repository_path']
assert src_before[production['repository_path']]['sha256']==production['sha256']
assert (root/production['repository_path']).stat().st_size==production['bytes']
instrumented=native['instrumented_adapter'];instrumented_path=Path(instrumented['path'])
assert instrumented_path.is_file() and not instrumented_path.is_symlink()
assert instrumented_path.stat().st_size==instrumented['bytes'] and filehash(instrumented_path)==instrumented['sha256']
replay=native['replay_evidence'];replay_path=root/replay['repository_path']
assert replay_path.is_file() and replay_path.stat().st_size==replay['bytes'] and filehash(replay_path)==replay['sha256']
assert digest(git('show',source+':'+replay['repository_path']))==replay['sha256']
assert Path(replay['path']).is_file() and filehash(Path(replay['path']))==replay['sha256']
with tarfile.open(replay_path,'r:xz') as archive:
 names=[member.name for member in archive.getmembers()]
 assert len(names)==len(set(names))
 archived_instrumented=archive.extractfile('lifecycle_instrumented_adapter.cpp').read()
 assert digest(archived_instrumented)==instrumented['sha256']
 assert archive.extractfile('lifecycle-instrumented-build-receipt.json').read()==Path(native['build_receipt']['path']).read_bytes()
 assert digest(archive.extractfile('after/'+production['repository_path']).read())==production['sha256']
 assert archive.extractfile('after/'+native['fixture_source']).read()==(root/native['fixture_source']).read_bytes()
assert native['fixture_source'] in src_before and native['fixture_source'] in plan['extra_inputs']
native_verification={'descriptor':native_binding_name,'descriptor_sha256':filehash(root/native_binding_name),'assets':native_assets,'production_adapter_matches_frozen_source':True,'instrumented_adapter_matches_replay_archive':True,'build_receipt_matches_archive':True,'replay_archive_sha256':replay['sha256'],'replay_archive_git_and_live_match':True,'declared_environment':native['environment'],'environment_scope':'The committed descriptor records the declared/replay environment value. The runner captures native library and build-receipt hashes before/after both focused intervals, but does not independently serialize child process environment values.','scope':'Six handle-lifecycle cases use a synthetic dictionary. These do not establish AyaSpell linguistic accuracy, dictionary installation/download acceptance or another operating system.'}

archives=read(runtime/'pub-cache-receipt.json');assert len(archives)==176 and all(x['verified'] for x in archives)
assert not consumer['github_actions_queried_or_awaited']
# Do not add repeats across VM/Node or any historical test run.
case_rows=[{'suite':suite,'name':name,'executions':executions} for (suite,name),executions in sorted(records.items())]
casefile=a.output.with_name(a.output.stem+'-cases.json');casefile.write_text(json.dumps(case_rows,indent=2)+'\n')
store_unique=set().union(*(cohort_records[x] for x in ['core-vm','core-node','store-vm','portable-node']))
main_unique=set().union(*(cohort_records[g['name']] for g in plan['groups']))
assert len(main_unique)==consumer_cases
node_unique=set().union(*(cohort_records[g['name']] for g in node_plan['groups']))
consumer_unique=main_unique|node_unique
assert consumer_unique==main_unique
expected_groups=[{'name': 'transport-uid-native', 'cwd': 'packages/quds_mail_transport', 'runner': 'dart', 'tests': ['test/configuration_test.dart', 'test/native_provider_test.dart', 'test/host_store_integration_test.dart', 'test/uid_discovery_test.dart']}, {'name': 'transport-tls-loopback-vm', 'cwd': 'packages/quds_mail_transport', 'runner': 'dart', 'tests': ['test/native_tls_test.dart', 'test/native_tls_cancellation_test.dart', 'test/native_tls_round_trip_test.dart']}, {'name': 'transport-node-boundary', 'cwd': 'packages/quds_mail_transport', 'runner': 'dart', 'platform': 'node', 'tests': ['test/unsupported_test.dart']}, {'name': 'uid-search-parser-and-wire', 'cwd': 'third_party/enough_mail', 'runner': 'dart', 'tests': ['test/src/imap/raw_uid_search_parser_test.dart', 'test/imap/raw_uid_search_test.dart']}, {'name': 'imap-response-dispatch-and-lifecycle', 'cwd': 'third_party/enough_mail', 'runner': 'dart', 'tests': ['test/imap/imap_client_test.dart', 'test/src/imap/raw_fetch_parser_test.dart', 'test/src/imap/search_parser_test.dart', 'test/connection_robustness_test.dart', 'test/reconnect_state_test.dart']}, {'name': 'mail-ui-store-consumers', 'cwd': 'packages/quds_mail_ui', 'runner': 'flutter', 'tests': ['test/controller_test.dart', 'test/example_test.dart', 'test/message_view_test.dart', 'test/presentation_test.dart']}, {'name': 'hunspell-provider-vm', 'cwd': 'packages/quds_proofing_hunspell', 'runner': 'dart', 'tests': ['test/hunspell_provider_test.dart']}, {'name': 'hunspell-native-lifecycle-vm', 'cwd': 'packages/quds_proofing_hunspell', 'runner': 'dart', 'tests': ['test/hunspell_native_lifecycle_test.dart']}, {'name': 'arabic-writing-vm', 'cwd': 'packages/quds_office_engine', 'runner': 'dart', 'tests': ['test/proofing/arabic_writing_rules_test.dart']}, {'name': 'arabic-editor-integration', 'cwd': 'packages/quds_office_editor', 'runner': 'flutter', 'tests': ['test/word_arabic_writing_integration_test.dart']}]
assert plan['groups']==expected_groups, 'Frozen plan differs from independently reviewed 23-suite selection'
expected_analysis=['packages/quds_mail_core/lib/src/ports/provider.dart', 'packages/quds_mail_core/lib/src/ports/repository.dart', 'packages/quds_mail_core/test/imap_sync_range_test.dart', 'packages/quds_mail_store/lib/src/repository.dart', 'packages/quds_mail_store/test/imap_sync_range_test.dart', 'packages/quds_mail_transport/lib/src/configuration.dart', 'packages/quds_mail_transport/lib/src/cursor.dart', 'packages/quds_mail_transport/lib/src/native/provider.dart', 'packages/quds_mail_transport/test/configuration_test.dart', 'packages/quds_mail_transport/test/host_store_integration_test.dart', 'packages/quds_mail_transport/test/native_provider_test.dart', 'packages/quds_mail_transport/test/support/imap_fixture.dart', 'packages/quds_mail_transport/test/uid_discovery_test.dart', 'third_party/enough_mail/lib/src/imap/imap_client.dart', 'third_party/enough_mail/lib/src/private/imap/raw_uid_search_parser.dart', 'third_party/enough_mail/test/imap/raw_uid_search_test.dart', 'third_party/enough_mail/test/src/imap/raw_uid_search_parser_test.dart', 'packages/quds_proofing_hunspell/lib/installer_io.dart', 'packages/quds_proofing_hunspell/lib/quds_proofing_hunspell.dart', 'packages/quds_proofing_hunspell/lib/src/hunspell_catalog.dart', 'packages/quds_proofing_hunspell/lib/src/hunspell_installer_io.dart', 'packages/quds_proofing_hunspell/lib/src/hunspell_provider.dart', 'packages/quds_proofing_hunspell/lib/src/hunspell_transport.dart', 'packages/quds_proofing_hunspell/lib/src/hunspell_transport_native.dart', 'packages/quds_proofing_hunspell/lib/src/hunspell_transport_stub.dart', 'packages/quds_proofing_hunspell/lib/src/hunspell_transport_web.dart', 'packages/quds_proofing_hunspell/lib/src/hunspell_words.dart', 'packages/quds_proofing_hunspell/test/hunspell_native_lifecycle_test.dart', 'packages/quds_proofing_hunspell/test/hunspell_native_test.dart', 'packages/quds_proofing_hunspell/test/hunspell_provider_test.dart', 'packages/quds_proofing_hunspell/tool/corpus_check.dart', 'packages/quds_proofing_hunspell/tool/web_compile_check.dart', 'packages/quds_office_engine/lib/src/proofing/arabic_writing_rules.dart', 'packages/quds_office_engine/test/proofing/arabic_writing_rules_test.dart']
assert plan['analysis']==plan['format']==expected_analysis
assert len(plan['analysis'])==len(set(plan['analysis']))==34
lifecycle_suite='packages/quds_proofing_hunspell/test/hunspell_native_lifecycle_test.dart'
lifecycle_expected={
 'native handle ownership normal and repeated disposal close exactly once',
 'native handle ownership reopening replaces and releases each owned handle once',
 'native handle ownership dispose during startup settles opening without allocation',
 'native handle ownership forced exit releases a handle after a stalled check',
 'native handle ownership forced exit preserves ownership while native open returns',
 'native handle ownership provider timeout settles and releases its native handle',
}
assert cohort_records['hunspell-native-lifecycle-vm']=={(lifecycle_suite,name) for name in lifecycle_expected}
tls_expected={'packages/quds_mail_transport/test/native_tls_test.dart':17,'packages/quds_mail_transport/test/native_tls_cancellation_test.dart':4,'packages/quds_mail_transport/test/native_tls_round_trip_test.dart':5}
tls_observed=collections.Counter(suite for suite,name in consumer_unique if suite in tls_expected)
assert dict(tls_observed)==tls_expected
suite_counts={suite:{'distinct_cases':sum(1 for p,n in records if p==suite),'executions':sum(len(v) for (p,n),v in records.items() if p==suite)} for suite in sorted({p for p,n in records})}
strict_static_diagnostics=[]
for check in consumer['runs']:
 if check['name']=='analysis':
  for line in (a.consumers/check['log']).read_text().splitlines():
   if re.search(r'^\s*(?:error|warning|info)\s*[•-]',line,re.I):strict_static_diagnostics.append(line)
assert not strict_static_diagnostics
assert not store_unique.intersection(consumer_unique)
assert cohort_records['core-vm']==cohort_records['core-node']
repeated=sum(len(x) for x in cohort_records.values())-len(records)
store_repeated=store_executions-len(store_unique)
assert repeated==store_repeated+node_cases
forecast={'core_store_executions':250,'core_store_distinct_scenarios':162,'main_focused_executions':438,'node_executions':96,'total_executions':784,'total_distinct_scenarios':600,'distinct_suites':37,'core_store_platform_repeats':88,'all_platform_repeats':184}
observed={'core_store_executions':store_executions,'core_store_distinct_scenarios':len(store_unique),'main_focused_executions':consumer_cases,'node_executions':node_cases,'total_executions':sum(len(x) for x in cohort_records.values()),'total_distinct_scenarios':len(records),'distinct_suites':len({x[0] for x in records}),'core_store_platform_repeats':store_repeated,'all_platform_repeats':repeated}
forecast_differences={key:{'forecast':value,'observed':observed[key]} for key,value in forecast.items() if observed[key]!=value}
# Forecasts corroborate rather than supply counts. Coverage, terminal status and
# identities above come independently from every raw event and the frozen plan.
assert not forecast_differences, forecast_differences
output={'accepted':True,'audited_at_utc':datetime.now(timezone.utc).isoformat(),'qualified_source':source,'qualified_tree':consumer['source_tree'],'core_store_qualified_source':store_source,'core_store_reused_by_source_continuity':store_source!=source,
 'counts':{'cohorts':cohorts,'core_store_executions':store_executions,'core_store_distinct_scenarios':len(store_unique),'main_focused_executions':consumer_cases,'main_focused_distinct_scenarios':len(main_unique),'node_executions':node_cases,'focused_executions':consumer_cases+node_cases,'focused_distinct_scenarios':len(consumer_unique),'focused_suites':len(set(all_requested)),'focused_suite_platform_executions':len(all_requested)+len(node_requested),'total_executions':sum(len(x) for x in cohort_records.values()),'total_distinct_scenarios':len(records),'repeated_vm_node_executions':repeated,'distinct_suites':len({x[0] for x in records}),'total_suite_platform_executions':sum(c['suites'] for c in cohorts),'python_runner_controls':python_controls,'unrelated_historical_test_totals_added':False},
 'source_binding':{'core_store_source_inputs_match_original_and_final_commit':True,'core_store_before_after_identical':True,'core_store_source_paths_verified':store_sources,'focused_before_after_identical':True,'focused_source_paths_verified':consumer_sources,'all_source_hashes_verified_against_qualified_git_and_live_checkout':True,'focused_source_tree_and_index_stable':True,'focused_complete_source_selection_verified':True,'node_source_paths_verified':len(node_src_before),'main_and_node_source_manifests_identical':True,'node_before_after_identical':True,'dependency_lock_unchanged':True},
 'runtime_binding':{'core_store_direct_launcher_native_inputs_before_after_identical':True,'core_store_direct_launcher_native_input_records':len(store['direct_launcher_inputs_after']),'focused_runtime_before_after_identical':True,'focused_runtime_records':len(env_after),'node_runtime_records':len(node_env_after),'node_runtime_before_after_identical':True,'node_runtime_values_match_main_and_live_readback':True,'all_focused_runtime_records_match_live_readback':True,'retained_restore_manifest_files_verified_live':len(retained),'official_sdk_archive_verified_in_restore_receipt':True,'verified_hosted_archive_count':len(archives),'scope':'The main focused and separate Node runners each captured their recorded runtime before/after their intervals; every recorded value also matches live readback. check_store captured its narrower direct launcher/config/native-asset inputs. Full retained-runtime readback corroborates provenance; it is not a full-runtime boundary capture for check_store.'},
 'validation':{'store_strict_analysis_format_resolution_and_whitespace_passed':True,'focused_strict_analysis_format_whitespace_passed':True,'focused_analysis_dart_paths':len(consumer['analysis_files']),'focused_format_dart_paths':len(consumer['formatted_files']),'browser_compilations':compilations,'actual_browser_execution':False,'all_log_and_manifest_receipt_hashes_verified':True,'compressed_focused_logs_equal_originals':True,'node_log_and_manifest_hashes_verified':True,'all_three_repeated_vm_and_node_case_identities_match_exactly':True},
 'tls_scope':{'suite_counts':dict(tls_observed),'distinct_loopback_and_adapter_cases':sum(tls_observed.values()),'live_external_accounts_exercised':False,'fixtures_bound_by_source_manifest':all(path in src_before for path in plan['extra_inputs'] if '/tls/' in path)},
 'arabic_platform_scope':{'suite':arabic_suite,'vm_cases':len(arabic_vm),'node_cases':len(cohort_records['arabic-writing-node']),'same_case_identities':True,'node_executions_add_zero_distinct_cases':True},
 'suite_counts':suite_counts,
 'native_runtime_binding':native_verification,
 'platform_repeats':node_platform_matches,
 'forecast_crosscheck':{'forecast':forecast,'observed':observed,'differences':forecast_differences},
 'hunspell_scope':{'provider_vm_cases':len(cohort_records['hunspell-provider-vm']),'provider_node_cases':len(cohort_records['hunspell-provider-node']),'provider_same_case_identities':cohort_records['hunspell-provider-vm']==cohort_records['hunspell-provider-node'],'instrumented_native_lifecycle_cases':len(cohort_records['hunspell-native-lifecycle-vm']),'actual_ayaspell_dictionary_or_installer_cases_executed_here':False},
 'strict_static_diagnostics':strict_static_diagnostics,
 'warnings':warnings,'warning_scope':'Runtime warning messages are preserved separately from strict analysis and failures. Test names identify their source. A Drift multiple-database warning in the separate-host-container test is expected debug output; other messages must be assessed individually.',
 'case_inventory':{'file':casefile.name,'sha256':filehash(casefile)},'github_actions':'NOT QUERIED OR AWAITED'}
a.output.write_text(json.dumps(output,indent=2)+'\n');print(json.dumps(output,indent=2))
