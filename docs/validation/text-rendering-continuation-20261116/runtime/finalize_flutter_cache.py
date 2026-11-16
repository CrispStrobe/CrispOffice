#!/usr/bin/env python3
from datetime import datetime, timezone
from functools import partial
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import threading
import time

root = Path('/workspace/scratch/796b63b8623e/toolchain')
sdk = root / 'flutter-runtime'
repo = root.parent / 'quds_office_suite'
wrapper = root / 'flutter_cli.sh'
wrapper.chmod(0o755)
out = root / 'setup/final'
out.mkdir(exist_ok=True)
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
record = {'started_at_utc': datetime.now(timezone.utc).isoformat(), 'commands': [],
          'framework_source_revision': subprocess.check_output(['git','rev-parse','HEAD'],cwd=sdk,text=True).strip(),
          'flutter_cli': str(wrapper), 'cli_kernel_sha256': sha(root/'flutter_tools.dill'),
          'cli_build': 'dart compile kernel --packages=packages/flutter_tools/.dart_tool/package_config.json packages/flutter_tools/bin/flutter_tools.dart',
          'native_binaries_rebuilt': False, 'sdk_source_changes': subprocess.check_output(['git','diff','--name-only'],cwd=sdk,text=True).splitlines(),
          'workspace_lock_sha256': sha(repo/'pubspec.lock'),
          'workspace_package_config_sha256': sha(repo/'.dart_tool/package_config.json'),
          'workspace_package_count': len(json.loads((repo/'.dart_tool/package_config.json').read_text())['packages'])}

class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self,*args): pass
server=ThreadingHTTPServer(('127.0.0.1',0),partial(QuietHandler,directory=str(root/'mirror')))
threading.Thread(target=server.serve_forever,daemon=True).start()
env={**os.environ,'FLUTTER_STORAGE_BASE_URL':f'http://127.0.0.1:{server.server_port}'}
def run(name,args):
    log=out/(name+'.log');begin=time.monotonic()
    print('START '+name,flush=True)
    with log.open('wb') as stream:
        p=subprocess.run([str(wrapper),*args],cwd=repo,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=180)
    record['commands'].append({'name':name,'args':args,'exit_code':p.returncode,'elapsed_seconds':time.monotonic()-begin,'log_sha256':sha(log)})
    print('END '+name+' '+str(p.returncode),flush=True)
    if p.returncode:
        print(log.read_text()[-10000:],flush=True)
        raise RuntimeError(name)
    return log
try:
    run('universal-artifacts',['precache','--informative','--no-web','--no-android','--no-ios','--no-linux','--no-windows','--no-macos','--no-fuchsia'])
    version_log=run('version',['--version','--machine'])
    text=version_log.read_text();record['actual_runtime']=json.loads(text[text.index('{'):])
    expected={'bin/cache/dart-sdk/bin/dart':'01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb',
              'bin/cache/artifacts/engine/linux-x64/flutter_tester':'800f4ca182df7dd2fb46a42dea5d76277b9dbc5e8cd2915e02bcbc978681b45f'}
    record['executable_hashes']={path:sha(sdk/path) for path in expected}
    assert record['executable_hashes']==expected
    assert record['workspace_lock_sha256']=='344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130'
    assert not record['sdk_source_changes']
    record['status']='ready'
except BaseException as error:
    record['status']='failed';record['error']=repr(error);raise
finally:
    record['finished_at_utc']=datetime.now(timezone.utc).isoformat()
    (out/'runtime.json').write_text(json.dumps(record,indent=2)+'\n')
    server.shutdown()
    print('FINAL_STATUS '+record['status'],flush=True)
