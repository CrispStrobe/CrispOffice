#!/usr/bin/env python3
"""Restore exact historical proofing sources without changing the active tree."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

root=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repository',type=Path,default=root.parent/'quds_office_suite')
parser.add_argument('--reference',default='62563c61f02ee44504776d9e7d26557f9bae490a')
parser.add_argument('--output',type=Path,default=root)
args=parser.parse_args()
repo=args.repository.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
base=out/'baseline_proofing'
ref=subprocess.check_output(['git','rev-parse',args.reference],cwd=repo,text=True).strip()
files={}
for name in ['german_writing_rules.dart','office_proofing.dart','proofing_text_ranges.dart']:
    path='packages/quds_office_engine/lib/src/proofing/'+name
    target=base/'lib/src/proofing'/name;target.parent.mkdir(parents=True,exist_ok=True)
    payload=subprocess.check_output(['git','show',ref+':'+path],cwd=repo)
    target.write_bytes(payload);files[path]=hashlib.sha256(payload).hexdigest()
license_bytes=subprocess.check_output(['git','show',ref+':LICENSE'],cwd=repo)
(base/'LICENSE').write_bytes(license_bytes)
config=json.loads((repo/'.dart_tool/package_config.json').read_text())
for package in config['packages']:
    if package['name']=='quds_office_engine':package['rootUri']=base.as_uri()+'/'
    elif not package['rootUri'].startswith('file:'):
        package['rootUri']=(repo/'.dart_tool'/package['rootUri']).resolve().as_uri()+'/'
(out/'baseline-package-config.json').write_text(json.dumps(config,indent=2)+'\n')
(out/'baseline-source-receipt.json').write_text(json.dumps({'commit':ref,'scope':'Exact three-file baseline proofing projection; same pinned characters dependency; no active source mutation.','files_sha256':files,'license_sha256':hashlib.sha256(license_bytes).hexdigest()},indent=2)+'\n')
print(json.dumps({'baseline_commit':ref,'source_files':len(files),'output':str(out)}))
