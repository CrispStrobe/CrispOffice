#!/usr/bin/env python3
"""Verify exact published Git trees, ancestry and all qualified source bytes."""
import argparse
import datetime
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--repo',type=Path,required=True)
p.add_argument('--main',required=True)
p.add_argument('--checkpoint',required=True)
p.add_argument('--source-manifest',type=Path,required=True)
p.add_argument('--live-refs',type=Path,required=True)
p.add_argument('--out',type=Path,required=True)
a=p.parse_args()
repo=a.repo.resolve()

def git(*arguments):
 return subprocess.check_output(['git',*arguments],cwd=repo)

def sha(data): return hashlib.sha256(data).hexdigest()

main=git('rev-parse',a.main).decode().strip()
checkpoint=git('rev-parse',a.checkpoint).decode().strip()
main_tree=git('rev-parse',main+'^{tree}').decode().strip()
checkpoint_tree=git('rev-parse',checkpoint+'^{tree}').decode().strip()
assert main_tree==checkpoint_tree,'Published main tree differs from checkpoint'
live={ref:oid for oid,ref in (line.split() for line in a.live_refs.read_text().splitlines())}
assert live['refs/heads/main']==main,'Observed live main differs'
assert live['refs/heads/codex/word-vba-paragraph-spacing-20261120']==checkpoint,'Observed live checkpoint differs'
ancestors=['3ee4e3622c9a2198d384ed1cb296ab092a8838d0',
 'c7e721b7703766491fd4459b69de30bf68d9010d',
 '27b39fa983c4875e3074e07b9430d503ebb4994e',
 '5ad4461a93c835479bf67acab63623944b3900a3',
 '0201b549d0dc3f601c50e36255d557034cb01699',
 '07860e6b5dbad983523d857bd9de4e13eadced7b',
 'd906a2d3c930b404571a223f4addc3e00ccf84e0',
 'ed750f1f6b8acab88406fd506e0dd511adcc4485',
 'a6c9bb6a6c71e50ff949241b1d5359f329c685aa',
 '8b9be399da380b0b8ab3abf238833eb221996c7d',
 'd1e9cbc0c5dd38f0c8d28e3d76e7fdd59990f3f4',
 'be47bed22a88382f016d823e526bae49590bd0eb',
 'a51c20737b1932d9c6475ea6dddc33fbd50b2c17',
 '5a73a056f7c757a64d56345c31eabdd6de6eb18a',
 '3bbd414d8f1129bd802b33c3af961d5c12489da2',checkpoint]
for ancestor in ancestors:
 subprocess.run(['git','merge-base','--is-ancestor',ancestor,main],cwd=repo,check=True)
data=a.source_manifest.read_bytes()
manifest=json.loads(gzip.decompress(data) if a.source_manifest.suffix=='.gz' else data)
expected_source='0201b549d0dc3f601c50e36255d557034cb01699'
assert (manifest.get('qualified_source') or manifest.get('source_commit'))==expected_source,'Unexpected qualification source'
assert git('rev-parse',expected_source+'^{tree}').decode().strip()=='86531c002a6b1d6e748849f7370a87072a5fa768'
entries=manifest['entries']
assert len(entries)==1131,'Incomplete qualification manifest'
qualified_names=set()
selected_names=set()
selection_prefixes=('packages/quds_office_engine/lib/','packages/quds_office_engine/test/','packages/quds_office_engine/tool/','packages/quds_office_engine/example/','packages/legacy_doc_parser/lib/')
selection_files={'pubspec.yaml','pubspec.lock','analysis_options.yaml','packages/quds_office_engine/pubspec.yaml','packages/quds_office_engine/analysis_options.yaml','packages/legacy_doc_parser/pubspec.yaml','packages/legacy_doc_parser/analysis_options.yaml','packages/quds_office_editor/fonts/LiberationSans-Regular.ttf','packages/quds_office_editor/fonts/LiberationMono-Regular.ttf'}
for row in git('ls-tree','-r','-z',expected_source).split(b'\0'):
 if row:
  meta,path=row.split(b'\t',1)
  name=path.decode()
  if name in selection_files or name.startswith(selection_prefixes):selected_names.add(name)
  if name in entries:
   mode,kind,oid=meta.decode().split()
   expected=entries[name]
   assert {'mode':mode,'type':kind,'blob':oid}==(expected.get('head') or {k:expected[k] for k in ['mode','type','blob']}),name
   qualified_names.add(name)
