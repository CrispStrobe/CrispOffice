#!/usr/bin/env python3
"""Check final changed Dart targets without modifying their bytes."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess

p=argparse.ArgumentParser()
p.add_argument('--repo', type=Path, required=True)
p.add_argument('--base', required=True)
p.add_argument('--output', type=Path, required=True)
a=p.parse_args()
repo=a.repo.resolve(); out=a.output.resolve()
out.mkdir(parents=True, exist_ok=False)
def git(*args):
    return subprocess.check_output(['git',*args],cwd=repo).decode().strip()
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
head=git('rev-parse','HEAD')
files=sorted(path for path in git('diff','--name-only',a.base,head).splitlines()
             if path.endswith('.dart') and path.startswith(('packages/','third_party/')) and (repo/path).is_file())
if not files: raise RuntimeError('No changed Dart targets')
before={path:digest(repo/path) for path in files}
sdk=Path(os.environ['FLUTTER_ROOT'])
dart=sdk/'bin/cache/dart-sdk/bin/dart'
steps=[]
for name,command in [('analysis',[str(dart),'analyze','--fatal-infos',*files]),
                     ('format',[str(dart),'format','--output=none','--set-exit-if-changed',*files])]:
    log=out/(name+'.log')
    with log.open('wb') as stream:
        proc=subprocess.run(command,cwd=repo,stdout=stream,stderr=subprocess.STDOUT,timeout=900)
    steps.append({'name':name,'command':command,'exit_code':proc.returncode,'log':log.name,'sha256':digest(log)})
after={path:digest(repo/path) for path in files}
record={'base':a.base,'head_before':head,'head_after':git('rev-parse','HEAD'),
        'selected_files':files,'selected_count':len(files),'source_before':before,
        'source_after':after,'inputs_unchanged':before==after,'steps':steps,
        'recorded_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'accepted':before==after and all(x['exit_code']==0 for x in steps),
        'scope':'Changed existing Dart targets in current repository packages and vendor source; not a whole-workspace analysis claim.'}
(out/'receipt.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps({'accepted':record['accepted'],'files':len(files),'steps':steps}))
raise SystemExit(0 if record['accepted'] else 1)
