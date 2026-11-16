from pathlib import Path
import argparse, collections, datetime, gzip, hashlib, json, re, subprocess, tarfile
parser=argparse.ArgumentParser(description='Verify archived proofing qualification evidence; does not rerun product tests.')
parser.add_argument('--repo', type=Path, required=True, help='Checkout containing the recovered evidence and Git history')
parser.add_argument('--output', type=Path, required=True, help='Destination JSON receipt')
args=parser.parse_args()
repo=args.repo.resolve()
p=repo/'docs/validation/proofing-20261116/continuation-hardening'
source='8b93e866b4661d19f4bbad4e1069c0a609441ebb'
head='95185d2f803215d768d440cbbc2ee74789574005'
issues=[]
checks=[]
def sha(x): return hashlib.sha256(x).hexdigest()
def readj(x): return json.loads(x.read_bytes())
def git(*args): return subprocess.check_output(['git','-C',str(repo),*args])
def check(label,actual,expected):
 ok=actual==expected
 checks.append({'check':label,'passed':ok})
 if not ok: issues.append({'check':label,'actual':actual,'expected':expected})
 return ok
def hashcheck(base,name,expected): return check(f'{base.relative_to(p)}/{name}: sha256',sha((base/name).read_bytes()),expected)
editor=readj(p/'editor/receipt.json'); engine=readj(p/'engine/receipt.json')
for folder,receipt in [('editor',editor),('engine',engine),('german',readj(p/'german/receipt.json'))]:
 for cmd in receipt.get('commands',[]):
  if cmd.get('log') and cmd.get('log_sha256'): hashcheck(p/folder,cmd['log'],cmd['log_sha256'])
  if cmd.get('events'):
   ev=cmd['events']; hashcheck(p/folder,ev['file'],ev['sha256'])
   events=[json.loads(l) for l in (p/folder/ev['file']).read_text().splitlines() if l.strip()]
   counts=collections.Counter('hidden' if e.get('hidden') else 'skipped' if e.get('skipped') else 'passed' if e['result']=='success' else 'failed' for e in events if e.get('type')=='testDone')
   for key in ('passed','failed','skipped','hidden'): check(f'{folder}/{ev["file"]}: {key}',counts[key],cmd['summary'][key])
   check(f'{folder}/{ev["file"]}: final done success',events[-1].get('success'),True)
  if folder in ('editor','engine'): check(f'{folder}/{cmd["label"]}: exit',cmd['exit_code'],0)
for name,expected in [('source_before',2049),('source_after',2049),('runtime_before',16),('runtime_after',16),('web_artifacts_before',0),('web_artifacts_after',117)]:
 spec=editor[name]; raw=(p/'editor'/spec['path']).read_bytes(); decoded=gzip.decompress(raw)
 hashcheck(p/'editor',spec['path'],spec['sha256'])
 check('editor/'+name+': uncompressed hash',sha(decoded),spec['uncompressed_sha256'])
 check('editor/'+name+': count',len(json.loads(decoded)),expected)
for name,expected in [('source_manifest',4291),('source_after_manifest',4291),('runtime_manifest',40),('runtime_after_manifest',40),('dependency_manifest',8097),('dependency_after_manifest',8097)]:
 spec=engine[name]; raw=(p/'engine'/spec['file']).read_bytes()
 hashcheck(p/'engine',spec['file'],spec['sha256'])
 check('engine/'+name+': count',len(json.loads(gzip.decompress(raw))),expected)
for folder,pairs in [('editor',['source','runtime']),('engine',['source','runtime','dependencies'])]:
 for item in pairs: check(f'{folder}/{item}: before equals after',(p/folder/(item+'-before.json.gz')).read_bytes(),(p/folder/(item+'-after.json.gz')).read_bytes())
for folder in ('editor','engine'):
 config=readj(p/folder/('workspace-before.package_config.json' if folder=='editor' else 'resolved-package-config.json'))
 check(folder+': resolved package count',len(config['packages']),108)
integ=readj(p/'editor/evidence-integrity.json')
hashcheck(p/'editor','receipt.json',integ['receipt_sha256'])
for name,entry in integ['files'].items():
 hashcheck(p/'editor',name,entry['sha256']); check('editor/'+name+': bytes',(p/'editor'/name).stat().st_size,entry['bytes'])
for entry in readj(p/'copied-evidence-integrity.json')['checks']: hashcheck(p,entry['file'],entry['sha256'])
for cmd in editor['commands']:
 if cmd.get('test_summary'):
  matches=re.findall(r'\+(\d+)(?:\s+~(\d+))?(?:\s+-(\d+))?: All tests passed!',(p/'editor'/cmd['log']).read_text())
  check('editor/'+cmd['label']+': log success count',int(matches[-1][0]) if matches else None,cmd['test_summary']['passed'])
 if 'analyze' in cmd['label']:
  check('editor/'+cmd['label']+': strict option','--fatal-infos' in cmd['argv'],True)
  check('editor/'+cmd['label']+': no issues','No issues found!' in (p/'editor'/cmd['log']).read_text(),True)
