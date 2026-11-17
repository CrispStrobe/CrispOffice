#!/usr/bin/env python3
"""Restore SHA-256 pinned official Pub archives for local qualification."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repository', type=Path, required=True)
parser.add_argument('--output-root', type=Path, required=True)
args = parser.parse_args()
root = args.output_root.resolve()
repo = args.repository.resolve()
root.mkdir(parents=True, exist_ok=True)
prior = repo / 'docs/validation/proofing-en-de-20261117/pub-cache-receipt.json'
cache = root / 'cache/pub'
downloads = root / 'downloads/pub'
downloads.mkdir(parents=True, exist_ok=True)
for path in [cache/'_temp',cache/'hosted/pub.dev',cache/'hosted-hashes/pub.dev']:
    path.mkdir(parents=True, exist_ok=True)
packages = [{k:p[k] for k in ['name','version','sha256']} for p in json.loads(prior.read_text())['packages']]

def fetch(p):
    key = p['name']+'-'+p['version']
    url = 'https://pub.dev/api/archives/'+key+'.tar.gz'
    file = downloads/(key+'.tar.gz')
    target = cache/'hosted/pub.dev'/key
    hashfile = cache/'hosted-hashes/pub.dev'/(key+'.sha256')
    for attempt in range(1,5):
        try:
            if not file.exists() or hashlib.file_digest(file.open('rb'),'sha256').hexdigest()!=p['sha256']:
                subprocess.run(['curl','--fail','--silent','--show-error','--location','--retry','2','--max-time','90',url,'-o',str(file)],check=True)
            digest = hashlib.file_digest(file.open('rb'),'sha256').hexdigest()
            assert digest==p['sha256'], key+' hash mismatch'
            if not target.exists():
                temp = cache/'_temp'/key
                temp.mkdir(exist_ok=True)
                with tarfile.open(file) as archive:
                    archive.extractall(temp,filter='data')
                temp.rename(target)
            # Pub compares the cache hash file byte-for-byte, without trimming.
            hashfile.write_text(digest)
            print('VERIFIED '+key,flush=True)
            return {**p,'url':url,'archive_bytes':file.stat().st_size,'status':'verified-download'}
        except Exception as e:
            if attempt==4:
                print('FAILED '+key+' '+repr(e),flush=True)
                return {**p,'url':url,'status':'failed','error':repr(e)}
            time.sleep(1)

start=time.monotonic()
with ThreadPoolExecutor(12) as pool:
    results=list(pool.map(fetch,packages))
receipt={'status':'passed' if all(p['status']=='verified-download' for p in results) else 'failed',
         'finished_at_utc':datetime.now(timezone.utc).isoformat(),'elapsed_seconds':time.monotonic()-start,
         'prior_receipt_sha256':hashlib.file_digest(prior.open('rb'),'sha256').hexdigest(),
         'packages':results}
(root/'pub-cache-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'status':receipt['status'],'count':len(results),'seconds':receipt['elapsed_seconds']}),flush=True)
raise SystemExit(0 if receipt['status']=='passed' else 1)
