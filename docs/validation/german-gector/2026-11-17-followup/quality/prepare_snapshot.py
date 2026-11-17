#!/usr/bin/env python3
"""Extract exact tracked compiler inputs for a frozen quality baseline."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
from urllib.parse import urljoin, urlparse, unquote

parser=argparse.ArgumentParser()
parser.add_argument('--repository',type=Path,required=True)
parser.add_argument('--commit',required=True)
parser.add_argument('--destination',type=Path,required=True)
parser.add_argument('--evidence',type=Path,required=True)
args=parser.parse_args()
repo=args.repository.resolve();dest=args.destination.resolve();evidence=args.evidence.resolve()
assert not dest.exists(), 'Snapshot destination must be fresh.'
evidence.mkdir(parents=True,exist_ok=True)
def git(*command):return subprocess.check_output(['git',*command],cwd=repo)
def sha(data):return hashlib.sha256(data).hexdigest()
commit=git('rev-parse',args.commit+'^{commit}').decode().strip()
tree={}
for record in git('ls-tree','-r','-z',commit).split(b'\0'):
 if not record:continue
 header,name=record.split(b'\t',1);mode,kind,oid=header.decode().split();tree[name.decode()]={'mode':mode,'type':kind,'git_blob':oid}
manifest=git('show',commit+':pubspec.yaml').decode()
workspace=re.findall(r'^  - ([^\s#]+)\s*$',manifest,re.M)
assert workspace and all(p.startswith(('packages/','apps/')) for p in workspace)
roots=['.',*workspace]
archive_paths=[]
for package in roots:
 prefix='' if package=='.'else package+'/'
 for name in ('pubspec.yaml','analysis_options.yaml'):
  if prefix+name in tree:archive_paths.append(prefix+name)
 library=prefix+'lib'
 if any(name.startswith(library+'/')for name in tree):archive_paths.append(library)
archive_paths.append('tools/proofing/german_model')
selected={name:metadata for name,metadata in tree.items()if any(name==p or name.startswith(p+'/')for p in archive_paths)}
assert selected and all(value['type']=='blob'and value['mode']in ('100644','100755')for value in selected.values())
archive=evidence/'source.tar'
assert not archive.exists()
subprocess.run(['git','archive','--format=tar',commit,*archive_paths,'--output',str(archive)],cwd=repo,check=True)
dest.mkdir()
with tarfile.open(archive)as stream:stream.extractall(dest,filter='data')
entries={}
for name,metadata in selected.items():
 data=(dest/name).read_bytes();oid=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest();assert oid==metadata['git_blob'],name
 entries[name]={**metadata,'bytes':len(data),'sha256':sha(data)}
actual={str(p.relative_to(dest))for p in dest.rglob('*')if p.is_file()}
assert actual==set(selected),sorted(actual^set(selected))
for package in roots:
 name=(''if package=='.'else package+'/')+'pubspec.yaml'
 assert(repo/name).read_bytes()==(dest/name).read_bytes(),f'Current resolved manifest differs from baseline: {name}'
lock=(repo/'pubspec.lock').read_bytes();(dest/'pubspec.lock').write_bytes(lock)
config=(repo/'.dart_tool/package_config.json').read_bytes();(dest/'.dart_tool').mkdir();(dest/'.dart_tool/package_config.json').write_bytes(config)
packages=json.loads(config)['packages'];mapped=[]
for package in packages:
 original=Path(unquote(urlparse(urljoin((repo/'.dart_tool/package_config.json').as_uri(),package['rootUri'])).path))
 copied=Path(unquote(urlparse(urljoin((dest/'.dart_tool/package_config.json').as_uri(),package['rootUri'])).path))
 if original.is_relative_to(repo):
  expected=dest/original.relative_to(repo);assert copied==expected
  library=original/package.get('packageUri','');mapped.append({'name':package['name'],'root':str(copied.relative_to(dest)),'library_present':(copied/package.get('packageUri','')).is_dir()})
 else:assert original==copied
record={'schema_version':1,'created_at_utc':datetime.now(timezone.utc).isoformat(),'commit':commit,'tracked_files':entries,'tracked_file_count':len(entries),'tracked_bytes':sum(x['bytes']for x in entries.values()),'archive_sha256':sha(archive.read_bytes()),'archive_bytes':archive.stat().st_size,'lock_sha256':sha(lock),'lock_source':'Copied byte-identical ignored frozen lock from current resolved workspace after verifying every manifest matches the baseline.','initial_package_config_sha256':sha(config),'package_config_mapping':'Copied canonical config unchanged: relative workspace roots now resolve into this exact baseline; external SDK/cache roots unchanged. Offline resolver must verify the graph.','resolved_packages':len(packages),'workspace_packages':mapped,'claims':'All archived file bytes verified against their Git blob identity. No native inference or model timing has run.'}
(evidence/'snapshot.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
# The verified extracted files are sufficient; avoid retaining a duplicate tar.
archive.unlink()
print(json.dumps({key:record[key]for key in ('commit','tracked_file_count','tracked_bytes','resolved_packages','workspace_packages')},indent=2))
