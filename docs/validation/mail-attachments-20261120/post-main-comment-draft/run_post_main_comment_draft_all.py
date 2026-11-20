#!/usr/bin/env python3
import hashlib,json,os,shutil,subprocess
from pathlib import Path
ROOT=Path('/workspace/scratch/75dc9d25dfaf');REPO=ROOT/'quds_office_suite'
OUT=ROOT/'final-validation/post-main-comment-draft'
EXPECTED='6184051c75d882cac53be3c1a9384e4556588ad1'
if OUT.exists():raise RuntimeError('Refuse overwrite evidence')
OUT.mkdir(parents=True)
adapter=ROOT/'run_post_main_comment_draft.py'
shutil.copyfile(adapter,OUT/adapter.name)
shutil.copyfile(__file__,OUT/Path(__file__).name)
args=['python',str(adapter),'post-main-comment-draft','--repo',str(REPO),'--output',str(OUT/'tests'),'--expected-head',EXPECTED]
for name,argv in [('tests',args),('checks',['python',str(ROOT/'run_post_main_comment_draft_checks.py')])]:
 print(json.dumps({'started':name,'argv':argv}),flush=True)
 with (OUT/(name+'-console.log')).open('wb') as log:
  proc=subprocess.run(argv,cwd=ROOT,env=os.environ.copy(),stdout=log,stderr=subprocess.STDOUT)
 print(json.dumps({'finished':name,'exit_code':proc.returncode}),flush=True)
 if proc.returncode:raise RuntimeError(name+' failed')
test=json.loads((OUT/'tests/receipt.json').read_text());checks=json.loads((OUT/'checks/receipt.json').read_text())
summary={'status':'passed' if test['status']==checks['status']=='passed' else 'failed','source_head':EXPECTED,'source_tree':'b5b9ffdf6f500a9047cd4d01f3aa6c1bf8e91190','tests':{k:test['tests'][k] for k in ['passed','failed','skipped','suite_count']},'test_receipt_sha256':hashlib.sha256((OUT/'tests/receipt.json').read_bytes()).hexdigest(),'checks_receipt_sha256':hashlib.sha256((OUT/'checks/receipt.json').read_bytes()).hexdigest(),'checks':['Exact-file format check','Exact-file strict analysis with fatal infos and warnings'],'test_guards':test['guards'],'checks_guards':checks['guards'],'source_delta':'Seven incoming lines in studio_comment_draft_proofing_test.dart handling the existing language-download modal; production/configuration unchanged from qualified58c6962.'}
(OUT/'receipt.json').write_text(json.dumps(summary,indent=2,sort_keys=True)+'\n')
print(json.dumps(summary),flush=True)
