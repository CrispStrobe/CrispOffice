from pathlib import Path
import hashlib,json,os,subprocess
from datetime import datetime,timezone
root=Path(__file__).resolve().parent.parent
runtime=root/'zotero-toolchain'
sdk=runtime/'flutter-sdk'
repo=root/'quds_office_suite'
workspace=root/'zotero-validation'
env=dict(os.environ,FLUTTER_ROOT=str(sdk),PUB_CACHE=str(runtime/'pub-cache'),TMPDIR=str(runtime/'tmp'),XDG_CONFIG_HOME=str(runtime/'config'),XDG_CACHE_HOME=str(runtime/'cache'),XDG_DATA_HOME=str(runtime/'data'),CI='true',DART_SUPPRESS_ANALYTICS='true',DASH__SUPPRESS_ANALYTICS='true',FLUTTER_SUPPRESS_ANALYTICS='true')
env['PATH']=str(sdk/'bin')+':'+env['PATH']
dart=sdk/'bin/cache/dart-sdk/bin/dart'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
commands=[]
def run(cmd,cwd,name):
    with (runtime/'logs'/name).open('wb') as out:
        r=subprocess.run(cmd,cwd=cwd,env=env,stdout=out,stderr=subprocess.STDOUT,timeout=240)
    commands.append(dict(command=cmd,cwd=str(cwd),exit_code=r.returncode,log=name))
    if r.returncode: raise RuntimeError('Failed '+name)
locks=[workspace/'pubspec.lock',sdk/'packages/flutter_tools/pubspec.lock']
before={str(p):sha(p) for p in locks}
run([str(dart),'pub','get','--offline','--enforce-lockfile'],workspace,'workspace-pub-get.log')
run([str(dart),'pub','get','--offline','--enforce-lockfile'],sdk/'packages/flutter_tools','flutter-tools-pub-get.log')
assert before=={str(p):sha(p) for p in locks}
link=repo/'.dart_tool'
if link.is_symlink(): assert link.resolve()==workspace/'.dart_tool'
elif link.exists(): raise RuntimeError('Source graph exists unexpectedly')
else: link.symlink_to(workspace/'.dart_tool',target_is_directory=True)
run([str(sdk/'bin/flutter'),'--version','--machine'],workspace,'flutter-version.json')
run([str(dart),'--version'],workspace,'dart-version.log')
tracked=subprocess.check_output(['git','status','--porcelain','--untracked-files=no'],cwd=sdk,text=True)
assert not tracked,tracked
prepared=json.loads((runtime/'setup/workspace-prepared.json').read_text())
manifests={p:sha(repo/p)==sha(workspace/p) for p in prepared['manifests_sha256']}
assert all(manifests.values()),manifests
config=json.loads((workspace/'.dart_tool/package_config.json').read_text())
receipt=dict(status='ready',recorded_at_utc=datetime.now(timezone.utc).isoformat(),source_head_at_setup=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),source=str(repo),workspace=str(workspace),sdk=str(sdk),environment_script=str(runtime/'env.sh'),runtime=json.loads((runtime/'logs/flutter-version.json').read_text()),archive=json.loads((runtime/'flutter-recovery.json').read_text()),executable_sha256={k:sha(v) for k,v in {'dart':dart,'flutter_tester':sdk/'bin/cache/artifacts/engine/linux-x64/flutter_tester'}.items()},framework_tracked_changes=[],workspace_package_count=len(config['packages']),workspace_lock_sha256=sha(locks[0]),flutter_tools_lock_sha256=sha(locks[1]),workspace_manifest_matches=manifests,commands=commands,product_tests_run=0,no_ci_actions_used=True)
(runtime/'runtime-ready.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({k:receipt[k] for k in ['status','source_head_at_setup','workspace_package_count','runtime','executable_sha256']},indent=2))
