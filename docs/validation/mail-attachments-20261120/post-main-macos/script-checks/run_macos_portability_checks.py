#!/usr/bin/env python3
"""Linux-only syntax and extracted Bash control-flow checks; no macOS build/signing."""
import hashlib,json,os,re,shlex,shutil,subprocess
from pathlib import Path
from datetime import datetime,timezone
ROOT=Path('/workspace/scratch/75dc9d25dfaf');REPO=ROOT/'quds_office_suite'
OUT=ROOT/'final-validation/macos-portability-refresh/script-checks'
EXPECTED='f8f36eb87b051a0b26ee68747dfd24c4717eaec1'
BASE='6184051c75d882cac53be3c1a9384e4556588ad1'
SCRIPT='packages/quds_office_editor/example/tool/build_macos_app.sh'
DART='packages/quds_proofing_spacy/lib/src/distribution.dart'
DOC='docs/release/macos-signing.md'
WORKFLOW='.github/workflows/macos-app-weekly.yml'
if OUT.exists():raise RuntimeError('Refuse overwrite evidence')
OUT.mkdir(parents=True)
shutil.copyfile(__file__,OUT/'run_macos_portability_checks.py')
def now():return datetime.now(timezone.utc).isoformat()
def record(p):
 b=p.read_bytes();return {'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest(),'git_blob_sha1':hashlib.sha1(f'blob {len(b)}\0'.encode()+b).hexdigest()}
def git(*args):return subprocess.check_output(['git',*args],cwd=REPO)
def head():return git('rev-parse','HEAD').decode().strip()
def write(p,d):p.write_text(json.dumps(d,indent=2,sort_keys=True)+'\n')
if head()!=EXPECTED:raise RuntimeError('Unexpected source '+head())
inputs={p:record(REPO/p) for p in [SCRIPT,DART,DOC,WORKFLOW]}
write(OUT/'inputs-before.json',inputs)
source=(REPO/SCRIPT).read_text()
old_dart=git('show',f'{BASE}:{DART}').decode();new_dart=(REPO/DART).read_text()
def no_doc_comments(s):return ''.join(x for x in s.splitlines(keepends=True) if not x.lstrip().startswith('///'))
comment_only=no_doc_comments(old_dart)==no_doc_comments(new_dart)
patch=git('diff','--unified=0',BASE,EXPECTED,'--',DART).decode()
changed=[x[1:] for x in patch.splitlines() if x[:1] in ('+','-') and not x.startswith(('+++','---'))]
all_changed_doc=bool(changed) and all(x.lstrip().startswith('///') for x in changed)
(OUT/'distribution-comment-only.diff').write_text(patch)
syntax_command=['bash','-n',str(REPO/SCRIPT)]
with (OUT/'syntax-stdout.log').open('wb') as stdout,(OUT/'syntax-stderr.log').open('wb') as stderr:
 syntax=subprocess.run(syntax_command,cwd=REPO,stdout=stdout,stderr=stderr)
# Execute the changed blocks verbatim, surrounded only by a synthetic fixture
# environment and stubs for external code-signing/code-digest operations.
a=source.index('if [[ "${QUDS_SKIP_SPACY:-0}" != 1 && "$REBUILD_SPACY" != 1 ]]; then')
b=source.index('\nlog "Sign ($SIGN_MODE)"',a)
pre=source[a:b]
c=source.index('for library in "${LIBRARIES[@]}"; do',b)
d=source.index('\ndone',c)+len('\ndone')
loop=source[c:d]
e=source.index('if [[ "${QUDS_SKIP_SPACY:-0}" != 1 ]]; then',d)
f=source.index('\ncodesign "${SIGN_ARGS[@]}" --entitlements',e)
post=source[e:f]
for name,body in [('pre-sign.sh',pre),('library-signing.sh',loop),('post-sign.sh',post)]:
 (OUT/name).write_text(body+'\n')
pins=dict(re.findall(r'^(SPACY_PIN_[A-Z0-9_]+)=([^\s]+)$',source,re.M))
code=pins['SPACY_PIN_CODE_SHA256'];unsigned=pins['SPACY_PIN_UNSIGNED_SHA256']
fixtures=[
 {'name':'adhoc-pinned-bytes-preserved','mode':'adhoc','rebuild':'0','exit':0,'note':'qualified','preserve':True},
 {'name':'release-normalized-crosscheck','mode':'developer-id','rebuild':'0','exit':0,'note':'qualified code'},
 {'name':'release-older-strip-code-gate','mode':'developer-id','rebuild':'0','before_unsigned':'older-tool-output','after_unsigned':'different-older-tool-output','exit':0,'note':'qualified code'},
 {'name':'release-code-drift-rejected','mode':'developer-id','rebuild':'0','before_unsigned':'older-tool-output','after_code':'0'*64,'exit':1,'error':'changed while signing'},
 {'name':'normalized-strip-drift-rejected','mode':'developer-id','rebuild':'0','after_unsigned':'mismatched-normalized-output','exit':1,'error':'changed while signing'},
 {'name':'adhoc-rebuild-signed-unqualified','mode':'adhoc','rebuild':'1','exit':0,'note':'UNQUALIFIED rebuild'},
 {'name':'adhoc-invalid-signature-rejected','mode':'adhoc','rebuild':'0','verify_exit':'7','exit':7,'preserve':True},
 {'name':'pinned-input-code-drift-rejected','mode':'adhoc','rebuild':'0','before_code':'0'*64,'exit':1,'error':'unexpected code digest','preserve':True},
]
rows=[]
for fixture in fixtures:
 folder=OUT/'cases'/fixture['name'];folder.mkdir(parents=True)
 frameworks=folder/'Frameworks';frameworks.mkdir();resources=folder/'Resources';resources.mkdir()
 spacy=frameworks/'libcrispembed-spacy.dylib';other=frameworks/'unrelated.dylib'
 spacy.write_bytes(b'Synthetic non-executable spaCy fixture bytes.\n');other.write_bytes(b'Synthetic other library.\n')
 before_spacy=record(spacy);before_other=record(other)
 data={'FRAMEWORKS':str(frameworks),'RESOURCES':str(resources),'SIGN_MODE':fixture['mode'],'REBUILD_SPACY':fixture['rebuild'],'SPACY_PIN_SHA256':before_spacy['sha256'],'SPACY_PIN_CODE_SHA256':code,'SPACY_PIN_UNSIGNED_SHA256':unsigned,'TEST_CODE_BEFORE':fixture.get('before_code',code),'TEST_CODE_AFTER':fixture.get('after_code',code),'TEST_UNSIGNED_BEFORE':fixture.get('before_unsigned',unsigned),'TEST_UNSIGNED_AFTER':fixture.get('after_unsigned',unsigned),'TEST_VERIFY_EXIT':fixture.get('verify_exit','0'),'TEST_CALL_LOG':str(folder/'codesign-calls.log'),'TEST_NOTE':str(folder/'note.txt')}
 prefix='set -euo pipefail\n'+''.join(k+'='+shlex.quote(v)+'\n' for k,v in data.items())
 prefix+='''LIBRARIES=(libcrispembed-spacy.dylib unrelated.dylib)
SIGN_ARGS=(--force --sign SYNTHETIC-IDENTITY)
code_sha256() { if [[ "$TEST_PHASE" == before ]]; then printf '%s\\n' "$TEST_CODE_BEFORE"; else printf '%s\\n' "$TEST_CODE_AFTER"; fi; }
unsigned_sha256() { if [[ "$TEST_PHASE" == before ]]; then printf '%s\\n' "$TEST_UNSIGNED_BEFORE"; else printf '%s\\n' "$TEST_UNSIGNED_AFTER"; fi; }
codesign() {
  printf '%s\\n' "$*" >> "$TEST_CALL_LOG"
  if [[ "$1" == --verify ]]; then return "$TEST_VERIFY_EXIT"; fi
  printf 'SYNTHETIC SIGNATURE CHANGE\\n' >> "${@: -1}"
}
TEST_PHASE=before
'''
 script=prefix+pre+'\n'+loop+'\nTEST_PHASE=after\n'+post+'\nprintf \'%s\\n\' "$SPACY_NOTE" > "$TEST_NOTE"\n'
 program=folder/'execute-extracted-blocks.sh';program.write_text(script)
 with (folder/'stdout.log').open('wb') as stdout,(folder/'stderr.log').open('wb') as stderr:
  result=subprocess.run(['bash',str(program)],cwd=folder,stdout=stdout,stderr=stderr,timeout=30)
 note=(folder/'note.txt').read_text() if (folder/'note.txt').exists() else ''
 error=(folder/'stderr.log').read_text()
 calls=(folder/'codesign-calls.log').read_text().splitlines() if (folder/'codesign-calls.log').exists() else []
 checks={'expected_exit':result.returncode==fixture['exit']}
 if 'note' in fixture:checks['expected_note']=fixture['note'] in note
 if 'error' in fixture:checks['expected_refusal']=fixture['error'] in error
 if fixture.get('preserve'):checks['spacy_bytes_preserved']=before_spacy==record(spacy)
 if fixture['name']=='adhoc-pinned-bytes-preserved':
  checks['spacy_verify_only']=len([x for x in calls if x.startswith('--verify --strict ') and x.endswith('libcrispembed-spacy.dylib')])==1 and not any(x.startswith('--force ') and x.endswith('libcrispembed-spacy.dylib') for x in calls)
  checks['other_library_still_signed']=record(other)!=before_other and any(x.startswith('--force ') and x.endswith('unrelated.dylib') for x in calls)
 if fixture['name']=='adhoc-rebuild-signed-unqualified':checks['rebuild_really_signed']=before_spacy!=record(spacy) and any(x.startswith('--force ') and x.endswith('libcrispembed-spacy.dylib') for x in calls)
 row={'scenario':fixture,'exit_code':result.returncode,'checks':checks,'accepted':all(checks.values()),'codesign_calls':calls,'note':note,'before_spacy':before_spacy,'after_spacy':record(spacy),'before_other':before_other,'after_other':record(other),'artifacts':{p.name:record(p) for p in folder.iterdir() if p.is_file()}}
 write(folder/'receipt.json',row);rows.append(row)
after={p:record(REPO/p) for p in inputs};write(OUT/'inputs-after.json',after)
checks={'bash_syntax_passed':syntax.returncode==0,'dart_delta_doc_comments_only':comment_only and all_changed_doc,'workflow_unchanged_from_captured_candidate':git('show',f'{BASE}:{WORKFLOW}')==(REPO/WORKFLOW).read_bytes(),'scoped_inputs_unchanged':inputs==after,'head_unchanged':head()==EXPECTED,'all_controlled_scenarios_passed':all(x['accepted'] for x in rows)}
receipt={'status':'passed' if all(checks.values()) else 'failed','source_head':EXPECTED,'source_tree':git('rev-parse','HEAD^{tree}').decode().strip(),'compared_candidate':BASE,'started_scope':'Source hashes cover build script, distribution Dart, release guidance and already-captured workflow.','syntax_command':syntax_command,'syntax_exit_code':syntax.returncode,'guards':checks,'scenario_count':len(rows),'scenarios':[{'name':r['scenario']['name'],'accepted':r['accepted'],'exit_code':r['exit_code'],'checks':r['checks']} for r in rows],'dart_non_doc_source_sha256':hashlib.sha256(no_doc_comments(new_dart).encode()).hexdigest(),'source_inputs':inputs,'finished_at_utc':now(),'qualification_limit':'Syntax and Linux Bash control-flow only. Verbatim changed script blocks execute against synthetic non-executable files, with codesign/code-digest/unsigned-digest calls stubbed. No macOS build, real Mach-O signing, signature verification, native library loading, notarization or shipping acceptance is established. Application test totals exclude these auxiliary scenarios.','help_not_invoked':'The full build script does not implement a side-effect-free --help action; unknown args are forwarded to Flutter only after native build steps.'}
write(OUT/'receipt.json',receipt)
print(json.dumps({'status':receipt['status'],'guards':checks,'scenario_count':len(rows)}),flush=True)
raise SystemExit(0 if all(checks.values()) else 1)