check('web build: successful marker','Built build/web' in (p/'editor/example-web-build.log').read_text(),True)
web=readj(p/'editor/summary.json')
wm=json.loads(gzip.decompress((p/'editor/web-artifacts-after.json.gz').read_bytes()))
check('web manifest: file count',len(wm),117)
check('web manifest: total bytes',sum(v['bytes'] for v in wm.values()),59826750)
check('exact tested tree',git('rev-parse',source+'^{tree}').decode().strip(),'834585ef6d66d995a633d6adf8e45a05628fe039')
changes=git('diff','--name-only',source,head).decode().splitlines()
expected_docs={'docs/PROOFING.md','packages/quds_office_editor/CHANGELOG.md','packages/quds_office_engine/CHANGELOG.md'}
unexpected=[f for f in changes if not(f.startswith('docs/validation/proofing-20261116/continuation-hardening/') or f in expected_docs)]
check('only documentation/evidence changes after frozen source',unexpected,[])
source_verifications={}
frozen_blobs={}
for entry in git('ls-tree','-r','-z',source).split(b'\0'):
 if entry:
  meta,file=entry.split(b'\t',1); frozen_blobs[file.decode()]=meta.decode().split()[2]
for folder in ('editor','engine'):
 manifest=json.loads(gzip.decompress((p/folder/'source-after.json.gz').read_bytes()))
 mismatches=[]; changed_docs=[]; retained_generated=[]
 for path,digest in manifest.items():
  local=repo/path
  if local.is_file():
   data=local.read_bytes()
   git_blob=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
   if sha(data)==digest and git_blob==frozen_blobs.get(path): continue
  if path=='pubspec.lock' and folder=='editor':
   actual=sha((p/'editor/workspace-after.pubspec.lock').read_bytes())
   if actual!=digest: mismatches.append(path)
   else: retained_generated.append(path)
   continue
  actual=sha(git('show',source+':'+path))
  if actual!=digest: mismatches.append(path)
  else: changed_docs.append(path)
 check(folder+': source manifest matches frozen commit',mismatches,[])
 source_verifications[folder]={'entries':len(manifest),'source_mismatches':mismatches,'post_validation_documentation_differences':changed_docs,'retained_generated_inputs_checked_against_saved_copy':retained_generated}
# Every preexisting handoff evidence blob is still identical at recovered final head.
def tree(commit,path):
 raw=git('ls-tree','-r','-z',commit,'--',path)
 out={}
 for entry in raw.split(b'\0'):
  if not entry: continue
  meta,file=entry.split(b'\t',1); out[file.decode()]=meta.decode().split()[2]
 return out
old=tree('9d9051859f0aa0fdf43dec938d31642ea3c67133','docs/validation/proofing-20261116')
now=tree(head,'docs/validation/proofing-20261116')
check('handoff evidence path count',len(old),228)
check('handoff evidence blobs unchanged',[f for f,h in old.items() if now.get(f)!=h],[])
archives=[]
for f in sorted(p.rglob('*.gz')):
 raw=f.read_bytes(); decoded=gzip.decompress(raw)
 entry={'path':str(f.relative_to(p)),'bytes':len(raw),'sha256':sha(raw),'decoded_bytes':len(decoded)}
 if f.name.endswith('.tar.gz'):
  with tarfile.open(f,'r:gz') as archive:
   members=[m for m in archive.getmembers() if m.isfile()]
   for m in members: archive.extractfile(m).read()
   entry['tar_files_read']=len(members)
 elif f.name.endswith('.json.gz'):
  entry['json_entries']=len(json.loads(decoded))
 archives.append(entry)
check('all compressed evidence decoded',len(archives)>0,True)
missing=[]
for f in p.rglob('*.md'):
 for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)',f.read_text()):
  if re.match(r'[a-zA-Z][a-zA-Z0-9+.-]*:',target) or target.startswith('#'): continue
  dest=(f.parent/target.split('#',1)[0]).resolve()
  if not dest.exists(): missing.append({'from':str(f.relative_to(p)),'target':target})
check('report relative links resolve',missing,[])
report={'checked_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'verifier_sha256':sha(Path(__file__).read_bytes()),'kind':'Independent recovered evidence integrity audit; no product tests or builds rerun','recovered_commit':head,'tested_source':source,'passed':not issues,'checks_count':len(checks),'failed_checks':issues,'checks':checks,'source_manifests':source_verifications,'post_source_changed_paths_count':len(changes),'post_source_non_evidence_docs':sorted(expected_docs),'handoff_evidence_files_unchanged':len(old),'compressed_evidence_files':archives,'test_counts':{'editor':347,'ime':1,'layout_export':295,'incoming':503,'harper_provider':8,'harper_native_passed':3,'harper_native_skipped':1},'web_manifest':{'files':len(wm),'bytes':sum(v['bytes'] for v in wm.values()),'note':'Recorded output manifest integrity verified; original build output bytes not present in checkout.'},'no_github_actions_queried':True,'no_dart_flutter_runs':True,'receipt_sha256':{'editor':sha((p/'editor/receipt.json').read_bytes()),'engine':sha((p/'engine/receipt.json').read_bytes())}}
out=args.output.resolve(); out.parent.mkdir(parents=True,exist_ok=True); out.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k not in ('checks','compressed_evidence_files')},indent=2))
raise SystemExit(0 if report['passed'] else 1)
