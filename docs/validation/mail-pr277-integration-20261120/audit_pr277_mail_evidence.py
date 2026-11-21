#!/usr/bin/env python3
"""Read-only audit of source-bound Mail records carried by captured PR277."""
import argparse,hashlib,io,json,os,subprocess,tarfile
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
head='383c0c0c5d3b4b1a6edccc8d09ffd1ca64029537';prefix='docs/validation/zotero-vertical-tables-20261120/'
env=dict(os.environ);env['GIT_NO_LAZY_FETCH']='1'
def blob(source,path):return subprocess.check_output(['git','-C',str(a.repo),'show',source+':'+path],env=env)
def doc(name):return json.loads(blob(head,prefix+name))
def digest(data):return hashlib.sha256(data).hexdigest()
index=doc('mail-final-evidence-index.json');data=blob(head,prefix+index['archive'])
assert len(data)==index['bytes'] and digest(data)==index['sha256']
with tarfile.open(fileobj=io.BytesIO(data),mode='r:gz') as archive:
 members={m.name:archive.extractfile(m).read() for m in archive.getmembers() if m.isfile()}
assert set(members)==set(index['files'])
for name,content in members.items():
 assert len(content)==index['files'][name]['bytes']
 assert digest(content)==index['files'][name]['sha256']
receipts={}; manifests={}
for cohort in ['core','hosts']:
 receipt=json.loads(members[f'mail-final-{cohort}-receipt.json'])
 before=json.loads(members[f'mail-final-{cohort}-sources-before.json'])
 after=json.loads(members[f'mail-final-{cohort}-sources-after.json'])
 assert before==after and receipt['runtime_unchanged'] and receipt['exit_code']==0
 assert receipt['frozen_head']==receipt['head_after']
 events=[]
 for line in members[f'mail-final-{cohort}.jsonl'].decode().splitlines():
  try:event=json.loads(line)
  except ValueError:continue
  if isinstance(event,dict):events.append(event)
 starts={e['test']['id']:e['test'] for e in events if e.get('type')=='testStart'}
 ends={e['testID']:e for e in events if e.get('type')=='testDone'}
 cases=[(starts[k],v) for k,v in ends.items() if k in starts and not v.get('hidden',False)]
 assert not [x for x in events if x.get('type')=='error']
 assert all(end.get('result')=='success' and not end.get('skipped') for _,end in cases)
 terminal=[e for e in events if e.get('type')=='done'];assert len(terminal)==1 and terminal[0]['success']
 assert len(cases)==receipt['passed']
 receipts[cohort]={'source_head':receipt['frozen_head'],'raw_passed':len(cases),'raw_terminal_success':True,'source_count':len(before),'source_runtime_sealed':True}
 manifests[cohort]=before
# Bind every archived relevant Mail source to its declared Git source. Exclude
# untracked local runtime files from Git claims; retain their historical hashes.
source='e8edb90a2948af60f41e50795c049a0a4d1ed3e6'
paths={path:value for manifest in manifests.values() for path,value in manifest.items()
 if path.startswith(('packages/quds_mail_','packages/quds_office_editor/example/lib/studio_mail','packages/quds_office_editor/example/test/studio_mail','third_party/enough_mail/')) or path in ['pubspec.yaml','pubspec.lock']}
proc=subprocess.Popen(['git','-C',str(a.repo),'cat-file','--batch'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
verified=[];missing=[];mismatched=[]
for path,expected in sorted(paths.items()):
 proc.stdin.write((source+':'+path+'\n').encode());proc.stdin.flush();header=proc.stdout.readline().decode().strip().split()
 if len(header)!=3 or header[1]!='blob':missing.append(path);continue
 content=proc.stdout.read(int(header[2]));assert proc.stdout.read(1)==b'\n'
 (verified if digest(content)==expected else mismatched).append(path)
proc.stdin.close();assert proc.wait()==0
assert not mismatched
qualification=doc('mail-final-qualification.json');post=doc('post-main-qualification.json');tail=doc('freshness-tail-qualification.json')
record={'schema_version':1,'incoming_main':head,
 'mail_final_archive':{'sha256':digest(data),'bytes':len(data),'verified_members':len(members)},
 'raw_recounts':receipts,
 'declared_mail_final_total':qualification['total_passed'],
 'mail_final_sources':{'new_core_and_hosts':source,'retained_transport_and_ui':qualification['cohorts']['transport']['source']},
 'git_source_binding':{'relevant_inputs':len(paths),'verified':len(verified),'missing_historical_blobs':missing,'mismatches':mismatched},
 'later_post_main':{'source':post['frozen_head'],'declared_mail_total':post['mail']['passed']},
 'latest_freshness_tail':{'source':tail['frozen_head'],'declared_mail_total':tail['mail']['total_passed'],'host_replacement_policy':tail['replacement_policy']},
 'acceptance_use':'Historical provenance only. None of these overlapping incoming totals is added to our accepted Mail union. Our new merged APIs/tests require the targeted frozen-source gate; unchanged cohorts retain our independently qualified prior inputs.',
 'source_limit':'The incoming mail-final-* package predates later reader/autoconnect changes. Its e8ed/38d qualification cannot be relabeled as383 or the merged source. Later incoming post-main/freshness packages remain separately source-bound.',
 'github_actions_queried':False,'network_used':False}
a.out.write_text(json.dumps(record,indent=2,sort_keys=True)+'\n');print(json.dumps(record,indent=2))
