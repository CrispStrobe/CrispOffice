#!/usr/bin/env python3
"""Compare exact baseline/candidate grammar on one independent source-bound corpus."""
import argparse
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

root=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repository',type=Path,default=root.parent/'quds_office_suite')
parser.add_argument('--dart',default=shutil.which('dart'))
parser.add_argument('--node',default=shutil.which('node'))
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
repo=args.repository.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
if not args.dart or not args.node:parser.error('Supply Dart and Node')
def sha(p):return hashlib.file_digest(p.open('rb'),'sha256').hexdigest()
def git(*cmd):return subprocess.check_output(['git',*cmd],cwd=repo,text=True).strip()
source_paths=['packages/quds_office_engine/lib/src/proofing/'+n for n in ['german_writing_rules.dart','german_grammar.dart','office_proofing.dart','proofing_text_ranges.dart']]
def snapshot():return {p:sha(repo/p) for p in source_paths}
dirty=git('diff','--name-only','HEAD','--',*source_paths)
if dirty:raise RuntimeError('Commit source before final independent qualification: '+dirty)
before=snapshot();head=git('rev-parse','HEAD');records=[]
for path,expected in before.items():
    committed=subprocess.check_output(['git','show',head+':'+path],cwd=repo)
    if hashlib.sha256(committed).hexdigest()!=expected:
        raise RuntimeError('Source is not identical to recorded commit: '+path)
def run(name,command):
    started=time.monotonic()
    result=subprocess.run(command,cwd=repo,text=True,capture_output=True,timeout=300)
    (out/(name+'.stdout.log')).write_text(result.stdout)
    (out/(name+'.stderr.log')).write_text(result.stderr)
    record={'name':name,'command':command,'exit_code':result.returncode,'elapsed_seconds':time.monotonic()-started,
      'stdout_sha256':sha(out/(name+'.stdout.log')),'stderr_sha256':sha(out/(name+'.stderr.log'))}
    records.append(record)
    print(name+': '+str(result.returncode),flush=True)
    return result

positive=json.loads((root/'positive_german_review_cases.json').read_text())
negative=[]
for name in ['valid_german_review_cases','adversarial-valid-german','adversarial-valid-german-2','adversarial-valid-german-3','adversarial-valid-german-4','adversarial-valid-german-5']:
    negative.extend(json.loads((root/(name+'.json')).read_text()))
(out/'positive-cases.json').write_text(json.dumps(positive,ensure_ascii=False,indent=2)+'\n')
(out/'positive-text.json').write_text(json.dumps([x['text'] for x in positive],ensure_ascii=False,indent=2)+'\n')
(out/'negative-text.json').write_text(json.dumps(negative,ensure_ascii=False,indent=2)+'\n')
started=datetime.now(timezone.utc).isoformat();errors=[]
try:
    result=run('prepare-baseline',[sys.executable,str(root/'prepare_baseline.py'),'--repository',str(repo),'--output',str(out/'baseline')]);result.check_returncode()
    baseline_config=out/'baseline/baseline-package-config.json';candidate_config=repo/'.dart_tool/package_config.json'
    results={}
    for label,config in [('baseline',baseline_config),('candidate',candidate_config)]:
        results[label]={}
        for polarity,file in [('positive',out/'positive-text.json'),('negative',out/'negative-text.json')]:
            result=run(label+'-'+polarity,[args.dart,'--packages='+str(config),str(root/'grammar_probe.dart'),str(file)]);result.check_returncode()
            results[label][polarity]=json.loads(result.stdout)
    result=run('build-variant-suite',[sys.executable,str(root/'build_grammar_review_suite.py')]);result.check_returncode()
    result=run('candidate-vm-variants',[args.dart,'--packages='+str(candidate_config),str(root/'grammar_review_suite.dart')]);result.check_returncode()
    vm=json.loads(result.stdout)
    result=run('compile-variants',[args.dart,'compile','js','--packages='+str(candidate_config),'-O2',str(root/'grammar_review_suite.dart'),'-o',str(out/'grammar-review.js')]);result.check_returncode()
    result=run('candidate-node-variants',[args.node,'-e','globalThis.self=globalThis; require(process.argv[1]);',str(out/'grammar-review.js')]);result.check_returncode()
    node=json.loads(result.stdout)
    comparison={}
    for label,items in results.items():
        rows=items['positive'];valid=items['negative']
        assert len(rows)==len(positive) and len(valid)==len(negative)
        matched=[]
        for expected,row in zip(positive,rows):
            exact=row['status']=='success' and row['text']==expected['text'] and len(row['findings'])==1
            if exact:
                f=row['findings'][0];exact=(f['rule']==expected['rule'] and f['text']==expected['original'] and f['replacements']==[expected['replacement']])
            matched.append(exact)
        all_success=all(r['status']=='success' for r in rows+valid)
        if not all_success:errors.append(label+' had non-success provider status')
        comparison[label]={'positive_sentences':len(rows),'positive_detected':sum(r['status']=='success' and bool(r['findings']) for r in rows),'positive_exact_corrections':sum(matched),
          'negative_sentences':len(valid),'negative_with_findings':sum(r['status']=='success' and bool(r['findings']) for r in valid),
          'all_provider_statuses_success':all_success,'missed_or_nonexact_cases':[expected['text'] for expected,match in zip(positive,matched) if not match],
          'negative_findings':[r for r in valid if r['findings']]}
    if comparison['candidate']['positive_exact_corrections']!=len(positive):errors.append('Candidate misses a targeted correction')
    if comparison['candidate']['negative_with_findings']:errors.append('Candidate reports findings on valid controls')
except Exception as error:
    errors.append(repr(error));comparison=locals().get('comparison',{});vm=locals().get('vm',None);node=locals().get('node',None)
after=snapshot()
if after!=before:errors.append('Candidate source changed during review')
receipt={'schema_version':1,'status':'passed' if not errors else 'failed','started_at_utc':started,'finished_at_utc':datetime.now(timezone.utc).isoformat(),
  'baseline_commit':'62563c61f02ee44504776d9e7d26557f9bae490a','candidate_commit':head,'source_sha256':before,'source_sha256_after':after,'source_unchanged':before==after,
  'corpus_sha256':{name:sha(out/name) for name in ['positive-cases.json','positive-text.json','negative-text.json']},
  'runtime_sha256':{'dart':sha(Path(args.dart).resolve()),'node':sha(Path(args.node).resolve()),'workspace_lock':sha(repo/'pubspec.lock')},
  'comparison':comparison,'vm_variants':vm,'node_variants':node,'commands':records,'errors':errors,
  'limitations':['This is a deliberately targeted first-party regression corpus, not population precision/recall or general German accuracy.','Both baseline and candidate comparisons use the identical de-DE texts and successful provider status. de-AT/de-CH and source/protection variants are separate candidate checks.','Original review false positives and unsupported helfst fixture are preserved in earlier review logs; final positive uses actual wrong-person hilfst.','An unflagged construction outside this finite grammar is not a correctness guarantee.']}
(out/'receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':receipt['status'],'comparison':comparison,'output':str(out)},ensure_ascii=False),flush=True)
raise SystemExit(0 if receipt['status']=='passed' else 1)
