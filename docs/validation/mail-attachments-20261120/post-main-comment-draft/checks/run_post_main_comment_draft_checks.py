#!/usr/bin/env python3
import fcntl,gzip,hashlib,importlib.util,json,os,shutil,subprocess,time
from pathlib import Path
ROOT=Path('/workspace/scratch/75dc9d25dfaf');REPO=ROOT/'quds_office_suite'
OUT=ROOT/'final-validation/post-main-comment-draft/checks'
EXPECTED='6184051c75d882cac53be3c1a9384e4556588ad1'
TARGET='packages/quds_office_editor/example/test/studio_comment_draft_proofing_test.dart'
RUNNER=REPO/'docs/validation/zotero-research-materials-20261120/run_validation.py'
if hashlib.sha256(RUNNER.read_bytes()).hexdigest()!='4d01ed59729abaa64e3ab643e8ebcb2f7136dd2d9f02cc4b07b81a06fbb919bf':raise RuntimeError('Primary runner changed')
spec=importlib.util.spec_from_file_location('comment_draft_primary',RUNNER);h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
h.COHORTS={'post-main-comment-draft':{'package':'packages/quds_office_editor/example','patterns':[],'additional':['studio_comment_draft_proofing_test.dart'],'runner':'flutter'}}
SDK=Path(os.environ['FLUTTER_ROOT']);DART=SDK/'bin/cache/dart-sdk/bin/dart'
if OUT.exists():raise RuntimeError('Refuse overwrite evidence')
OUT.mkdir(parents=True)
shutil.copyfile(__file__,OUT/'run_post_main_comment_draft_checks.py')
with (SDK.parent/'qualified-local-validation.lock').open('a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 head=h.git_head(REPO)
 if head!=EXPECTED:raise RuntimeError('Unexpected HEAD '+head)
 selected=h.select_tests(REPO,'post-main-comment-draft')
 inputs=h.Inputs(REPO,SDK,'post-main-comment-draft',selected)
 before=inputs.snapshot();match=h.source_matches_head(REPO,head,before['source'])
 if not match['matches']:raise RuntimeError('Uncommitted source '+str(match))
 (OUT/'inputs.json.gz').write_bytes(gzip.compress(h.canonical_json({'before':before,'reachable_packages':sorted(inputs.reachable)})+b'\n',mtime=0))
 steps=[]
 for name,args in [('format',[str(DART),'format','--output=none','--set-exit-if-changed',TARGET]),('analysis',[str(DART),'analyze','--fatal-infos','--fatal-warnings',TARGET])]:
  rec={'name':name,'command':args,'cwd':str(REPO),'started_at_utc':h.utc()}
  h.write_json(OUT/(name+'-command.json'),rec)
  start=time.monotonic()
  with (OUT/(name+'-stdout.log')).open('wb') as stdout,(OUT/(name+'-stderr.log')).open('wb') as stderr:
   process=subprocess.run(args,cwd=REPO,env=os.environ.copy(),stdout=stdout,stderr=stderr,timeout=600)
  rec.update(exit_code=process.returncode,elapsed_seconds=time.monotonic()-start,finished_at_utc=h.utc(),stdout=h.file_record(OUT/(name+'-stdout.log')),stderr=h.file_record(OUT/(name+'-stderr.log')))
  steps.append(rec);h.write_json(OUT/(name+'-result.json'),rec)
 after_inputs=h.Inputs(REPO,SDK,'post-main-comment-draft',h.select_tests(REPO,'post-main-comment-draft'));after=after_inputs.snapshot();end=h.git_head(REPO)
 matched_after=h.source_matches_head(REPO,end,after['source']);changes=h.changed_paths(before,after)
 guards={**{area+'_unchanged':not paths for area,paths in changes.items()},'source_matches_start_commit':match['matches'],'source_matches_finish_commit':matched_after['matches'],'all_checks_exit_zero':all(x['exit_code']==0 for x in steps),'expected_head_unchanged':head==end==EXPECTED}
 fingerprints={'before_sha256':{area:h.digest(x) for area,x in before.items()},'after_sha256':{area:h.digest(x) for area,x in after.items()},'changed_paths':changes,'source_matches_start':match,'source_matches_finish':matched_after}
 h.write_json(OUT/'input-check.json',fingerprints)
 receipt={'status':'passed' if all(guards.values()) else 'failed','source_head_at_start':head,'source_head_at_finish':end,'selected_file':TARGET,'steps':steps,'guards':guards,'fingerprints':fingerprints,'finished_at_utc':h.utc(),'source_file_count':len(before['source']),'no_github_ci_or_status_endpoints':True,'artifacts':{p.name:h.file_record(p) for p in [OUT/'inputs.json.gz',OUT/'input-check.json']}}
 h.write_json(OUT/'receipt.json',receipt)
 print(json.dumps({'status':receipt['status'],'guards':guards}))
 raise SystemExit(0 if all(guards.values()) else 1)
