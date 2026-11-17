#!/usr/bin/env python3
"""Prepare or execute serial quality replay from a source-bound AOT snapshot.

Default operation only prints the commands. --execute runs real native inference;
the caller coordinates it with other local tests, builds and measurements.
"""
import argparse
from datetime import datetime,timezone
import hashlib,importlib.util,json,os
from pathlib import Path
import subprocess

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--source-root',type=Path,required=True)
p.add_argument('--build-dir',type=Path,required=True)
p.add_argument('--panels',type=Path,required=True)
p.add_argument('--output-dir',type=Path,required=True)
p.add_argument('--bundle-dir',type=Path,default=os.environ.get('QUDS_GECTOR_MODEL'))
p.add_argument('--model-sha256',default='549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b')
p.add_argument('--library',type=Path,default=os.environ.get('QUDS_GECTOR_LIBRARY'))
p.add_argument('--library-sha256',default=os.environ.get('QUDS_GECTOR_LIBRARY_SHA256'))
p.add_argument('--only',choices=['original-30','development-76','syntax-56','context-83','completion-28','holdout-104'])
p.add_argument('--execute',action='store_true')
a=p.parse_args()
assert a.bundle_dir and a.library and a.library_sha256 and os.environ.get('FLUTTER_ROOT'),'Activate the retained runtime or provide explicit model/native assets.'
root=a.source_root.resolve();build_dir=a.build_dir.resolve();panels_path=a.panels.resolve();out=a.output_dir.resolve()
def sha(path):
 with path.open('rb')as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
build=json.loads((build_dir/'quality-build.json').read_text())
assert all(build[k]is True for k in ('completed','passed','source_stable','dependencies_stable','sdk_stable'))
assert build['target']=='incremental-quality'
spec=importlib.util.spec_from_file_location('quality_build',root/'tools/proofing/german_model/build_gector_aot.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
assert module.source_snapshot(root,target='incremental-quality')==build['source_files'],'Source changed since this AOT build.'
assert module.dependency_snapshot(root)==build['dependency_inputs'],'Resolved package libraries changed since build.'
sdk=Path(os.environ['FLUTTER_ROOT'])/'bin/cache/dart-sdk/bin';runtime=sdk/'dartaotruntime';program=build_dir/'quality.aot'
assert sha(runtime)==build['runtime']['executable']['sha256']
assert sha(program)==build['runtime']['entrypoint']['sha256']
model=a.bundle_dir/'gector-de-mixed-q4_k.gguf'
assert sha(model)==a.model_sha256 and sha(a.library)==a.library_sha256
manifest=json.loads(panels_path.read_text());plans=[]
for panel in manifest['panels']:
 if a.only and panel['name']!=a.only:continue
 corpus=panels_path.parent/panel['run_file'];assert sha(corpus)==panel['run_sha256']
 output=out/(panel['name']+'.json');log=out/(panel['name']+'.log');assert not output.exists() and not log.exists(), 'Use fresh output files.'
 command=[str(runtime),str(program),'--source-root',str(root),'--cases',str(corpus),'--bundle-dir',str(a.bundle_dir),'--model',str(model),'--model-sha256',a.model_sha256,'--library',str(a.library),'--library-sha256',a.library_sha256,'--output',str(output)]
 plans.append({'panel':panel['name'],'command':command,'log':str(log),'corpus_sha256':panel['run_sha256']})
if not a.execute:
 print(json.dumps({'executed':False,'native_inference_run':False,'plans':plans},indent=2));raise SystemExit(0)
out.mkdir(parents=True,exist_ok=True)
for plan in plans:
 output=out/(plan['panel']+'.json');receipt=out/(plan['panel']+'-invocation.json')
 assert not receipt.exists()
 invocation={'panel':plan['panel'],'command':plan['command'],'started_at_utc':datetime.now(timezone.utc).isoformat(),'program_sha256':sha(program),'build_receipt_sha256':sha(build_dir/'quality-build.json'),'corpus_sha256':plan['corpus_sha256'],'native_inference_run':True,'interpretation':'Quality replay only; observed durations are not benchmark evidence.'}
 receipt.write_text(json.dumps(invocation,indent=2)+'\n')
 with Path(plan['log']).open('x')as stream:
  result=subprocess.run(plan['command'],cwd=root,env={**os.environ,'CRISPEMBED_GECTOR':'1'},stdout=stream,stderr=subprocess.STDOUT,timeout=600)
 invocation.update(exit_code=result.returncode,finished_at_utc=datetime.now(timezone.utc).isoformat(),log_sha256=sha(Path(plan['log'])))
 if output.exists():invocation['output_sha256']=sha(output)
 receipt.write_text(json.dumps(invocation,indent=2)+'\n')
 assert result.returncode==0,Path(plan['log']).read_text()[-6000:]
 report=json.loads(output.read_text());assert all(report[k]is True for k in ('completed','operational_passed','source_stable','status_contract_passed'))
 assert report['cases_sha256']==plan['corpus_sha256']
 print(json.dumps({'panel':plan['panel'],'operational_passed':True,'summary':report['summary']},ensure_ascii=False),flush=True)
