#!/usr/bin/env python3
"""Qualify only the reconciled PR214/PR212 language-download integration."""
from pathlib import Path
from datetime import datetime,timezone
import gzip,hashlib,importlib.util,json,os,shutil,signal,subprocess,time

ROOT=Path('/workspace/scratch/f6338d3de284')
REPO=ROOT/'quds_office_suite';OUT=ROOT/'continuation-validation'/'focused'
SOURCE='2cb7ed411afba8e81e19c28457ac632de78918bc'
PRIOR='b2c05a0afa0ae606b061b13d5e50937c2a8eb1df'
SDK=ROOT/'runtime/flutter';CACHE=ROOT/'runtime/pub-cache'
HELPER=REPO/'docs/validation/mail-archive-portability-20261119/run-local-validation.py'
spec=importlib.util.spec_from_file_location('preserved_helpers',HELPER);h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
h.DOCUMENT_INPUTS={'docs/validation/mail-archive-resume-20261119/run-mail-validation.py','docs/validation/mail-archive-portability-20261119/run-local-validation.py','docs/roadmaps/mail/archive-search.md'}
PATHS=['packages/quds_office_editor/example/lib/studio_downloads_manager.dart','packages/quds_office_editor/example/lib/studio_spacy_host_native.dart','packages/quds_office_editor/example/test/studio_downloads_manager_test.dart','packages/quds_office_editor/example/test/studio_spacy_setup_test.dart']
TESTS=PATHS[2:]
def now():return datetime.now(timezone.utc).isoformat()
def capture(argv):return subprocess.check_output(argv,cwd=REPO,text=True).strip()
def manifest(paths):return {str(p):{'bytes':p.stat().st_size,'sha256':h.sha(p)} for p in sorted(set(paths)) if p.is_file()}
def runtime_inputs():
 paths={SDK/'bin/cache/flutter_tools.snapshot',SDK/'bin/cache/flutter.version.json',REPO/'.dart_tool/package_config.json',ROOT/'runtime/bin/flutter',ROOT/'runtime/bin/dart',ROOT/'runtime/env.sh',SDK/'packages/flutter_tools/.dart_tool/package_config.json'}
 required=paths|{SDK/'bin/cache/dart-sdk/bin/dart',SDK/'bin/cache/artifacts/engine/linux-x64/flutter_tester'}
 if any(not p.is_file() for p in required):raise RuntimeError('Required runtime/configuration input missing: '+str([str(p) for p in required if not p.is_file()]))
 for sub in ['bin/cache/dart-sdk/bin','bin/cache/dart-sdk/lib','bin/cache/artifacts/engine/linux-x64','bin/cache/artifacts/engine/common/flutter_patched_sdk','bin/cache/artifacts/engine/common/flutter_patched_sdk_product','bin/cache/artifacts/material_fonts']:
  if not (SDK/sub).is_dir() or not any(p.is_file() for p in (SDK/sub).rglob('*')):raise RuntimeError('Runtime component empty: '+sub)
  paths.update(p for p in (SDK/sub).rglob('*') if p.is_file())
 return manifest(paths)
def snapshot():return {'source':h.source_manifest(REPO),'dependencies':h.dependency_manifest(REPO/'.dart_tool/package_config.json',CACHE,SDK,REPO),'runtime':runtime_inputs()}
def write_snapshots(label,values):
 for name,value in values.items():h.write_manifest(OUT/(name+'-'+label+'.json.gz'),value)
