#!/usr/bin/env python3
"""Extract unmodified required SDK members from the official pinned engine ZIP.

This is a selected installation, not a claim of whole ZIP SHA256 verification.
Every member CRC and size is checked, each installed file receives a SHA256
receipt, and the executable is compared with the previous full-SDK qualification.
"""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path, PurePosixPath
import hashlib, io, json, os, struct, time, urllib.request, zipfile, zlib

ROOT=Path(__file__).resolve().parents[1]
URL='https://storage.googleapis.com/flutter_infra_release/flutter/cf636b1dfb818dd6a3ff16e390e93b1a036969c8/dart-sdk-linux-x64.zip'
TOTAL=238851283
TAIL=ROOT/'downloads/dart-zip-tail.bin'
PREFIX=ROOT/'downloads/dart-sdk-linux-x64.zip'
PARTS=ROOT/'downloads/dart-selected-parts'
INSTALL=ROOT/'flutter-source/bin/cache'
PARTS.mkdir(parents=True,exist_ok=True)
data=TAIL.read_bytes()
eocd=struct.unpack_from('<4s4H2LH',data,data.rfind(b'PK\x05\x06'))
central=eocd[6]
z=zipfile.ZipFile(io.BytesIO(data[central-(TOTAL-len(data)):]))
infos=sorted(z.infolist(),key=lambda x:x.header_offset)
for info in infos: info.header_offset+=central

snapshot_names={
 'kernel_worker_aot.dart.snapshot','dartdev_aot.dart.snapshot',
 'dds_aot.dart.snapshot','frontend_server_aot.dart.snapshot',
 'kernel-service.dart.snapshot','dart_tooling_daemon_aot.dart.snapshot',
 'analysis_server_aot.dart.snapshot','gen_kernel_aot.dart.snapshot',
}
def selected(name):
 if not name.startswith('dart-sdk/bin/'):
  return True
 if name in {'dart-sdk/bin/dart','dart-sdk/bin/dartvm','dart-sdk/bin/dartaotruntime','dart-sdk/bin/utils/gen_snapshot','dart-sdk/bin/resources/devtools/version.json'}:
  return True
 return name.startswith('dart-sdk/bin/snapshots/') and PurePosixPath(name).name in snapshot_names

chosen=[x for x in infos if selected(x.filename)]
intervals=[]
for i,info in enumerate(infos):
 if selected(info.filename):
  lo=info.header_offset
  hi=infos[i+1].header_offset if i+1<len(infos) else central
  if intervals and lo-intervals[-1][1]<65536:
   intervals[-1][1]=hi
  else:
   intervals.append([lo,hi])
blocks=[]
for lo,hi in intervals:
 for start in range(lo,hi,4*1024*1024):
  blocks.append((start,min(hi,start+4*1024*1024)))
prefix_bytes=PREFIX.stat().st_size if PREFIX.exists() else 0
start=time.monotonic()
print(json.dumps({'selected_members':len(chosen),'selected_compressed_bytes':sum(hi-lo for lo,hi in blocks),'available_prefix_bytes':prefix_bytes}),flush=True)

def fetch(block):
 lo,hi=block
 target=PARTS/f'{lo}-{hi}.bin'
 if target.exists() and target.stat().st_size==hi-lo: return block
 local_end=min(hi,max(lo,prefix_bytes))
 local=b''
 if local_end>lo:
  with PREFIX.open('rb') as stream:
   stream.seek(lo);local=stream.read(local_end-lo)
 if local_end==hi:
  target.write_bytes(local);return block
 partial=target.with_suffix('.partial')
 if not partial.exists(): partial.write_bytes(local)
 for attempt in range(10):
  try:
   resume=lo+partial.stat().st_size
   if resume==hi:
    partial.replace(target)
    return block
   req=urllib.request.Request(URL,headers={'Range':f'bytes={resume}-{hi-1}'})
   with urllib.request.urlopen(req,timeout=180) as response:
    if response.status!=206 or response.headers.get('Content-Range')!=f'bytes {resume}-{hi-1}/{TOTAL}':
     raise RuntimeError('Unexpected HTTP range response')
    with partial.open('ab') as stream:
     while chunk:=response.read(65536): stream.write(chunk)
   if partial.stat().st_size!=hi-lo: raise RuntimeError('Incomplete range; resume verified byte position')
   partial.replace(target)
   print(json.dumps({'range':[lo,hi],'download_bytes':hi-local_end,'seconds':round(time.monotonic()-start,2)}),flush=True)
   return block
  except Exception as e:
   print(json.dumps({'range':[lo,hi],'attempt':attempt,'error':str(e)}),flush=True)
   if attempt==9: raise

with ThreadPoolExecutor(max_workers=6) as pool:
 for f in as_completed([pool.submit(fetch,b) for b in blocks]): f.result()

segments={}
for lo,hi in intervals:
 segments[lo]=b''.join((PARTS/f'{a}-{b}.bin').read_bytes() for a,b in blocks if lo<=a<hi)
manifest=[]
for info in chosen:
 if PurePosixPath(info.filename).is_absolute() or '..' in PurePosixPath(info.filename).parts:
  raise RuntimeError('Unsafe member')
 for lo,raw in segments.items():
  offset=info.header_offset-lo
  if 0<=offset<len(raw): break
 else: raise RuntimeError('Missing member range')
 header=struct.unpack_from('<4s5H3L2H',raw,offset)
 if header[0]!=b'PK\x03\x04': raise RuntimeError('Bad member signature')
 at=offset+30+header[-2]+header[-1]
 compressed=raw[at:at+info.compress_size]
 payload=zlib.decompress(compressed,-15) if info.compress_type==8 else compressed
 if len(payload)!=info.file_size or (zlib.crc32(payload)&0xffffffff)!=info.CRC:
  raise RuntimeError('Invalid member '+info.filename)
 target=INSTALL/info.filename
 target.parent.mkdir(parents=True,exist_ok=True)
 target.write_bytes(payload)
 mode=(info.external_attr>>16)&0o777
 target.chmod(mode or 0o644)
 manifest.append({'path':info.filename,'bytes':len(payload),'sha256':hashlib.sha256(payload).hexdigest(),'zip_crc32':f'{info.CRC:08x}'})
dart=INSTALL/'dart-sdk/bin/dart'
actual=hashlib.sha256(dart.read_bytes()).hexdigest()
expected='01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb'
if actual!=expected: raise RuntimeError('Dart executable differs from previous full-archive qualification')
if (INSTALL/'dart-sdk/version').read_text().strip()!='3.13.7': raise RuntimeError('Unexpected Dart version')
receipt={'url':URL,'engine_revision':'cf636b1dfb818dd6a3ff16e390e93b1a036969c8','central_directory_sha256':hashlib.sha256(data).hexdigest(),'whole_archive_sha256_verified':False,'verification':'official pinned HTTPS artifact, exact ranges, all selected ZIP CRCs and sizes, per-file SHA256, executable matches previously qualified full archive','selected_members':len(manifest),'files':manifest,'elapsed_seconds':time.monotonic()-start,'omitted':'DevTools UI, web compiler snapshots, sanitizer runtimes, redundant JIT analysis snapshot; complete SDK lib retained','executable_sha256':actual}
(ROOT/'setup/dart-selected-install.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'status':'installed','dart':str(dart),'sha256':actual,'members':len(manifest)}),flush=True)
