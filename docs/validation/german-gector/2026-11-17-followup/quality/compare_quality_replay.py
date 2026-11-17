#!/usr/bin/env python3
"""Independently reconstruct raw quality projections and compare fixed panels.

This auditor never runs a provider. It verifies UTF-16 source edits, first-offer
projection, the deterministic/model merge, statuses, corpus identity and build
binding before checking lost exact corrections or newly flagged clean inputs.
"""
import argparse
from collections import Counter
import hashlib,json
from pathlib import Path

LANES=('writing_only','deterministic','model_only','combined')
PRIORITY={'grammar':0,'spelling':1,'style':2}
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def utf16(text):return text.encode('utf-16-le')
def key(value):return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'))
def conflicts(a,b):
 if a['start']==a['end']:return b['start']<=a['start']<=b['end']
 if b['start']==b['end']:return a['start']<=b['start']<=a['end']
 return a['start']<b['end'] and b['start']<a['end']
def display(results):
 return sorted([f for r in results if r['status']=='success'for f in r['findings']],key=lambda f:(f['start'],f['end'],PRIORITY[f['category']]))
def reconstruct(row,outcome):
 results=outcome['results'];statuses=[r['status']for r in results]
 assert len(set(r['provider_id']for r in results))==len(results)
 assert all(s in ('success','unsupported')for s in statuses)
 complete='success'in statuses and all(s in ('success','unsupported')for s in statuses)
 source=utf16(row['input']);offset=row['start_offset'];accepted=[];skipped=[]
 for result in results:
  if result['status']!='success':assert not result['findings'];continue
  for f in result['findings']:
   assert f['provider_id']==result['provider_id']
   start,end=f['start']-offset,f['end']-offset
   assert isinstance(start,int)and isinstance(end,int)and 0<=start<=end<=len(source)//2
   assert source[2*start:2*end].decode('utf-16-le')==f['original']
   assert all(isinstance(text,str)and utf16(text)is not None for text in f['replacements'])
   reason='incomplete-report'if not complete else'no-replacement-advisory'if not f['replacements']else'overlap-with-earlier-projection'if any(conflicts(previous,f)for previous in accepted)else None
   if reason:skipped.append({**f,'reason':reason})
   else:accepted.append(f)
 corrected=None
 if complete:
  corrected=source
  for f in sorted(accepted,key=lambda f:f['start'],reverse=True):
   start,end=f['start']-offset,f['end']-offset
   corrected=corrected[:2*start]+utf16(f['replacements'][0])+corrected[2*end:]
  corrected=corrected.decode('utf-16-le')
 shown=display(results)
 reconstructed={'complete':complete,'clean_report':complete and not shown,'flagged':bool(shown),'corrected':corrected,'changed':corrected is not None and corrected!=row['input'],'exact_expected':complete and corrected==row['expected']}
 assert all(outcome[name]==value for name,value in reconstructed.items()),(row['id'],reconstructed)
 assert outcome['displayed_findings']==shown
 assert outcome['projected_findings']==[{**f,'replacement_index':0}for f in accepted]
 assert outcome['skipped_findings']==skipped
 return {**reconstructed,'unsupported_only':bool(statuses)and all(s=='unsupported'for s in statuses)}
def declared(raw):
 locale=raw.get('locale','de-DE');assert locale in ('de-DE','de-AT','de-CH')
 return {'id':raw['id'],'kind':raw['kind'],'input':raw['input'],'expected':raw.get('expected',raw['input']),'locale':locale,'language':locale,'expected_model_status':raw.get('expected_model_status','success'if locale=='de-DE'else'unsupported'),**{k:raw[k]for k in ('category','pair_id')if k in raw}}
def metrics(rows,lane):
 return {
  'exact_error_ids':[r['id']for r in rows if r['kind']=='error'and r['verified'][lane]['exact_expected']],
  'changed_nonexact_error_ids':[r['id']for r in rows if r['kind']=='error'and r['verified'][lane]['changed']and not r['verified'][lane]['exact_expected']],
  'changed_clean_ids':[r['id']for r in rows if r['kind']=='clean'and r['verified'][lane]['changed']],
  'flagged_clean_ids':[r['id']for r in rows if r['kind']=='clean'and r['verified'][lane]['flagged']],
  'unsupported_only_ids':[r['id']for r in rows if r['verified'][lane]['unsupported_only']],
 }
