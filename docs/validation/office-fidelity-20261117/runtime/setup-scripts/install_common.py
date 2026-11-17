#!/usr/bin/env python3
"""Install original common Flutter engine artifacts from the pinned engine."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib,json,urllib.request,zipfile

ROOT=Path(__file__).resolve().parents[1]
SDK=ROOT/'flutter-source'
ENGINE='cf636b1dfb818dd6a3ff16e390e93b1a036969c8'
BASE='https://storage.googleapis.com/flutter_infra_release/flutter/'+ENGINE+'/'
items=[('sky_engine.zip','pkg'),('flutter_gpu.zip','pkg'),('flutter_patched_sdk.zip','artifacts/engine/common'),('flutter_patched_sdk_product.zip','artifacts/engine/common')]

def install(pair):
 name,relative=pair;url=BASE+name
 archive=ROOT/'downloads'/name
 for attempt in range(10):
  offset=archive.stat().st_size if archive.exists() else 0
  request=urllib.request.Request(url,headers={'Range':f'bytes={offset}-'} if offset else {})
  try:
   if offset:
    try:
     with zipfile.ZipFile(archive) as z:
      if z.testzip() is None: break
    except zipfile.BadZipFile: pass
   with urllib.request.urlopen(request,timeout=90) as response:
    mode='ab' if response.status==206 and offset else 'wb'
    total=int(response.headers['Content-Range'].split('/')[-1]) if response.status==206 else int(response.headers['Content-Length'])
    with archive.open(mode) as stream:
     while data:=response.read(65536): stream.write(data)
   if archive.stat().st_size!=total: raise RuntimeError('Incomplete download, resuming')
   break
  except Exception as e:
   print(json.dumps({'name':name,'attempt':attempt,'error':str(e)}),flush=True)
   if attempt==9: raise
 target=SDK/'bin/cache'/relative
 target.mkdir(parents=True,exist_ok=True)
 manifest=[]
 with zipfile.ZipFile(archive) as z:
  if z.testzip() is not None: raise RuntimeError('ZIP CRC failure')
  z.extractall(target)
  for info in z.infolist():
   path=target/info.filename
   if path.is_file():
    path.chmod((info.external_attr>>16)&0o777 or 0o644)
    manifest.append({'path':str(path.relative_to(SDK)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
 receipt={'url':url,'archive_bytes':archive.stat().st_size,'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'files':manifest}
 print(json.dumps({'installed':name,'members':len(manifest)}),flush=True)
 return receipt

with ThreadPoolExecutor(max_workers=3) as pool: receipts=list(pool.map(install,items))
(ROOT/'setup/common-install.json').write_text(json.dumps({'engine_revision':ENGINE,'artifacts':receipts},indent=2)+'\n')
print('COMMON_INSTALLED',flush=True)
