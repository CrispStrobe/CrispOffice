#!/usr/bin/env python3
"""Exercise the independent reporter ledger against retained real streams and deliberate corruptions."""
import copy
import importlib.util
import json
from pathlib import Path
import tarfile

ROOT=Path(__file__).parent
spec=importlib.util.spec_from_file_location('independent_audit',ROOT/'audit_qualification.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
repo=Path('/workspace/scratch/e63c6a1344bc/quds_office_suite')
archive=repo/'docs/validation/office-main-integration-20261119/host-final/qualification-evidence.tar.xz'
readbacks=[]
with tarfile.open(archive) as bundle:
 for phase in ['main','node']:
  receipt=json.load(bundle.extractfile(phase+'/verification.json'))
  old_repo=Path(receipt['package_config']).parent.parent
  groups={g['name']:g for g in receipt['planned_groups']}
  for row in receipt['runs']:
   if row['name'] not in groups:continue
   group=groups[row['name']]
   data=bundle.extractfile(phase+'/'+row['log']).read()
   requested={module.repo_suite(name,old_repo,group['cwd']) for name in group['tests']}
   parsed=module.reparse_events(data,old_repo,group['cwd'],requested,group.get('platform','vm'))
   readbacks.append(dict(phase=phase,group=row['name'],accepted=parsed['valid'],
                        reconstructed_cases=parsed['visible_cases'],matches_saved_count=parsed['visible_cases']==row['passed'],
                        issues=parsed['issues']))
   if not(parsed['valid'] and parsed['visible_cases']==row['passed']):raise RuntimeError(readbacks[-1])
fixture=[
 {'type':'start','time':0,'protocolVersion':'0.1.1'},
 {'type':'suite','time':1,'suite':{'id':0,'platform':'vm','path':'test/example_test.dart'}},
 {'type':'allSuites','time':2,'count':1},
 {'type':'testStart','time':3,'test':{'id':1,'suiteID':0,'name':'loading test/example_test.dart','groupIDs':[],'metadata':{'skip':False}}},
 {'type':'testDone','time':4,'testID':1,'result':'success','skipped':False,'hidden':True},
 {'type':'group','time':5,'group':{'id':2,'suiteID':0,'parentID':None,'metadata':{'skip':False}}},
 {'type':'testStart','time':6,'test':{'id':3,'suiteID':0,'name':'one actual case','groupIDs':[2],'metadata':{'skip':False}}},
 {'type':'testDone','time':7,'testID':3,'result':'success','skipped':False,'hidden':False},
 {'type':'done','time':8,'success':True},
]
def parse(events):
 raw='\n'.join(json.dumps(x) for x in events).encode()
 return module.reparse_events(raw,Path('/repo'),'packages/a',{'packages/a/test/example_test.dart'},'vm')
assert parse(fixture)['valid']
mutants=[]
def add(name,edit):
 events=copy.deepcopy(fixture);edit(events)
 result=parse(events)
 mutants.append(dict(name=name,rejected=not result['valid'],issues=result['issues']))
 if result['valid']:raise RuntimeError('Invalid reporter stream accepted: '+name)
add('unfinished_case',lambda e:e.pop(7))
add('duplicate_completion',lambda e:e.insert(8,dict(e[7])))
add('missing_terminal',lambda e:e.pop())
add('failed_result',lambda e:e[7].update(result='error'))
add('skipped_result',lambda e:e[7].update(skipped=True))
add('unexpected_suite',lambda e:e[1]['suite'].update(path='test/another_test.dart'))
add('hidden_actual_case',lambda e:e[7].update(hidden=True))
add('layout_diagnostic',lambda e:e.insert(7,{'type':'print','time':6,'testID':3,'messageType':'print','message':'A RenderFlex overflowed by 12 pixels on the right.'}))
add('extra_post_terminal_event',lambda e:e.append({'type':'print','time':9,'testID':3,'messageType':'print','message':'late'}))
add('unknown_test_completion',lambda e:e[7].update(testID=999))
add('no_visible_cases',lambda e:e.__setitem__(slice(5,8),[]))
add('duplicate_visible_identity',lambda e:e.__setitem__(slice(8,8),[
 {'type':'testStart','time':7,'test':{'id':4,'suiteID':0,'name':'one actual case','groupIDs':[2],'metadata':{'skip':False}}},
 {'type':'testDone','time':7,'testID':4,'result':'success','skipped':False,'hidden':False}]))
raw='\n'.join(json.dumps(x) for x in fixture).encode()+b'\nnot-json'
malformed=module.reparse_events(raw,Path('/repo'),'packages/a',{'packages/a/test/example_test.dart'},'vm')
assert not malformed['valid']
mutants.append(dict(name='non_json_stdout',rejected=True,issues=malformed['issues']))
# Failed and skipped executions remain visible, but must not be called passes.
outcome_controls=[]
for label, completion, terminal, expected in [
 ('honest_failure', {'result':'failure','skipped':False}, False, {'executions':1,'passed':0,'failed':1,'skipped':0}),
 ('honest_skip', {'result':'success','skipped':True}, True, {'executions':1,'passed':0,'failed':0,'skipped':1}),
]:
 events=copy.deepcopy(fixture)
 events[7].update(completion);events[-1]['success']=terminal
 if label=='honest_failure':
  events.insert(7,{'type':'error','time':6,'testID':3,'error':'controlled assertion failure','stackTrace':'control','isFailure':True})
 result=parse(events)
 reported={key:value for key,value in expected.items() if key!='executions'}
 assert result['outcomes']==expected
 assert result['per_suite_outcomes']=={'packages/a/test/example_test.dart':reported}
 assert module.reported_outcomes_match(reported,result['outcomes'])
 assert not result['valid']
 outcome_controls.append(dict(name=label,accepted_as_qualification=False,reported_counts_match=True,counts=result['outcomes']))

# Recount the preserved failed run without pretending its live source still matches.
failed_path=repo.parent/'qualification-main'
failed_readback=None
if (failed_path/'verification.json').exists():
 receipt=json.loads((failed_path/'verification.json').read_text())
 if receipt.get('failed',0)>0:
  rows=[];all_cases=[];groups={g['name']:g for g in receipt['planned_groups']}
  for row in receipt['runs']:
   if row['name'] not in groups:continue
   group=groups[row['name']];raw=(failed_path/row['log']).read_bytes()
   assert module.sha(raw)==row['log_sha256']
   requested={module.repo_suite(name,repo,group['cwd']) for name in group['tests']}
   result=module.reparse_events(raw,repo,group['cwd'],requested,group.get('platform','vm'))
   saved_suite={module.repo_suite(path,repo,group['cwd']):counts for path,counts in row['per_suite'].items()}
   assert module.reported_outcomes_match(row,result['outcomes'])
   assert saved_suite==result['per_suite_outcomes']
   assert row['reporter_error_count']==len(result['error_events'])
   rows.append(dict(name=row['name'],counts=result['outcomes'],reported_counts_match=True,
                    raw_acceptance=result['valid'],log_sha256=row['log_sha256']))
   all_cases.extend(result['cases'])
  combined=module.outcome_counts(all_cases)
  assert module.reported_outcomes_match(receipt,combined)
  failed_readback=dict(source_commit=receipt['source_commit'],scope='Raw outcomes only; current live source is intentionally not requalified',
                       counts=combined,reported_counts_match=True,groups=rows,
                       receipt_sha256=module.sha((failed_path/'verification.json').read_bytes()))
  (ROOT/'first-attempt-outcome-recount.json').write_text(json.dumps(failed_readback,indent=2)+'\n')

report=dict(accepted=True,scope='Auditor controls only; zero product executions contributed',
            retained_streams=len(readbacks),retained_visible_events=sum(r['reconstructed_cases'] for r in readbacks),
            controls=len(mutants)+1+len(outcome_controls),valid_control=True,invalid_streams_rejected=mutants,
            outcome_accounting_controls=outcome_controls,failed_attempt_raw_recount=failed_readback,historical_reparses=readbacks,
            auditor_sha256=module.sha((ROOT/'audit_qualification.py').read_bytes()))
(ROOT/'auditor-controls.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['accepted','retained_streams','retained_visible_events','controls']}))
