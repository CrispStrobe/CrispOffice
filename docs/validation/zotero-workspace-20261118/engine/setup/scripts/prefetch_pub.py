#!/usr/bin/env python3
"""Verify and install exact hosted archives from one or more Pub lockfiles."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import hashlib, io, json, shutil, sys, tarfile, time, urllib.request, yaml

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'pub-cache'
for sub in ['_temp','hosted/pub.dev','hosted-hashes/pub.dev']:
    (CACHE/sub).mkdir(parents=True,exist_ok=True)
packages={}
for file in sys.argv[1:]:
    if file.endswith('.json'):
        for item in json.loads(Path(file).read_text())['packages']:
            packages[item['name']+'-'+item['version']]={key:item[key] for key in ['name','version','sha256']}
        continue
    for name, spec in yaml.safe_load(Path(file).read_text())['packages'].items():
        if spec['source'] == 'hosted':
            if spec['description']['url'] != 'https://pub.dev':
                raise RuntimeError('Unrecognized host')
            packages[name+'-'+spec['version']]={'name':name,'version':spec['version'],'sha256':spec['description']['sha256']}

def fetch(pair):
    key,spec=pair
    target=CACHE/'hosted/pub.dev'/key
    hash_path=CACHE/'hosted-hashes/pub.dev'/(key+'.sha256')
    if target.is_dir() and hash_path.is_file() and hash_path.read_text()==spec['sha256']:
        return dict(spec,status='verified-cache')
    url='https://pub.dev/api/archives/'+key+'.tar.gz'
    archive_file=CACHE/'_temp'/(key+'.tar.gz.partial')
    for attempt in range(8):
        try:
            offset=archive_file.stat().st_size if archive_file.exists() else 0
            request=urllib.request.Request(url,headers={'Range':f'bytes={offset}-'} if offset else {})
            with urllib.request.urlopen(request,timeout=120) as r:
                if offset and r.status==206:
                    total=int(r.headers['Content-Range'].split('/')[-1])
                    mode='ab'
                else:
                    offset=0
                    total=int(r.headers['Content-Length'])
                    mode='wb'
                with archive_file.open(mode) as stream:
                    while part:=r.read(65536): stream.write(part)
            if archive_file.stat().st_size!=total:
                raise RuntimeError('Incomplete archive body; resuming exact byte position')
            payload=archive_file.read_bytes()
            actual=hashlib.sha256(payload).hexdigest()
            if actual != spec['sha256']:
                raise RuntimeError('Archive hash mismatch')
            temporary=CACHE/'_temp'/key
            if temporary.exists(): shutil.rmtree(temporary)
            temporary.mkdir()
            with tarfile.open(fileobj=io.BytesIO(payload),mode='r:gz') as archive:
                archive.extractall(temporary,filter='data')
            if target.exists(): shutil.rmtree(target)
            temporary.rename(target)
            hash_path.write_text(actual)
            return dict(spec,url=url,bytes=len(payload),actual_sha256=actual,status='verified-download')
        except Exception as e:
            if attempt==7:
                return dict(spec,url=url,status='failed',error=str(e))

results=[]
start=time.monotonic()
with ThreadPoolExecutor(max_workers=8) as pool:
    for f in as_completed([pool.submit(fetch,item) for item in sorted(packages.items())]):
        result=f.result()
        results.append(result)
        print(json.dumps(result),flush=True)
receipt={'packages':sorted(results,key=lambda x:(x['name'],x['version'])),'seconds':time.monotonic()-start}
(ROOT/'setup'/('prefetch-'+str(len(packages))+'.json')).write_text(json.dumps(receipt,indent=2)+'\n')
sys.exit(0 if all(x['status']!='failed' for x in results) else 1)
