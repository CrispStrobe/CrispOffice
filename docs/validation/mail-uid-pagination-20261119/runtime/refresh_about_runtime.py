#!/usr/bin/env python3
"""Rebind the final About workspace while preserving every prior runtime input."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess


def sha(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',required=True,type=Path)
    parser.add_argument('--runtime',required=True,type=Path)
    parser.add_argument('--preparation',required=True,type=Path)
    args=parser.parse_args()
    repo,runtime,preparation=(p.resolve() for p in (args.repo,args.runtime,args.preparation))
    receipt_path=runtime/'runtime.json'
    preserved=runtime/'runtime-before-about.json'
    if not preserved.exists():
        preserved.write_bytes(receipt_path.read_bytes())
    if sha(preserved)!='71d8cfd27118380f4dcf497786e6949ae2dd56ef60125b11cb3d1f79f7e2b5af':
        raise RuntimeError('Preserve the exact final installed-backend receipt before the About workspace refresh')
    receipt=json.loads(preserved.read_text())
    if sha(repo/'pubspec.lock')!=receipt['workspace_lock_sha256']:
        raise RuntimeError('The incoming About workspace changed the locked dependency versions')
    prior_inputs=dict(receipt['additional_inputs'])
    for name,identity in prior_inputs.items():
        if sha(Path(name))!=identity:
            raise RuntimeError('Previously bound runtime input changed: '+name)
    restorer_path=repo/'docs/validation/document-review-notes-20261118/runtime/restore_runtime.py'
    spec=importlib.util.spec_from_file_location('restored_runtime',restorer_path)
    restorer=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(restorer)
    packages=restorer.verified_workspace_packages(repo)
    if packages!=receipt['workspace_packages']:
        raise RuntimeError('The final About refresh changed the verified workspace package-name set')
    restorer.bind_test_inputs(repo,runtime,receipt,node_tests=True)
    if any(name in prior_inputs and prior_inputs[name]!=identity for name,identity in receipt['additional_inputs'].items()):
        raise RuntimeError('The final About refresh changed a previously bound native/Node input')
    receipt['additional_inputs']={**prior_inputs,**receipt['additional_inputs']}
    log=preparation/'workspace-pub-get.log'
    graph=repo/'.dart_tool/package_graph.json'
    for path in (preserved,log,graph,preparation/'workspace-before.json'):
        receipt['additional_inputs'][str(path)]=sha(path)
    before=json.loads((preparation/'workspace-before.json').read_text())
    config=repo/'.dart_tool/package_config.json'
    receipt['about_workspace_refresh']={
        'at_utc':datetime.now(timezone.utc).isoformat(),
        'source_commit':subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip(),
        'prior_runtime_receipt':str(preserved),'prior_runtime_sha256':sha(preserved),
        'package_config_sha256':sha(config),'package_config_unchanged':sha(config)==before['package_config_sha256'],
        'package_graph_sha256':sha(graph),'package_graph_unchanged':sha(graph)==before['package_graph_sha256'],
        'workspace_lock_sha256':sha(repo/'pubspec.lock'),
        'studio_pubspec_sha256':sha(repo/'packages/quds_office_editor/example/pubspec.yaml'),
        'offline_resolution_log':str(log),'offline_resolution_log_sha256':sha(log),
        'refresh_script_sha256':sha(Path(__file__)),
        'scope':'Offline workspace metadata refresh after the final About/url_launcher integration; every prior runtime input retained unchanged',
    }
    temporary=receipt_path.with_suffix('.about.tmp')
    temporary.write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    temporary.replace(receipt_path)
    print(json.dumps({'status':receipt['status'],'workspace_package_count':len(packages['resolved']),
                      'additional_inputs':len(receipt['additional_inputs']),'runtime_sha256':sha(receipt_path),
                      'package_config_unchanged':receipt['about_workspace_refresh']['package_config_unchanged'],
                      'package_graph_unchanged':receipt['about_workspace_refresh']['package_graph_unchanged']},indent=2))


if __name__=='__main__':main()
