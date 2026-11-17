#!/usr/bin/env python3
"""Run the actual same Dart provider corpus on a selected checkout, VM and Node.

No candidate source is substituted into the baseline. Package roots are resolved
absolutely and every workspace root is redirected to --target. Corpus scores
are diagnostics; operational failures and changing source inputs fail the run.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import shutil
import time
from urllib.parse import unquote, urlparse

HERE=Path(__file__).resolve()
REPO=HERE.parents[2]

def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def command(argv,cwd,output,timeout=600):
    begin=time.monotonic()
    with output.open('wb') as stream:
        run=subprocess.run(argv,cwd=cwd,stdout=stream,stderr=subprocess.STDOUT,timeout=timeout)
    return {'argv': [a if not a.startswith('-DQUDS_MORPHOLOGY_CORPUS=') else '-DQUDS_MORPHOLOGY_CORPUS=<exact canonical corpus JSON>' for a in argv],
            'exit_code':run.returncode,'elapsed_seconds':time.monotonic()-begin,'output':output.name,'sha256':digest(output)}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--target',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--dart',type=Path,required=True)
    p.add_argument('--node',default='node')
    p.add_argument('--base-only',action='store_true')
    p.add_argument('--vm-only',action='store_true')
    p.add_argument('--corpus',type=Path,default=HERE.with_name('german_morphology_cases.json'))
    args=p.parse_args()
    target=args.target.resolve(); out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    runner=HERE.with_name('qualify_german_morphology.dart')
    corpus=args.corpus.resolve()
    definition=json.dumps(json.loads(corpus.read_text()),ensure_ascii=False,separators=(',',':'))
    original_config=REPO/'.dart_tool/package_config.json'
    config=json.loads(original_config.read_text())
    for package in config['packages']:
        uri=package['rootUri']
        source=Path(unquote(urlparse(uri).path)) if uri.startswith('file:') else (original_config.parent/uri).resolve()
        if source.is_relative_to(REPO): source=target/source.relative_to(REPO)
        package['rootUri']=source.as_uri()+'/'
    config_path=out/'package-config.json'
    config_path.write_text(json.dumps(config,indent=2)+'\n')
    inputs={}
    dependency_paths={}
    for path in sorted((target/'packages/quds_office_engine/lib/src/proofing').rglob('*.dart')):
        inputs[str(path.relative_to(target))]=digest(path)
    for package in config['packages']:
        if package['name']=='characters':
            root=Path(unquote(urlparse(package['rootUri']).path))
            for path in sorted((root/'lib').rglob('*.dart')):
                key='dependency:characters/'+str(path.relative_to(root))
                inputs[key]=digest(path)
                dependency_paths[key]=path
    receipt={'started_at_utc':datetime.now(timezone.utc).isoformat(),
             'source_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=target,text=True).strip(),
             'source_target':str(target),'workspace_config_sha256':digest(original_config),
             'corpus_sha256':digest(corpus),'runner_sha256':digest(runner),'harness_sha256':digest(HERE),
             'source_inputs_sha256':inputs,'runtime_dart_sha256':digest(args.dart.resolve()),'runtime_node_sha256':digest(Path(shutil.which(args.node)).resolve()),
             'source_dirty_files':subprocess.check_output(['git','status','--porcelain','--untracked-files=all','--','packages/quds_office_engine/lib/src/proofing'],cwd=target,text=True).splitlines(),
             'dart_version':subprocess.check_output([str(args.dart),'--version'],text=True,stderr=subprocess.STDOUT).strip(),
             'node_version':subprocess.check_output([args.node,'--version'],text=True).strip(),
             'github_actions_used':False,'commands':[]}
    defines=['-DQUDS_MORPHOLOGY_CORPUS='+definition,'-DQUDS_MORPHOLOGY_VARIANTS='+('false' if args.base_only else 'true')]
    vm=[str(args.dart),'--packages='+str(config_path),*defines,str(runner)]
    receipt['commands'].append(command(vm,target,out/'vm-results.json'))
    if receipt['commands'][-1]['exit_code']:
        print((out/'vm-results.json').read_text()[-8000:]);raise RuntimeError('VM probe failed')
    vm_result=json.loads((out/'vm-results.json').read_text())
    receipt['vm_summary']=vm_result['summary']
    if not args.vm_only:
        js=out/'morphology-probe.js'
        compile_args=[str(args.dart),'compile','js','--packages='+str(config_path),*defines,str(runner),'-o',str(js)]
        receipt['commands'].append(command(compile_args,target,out/'compile-js.log'))
        if receipt['commands'][-1]['exit_code']:
            print((out/'compile-js.log').read_text()[-8000:]);raise RuntimeError('JS compilation failed')
        receipt['commands'].append(command([args.node,'-e','globalThis.self=globalThis; require(process.argv[1]);',str(js)],target,out/'node-results.json'))
        if receipt['commands'][-1]['exit_code']:
            print((out/'node-results.json').read_text()[-8000:]);raise RuntimeError('Node probe failed')
        node_result=json.loads((out/'node-results.json').read_text())
        receipt['node_summary']=node_result['summary']
        receipt['vm_node_semantically_equal']=vm_result==node_result
        receipt['compiled_javascript_sha256']=digest(js)
    after={}
    for path in sorted((target/'packages/quds_office_engine/lib/src/proofing').rglob('*.dart')):
        after[str(path.relative_to(target))]=digest(path)
    for key,path in dependency_paths.items(): after[key]=digest(path)
    receipt['source_unchanged']=after==inputs
    receipt['probe_unchanged']=receipt['runner_sha256']==digest(runner) and receipt['corpus_sha256']==digest(corpus) and receipt['harness_sha256']==digest(HERE)
    receipt['runtimes_unchanged']=receipt['runtime_dart_sha256']==digest(args.dart.resolve()) and receipt['runtime_node_sha256']==digest(Path(shutil.which(args.node)).resolve())
    receipt['completed_at_utc']=datetime.now(timezone.utc).isoformat()
    receipt['status']='passed' if all(c['exit_code']==0 for c in receipt['commands']) and receipt['source_unchanged'] and receipt['probe_unchanged'] and receipt['runtimes_unchanged'] and vm_result['summary']['operational_failures']==0 and receipt.get('vm_node_semantically_equal',True) else 'failed'
    (out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({k:v for k,v in receipt.items() if k in ['status','source_head','vm_summary','node_summary','vm_node_semantically_equal','source_unchanged','probe_unchanged']},indent=2))
    if receipt['status']!='passed': raise SystemExit(1)
if __name__=='__main__': main()
