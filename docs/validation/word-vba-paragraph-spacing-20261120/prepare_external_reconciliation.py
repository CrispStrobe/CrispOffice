#!/usr/bin/env python3
"""Reconcile reviewed, disjoint late heads without changing the tested checkout."""
import gzip,hashlib,json,os,subprocess
from pathlib import Path
root=Path(__file__).resolve().parent.parent;repo=root/'quds_office_suite';rt=root/'runtime'
parent='d906a2d3c930b404571a223f4addc3e00ccf84e0'
heads=['a51c20737b1932d9c6475ea6dddc33fbd50b2c17','5a73a056f7c757a64d56345c31eabdd6de6eb18a','3bbd414d8f1129bd802b33c3af961d5c12489da2']
qualified='0201b549d0dc3f601c50e36255d557034cb01699';idx=rt/'late-reconciliation.index'
if idx.exists():idx.unlink()
env=os.environ.copy();env['GIT_INDEX_FILE']=str(idx)
def git(*args,input=None):return subprocess.check_output(['git',*args],cwd=repo,env=env,input=input)
def index_entries():
 out={}
 for row in git('ls-files','--stage','-z').split(b'\0'):
  if row:
   meta,path=row.split(b'\t',1);mode,oid,stage=meta.decode().split();assert stage=='0';out[path.decode()]={'mode':mode,'type':'blob','blob':oid}
 return out
def commit_entry(commit,path):
 data=git('ls-tree','-z',commit,'--',path)
 if not data:return None
 meta,name=data[:-1].split(b'\t',1);mode,kind,oid=meta.decode().split();assert name.decode()==path
 return {'mode':mode,'type':kind,'blob':oid}
def put(path,data,mode='100644'):
 oid=git('hash-object','-w','--stdin',input=data).decode().strip();git('update-index','--add','--cacheinfo',mode,oid,path);return oid
assert git('rev-parse','HEAD').decode().strip()==qualified
git('read-tree',parent);proofs=[];touched=set()
for head in heads:
 base=git('merge-base',parent,head).decode().strip();raw=git('diff','--raw','--no-renames','--no-abbrev','-z',base,head).split(b'\0');rows=[]
 for i in range(0,len(raw)-1,2):
  header=raw[i].decode().split();path=raw[i+1].decode();assert path not in touched,path
  current=index_entries().get(path);before=commit_entry(base,path);after=commit_entry(head,path)
  assert current==before,(path,'conflicting delta')
  if after is None:git('update-index','--force-remove',path)
  else:
   assert after['type']=='blob';git('update-index','--add','--cacheinfo',after['mode'],after['blob'],path)
  touched.add(path);rows.append({'path':path,'before':before,'imported':after})
 proofs.append({'head':head,'merge_base':base,'changed_path_count':len(rows),'paths':rows,'all_delta_paths_were_unmodified_at_destination':True})
mac='packages/quds_office_editor/example/tool/build_macos_app.sh';candidate=(root/'macos-build-correction-20261120/build_macos_app.corrected.sh').read_bytes()
assert hashlib.sha256(candidate).hexdigest()=='8592dd41fb59da7fa3ead05287005cfa06d90c02bb5de495e9f985062ffff904'
assert index_entries()[mac]==commit_entry(heads[0],mac)
mac_blob=put(mac,candidate,'100755')
manifest=json.loads(gzip.decompress((rt/'line-spacing-portable-final/inputs-before.json.gz').read_bytes()))
entries=index_entries();selected={name for name in entries if name in manifest['selection']['configuration_files'] or any(name.startswith(p+'/') for p in manifest['selection']['directories'])}
assert selected==set(manifest['entries']) and len(selected)==1131
for name,value in manifest['entries'].items():assert entries[name]==value['head'],name
contract='docs/VBA_WORD_MACROS.md';assert entries[contract]==commit_entry(qualified,contract)
late_review=json.loads((root/'intake-review/late-intake-review.json').read_text())
assert late_review['correction_review']['status']=='ACCEPTED_FOR_INTEGRATION'
assert late_review['correction_review']['candidate_sha256']==hashlib.sha256(candidate).hexdigest()
receipt={'schema':'quds-word-spacing-late-integration/v1','accepted_for_checkpoint':True,'parent_checkpoint':parent,'qualified_word_source':qualified,'additional_actual_parents':heads,'delta_proofs':proofs,'all_selected_deltas_disjoint':True,'word_source_input_count':1131,'exact_word_input_selection_preserved':True,'all_qualified_word_modes_types_blobs_unchanged':True,'reviewed_word_contract_unchanged':True,'macos_correction':{'path':mac,'mode':'100755','blob':mac_blob,'bytes':len(candidate),'sha256':hashlib.sha256(candidate).hexdigest(),'producer_isolated_checks':61,'independent_expectations':36,'actual_macos_build':False,'actual_bash3_execution':False},'word_runtime_status':'Bounded regression remains in progress at this checkpoint; final acceptance will be recorded separately.','local_head_and_tracked_worktree_unchanged':True,'github_actions':'not queried or awaited'}
base='docs/validation/word-vba-paragraph-spacing-20261120/'
put(base+'late-integration-binding.json',(json.dumps(receipt,indent=2)+'\n').encode())
put(base+'prepare_external_reconciliation.py',Path(__file__).read_bytes())
for name in ['late-intake-review.json','late-intake-review.md']:put(base+name,(root/'intake-review'/name).read_bytes())
items=[];raw=git('diff','--cached','--raw','--no-renames','--no-abbrev','-z',parent).split(b'\0')
for i in range(0,len(raw)-1,2):
 h=raw[i].decode().split();path=raw[i+1].decode();assert h[4]!='D';data=git('cat-file','blob',h[3]);items.append({'path':path,'mode':h[1],'type':'blob','expected_sha':h[3],'bytes':len(data),'content':data.decode()})
cp={'parent':parent,'additional_parents':heads,'base_tree':git('rev-parse',parent+'^{tree}').decode().strip(),'tree':git('write-tree').decode().strip(),'entries':items}
(rt/'checkpoint-06-metadata.json').write_text(json.dumps(cp))
assert git('rev-parse','HEAD').decode().strip()==qualified
assert subprocess.check_output(['git','status','--porcelain','--untracked-files=no'],cwd=repo)==b''
print(json.dumps({'parent':parent,'additional_parents':heads,'tree':cp['tree'],'files':len(items),'selected_word_inputs_unchanged':1131,'reviewed_contract_unchanged':True,'macos_script_sha256':hashlib.sha256(candidate).hexdigest(),'local_checkout_unchanged':True},indent=2))
