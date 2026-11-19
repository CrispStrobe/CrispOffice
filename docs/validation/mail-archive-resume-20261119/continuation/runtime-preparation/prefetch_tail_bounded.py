#!/usr/bin/env python3
"""Prepare future locked packages without approaching the serial writer or disk reserve."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path,PurePosixPath
import hashlib,io,json,shutil,tarfile,threading,urllib.parse,urllib.request
import yaml
ROOT=Path('/workspace/scratch/f6338d3de284/runtime');OUT=ROOT.parent/'runtime-preparation';REPO=ROOT.parent/'quds_office_suite';SDK=ROOT/'flutter';CACHE=ROOT/'pub-cache'
packages={}
for lock in [REPO/'pubspec.lock',SDK/'packages/flutter_tools/pubspec.lock']:
 for name,item in yaml.safe_load(lock.read_text())['packages'].items():
  if item['source']=='hosted':packages[name+'-'+item['version']]={'name':name,'version':item['version'],'sha256':item['description']['sha256']}
pairs=sorted(packages.items());positions={k:i for i,(k,_) in enumerate(pairs)};lock=threading.Lock();written=0;records=[]
def selected(n):return bool(PurePosixPath(n).parts) and PurePosixPath(n).parts[0] not in {'test','tests','test_fixes','test_data','testdata','example','examples','doc','docs','benchmark','benchmarks','.github','.git','web'}
def serial_position():
 try:
  a=json.loads((OUT/'pub-cache-receipt.json').read_text());return positions[a[-1]['name']+'-'+a[-1]['version']]
 except (ValueError,IndexError):return len(pairs)
def worker(pair):
 global written
 key,item=pair;target=CACHE/'hosted/pub.dev'/key;mark=CACHE/'hosted-hashes/pub.dev'/(key+'.sha256')
 if target.exists() or positions[key]<serial_position()+10:return
 with lock:
  if shutil.disk_usage(ROOT).free<650*1024*1024 or written>70*1024*1024:return
 url='https://pub.dev/api/archives/'+urllib.parse.quote(key,safe='-._+')+'.tar.gz'
 try:
  with urllib.request.urlopen(url,timeout=45) as response:data=response.read(40*1024*1024+1)
  if len(data)>40*1024*1024:raise RuntimeError('Archive size limit')
  assert hashlib.sha256(data).hexdigest()==item['sha256']
  with tarfile.open(fileobj=io.BytesIO(data),mode='r:gz') as bundle:
   members=[m for m in bundle.getmembers() if selected(m.name)];size=sum(m.size for m in members)
   with lock:
    if target.exists() or positions[key]<serial_position()+10 or shutil.disk_usage(ROOT).free-size<600*1024*1024 or written+size>80*1024*1024:return
    target.mkdir();bundle.extractall(target,members=members,filter='data');mark.write_text(item['sha256']);written+=size
    records.append(dict(item,url=url,archive_bytes=len(data),extracted_bytes=size,verified=True))
    (OUT/'bounded-tail-prefetch.json').write_text(json.dumps({'disk_reserve_bytes':600*1024*1024,'total_write_cap_bytes':80*1024*1024,'workers':3,'minimum_distance_from_serial_writer':10,'written_bytes':written,'archives':records},indent=2)+'\n')
    if len(records)%10==0:print(len(records),'future packages prepared; free',shutil.disk_usage(ROOT).free,flush=True)
 except Exception as e:
  with lock:print(key,type(e).__name__,str(e),flush=True)
with ThreadPoolExecutor(max_workers=3) as pool:list(pool.map(worker,pairs[100:]))
print('Bounded prefetch complete',len(records),written,flush=True)