def verify_report(path,corpus,build,expected_hash):
 report=json.loads(path.read_text());gold=[declared(raw)for raw in json.loads(corpus.read_text())]
 assert all(report[name]is True for name in ('completed','operational_passed','source_stable','status_contract_passed','live_native_provider'))
 assert report['cases_sha256']==sha(corpus)==expected_hash
 assert report['source_files']==report['source_files_after']=={**build['source_files'],'declared-corpus':expected_hash}
 assert report['runtime']['entrypoint']['sha256']==build['runtime']['entrypoint']['sha256']
 assert report['runtime']['executable']['sha256']==build['runtime']['executable']['sha256']
 assert report['runtime']['checks_per_case']==1 and report['runtime']['native_threads']==2
 assert report['declared_cases']==gold
 rows=report['cases'];assert len(rows)==len(gold)and len({r['id']for r in rows})==len(rows)
 for row,expected in zip(rows,gold,strict=True):
  assert all(row[k]==v for k,v in expected.items())
  assert set(row['outcomes'])==set(LANES)
  assert row['status_contract_passed']is True
  outcomes=row['outcomes'];det=outcomes['deterministic']['results'];model=outcomes['model_only']['results']
  assert outcomes['writing_only']['results']==[r for r in det if r['provider_id']=='german-writing']
  assert {r['provider_id']for r in det}=={'german-writing','german-spelling'}
  assert len(model)==1
  assert all(r['status']=='success'for r in det)
  assert model[0]['status']==expected['expected_model_status']
  assert row['expected_statuses']=={**{r['provider_id']:'success'for r in det},model[0]['provider_id']:expected['expected_model_status']}
  accepted=display(det);merged=list(det);accepted_model=[]
  for result in model:
   keep=[]
   for f in result['findings']:
    if not any(conflicts(previous,f)for previous in accepted):keep.append(f);accepted.append(f)
   merged.append({**result,'findings':keep});accepted_model.extend(keep)
  assert outcomes['combined']['results']==merged
  assert row['accepted_model_findings']==accepted_model
  remaining=Counter(key(f)for f in accepted_model);suppressed=[]
  for f in display(model):
   if remaining[key(f)]:remaining[key(f)]-=1
   else:suppressed.append(f)
  assert row['suppressed_model_findings']==suppressed
  row['verified']={lane:reconstruct(row,outcomes[lane])for lane in LANES}
 for language in [None,*sorted({r['language']for r in rows})]:
  cohort=rows if language is None else[r for r in rows if r['language']==language]
  summary=report['summary']if language is None else report['summary']['by_language'][language]
  assert summary['case_count']==len(cohort)
  assert summary['error_count']==sum(r['kind']=='error'for r in cohort)
  assert summary['clean_count']==sum(r['kind']=='clean'for r in cohort)
  for lane in LANES:
   for name,ids in metrics(cohort,lane).items():
    assert summary['lanes'][lane][name]==ids
    assert summary['lanes'][lane][name[:-4]+'_count']==len(ids)
 return report,rows

def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ('baseline','final','baseline-build','final-build','panels','output'):p.add_argument('--'+name,type=Path,required=True)
 a=p.parse_args();assert not a.output.exists(),'Audit output must be fresh.'
 manifest=json.loads(a.panels.read_text());baseline_build=json.loads(a.baseline_build.read_text());final_build=json.loads(a.final_build.read_text())
 assert baseline_build['passed']and final_build['passed']
 output={'schema_version':1,'interpretation':'Independently reconstructed comparison of reused synthetic panels. These are regression results, not representative German accuracy. No durations are benchmark evidence.','panels':[],'passed':True,'checks':['frozen corpus and metadata-only syntax adapter identities','source and AOT build bindings','UTF-16 source finding ranges','first-replacement projection and skipped overlaps','deterministic/model merge reconstruction','provider status contracts including regional unsupported model','producer summary independently reconstructed from raw results','no previously exact correction lost','no newly changed or flagged clean input']}
 for panel in manifest['panels']:
  corpus=a.panels.parent/panel['run_file'];before_path=a.baseline/(panel['name']+'.json');after_path=a.final/(panel['name']+'.json')
  before,brows=verify_report(before_path,corpus,baseline_build,panel['run_sha256']);after,frows=verify_report(after_path,corpus,final_build,panel['run_sha256'])
  assert before['declared_cases']==after['declared_cases']
  for field in ('model','native_library_sha256','bundle_assets','vocabulary','projection_policy'):assert before[field]==after[field],field
  by_language={}
  for language in sorted({r['language']for r in brows}):
   b=[r for r in brows if r['language']==language];f=[r for r in frows if r['language']==language];lanes={}
   for lane in LANES:
    bm,fm=metrics(b,lane),metrics(f,lane)
    lost=sorted(set(bm['exact_error_ids'])-set(fm['exact_error_ids']));added=sorted(set(fm['exact_error_ids'])-set(bm['exact_error_ids']));new_changed=sorted(set(fm['changed_clean_ids'])-set(bm['changed_clean_ids']));new_flagged=sorted(set(fm['flagged_clean_ids'])-set(bm['flagged_clean_ids']))
    passed=not(lost or new_changed or new_flagged);output['passed']&=passed
    lanes[lane]={'baseline':{**bm,**{name[:-4]+'_count':len(ids)for name,ids in bm.items()}},'final':{**fm,**{name[:-4]+'_count':len(ids)for name,ids in fm.items()}},'lost_exact_ids':lost,'added_exact_ids':added,'new_changed_clean_ids':new_changed,'new_flagged_clean_ids':new_flagged,'passed':passed}
   by_language[language]={'cases':len(b),'errors':sum(r['kind']=='error'for r in b),'clean':sum(r['kind']=='clean'for r in b),'lanes':lanes}
  changes=[]
  for b,f in zip(brows,frows,strict=True):
   changed={lane:{'before':b['verified'][lane]['corrected'],'after':f['verified'][lane]['corrected']}for lane in LANES if b['verified'][lane]['corrected']!=f['verified'][lane]['corrected']}
   bspell=next(r for r in b['outcomes']['deterministic']['results']if r['provider_id']=='german-spelling');fspell=next(r for r in f['outcomes']['deterministic']['results']if r['provider_id']=='german-spelling')
   if changed or bspell!=fspell:changes.append({'id':b['id'],'input':b['input'],'expected':b['expected'],'projection_changes':changed,'spelling_before':bspell['findings'],'spelling_after':fspell['findings']})
  output['panels'].append({'name':panel['name'],'cases':len(brows),'baseline_sha256':sha(before_path),'final_sha256':sha(after_path),'corpus_sha256':panel['run_sha256'],'by_language':by_language,'changed_cases':changes})
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({'passed':output['passed'],'panels':len(output['panels']),'case_comparisons':sum(p['cases']for p in output['panels'])},indent=2))
 if not output['passed']:raise SystemExit(1)
if __name__=='__main__':main()
