#!/usr/bin/env python3
"""Finish the actual minimal Flutter runtime without changing SDK sources."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,time

ROOT=Path(__file__).resolve().parents[1]
SDK=ROOT/'flutter-source'
REPO=ROOT.parent/'quds_office_suite'
OUT=ROOT/'setup'
required=['dart-selected-install.json','common-install.json','engine-install.json','prefetch-162.json']
start=time.monotonic()
while not all((OUT/name).is_file() for name in required):
 if time.monotonic()-start>1200: raise RuntimeError('Timed out awaiting verified runtime downloads')
 print(json.dumps({'waiting_for':[name for name in required if not (OUT/name).is_file()]}),flush=True)
 time.sleep(20)
prefetch=json.loads((OUT/'prefetch-162.json').read_text())
if any(x['status']=='failed' for x in prefetch['packages']): raise RuntimeError('Pinned package prefetch incomplete')
for name in ['tmp','config','data','cache','bin']: (ROOT/name).mkdir(exist_ok=True)
env=dict(os.environ,PUB_CACHE=str(ROOT/'pub-cache'),TMPDIR=str(ROOT/'tmp'),FLUTTER_ROOT=str(SDK),CI='true',DART_SUPPRESS_ANALYTICS='true',FLUTTER_SUPPRESS_ANALYTICS='true',XDG_CONFIG_HOME=str(ROOT/'config'),XDG_CACHE_HOME=str(ROOT/'cache'),XDG_DATA_HOME=str(ROOT/'data'))
dart=SDK/'bin/cache/dart-sdk/bin/dart'
record={'status':'running','sdk_root':str(SDK),'dart':str(dart),'commands':[],'runtime_method':'genuine pinned Flutter source and selected unmodified SDK archive members; direct tool-source launcher','github_actions_used':False}
def save(): (OUT/'runtime-receipt.json').write_text(json.dumps(record,indent=2)+'\n')
def run(name,args,cwd=REPO,timeout=300):
 print('START '+name,flush=True)
 log=OUT/(name+'.log')
 before=time.monotonic()
 with log.open('wb') as output:
  result=subprocess.run([str(x) for x in args],cwd=cwd,env=env,stdout=output,stderr=subprocess.STDOUT,timeout=timeout)
 item={'name':name,'args':[str(x) for x in args],'cwd':str(cwd),'exit_code':result.returncode,'seconds':time.monotonic()-before,'log':log.name,'log_sha256':hashlib.sha256(log.read_bytes()).hexdigest()}
 record['commands'].append(item);save()
 print('END '+name+' '+str(result.returncode),flush=True)
 if result.returncode:
  print(log.read_text(errors='replace')[-10000:],flush=True)
  raise RuntimeError(name+' failed')
 return log
try:
 save()
 revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=SDK).decode().strip()
 if revision!='737ba8f885dc774b53b442759999a312c9461e4e': raise RuntimeError('Wrong framework commit')
 run('dart-version',[dart,'--version'])
 run('generate-engine-stamp',[SDK/'bin/internal/update_engine_version.sh'],SDK)
 engine=(SDK/'bin/internal/engine.version').read_text().strip()
 if engine!='cf636b1dfb818dd6a3ff16e390e93b1a036969c8': raise RuntimeError('Wrong engine')
 # The cache stamp records the engine actually installed from all five original
 # FlutterSdk artifacts. It is not a framework or Dart identity override.
 for path in ['bin/cache/pkg/sky_engine','bin/cache/pkg/flutter_gpu','bin/cache/artifacts/engine/common','bin/cache/artifacts/engine/linux-x64/flutter_tester']:
  if not (SDK/path).exists(): raise RuntimeError('Missing verified engine artifact '+path)
 (SDK/'bin/cache/flutter_sdk.stamp').write_text(engine)
 record['engine_cache_stamp']={'value':engine,'source':'actual verified installed official engine artifacts; no SDK identity override'}
 run('flutter-tools-offline',[dart,'pub','--suppress-analytics','--directory',SDK/'packages/flutter_tools','get','--offline'])
 launcher=ROOT/'bin/flutter'
 launcher.write_text('#!/bin/sh\nexec "'+str(dart)+'" --packages="'+str(SDK/'packages/flutter_tools/.dart_tool/package_config.json')+'" "'+str(SDK/'packages/flutter_tools/bin/flutter_tools.dart')+'" "$@"\n')
 launcher.chmod(0o755)
 dartlink=ROOT/'bin/dart'
 if not dartlink.exists(): dartlink.symlink_to(dart)
 env['PATH']=str(ROOT/'bin')+':'+env.get('PATH','')
 (ROOT/'env.sh').write_text('export FLUTTER_ROOT='+str(SDK)+'\nexport PUB_CACHE='+str(ROOT/'pub-cache')+'\nexport TMPDIR='+str(ROOT/'tmp')+'\nexport XDG_CONFIG_HOME='+str(ROOT/'config')+'\nexport XDG_DATA_HOME='+str(ROOT/'data')+'\nexport XDG_CACHE_HOME='+str(ROOT/'cache')+'\nexport CI=true DART_SUPPRESS_ANALYTICS=true FLUTTER_SUPPRESS_ANALYTICS=true\nexport PATH='+str(ROOT/'bin')+':"$PATH"\n')
 version_log=run('flutter-version',[launcher,'--version','--machine'])
 record['actual_runtime']=json.loads(version_log.read_text())
 source_lock=REPO/'docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock'
 payload=source_lock.read_bytes();digest=hashlib.sha256(payload).hexdigest()
 if digest!='344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130': raise RuntimeError('Historical project lock bytes differ')
 (REPO/'pubspec.lock').write_bytes(payload)
 run('workspace-offline',[launcher,'pub','get','--offline','--enforce-lockfile'])
 if hashlib.sha256((REPO/'pubspec.lock').read_bytes()).hexdigest()!=digest: raise RuntimeError('Project lock changed')
 record['workspace_lock_sha256']=digest
 record['package_count']=len(json.loads((REPO/'.dart_tool/package_config.json').read_text())['packages'])
 record['framework_revision']=revision
 record['dart_executable_sha256']=hashlib.sha256(dart.read_bytes()).hexdigest()
 record['flutter_tester_sha256']=hashlib.sha256((SDK/'bin/cache/artifacts/engine/linux-x64/flutter_tester').read_bytes()).hexdigest()
 record['status']='ready'
except Exception as e:
 record['status']='failed';record['error']=str(e)
 raise
finally:
 save()
 print(json.dumps(record),flush=True)