if OUT.exists():raise RuntimeError('Output already exists; preserve previous attempt and choose new path')
OUT.mkdir(parents=True)
actual_head=capture(['git','rev-parse','HEAD']);subprocess.run(['git','merge-base','--is-ancestor',SOURCE,actual_head],cwd=REPO,check=True)
diff=capture(['git','diff','--name-only',SOURCE,'--','packages','apps','third_party','tool','tools','pubspec.yaml','pubspec.lock'])
if diff:raise RuntimeError('Product differs from frozen checkpoint: '+diff)
record={'schema':1,'status':'running','started_at_utc':now(),'source_head':SOURCE,'source_tree':capture(['git','rev-parse',SOURCE+'^{tree}']),'execution_head':actual_head,'execution_tree':capture(['git','rev-parse','HEAD^{tree}']),'selected_test_files':TESTS,'analysis_and_format_targets':PATHS,'github_actions_used':False,'dependency_resolution_during_validation':False,'prior_acceptance_counted_again':False,'runner_sha256':h.sha(Path(__file__)),'event_parser_sha256':h.sha(HELPER),'steps':[],'scope':'Incremental Linux Flutter widget/fixture qualification of bundled language download labels, sizing and NER status after reconciling PR214. No installed macOS/native-model/network interoperability claim. Original 2243-case acceptance is retained separately.'}
def save():h.write_json(OUT/'receipt.json',record)
def step(name,argv,cwd,tests=False):
 if shutil.disk_usage(ROOT).free<350*1024*1024:raise RuntimeError('Pre-command disk reserve below 350 MiB')
 folder=OUT/name;folder.mkdir();row={'name':name,'argv':[str(a) for a in argv],'cwd':str(cwd),'started_at_utc':now(),'expected_test_files':TESTS if tests else []}
 h.write_json(folder/'command.json',row);start=time.monotonic()
 env={k:v for k,v in os.environ.items() if not k.startswith('QUDS_')}
 print('START '+name,flush=True)
 with (folder/'stdout.log').open('wb') as stdout,(folder/'stderr.log').open('wb') as stderr:
  p=subprocess.Popen(argv,cwd=cwd,env=env,stdout=stdout,stderr=stderr,start_new_session=True)
  while p.poll() is None:
   if shutil.disk_usage(ROOT).free<150*1024*1024 or time.monotonic()-start>600:
    row['interrupted_reason']='disk-reserve-or-time-budget';os.killpg(p.pid,signal.SIGTERM)
    try:p.wait(timeout=5)
    except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
    break
   time.sleep(.25)
 row.update(exit_code=p.returncode,finished_at_utc=now(),elapsed_seconds=round(time.monotonic()-start,3),stdout_sha256=h.sha(folder/'stdout.log'),stderr_sha256=h.sha(folder/'stderr.log'))
 row['accepted']=p.returncode==0 and 'interrupted_reason' not in row
 if tests:
  parsed=h.parse_tests(folder/'stdout.log',REPO,TESTS,cwd);h.write_json(folder/'test-cases.json',parsed)
  row['test_counts']={k:parsed[k] for k in ['passed','failed','skipped']};row['accepted']=row['accepted'] and parsed['accepted'];row['test_cases_sha256']=h.sha(folder/'test-cases.json')
 h.write_json(folder/'result.json',row);record['steps'].append(row);save();print('END '+name+' '+str(row['exit_code']),flush=True)
 if not row['accepted']:raise RuntimeError('Command did not pass: '+name)
try:
 before=snapshot();write_snapshots('before',before)
 prior=json.loads(gzip.decompress((REPO/'docs/validation/mail-archive-resume-20261119/final/source-before.json.gz').read_bytes()))
 record['differences_from_original_accepted_source']=[p for p in sorted(set(prior)|set(before['source'])) if prior.get(p)!=before['source'].get(p)]
 if record['differences_from_original_accepted_source']!=sorted([PATHS[0],PATHS[2],PATHS[3]]):raise RuntimeError('Unexpected source delta versus original accepted milestone')
 h.write_json(OUT/'selection.json',{'source_head':SOURCE,'tests':TESTS,'analysis_and_format_targets':PATHS,'original_source_input_count':len(prior)})
 dart=SDK/'bin/cache/dart-sdk/bin/dart';flutter=ROOT/'runtime/bin/flutter'
 step('format',[dart,'format','--output=none','--set-exit-if-changed',*PATHS],REPO)
 step('analysis',[dart,'analyze','--fatal-infos','--fatal-warnings',*PATHS],REPO)
 step('whitespace',['git','diff','--check',PRIOR,SOURCE,'--',*PATHS],REPO)
 step('studio-downloads-spacy',[flutter,'test','--no-pub','--reporter=json',*[p.removeprefix('packages/quds_office_editor/example/') for p in TESTS]],REPO/'packages/quds_office_editor/example',tests=True)
 after=snapshot();write_snapshots('after',after)
 record['bound_inputs']={name:{'inputs':len(value),'digest':h.digest(value),'before_after_equal':value==after[name],'changes':[p for p in sorted(set(value)|set(after[name])) if value.get(p)!=after[name].get(p)]} for name,value in before.items()}
 if any(not v['before_after_equal'] for v in record['bound_inputs'].values()):raise RuntimeError('Input identity changed during focused qualification')
 record['test_totals']=record['steps'][-1]['test_counts'];record['required_commands_passed']=len(record['steps'])
 record['execution_head_after']=capture(['git','rev-parse','HEAD']);record['native_assets_generated']=manifest([p for folder in [REPO/'.dart_tool/hooks_runner',REPO/'.dart_tool/lib'] for p in folder.rglob('*') if p.is_file()])
 record['status']='passed'
except BaseException as e:
 record['status']='failed';record['error']=repr(e);raise
finally:
 record['finished_at_utc']=now();record['free_bytes']=shutil.disk_usage(ROOT).free;save();print(json.dumps({'status':record['status'],'test_totals':record.get('test_totals'),'error':record.get('error')}),flush=True)
