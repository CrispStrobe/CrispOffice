#!/usr/bin/env python3
"""Finish this task's interrupted toolchain restore within a hard disk reserve."""
from datetime import datetime,timezone
from pathlib import Path,PurePosixPath
import hashlib,io,json,os,shlex,shutil,subprocess,tarfile,urllib.parse,urllib.request
import yaml
ROOT=Path('/workspace/scratch/f6338d3de284/runtime');SDK=ROOT/'flutter';CACHE=ROOT/'pub-cache'
OUT=ROOT.parent/'runtime-preparation';REPO=ROOT.parent/'quds_office_suite'
RESERVE=400*1024*1024
record=json.loads((OUT/'runtime.json').read_text());record['status']='resuming-with-disk-budget';record['disk_reserve_bytes']=RESERVE
record['resumed_at_utc']=datetime.now(timezone.utc).isoformat();record['approval_review_disposition']='Interrupted unbounded concurrent cache restore; released only task-owned unexecuted web tooling and SDK history, then resumed sequentially with pre-extraction reserve checks.'
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return h.hexdigest()
def save(): (OUT/'runtime.json').write_text(json.dumps(record,indent=2)+'\n')
def selected(name):
 p=PurePosixPath(name).parts
 return bool(p) and p[0] not in {'test','tests','test_fixes','test_data','testdata','example','examples','doc','docs','benchmark','benchmarks','.github','.git','web'}
def run(name,argv,cwd):
 log=OUT/(name+'.log');start=datetime.now(timezone.utc).isoformat()
 with log.open('wb') as f:r=subprocess.run([str(x) for x in argv],cwd=cwd,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=300)
 record['runs'].append({'name':name,'command':[str(x) for x in argv],'cwd':str(cwd),'exit_code':r.returncode,'log':str(log),'log_sha256':sha(log),'started_at_utc':start});save();print(name,r.returncode,flush=True)
 if r.returncode:raise RuntimeError(name+': '+log.read_text(errors='replace')[-8000:])
 return log
