#!/usr/bin/env python3
"""Read existing golden routing and image bytes; never render or replace them."""
import argparse,hashlib,json,os,re,struct,subprocess
from pathlib import Path
from datetime import datetime,timezone
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo',type=Path,required=True)
parser.add_argument('--toolchain',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
a=parser.parse_args()
repo,toolchain,out=[p.resolve() for p in (a.repo,a.toolchain,a.output)]
out.mkdir(parents=True,exist_ok=True)
if (out/'verification.json').exists():raise RuntimeError('Use a fresh output directory')
helper=repo/'packages/quds_office_editor/test/support/office_golden.dart'
helper_text=helper.read_text()
block=re.search(r'const linuxReferences = \{([\s\S]*?)\};',helper_text).group(1)
names=re.findall(r"'([^']+)'",block)
assert len(names)==7 and len(set(names))==7
assert all(re.fullmatch(r'[A-Za-z0-9_]+\.png',name) for name in names)
probe=toolchain/'golden_route_probe.dart'
probe.write_text('import "dart:convert";\nimport "dart:io";\nimport '+json.dumps(helper.as_uri())+';\nvoid main(){print(jsonEncode({"platform":Platform.operatingSystem,"routes":{for(final name in const '+json.dumps(names)+') name:officeGolden(name)}}));}\n')
dart=toolchain/'flutter-sdk/bin/cache/dart-sdk/bin/dart'
command=[str(dart),str(probe)]
env=dict(os.environ,CI='true',DART_SUPPRESS_ANALYTICS='true',DASH__SUPPRESS_ANALYTICS='true',FLUTTER_SUPPRESS_ANALYTICS='true')
def record(path):
    data=path.read_bytes()
    blob=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
    relative=str(path.relative_to(repo))
    tracked=subprocess.check_output(['git','rev-parse','HEAD:'+relative],cwd=repo,text=True).strip()
    return {'path':relative,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'git_blob_sha1':blob,'head_blob_sha1':tracked,'matches_checked_in_head':blob==tracked}
helper_before=record(helper)
result=subprocess.run(command,env=env,cwd=repo,capture_output=True,text=True,timeout=60)
(out/'stdout.json').write_text(result.stdout)
(out/'stderr.log').write_text(result.stderr)
assert result.returncode==0,result.stderr
routed=json.loads(result.stdout)
assert routed['platform']=='linux',routed
images=[]
for name,path in routed['routes'].items():
    expected='goldens/linux/'+name
    assert path==expected,(name,path)
    actual=repo/'packages/quds_office_editor/test'/path
    image=record(actual)
    data=actual.read_bytes()
    assert data[:8]==b'\x89PNG\r\n\x1a\n' and data[12:16]==b'IHDR'
    width,height=struct.unpack('>II',data[16:24])
    images.append({'name':name,'helper_result':path,'png_width':width,'png_height':height,**image})
helper_after=record(helper)
passed=helper_before==helper_after and helper_before['matches_checked_in_head'] and all(x['matches_checked_in_head'] and x['png_width']>0 and x['png_height']>0 for x in images)
receipt={'status':'passed' if passed else 'failed','recorded_at_utc':datetime.now(timezone.utc).isoformat(),'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'command':command,'actual_process_exit_code':result.returncode,'platform':routed['platform'],'helper_before':helper_before,'helper_after':helper_after,'images':images,'probe_source':probe.read_text(),'scope':'Executed the existing officeGolden helper for its seven Linux-specific names and verified tracked PNG identities/dimensions. No raster rendering, screenshot comparison, --update-goldens, image mutation, or test-case additions.'}
(out/'verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'status':receipt['status'],'image_count':len(images),'helper_sha256':helper_before['sha256'],'all_checked_in':all(x['matches_checked_in_head'] for x in images)},indent=2))
raise SystemExit(0 if passed else 1)
