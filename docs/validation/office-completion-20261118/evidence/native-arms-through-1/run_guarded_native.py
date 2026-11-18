"""Run native preparation or serial sweep with the unchanged frozen-source guard."""
import argparse
from datetime import datetime,timezone
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

parser=argparse.ArgumentParser()
parser.add_argument('--phase',choices=['prepare','sweep'],required=True)
parser.add_argument('--commit',required=True)
parser.add_argument('--workspace',type=Path,required=True)
args=parser.parse_args()
ROOT=Path(__file__).resolve().parent
REPO=ROOT.parent/'qualification-source'
WORK=args.workspace.resolve()
DART=ROOT.parent/'toolchains/flutter/bin/cache/dart-sdk/bin/dart'
REF=ROOT/'consumer-runtime/retained-reference'
NATIVE=ROOT/'native-qualification-runtime'
PACK=NATIVE/'native-development-pack'
PREP=ROOT/('native-prepare-'+args.commit[:8])/'result'
RUN=ROOT/('native-'+args.phase+'-'+args.commit[:8])
RUN.mkdir(exist_ok=False)
OUT=RUN/'result'
GUARD=RUN/'guard'
manifest=json.loads((PACK/'pack.json').read_text())
extra=[PACK/'pack.json',NATIVE/'reference-f32.json',PACK/manifest['native']['path'],PACK/manifest['model']['directory']/manifest['model']['file']]
if args.phase=='prepare':
    command=[sys.executable,ROOT/'native_prepare_child.py','--repo',REPO,'--workspace',WORK,'--dart',DART,'--output',OUT]
    extra.append(ROOT/'native_prepare_child.py')
    timeout=900
else:
    assert json.loads((PREP/'provider-build.json').read_text())['passed']
    command=[sys.executable,REPO/'docs/validation/german-gector/2026-11-17-followup/native-threads/run_native_thread_sweep.py','--source-root',WORK,'--dart',DART,'--aot',PREP/'provider.aot','--build-receipt',PREP/'provider-build.json','--pack',PACK,'--reference',NATIVE/'reference-f32.json','--output-dir',OUT]
    extra.extend([PREP/'provider.aot',PREP/'provider-build.json',PREP/'audit-controls.json'])
    timeout=3720
guard=[sys.executable,REPO/'docs/validation/office-union-20261117/setup/guard_frozen_run.py','--repo',REPO,'--workspace',WORK,'--dart',DART,'--consumer-root',REF,'--commit',args.commit,'--output',GUARD]
for p in extra:guard.extend(['--extra-input',p])
argv=list(map(str,[*guard,'--',*command]))
env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1',CI='true',DART_SUPPRESS_ANALYTICS='true',FLUTTER_SUPPRESS_ANALYTICS='true',TMPDIR=str(WORK/'tmp'),XDG_CONFIG_HOME=str(WORK/'config'))
env['PATH']=str(DART.parent)+os.pathsep+env.get('PATH','')
row={'phase':args.phase,'source_commit':args.commit,'argv':argv,'started_utc':datetime.now(timezone.utc).isoformat(),'timeout_seconds':timeout,'passed':False}
(RUN/'orchestration.json').write_text(json.dumps(row,indent=2)+'\n')
with (RUN/'guard.stdout.log').open('wb') as stdout,(RUN/'guard.stderr.log').open('wb') as stderr:
    proc=subprocess.Popen(argv,cwd=REPO,env=env,stdout=stdout,stderr=stderr,start_new_session=True)
    try:row['exit_code']=proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        row['timeout']=True;os.killpg(proc.pid,signal.SIGTERM)
        try:proc.wait(timeout=10)
        except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.wait()
        row['exit_code']=proc.returncode
row['finished_utc']=datetime.now(timezone.utc).isoformat()
row['passed']=row['exit_code']==0 and json.loads((GUARD/'receipt.json').read_text())['passed']
(RUN/'orchestration.json').write_text(json.dumps(row,indent=2)+'\n')
spec=importlib.util.spec_from_file_location('pack',REPO/'docs/validation/office-reconciled-20261117/resume/package_checkpoint.py')
pack=importlib.util.module_from_spec(spec);spec.loader.exec_module(pack)
files={str(p.relative_to(RUN)):p for p in RUN.rglob('*') if p.is_file() and not p.is_symlink() and p.name!='provider.aot' and '__pycache__' not in p.parts}
files['run_guarded_native.py']=Path(__file__).resolve()
files['native_prepare_child.py']=ROOT/'native_prepare_child.py'
pack.pack(RUN.with_suffix('.tar.xz'),files,('Passed ' if row['passed'] else 'Failed/incomplete ')+'native '+args.phase+' on frozen '+args.commit+'; generated provider executable omitted, exact build receipt retained.')
print(json.dumps({'phase':args.phase,'passed':row['passed'],'source_commit':args.commit,'output':str(RUN),'archive':str(RUN.with_suffix('.tar.xz'))}),flush=True)
raise SystemExit(0 if row['passed'] else 1)
