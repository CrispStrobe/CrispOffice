#!/usr/bin/env python3
"""Independent raw-event, source and runtime audit of transport and Mail qualification."""
import argparse,collections,gzip,hashlib,json,re,subprocess
from datetime import datetime,timezone
from pathlib import Path,PurePosixPath
ap=argparse.ArgumentParser()
ap.add_argument('--repo',type=Path,required=True)
ap.add_argument('--store',type=Path,required=True)
ap.add_argument('--consumers',type=Path,required=True)
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
git('merge-base','--is-ancestor',store_source,source)
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
assert [x['passed_executions'] for x in cohorts]==[31,31,95,42]
assert '--enforce-lockfile' in store['checks'][2]['command'] and '--offline' in store['checks'][2]['command']
assert consumer['success'] is True and consumer['source_commit']==source and consumer['source_tree']==git('rev-parse',source+'^{tree}').decode().strip()
for key in ['source_unchanged','environment_unchanged','source_head_unchanged','source_index_unchanged','tracked_worktree_clean_before','tracked_worktree_clean_after']:assert consumer[key] is True,key
for key in ['source_mismatches','environment_mismatches','unexpected_native_mappings_after','sparse_source_omissions']:assert not consumer[key]
for name,value in consumer['manifest_sha256'].items():assert filehash(a.consumers/name)==value
src_before=read(a.consumers/'source-before.json');src_after=read(a.consumers/'source-after.json');env_before=read(a.consumers/'environment-before.json');env_after=read(a.consumers/'environment-after.json')
assert src_before==src_after and env_before==env_after
consumer_sources=verify_sources(src_before,True);assert consumer_sources==consumer['source_input_count']
plan_raw=git('show',source+':'+consumer['plan']);assert digest(plan_raw)==consumer['plan_sha256'];plan=json.loads(plan_raw);assert plan['groups']==consumer['planned_groups']
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
assert len({str(PurePosixPath(g['cwd'])/t) for g in plan['groups'] for t in g['tests']})==sum(len(g['tests']) for g in plan['groups'])==32
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
retained=read(runtime/'retained-inputs.json')
for name,record in retained.items():assert (runtime/name).is_file() and filehash(runtime/name)==record['sha256'],name
runtime_receipt=read(runtime/'runtime.json');assert filehash(runtime/'runtime.json')==consumer['runtime_receipt_sha256']
assert runtime_receipt['status']=='ready' and runtime_receipt['archive']['verified'] is True
assert filehash(root/'pubspec.lock')==runtime_receipt['workspace_lock_sha256']==consumer['workspace_lock_sha256']
archives=read(runtime/'pub-cache-receipt.json');assert len(archives)==176 and all(x['verified'] for x in archives)
assert not consumer['github_actions_queried_or_awaited']
# Do not add repeats across VM/Node or any historical test run.
case_rows=[{'suite':suite,'name':name,'executions':executions} for (suite,name),executions in sorted(records.items())]
casefile=a.output.with_name(a.output.stem+'-cases.json');casefile.write_text(json.dumps(case_rows,indent=2)+'\n')
store_unique=set().union(*(cohort_records[x] for x in ['core-vm','core-node','store-vm','portable-node']))
consumer_unique=set().union(*(cohort_records[g['name']] for g in plan['groups']))
assert len(consumer_unique)==consumer_cases
assert [g['name'] for g in plan['groups']]==['transport-native','transport-node-boundary','vendor-imap-and-byte-reader','vendor-connection-and-protocols','mime-consumer-vm','mail-ui-consumers']
assert not store_unique.intersection(consumer_unique)
assert cohort_records['core-vm']==cohort_records['core-node']
repeated=sum(len(x) for x in cohort_records.values())-len(records)
output={'accepted':True,'audited_at_utc':datetime.now(timezone.utc).isoformat(),'qualified_source':source,'qualified_tree':consumer['source_tree'],'core_store_qualified_source':store_source,'core_store_reused_by_source_continuity':store_source!=source,
 'counts':{'cohorts':cohorts,'core_store_executions':199,'core_store_distinct_scenarios':len(store_unique),'focused_executions':consumer_cases,'focused_distinct_scenarios':len(consumer_unique),'focused_suites':32,'total_executions':sum(len(x) for x in cohort_records.values()),'total_distinct_scenarios':len(records),'repeated_vm_node_executions':repeated,'distinct_suites':len({x[0] for x in records}),'python_runner_controls':python_controls,'unrelated_historical_test_totals_added':False},
 'source_binding':{'core_store_source_inputs_match_original_and_final_commit':True,'core_store_before_after_identical':True,'core_store_source_paths_verified':store_sources,'focused_before_after_identical':True,'focused_source_paths_verified':consumer_sources,'all_source_hashes_verified_against_qualified_git_and_live_checkout':True,'focused_source_tree_and_index_stable':True,'dependency_lock_unchanged':True},
 'runtime_binding':{'core_store_direct_launcher_native_inputs_before_after_identical':True,'core_store_direct_launcher_native_input_records':len(store['direct_launcher_inputs_after']),'focused_runtime_before_after_identical':True,'focused_runtime_records':len(env_after),'all_focused_runtime_records_match_live_readback':True,'retained_restore_manifest_files_verified_live':len(retained),'official_sdk_archive_verified_in_restore_receipt':True,'verified_hosted_archive_count':len(archives),'scope':'The focused transport runner captured the full runtime before/after its interval. check_store captured its narrower direct launcher/config/native-asset inputs. Full retained-runtime readback corroborates provenance; it is not a full-runtime boundary capture for check_store.'},
 'validation':{'store_strict_analysis_format_resolution_and_whitespace_passed':True,'focused_strict_analysis_format_whitespace_passed':True,'focused_analysis_dart_paths':len(consumer['analysis_files']),'focused_format_dart_paths':len(consumer['formatted_files']),'browser_compilations':compilations,'actual_browser_execution':False,'all_log_and_manifest_receipt_hashes_verified':True,'compressed_focused_logs_equal_originals':True},
 'warnings':warnings,'warning_scope':'Runtime warning messages are preserved separately from strict analysis and failures. Test names identify their source. A Drift multiple-database warning in the separate-host-container test is expected debug output; other messages must be assessed individually.',
 'case_inventory':{'file':casefile.name,'sha256':filehash(casefile)},'github_actions':'NOT QUERIED OR AWAITED'}
a.output.write_text(json.dumps(output,indent=2)+'\n');print(json.dumps(output,indent=2))
