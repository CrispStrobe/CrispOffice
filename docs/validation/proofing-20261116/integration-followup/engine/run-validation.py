#!/usr/bin/env python3
"""Source-bound engine validation in an isolated pure-Dart dependency harness.

This does not claim Flutter workspace resolution, editor execution, browser
acceptance, or a new native/WebAssembly Harper build. No Actions are used.
"""
from pathlib import Path
from datetime import datetime, timezone
import gzip, hashlib, json, os, platform, shutil, subprocess, sys, time

ROOT = Path(__file__).resolve().parents[2]
REPO = ROOT / 'quds_office_suite'
ENGINE = REPO / 'packages/quds_office_engine'
HARPER = REPO / 'packages/quds_proofing_harper'
ENV = ROOT / 'runtime/engine-env'
OUT = Path(__file__).resolve().parent
DART = ROOT / 'runtime/dart-sdk/bin/dart'
SOURCE = '6f87a4e849f9dc172fea7a0e57d1d9072d99efe3'
TEST_RUNNER = ROOT / 'runtime/pub-cache/hosted/pub.dev/test-1.33.0/bin/test.dart'
TEST = [DART, '--packages='+str(REPO/'.dart_tool/package_config.json'), TEST_RUNNER]

def sha(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
 return h.hexdigest()

def now(): return datetime.now(timezone.utc).isoformat()

def git(*args): return subprocess.check_output(['git',*args],cwd=REPO).decode().strip()

def sources():
 return {p:sha(REPO/p) for p in git('ls-files').splitlines()
         if not p.startswith('docs/validation/') and (REPO/p).is_file()}

def runtime():
 paths=[DART,ROOT/'runtime/dart-sdk/bin/dartaotruntime',ENV/'pubspec.yaml',ENV/'pubspec.lock',ENV/'.dart_tool/package_config.json',REPO/'.dart_tool/package_config.json',Path(shutil.which('node')),Path(sys.executable),Path(__file__)]
 paths+=list((ROOT/'runtime/dart-sdk/bin/snapshots').glob('*'))
 paths+=list((ROOT/'runtime/dart-sdk/lib/_internal').glob('*.dill'))
 return {str(p):sha(p) for p in paths if p.is_file()}

def dependency_files():
 cache=ROOT/'runtime/pub-cache'
 return {str(p.relative_to(ROOT)):sha(p) for p in sorted(cache.rglob('*'))
         if p.is_file() and p.suffix in {'.dart','.yaml','.json'} and '.cache' not in p.parts}

def compressed(name,data):
 path=OUT/name
 path.write_bytes(gzip.compress((json.dumps(data,sort_keys=True,indent=2)+'\n').encode(),mtime=0))
 return {'file':name,'sha256':sha(path),'entries':len(data)}

assert git('rev-parse','HEAD')==SOURCE
assert not git('status','--porcelain','--untracked-files=no'), 'Tracked source changes before validation'
before=sources(); runtime_before=runtime(); dependencies_before=dependency_files()
record={'schema_version':1,'source_commit':SOURCE,'started_at_utc':now(),'scope':'Pure Dart engine, German spelling/writing rules, hyphenation/layout/export, incoming ODS/Zotero regressions, optional Harper provider contract; no editor/browser/native Harper acceptance claim.',
 'dependency_mode':'Isolated pure-Dart harness; package paths resolve to this source checkout. It does not resolve the Flutter root workspace. Exact harness, lock and package config retained.',
 'prior_attempt':'initial-harness-attempt.tar.gz preserves the first attempt; engine fixture tests were run from the harness directory, causing missing relative fixture/font paths. Final tests run from their package directories through the same locked test runner; source code unchanged.', 'github_actions':'Not queried or waited for.','platform':platform.platform(),'python':sys.version,
 'source_manifest':compressed('source-before.json.gz',before),'runtime_manifest':compressed('runtime-before.json.gz',runtime_before),
 'dependency_manifest':compressed('dependencies-before.json.gz',dependencies_before),'commands':[]}
for origin,name in [(ENV/'pubspec.yaml','harness-pubspec.yaml'),(ENV/'pubspec.lock','harness-pubspec.lock'),(ENV/'.dart_tool/package_config.json','harness-package-config.json'),(ROOT/'runtime/dart-runtime.json','dart-runtime.json')]:
 shutil.copyfile(origin,OUT/name)

def save(): (OUT/'receipt.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
save()

def run(label,cmd,cwd,timeout=420):
 start=time.monotonic(); begin=now(); log=OUT/(label+'.log')
 with log.open('w') as f:
  try:
   code=subprocess.run([str(c) for c in cmd],cwd=cwd,stdout=f,stderr=subprocess.STDOUT,timeout=timeout).returncode
  except subprocess.TimeoutExpired: code=124; f.write('\nValidation timeout reached.\n')
 entry={'label':label,'command':[str(c) for c in cmd],'working_directory':str(cwd),'started_at_utc':begin,'exit_code':code,'duration_seconds':round(time.monotonic()-start,3),'log':log.name,'log_sha256':sha(log)}
 record['commands'].append(entry);save();print(label,code,flush=True)
 if code: print('\n'.join(log.read_text().splitlines()[-40:]),flush=True)
 return code==0

success=True
try:
 for label,cmd,cwd in [
  ('dart-version',[DART,'--version'],ENV),
  ('node-version',['node','--version'],ENV),
  ('engine-analysis',[DART,'analyze','--fatal-infos','lib','test','tool'],ENGINE),
  ('german-tests',[*TEST,'test/proofing','--reporter=expanded'],ENGINE),
  ('hyphenation-regeneration',[sys.executable,'tool/proofing/generate_hyphenation.py'],ENGINE),
  ('dictionary-regeneration',[sys.executable,'tool/proofing/generate_german_lexicon.py','--check','--download'],ENGINE),
  ('compile-german-javascript',[DART,'compile','js','-O2',ENGINE/'tool/proofing/german_js_smoke.dart','-o',OUT/'german-proofing.js'],ENV),
  ('german-javascript',['node','-e','globalThis.self=globalThis; require(process.argv[1]);',OUT/'german-proofing.js'],ENV),
 ]:
  success=run(label,cmd,cwd) and success
 tests=['proofing_hyphenation','variable_line_breaker','bidi','word_layout','word_styles_layout','style_cascade','word_style_introduction','styleless_import_fidelity','word_referenced_styles_and_breaks','word_package_preservation','word_preserved_header','word_note_numbering','word_footnote_reference','word_note_script_break','word_table_tall_frame_layout','word_table_tall_toc_layout','word_table_nested_layout','word_small_caps','office_pdf_export','arabic_pdf_export','word_zotero_bibliography_layout']
 success=run('hyphenation-layout-export-tests',[*TEST,'--concurrency=4','--reporter=expanded',*[f'test/{n}_test.dart' for n in tests]],ENGINE) and success
 incoming=['ods_sheet_reader','word_comment_proofing_styles']+sorted(p.stem[:-5] for p in (ENGINE/'test').glob('*zotero*_test.dart'))
 success=run('incoming-ods-zotero-tests',[*TEST,'--concurrency=4','--reporter=expanded',*[f'test/{n}_test.dart' for n in incoming]],ENGINE) and success
 success=run('harper-analysis',[DART,'analyze','--fatal-infos','lib','test'],HARPER) and success
 success=run('harper-provider-tests',[*TEST,'test/harper_provider_test.dart','--reporter=expanded'],HARPER) and success
 success=run('harper-native-guards',[*TEST,'test/harper_native_test.dart','--reporter=expanded'],HARPER) and success
 js=OUT/'german-proofing.js'
 if js.exists(): record['compiled_javascript_sha256']=sha(js)
finally:
 after=sources(); runtime_after=runtime(); deps_after=dependency_files()
 record.update({'source_unchanged':before==after,'runtime_unchanged':runtime_before==runtime_after,'dependencies_unchanged':dependencies_before==deps_after,'git_tracked_status':git('status','--porcelain','--untracked-files=no'),'finished_at_utc':now(), 'passed':success and before==after and runtime_before==runtime_after and dependencies_before==deps_after})
 record['source_after_manifest']=compressed('source-after.json.gz',after)
 record['runtime_after_manifest']=compressed('runtime-after.json.gz',runtime_after)
 record['dependency_after_manifest']=compressed('dependencies-after.json.gz',deps_after)
 if before!=after: record['changed_source_paths']=[p for p in sorted(before.keys()|after.keys()) if before.get(p)!=after.get(p)]
 save()
 print(json.dumps({k:record[k] for k in ['passed','source_unchanged','runtime_unchanged','dependencies_unchanged','source_manifest']}),flush=True)
sys.exit(0 if record['passed'] else 1)