try:
 assert record['archive']['verified'] and record['archive']['sha256']=='baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2'
 packages={}
 for lock in (SDK/'packages/flutter_tools/pubspec.lock',REPO/'pubspec.lock'):
  for name,item in yaml.safe_load(lock.read_text())['packages'].items():
   if item['source']!='hosted':continue
   d=item['description'];assert d['url']=='https://pub.dev'
   key=name+'-'+item['version'];entry={'name':name,'version':item['version'],'sha256':d['sha256']}
   assert key not in packages or packages[key]==entry;packages[key]=entry
 receipts=[];omitted=[]
 for i,(key,item) in enumerate(sorted(packages.items())):
  target=CACHE/'hosted/pub.dev'/key;mark=CACHE/'hosted-hashes/pub.dev'/(key+'.sha256')
  url='https://pub.dev/api/archives/'+urllib.parse.quote(key,safe='-._+')+'.tar.gz'
  if target.is_dir() and mark.is_file() and mark.read_text()==item['sha256']:
   for p in list(target.iterdir()):
    if not selected(p.name):
     size=sum(x.stat().st_size for x in p.rglob('*') if x.is_file()) if p.is_dir() else p.stat().st_size
     omitted.append({'package':key,'path':p.name,'bytes':size})
     if p.is_dir():shutil.rmtree(p)
     else:p.unlink()
   receipts.append(dict(item,url=url,verified=True,disposition='Reuse archive-verified cache marker from interrupted restore; unexecuted test/example/docs omitted'))
  else:
   if shutil.disk_usage(ROOT).free<RESERVE:raise RuntimeError('Free-space reserve reached before network retrieval')
   with urllib.request.urlopen(url,timeout=60) as response:data=response.read(40*1024*1024+1)
   if len(data)>40*1024*1024:raise RuntimeError('Package exceeds bounded in-memory archive limit')
   actual=hashlib.sha256(data).hexdigest();assert actual==item['sha256'],key
   with tarfile.open(fileobj=io.BytesIO(data),mode='r:gz') as bundle:
    members=[m for m in bundle.getmembers() if selected(m.name)];size=sum(m.size for m in members)
    if shutil.disk_usage(ROOT).free-size<RESERVE:raise RuntimeError('Package '+key+' would cross disk reserve')
    if target.exists():shutil.rmtree(target)
    target.mkdir(parents=True)
    bundle.extractall(target,members=members,filter='data')
   mark.write_text(actual);receipts.append(dict(item,url=url,bytes=len(data),extracted_bytes=size,verified=True,disposition='SHA256-verified archive with non-runtime tests/examples/docs omitted'))
  (OUT/'pub-cache-receipt.json').write_text(json.dumps(receipts,indent=2)+'\n')
  if i%20==0:print(json.dumps({'completed_archives':i+1,'free_bytes':shutil.disk_usage(ROOT).free}),flush=True)
 (OUT/'omitted-dependency-nonruntime-directories.json').write_text(json.dumps(omitted,indent=2)+'\n')
 record['hosted_archives_verified']=len(receipts)
 env=dict(os.environ,PUB_CACHE=str(CACHE),FLUTTER_ROOT=str(SDK),CI='true',DART_SUPPRESS_ANALYTICS='true',FLUTTER_SUPPRESS_ANALYTICS='true',DASH__SUPPRESS_ANALYTICS='true',XDG_CONFIG_HOME=str(ROOT/'config'),XDG_CACHE_HOME=str(ROOT/'cache'),XDG_DATA_HOME=str(ROOT/'data'),TMPDIR=str(ROOT/'tmp'))
 dart=SDK/'bin/cache/dart-sdk/bin/dart';tester=SDK/'bin/cache/artifacts/engine/linux-x64/flutter_tester'
 expected={str(dart):'01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb',str(tester):'800f4ca182df7dd2fb46a42dea5d76277b9dbc5e8cd2915e02bcbc978681b45f'}
 for p,d in expected.items():assert sha(Path(p))==d,p
 record['executables_sha256']=expected
 run('flutter-tools-pub-get',[dart,'pub','get','--offline','--enforce-lockfile'],SDK/'packages/flutter_tools')
 flutter=ROOT/'bin/flutter';flutter.write_text('#!/bin/sh\nexec "'+str(dart)+'" "'+str(SDK/'bin/cache/flutter_tools.snapshot')+'" --no-version-check "$@"\n');flutter.chmod(0o755)
 wrapper=ROOT/'bin/dart';wrapper.write_text('#!/bin/sh\nexec "'+str(dart)+'" "$@"\n');wrapper.chmod(0o755)
 env['PATH']=str(ROOT/'bin')+':'+env.get('PATH','')
 (ROOT/'env.sh').write_text('\n'.join('export '+k+'='+shlex.quote(v) for k,v in env.items() if k in ['PUB_CACHE','FLUTTER_ROOT','CI','DART_SUPPRESS_ANALYTICS','FLUTTER_SUPPRESS_ANALYTICS','DASH__SUPPRESS_ANALYTICS','XDG_CONFIG_HOME','XDG_CACHE_HOME','XDG_DATA_HOME','TMPDIR'])+'\nexport PATH='+shlex.quote(str(ROOT/'bin'))+':"$PATH"\n')
 before={name:sha(REPO/name) for name in ['pubspec.yaml','pubspec.lock']}
 run('workspace-pub-get',[dart,'pub','get','--offline','--enforce-lockfile'],REPO)
 after={name:sha(REPO/name) for name in before};assert before==after
 record['tracked_manifests_before']=before;record['tracked_manifests_after']=after
 version=run('flutter-version',[flutter,'--version','--machine'],REPO);record['runtime']=json.loads(version.read_text())
 assert record['runtime']['frameworkRevision']=='737ba8f885dc774b53b442759999a312c9461e4e' and record['runtime']['dartSdkVersion']=='3.13.7'
 record['workspace_package_count']=len(json.loads((REPO/'.dart_tool/package_config.json').read_text())['packages'])
 record['environment_script']=str(ROOT/'env.sh');record['status']='ready'
except BaseException as e:
 record['status']='failed';record['error']=repr(e);raise
finally:
 record['finished_at_utc']=datetime.now(timezone.utc).isoformat();record['free_bytes']=shutil.disk_usage(ROOT).free;save();print(json.dumps({'status':record['status'],'error':record.get('error'),'free_bytes':record['free_bytes']}),flush=True)
