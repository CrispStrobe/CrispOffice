from pathlib import Path
import hashlib, json, os, shutil, subprocess
from datetime import datetime, timezone
root=Path('/workspace/scratch/8e9460dcd580/runtime')
sdk=root/'flutter'
clone=root/'flutter-shallow-git'
backup=root/'flutter-git-original'
def run(*args,cwd): return subprocess.check_output(list(args),cwd=cwd,text=True).strip()
def size(path):return sum(p.stat().st_size for p in path.rglob('*') if p.is_file())
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
head=run('git','rev-parse','HEAD',cwd=sdk)
tree=run('git','rev-parse','HEAD^{tree}',cwd=sdk)
source_files=[sdk/'bin/cache/dart-sdk/bin/dart',sdk/'bin/cache/artifacts/engine/linux-x64/flutter_tester',sdk/'bin/cache/flutter_tools.snapshot']
before={str(p):sha(p) for p in source_files}
old_size=size(sdk/'.git')
subprocess.run(['git','clone','--no-checkout','--depth=1','--single-branch','--branch','3.47.8',sdk.as_uri(),str(clone)],check=True)
assert run('git','rev-parse','HEAD',cwd=clone)==head
assert run('git','rev-parse','HEAD^{tree}',cwd=clone)==tree
assert run('git','rev-parse','3.47.8^{commit}',cwd=clone)==head
subprocess.run(['git','branch','stable',head],cwd=clone,check=True)
subprocess.run(['git','symbolic-ref','HEAD','refs/heads/stable'],cwd=clone,check=True)
subprocess.run(['git','remote','set-url','origin','https://github.com/flutter/flutter.git'],cwd=clone,check=True)
subprocess.run(['git','config','branch.stable.remote','origin'],cwd=clone,check=True)
subprocess.run(['git','config','branch.stable.merge','refs/heads/stable'],cwd=clone,check=True)
shutil.copy2(sdk/'.git/index',clone/'.git/index')
os.rename(sdk/'.git',backup)
os.rename(clone/'.git',sdk/'.git')
assert run('git','rev-parse','HEAD',cwd=sdk)==head
assert run('git','rev-parse','HEAD^{tree}',cwd=sdk)==tree
assert before=={str(p):sha(p) for p in source_files}
new_size=size(sdk/'.git')
shutil.rmtree(backup)
shutil.rmtree(clone)
receipt={'captured_at':datetime.now(timezone.utc).isoformat(),'reason':'Release only unused SDK Git history while preserving exact release commit, tree, tag, working source, executable bytes and stable channel metadata.','head':head,'tree':tree,'tag':'3.47.8','full_git_bytes':old_size,'shallow_git_bytes':new_size,'reclaimed_bytes':old_size-new_size,'verified_executables':before}
(root/'sdk-history-reduction.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt))
