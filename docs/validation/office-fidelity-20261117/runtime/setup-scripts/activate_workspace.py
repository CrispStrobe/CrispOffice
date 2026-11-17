#!/usr/bin/env python3
"""Activate the unchanged recorded dependency lock in the integrated checkout."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, os, subprocess
ROOT=Path(__file__).resolve().parents[1]
REPO=ROOT.parent/'quds_office_suite'
SDK=ROOT/'flutter-source'
OUT=ROOT/'setup'
PIN='344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source=REPO/'docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock'
lock=REPO/'pubspec.lock'
if sha(source)!=PIN: raise RuntimeError('Recorded dependency lock does not match qualification')
if lock.exists() and sha(lock)!=PIN: raise RuntimeError('Existing local lock differs; refusing replacement')
if not lock.exists(): lock.write_bytes(source.read_bytes())
paths=subprocess.check_output(['git','ls-files','pubspec.yaml','**/pubspec.yaml'],cwd=REPO,text=True).splitlines()
before={p:sha(REPO/p) for p in paths}
env=dict(os.environ,PUB_CACHE=str(ROOT/'pub-cache'),TMPDIR=str(ROOT/'tmp'),FLUTTER_ROOT=str(SDK),CI='true',DART_SUPPRESS_ANALYTICS='true',FLUTTER_SUPPRESS_ANALYTICS='true',XDG_CONFIG_HOME=str(ROOT/'config'),XDG_CACHE_HOME=str(ROOT/'cache'),XDG_DATA_HOME=str(ROOT/'data'))
env['PATH']=str(ROOT/'bin')+':'+env.get('PATH','')
args=[str(SDK/'bin/cache/dart-sdk/bin/dart'),'pub','--suppress-analytics','get','--offline','--enforce-lockfile']
record={'started_at_utc':datetime.now(timezone.utc).isoformat(),'source_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip(),'argv':args,'cwd':str(REPO),'manifests_before':before,'lock_before':sha(lock),'github_actions_used':False}
log=OUT/'workspace-offline.log'
with log.open('wb') as stream:
 r=subprocess.run(args,cwd=REPO,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=240)
record.update(exit_code=r.returncode,log_sha256=sha(log),lock_after=sha(lock),manifests_after={p:sha(REPO/p) for p in paths},finished_at_utc=datetime.now(timezone.utc).isoformat())
record['status']='ready' if r.returncode==0 and record['lock_after']==PIN and record['manifests_after']==before else 'failed'
if record['status']=='ready': record['package_count']=len(json.loads((REPO/'.dart_tool/package_config.json').read_text())['packages'])
(OUT/'workspace-activation.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps({k:v for k,v in record.items() if k not in ['manifests_before','manifests_after']},indent=2))
if record['status']!='ready': print(log.read_text(errors='replace')[-8000:]);raise SystemExit(1)
