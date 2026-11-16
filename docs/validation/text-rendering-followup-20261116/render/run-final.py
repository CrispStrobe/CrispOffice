from pathlib import Path
import datetime, hashlib, json, os, subprocess, time
base=Path('/workspace/scratch/51b89fd39d6a')
repo=base/'quds_office_suite'
editor=repo/'packages/quds_office_editor'
out=base/'text-toolchain/unicode-render'
sdk=base/'text-toolchain/flutter'
inputs=sorted((repo/'packages/quds_office_engine/lib').rglob('*.dart'))
inputs += [editor/'test/font_subset_render_test.dart',editor/'fonts/LiberationSans-Regular.ttf',repo/'pubspec.lock',repo/'pubspec.yaml',editor/'pubspec.yaml',repo/'packages/quds_office_engine/pubspec.yaml']
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def hashes():return {str(p.relative_to(repo)):digest(p) for p in inputs}
before=hashes()
start=datetime.datetime.now(datetime.timezone.utc).isoformat()
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()
commands=[('test',[str(sdk/'bin/flutter'),'test','--no-pub','--reporter','json','test/font_subset_render_test.dart','--dart-define=QUDS_SUBSET_RENDER_OUTPUT='+str(out)]),('analyze',[str(sdk/'bin/cache/dart-sdk/bin/dart'),'analyze','--fatal-infos','test/font_subset_render_test.dart']),('format',[str(sdk/'bin/cache/dart-sdk/bin/dart'),'format','--output=none','--set-exit-if-changed','test/font_subset_render_test.dart'])]
results=[]
for label,argv in commands:
 t=time.monotonic()
 with (out/('final-'+label+'.log')).open('wb') as log:
  proc=subprocess.run(argv,cwd=editor,stdout=log,stderr=subprocess.STDOUT,timeout=180)
 result={'name':label,'argv':argv,'cwd':str(editor),'exit_code':proc.returncode,'elapsed_seconds':time.monotonic()-t,'log':'final-'+label+'.log','log_sha256':digest(out/('final-'+label+'.log'))}
 results.append(result)
 print(json.dumps(result),flush=True)
after=hashes()
changed=[p for p in before if before[p]!=after[p]]
events=[]
for line in (out/'final-test.log').read_text().splitlines():
 try:events.append(json.loads(line))
 except ValueError:pass
visible={e['testID']:e for e in events if e.get('type')=='testDone' and not e.get('hidden',False)}
record={'started_utc':start,'observed_head_at_start':head,'commands':results,'test_summary':{'visible_outcomes':len(visible),'successes':sum(e['result']=='success' for e in visible.values()),'failures':sum(e['result']!='success' for e in visible.values()),'skips':sum(e['skipped'] for e in visible.values()),'done':next((e for e in reversed(events) if e.get('type')=='done'),None)},'input_count':len(before),'inputs_before':before,'inputs_after':after,'changed_inputs':changed,'scope':'Two native Flutter rendering regressions using synthetic Unicode aliases of bundled Liberation Sans Latin glyphs. Exact rasters compare PDF-reopened to directly generated identical Unicode subsets; outline bytes and advance widths are also checked against the independent source font. Cross-cmap bitmap parity is explicitly not asserted.','github_actions_used':False}
(out/'final-receipt.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps({'test_summary':record['test_summary'],'changed_inputs':changed,'input_count':len(before)}),flush=True)
raise SystemExit(0 if not changed and all(r['exit_code']==0 for r in results) else 1)
