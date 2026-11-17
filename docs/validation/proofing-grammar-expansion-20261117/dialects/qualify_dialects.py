#!/usr/bin/env python3
"""Bind actual five-dialect native/Wasm provider probes to their source/runtime."""
import argparse
from datetime import datetime,timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

root=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repository',type=Path,default=root.parent/'quds_office_suite')
parser.add_argument('--dart',default=shutil.which('dart'))
parser.add_argument('--node',default=shutil.which('node'))
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
repo=args.repository.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
if not args.dart or not args.node:parser.error('Supply Dart and Node')
package=repo/'packages/quds_proofing_harper';build=package/'build';config=repo/'.dart_tool/package_config.json'
def sha(p):return hashlib.file_digest(p.open('rb'),'sha256').hexdigest()
sys.path.insert(0,str(package/'tool'))
from verify import verify_distribution
build_receipt=verify_distribution(build)
def snapshot():
    paths=list((repo/'packages/quds_office_engine/lib').rglob('*.dart'))
    paths.extend(package/name for name in build_receipt['source_sha256'])
    return {str(p.relative_to(repo)):sha(p) for p in sorted(set(paths))}
before=snapshot();started=datetime.now(timezone.utc).isoformat();commands=[];errors=[]
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()
def run(name,args,env=None):
    start=time.monotonic();r=subprocess.run(args,cwd=repo,text=True,capture_output=True,env=env,timeout=120)
    (out/(name+'.stdout.log')).write_text(r.stdout);(out/(name+'.stderr.log')).write_text(r.stderr)
    commands.append({'name':name,'command':args,'exit_code':r.returncode,'seconds':time.monotonic()-start,'stdout_sha256':sha(out/(name+'.stdout.log')),'stderr_sha256':sha(out/(name+'.stderr.log'))})
    print(name+': '+str(r.returncode),flush=True)
    r.check_returncode();return r
native=None;web=None
try:
    native_library=build/'native/libquds_proofing_harper.so'
    env={**os.environ,'QUDS_HARPER_TEST_LIBRARY':str(native_library)}
    result=run('native',[args.dart,'--packages='+str(config),str(root/'harper_dialect_native.dart')],env)
    native=json.loads(result.stdout)
    compiled=out/'harper_dialect_web.js'
    run('compile-web',[args.dart,'compile','js','--packages='+str(config),'-O2',str(root/'harper_dialect_web.dart'),'-o',str(compiled)])
    result=run('wasm',[args.node,str(root/'run_harper_dialect_web.mjs'),str(compiled),str(build/'web/harper_worker.mjs'),str(package/'tool/node_worker_bridge.mjs')])
    web=json.loads(result.stdout)
    for result in [native,web]:
        assert result['status']=='passed' and result['successful_requests']==20 and result['unsupported_requests']==4
    verify_distribution(build)
except Exception as error:errors.append(repr(error))
after=snapshot()
if before!=after:errors.append('Source changed during dialect review')
receipt={'schema_version':1,'status':'passed' if not errors else 'failed','started_at_utc':started,'finished_at_utc':datetime.now(timezone.utc).isoformat(),'source_commit':head,
  'source_sha256':before,'source_sha256_after':after,'source_unchanged':before==after,'build_receipt_sha256':sha(build/'build-receipt.json'),'artifact_sha256':build_receipt['files'],
  'probe_sha256':{name:sha(root/name) for name in ['harper_dialect_common.dart','harper_dialect_native.dart','harper_dialect_web.dart','run_harper_dialect_web.mjs']},
  'commands':commands,'native':native,'wasm':web,'errors':errors,
  'limits':['Linux x86_64 native runtime and actual shipped Wasm executed through the recorded Node Worker/fetch bridge.','These checks do not establish real browser, CSP, deployed hosting, mobile or other native-platform acceptance.','Five dialects are exercised through canonical tags and Latin/Unicode-preference aliases; twenty successful requests are sequential/concurrent variants, not independent grammar examples.']}
(out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'status':receipt['status'],'source_files':len(before),'output':str(out),'errors':errors}),flush=True)
raise SystemExit(0 if receipt['status']=='passed' else 1)