assert qualified_names==set(entries)==selected_names,'Qualification entries do not exactly cover the reviewed input selection'
tree={}
for row in git('ls-tree','-r','-z',main).split(b'\0'):
 if row:
  meta,path=row.split(b'\t',1)
  mode,kind,oid=meta.decode().split()
  tree[path.decode()]={'mode':mode,'type':kind,'blob':oid}
ordered=sorted(entries)
for name in ordered:
 expected=entries[name]
 expected_tree=expected.get('head') or {k:expected[k] for k in ['mode','type','blob']}
 assert tree[name]==expected_tree,name
requests=''.join(tree[name]['blob']+'\n' for name in ordered).encode()
payload=subprocess.run(['git','cat-file','--batch'],cwd=repo,input=requests,stdout=subprocess.PIPE,check=True).stdout
cursor=0
verified=[]
for name in ordered:
 end=payload.index(b'\n',cursor)
 oid,kind,size=payload[cursor:end].decode().split()
 cursor=end+1
 size=int(size)
 content=payload[cursor:cursor+size]
 cursor+=size
 assert payload[cursor:cursor+1]==b'\n'
 cursor+=1
 expected=entries[name]
 assert kind=='blob' and oid==tree[name]['blob']
 assert size==expected['bytes'] and sha(content)==expected['sha256'],name
 assert hashlib.sha1(f'blob {size}\0'.encode()+content).hexdigest()==oid,name
 verified.append(name)
assert cursor==len(payload)
contract='docs/VBA_WORD_MACROS.md'
assert git('ls-tree',expected_source,'--',contract)==git('ls-tree',main,'--',contract),'Reviewed Word contract changed'
contract_bytes=git('show',main+':'+contract)
macos_script='packages/quds_office_editor/example/tool/build_macos_app.sh'
macos_bytes=git('show',main+':'+macos_script)
assert sha(macos_bytes)=='8592dd41fb59da7fa3ead05287005cfa06d90c02bb5de495e9f985062ffff904','Reviewed macOS correction differs'
assert tree[macos_script]['mode']=='100755','macOS build script lost executable mode'
assert git('rev-parse','HEAD').decode().strip()==main,'Local HEAD is not published main'
assert git('symbolic-ref','--short','HEAD').decode().strip()=='main','Local branch is not main'
worktree_status=git('status','--porcelain').decode()
assert worktree_status=='','Local worktree is not clean'
result={'schema':'quds-word-spacing-post-merge-verification/v1','accepted':True,
 'verified_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'remote_main':main,'preserved_checkpoint':checkpoint,
 'main_tree':main_tree,'checkpoint_tree':checkpoint_tree,'full_trees_equal':True,
 'required_ancestors':ancestors,'all_required_ancestors_retained':True,
 'qualified_source':expected_source,'qualified_source_paths':len(verified),'all_modes_objects_sizes_sha256_match':True,
 'source_manifest_sha256':sha(data),'live_refs_sha256':sha(a.live_refs.read_bytes()),
 'reviewed_word_contract':{'path':contract,'bytes':len(contract_bytes),'sha256':sha(contract_bytes),'matches_qualified_source':True},
 'reviewed_macos_correction':{'path':macos_script,'sha256':sha(macos_bytes),'matches_reviewed_candidate':True},
 'local_branch':'main','local_head_matches_remote':True,'git_worktree_status':worktree_status,
 'github_actions':'not queried or awaited'}
a.out.parent.mkdir(parents=True,exist_ok=True)
a.out.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
