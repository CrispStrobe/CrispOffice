#!/usr/bin/env python3
"""Strict targeted analysis with inherited complete source/dependency input fingerprints."""
import fcntl,gzip,hashlib,importlib.util,json,os,shutil,signal,subprocess,time
from pathlib import Path
ROOT=Path('/workspace/scratch/75dc9d25dfaf')
REPO=ROOT/'quds_office_suite'
OUT=ROOT/'final-validation/engine-spacy-analysis'
SDK=Path(os.environ['FLUTTER_ROOT'])
RUNNER=ROOT/'run_pure_dart_validation.py'
spec=importlib.util.spec_from_file_location('qualified_runner',RUNNER)
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
plan=json.loads((ROOT/'final-validation/pure-dart-plan.json').read_text())
targets=plan['analysis_targets']
if OUT.exists():raise RuntimeError('Refuse overwrite existing analysis evidence')
OUT.mkdir(parents=True)
shutil.copyfile(__file__,OUT/'run_engine_spacy_analysis.py')
lock=(SDK.parent/'qualified-pure-dart-validation.lock').open('a')
fcntl.flock(lock,fcntl.LOCK_EX)
try:
 head=h.git_head(REPO)
 selected=h.select_tests(REPO,'engine-rendering')
 inputs=h.Inputs(REPO,SDK,'engine-rendering',selected)
 spacy_inputs=h.Inputs(REPO,SDK,'spacy-package',h.select_tests(REPO,'spacy-package'))
 before=inputs.snapshot()
 before['dependencies'].update(spacy_inputs.dependencies())
 matched=h.source_matches_head(REPO,head,before['source'])
 if not matched['matches']:
  h.write_json(OUT/'refused-source.json',matched)
  raise RuntimeError('Inputs are not committed')
 command=[str(SDK/'bin/cache/dart-sdk/bin/dart'),'analyze','--fatal-infos','--fatal-warnings',*targets]
 receipt={'status':'running','command':command,'cwd':str(REPO),'source_head_at_start':head,'targets':targets,'started_at_utc':h.utc(),'watchdog_seconds':1200,'validation_runner':{'path':str(RUNNER),**h.file_record(RUNNER)},'no_github_ci_or_status_endpoints':True}
 h.write_json(OUT/'receipt.json',receipt)
 (OUT/'inputs.json.gz').write_bytes(gzip.compress(h.canonical_json({'before':before,'reachable_packages':sorted(inputs.reachable|spacy_inputs.reachable)})+b'\n',mtime=0))
 start=time.monotonic();timed_out=False
 with (OUT/'stdout.log').open('wb') as stdout,(OUT/'stderr.log').open('wb') as stderr:
  proc=subprocess.Popen(command,cwd=REPO,env=os.environ.copy(),stdout=stdout,stderr=stderr,start_new_session=True)
  try:code=proc.wait(timeout=1200)
  except subprocess.TimeoutExpired:
   timed_out=True;os.killpg(proc.pid,signal.SIGTERM)
   try:code=proc.wait(timeout=5)
   except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);code=proc.wait()
 after_inputs=h.Inputs(REPO,SDK,'engine-rendering',h.select_tests(REPO,'engine-rendering'))
 after=after_inputs.snapshot()
 after_spacy=h.Inputs(REPO,SDK,'spacy-package',h.select_tests(REPO,'spacy-package'))
 after['dependencies'].update(after_spacy.dependencies())
 end=h.git_head(REPO)
 matched_after=h.source_matches_head(REPO,end,after['source'])
 changes=h.changed_paths(before,after)
 checks={**{area+'_unchanged':not paths for area,paths in changes.items()},'source_matches_start_commit':matched['matches'],'source_matches_finish_commit':matched_after['matches'],'strict_analyzer_exit_zero':code==0,'no_timeout':not timed_out}
 fingerprint={'before_sha256':{area:h.digest(records) for area,records in before.items()},'after_sha256':{area:h.digest(records) for area,records in after.items()},'changed_paths':changes,'source_matches_start':matched,'source_matches_finish':matched_after}
 h.write_json(OUT/'input-check.json',fingerprint)
 receipt.update(status='passed' if all(checks.values()) else 'failed',finished_at_utc=h.utc(),elapsed_seconds=time.monotonic()-start,source_head_at_finish=end,exit_code=code,timed_out=timed_out,guards=checks,fingerprints=fingerprint,source_file_count=len(before['source']),artifacts={p.name:h.file_record(p) for p in [OUT/'stdout.log',OUT/'stderr.log',OUT/'inputs.json.gz',OUT/'input-check.json']})
 h.write_json(OUT/'receipt.json',receipt)
 print(json.dumps({'status':receipt['status'],'exit_code':code,'guards':checks}),flush=True)
 raise SystemExit(0 if all(checks.values()) else 1)
finally:
 fcntl.flock(lock,fcntl.LOCK_UN);lock.close()
