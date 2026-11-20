#!/usr/bin/env python3
import argparse
import shlex
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib, io, json, os, shutil, subprocess, tarfile, time, urllib.parse, urllib.request
from pathlib import Path, PurePosixPath
import yaml
parser=argparse.ArgumentParser(description='Reproduce the pinned Mail qualification runtime. Requires Python PyYAML and a fresh checkout/runtime directory.')
parser.add_argument('--repo',type=Path,required=True)
parser.add_argument('--runtime',type=Path,required=True)
args=parser.parse_args()
ROOT=args.runtime.resolve()
REPO=args.repo.resolve()
if ROOT.exists():raise SystemExit('Use a fresh runtime directory.')
if (REPO/'.dart_tool/package_config.json').exists():raise SystemExit('Use a fresh checkout without resolved workspace dependencies.')
if not (REPO/'packages/quds_mail_store/pubspec.yaml').is_file():raise SystemExit('Expected the Quds Office workspace.')
SDK=ROOT/'flutter'
CACHE=ROOT/'pub-cache'
OUT=ROOT/'logs'
URL='https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.8-stable.tar.xz'
EXPECTED='baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2'
for p in (ROOT,OUT,CACHE,ROOT/'bin',ROOT/'tmp',ROOT/'config',ROOT/'cache',ROOT/'data'):
    p.mkdir(exist_ok=True,parents=True)
record={'started_at_utc':datetime.now(timezone.utc).isoformat(),'status':'running','source':str(REPO),'sdk':str(SDK),'runs':[]}
def sha(path):
    digest=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(8*1024*1024),b''):digest.update(block)
    return digest.hexdigest()
def save():
    (ROOT/'runtime.json').write_text(json.dumps(record,indent=2)+'\n')
class DigestReader:
    def __init__(self,stream):
        self.stream=stream;self.hash=hashlib.sha256();self.total=0
    def read(self,n=-1):
        data=self.stream.read(n);self.hash.update(data);self.total+=len(data);return data
def selected(name):
    parts=PurePosixPath(name).parts
    if not parts or parts[0]!='flutter':return False
    if len(parts)==1:return True
    if parts[1]=='.git':return True
    if parts[1]=='bin':
        relative='/'.join(parts[1:])
        if relative.startswith('bin/cache/artifacts/engine/'):
            platform=parts[5] if len(parts)>5 else ''
            if platform.startswith(('android','ios','darwin','windows','linux-arm64','linux-x64-profile','linux-x64-release')):return False
        # The full genuine Dart SDK is retained.
        return True
    if parts[1]=='packages':
        return not (len(parts)>3 and parts[3] in {'test','test_private','test_fixes','example','examples','benchmark','benchmarks'})
    return len(parts)==2 and parts[1] in {'LICENSE','AUTHORS','README.md','version','.metadata','pubspec.yaml','pubspec.lock','analysis_options.yaml','flutter_console.bat'}
def run(name,argv,cwd):
    print('START '+name,flush=True)
    log=OUT/(name+'.log')
    with log.open('wb') as stream:
        result=subprocess.run([str(x) for x in argv],cwd=cwd,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=300)
    record['runs'].append({'name':name,'command':[str(x) for x in argv],'cwd':str(cwd),'exit_code':result.returncode,'log':str(log),'log_sha256':sha(log)})
    save()
    print('END '+name+' exit='+str(result.returncode),flush=True)
    if result.returncode:raise RuntimeError(name+': '+log.read_text(errors='replace')[-10000:])
    return log
try:
    save()
    print('Downloading and verifying official SDK',flush=True)
    expanded=0;files=[];last=time.monotonic()
    with urllib.request.urlopen(URL,timeout=120) as response:
        reader=DigestReader(response)
        with tarfile.open(fileobj=reader,mode='r|xz') as bundle:
            for member in bundle:
                if selected(member.name):
                    expanded+=member.size
                    if expanded>10*1024**3 or shutil.disk_usage(ROOT).free<2*1024**3:raise RuntimeError('SDK extraction reached disk budget')
                    bundle.extract(member,ROOT,filter='data')
                    if member.isfile():files.append({'path':member.name,'bytes':member.size})
                if time.monotonic()-last>20:
                    print(json.dumps({'downloaded_bytes':reader.total,'expanded_bytes':expanded,'free_bytes':shutil.disk_usage(ROOT).free}),flush=True);last=time.monotonic()
        while reader.read(8*1024*1024):pass
        actual=reader.hash.hexdigest()
        if actual!=EXPECTED:raise RuntimeError('Official SDK archive hash mismatch: '+actual)
    record['archive']={'url':URL,'sha256':actual,'bytes':reader.total,'verified':True,'extracted_bytes':expanded}
    (ROOT/'archive-members.json').write_text(json.dumps(files,indent=2)+'\n')
    save()
    (ROOT/'sdk-ready').touch()
    # Use the captured lock pins; resolve the fresh workspace only after SDK setup.
    initial_lock_sha=sha(REPO/'pubspec.lock')
    record['workspace_lock_initial_sha256']=initial_lock_sha
    save()
    shutil.copyfile(REPO/'pubspec.lock',ROOT/'captured-workspace-pubspec.lock')
    locks=[SDK/'packages/flutter_tools/pubspec.lock',ROOT/'captured-workspace-pubspec.lock']
    packages={}
    for lock in locks:
        for name,item in yaml.safe_load(lock.read_text())['packages'].items():
            if item['source']!='hosted':continue
            info=item['description']
            if info['url']!='https://pub.dev':raise RuntimeError('Unexpected package host')
            key=name+'-'+item['version']
            entry={'name':name,'version':item['version'],'sha256':info['sha256']}
            if key in packages and packages[key]!=entry:raise RuntimeError('Conflicting package hashes')
            packages[key]=entry
    for p in (CACHE/'_temp',CACHE/'hosted/pub.dev',CACHE/'hosted-hashes/pub.dev'):p.mkdir(exist_ok=True,parents=True)
    def fetch(pair):
        key,item=pair
        target=CACHE/'hosted/pub.dev'/key
        mark=CACHE/'hosted-hashes/pub.dev'/(key+'.sha256')
        url='https://pub.dev/api/archives/'+urllib.parse.quote(key,safe='-._+')+'.tar.gz'
        for attempt in range(3):
            try:
                with urllib.request.urlopen(url,timeout=120) as response:data=response.read()
                break
            except Exception:
                if attempt==2:raise
        actual=hashlib.sha256(data).hexdigest()
        if actual!=item['sha256']:raise RuntimeError('Package hash mismatch '+key)
        target.mkdir(exist_ok=False)
        with tarfile.open(fileobj=io.BytesIO(data),mode='r:gz') as bundle:bundle.extractall(target,filter='data')
        mark.write_text(actual)
        return dict(item,url=url,bytes=len(data),verified=True)
    print('Restoring '+str(len(packages))+' pinned Pub packages',flush=True)
    with ThreadPoolExecutor(max_workers=16) as pool:receipts=list(pool.map(fetch,sorted(packages.items())))
    (ROOT/'pub-cache-receipt.json').write_text(json.dumps(receipts,indent=2)+'\n')
    record['hosted_archives_verified']=len(receipts)
    env=dict(os.environ,PUB_CACHE=str(CACHE),FLUTTER_ROOT=str(SDK),CI='true',DART_SUPPRESS_ANALYTICS='true',FLUTTER_SUPPRESS_ANALYTICS='true',DASH__SUPPRESS_ANALYTICS='true',XDG_CONFIG_HOME=str(ROOT/'config'),XDG_CACHE_HOME=str(ROOT/'cache'),XDG_DATA_HOME=str(ROOT/'data'),TMPDIR=str(ROOT/'tmp'))
    dart=SDK/'bin/cache/dart-sdk/bin/dart'
    tester=SDK/'bin/cache/artifacts/engine/linux-x64/flutter_tester'
    expected_executables={str(dart):'01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb',str(tester):'800f4ca182df7dd2fb46a42dea5d76277b9dbc5e8cd2915e02bcbc978681b45f'}
    for path,digest in expected_executables.items():
        if sha(Path(path))!=digest:raise RuntimeError('Executable differs '+path)
    record['executables_sha256']=expected_executables
    run('flutter-tools-pub-get',[dart,'pub','get','--offline','--enforce-lockfile'],SDK/'packages/flutter_tools')
    flutter=ROOT/'bin/flutter'
    flutter.write_text('#!/bin/sh\nexec '+shlex.quote(str(dart))+' '+shlex.quote(str(SDK/'bin/cache/flutter_tools.snapshot'))+' --no-version-check "$@"\n');flutter.chmod(0o755)
    dart_wrapper=ROOT/'bin/dart'
    dart_wrapper.write_text('#!/bin/sh\nexec '+shlex.quote(str(dart))+' "$@"\n');dart_wrapper.chmod(0o755)
    env['PATH']=str(ROOT/'bin')+':'+env.get('PATH','')
    import shlex
    (ROOT/'env.sh').write_text('\n'.join('export '+key+'='+shlex.quote(value) for key,value in env.items() if key in ['PUB_CACHE','FLUTTER_ROOT','CI','DART_SUPPRESS_ANALYTICS','FLUTTER_SUPPRESS_ANALYTICS','DASH__SUPPRESS_ANALYTICS','XDG_CONFIG_HOME','XDG_CACHE_HOME','XDG_DATA_HOME','TMPDIR'])+'\nexport PATH='+shlex.quote(str(ROOT/'bin'))+':"$PATH"\n')
    if sha(REPO/'pubspec.lock')!=initial_lock_sha:raise RuntimeError('Workspace lock moved before resolution')
    manifests=[REPO/'pubspec.yaml',REPO/'pubspec.lock',*REPO.glob('packages/**/pubspec.yaml'),*REPO.glob('apps/**/pubspec.yaml'),*REPO.glob('third_party/**/pubspec.yaml')]
    manifest_before={str(path):sha(path) for path in manifests}
    run('workspace-pub-get',[dart,'pub','get','--offline','--enforce-lockfile'],REPO)
    if manifest_before!={str(path):sha(path) for path in manifests}:raise RuntimeError('Workspace manifests changed during resolution')
    record['workspace_resolution']='Offline --enforce-lockfile; tracked manifests unchanged'
    configuration=REPO/'.dart_tool/package_config.json'
    runner_directory=ROOT/'test-runner'
    runner_directory.mkdir()
    test_version=yaml.safe_load((REPO/'pubspec.lock').read_text())['packages']['test']['version']
    if test_version!='1.31.1':raise RuntimeError('Unexpected package:test pin for this recorded qualification')
    test_entry=CACHE/'hosted/pub.dev'/('test-'+test_version)/'bin/test.dart'
    run('test-runner-compile',[dart,'compile','kernel','--packages='+str(configuration),test_entry,'-o',runner_directory/'test-runner.dill'],REPO)
    run('test-runner-startup',[dart,'--packages='+str(configuration),runner_directory/'test-runner.dill','--version'],REPO)
    probe_source="""import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
void main() {
  final database = sqlite3.openInMemory();
  try {
    database.execute('CREATE VIRTUAL TABLE smoke USING fts5(body)');
    database.execute('INSERT INTO smoke(body) VALUES (?)', ['ready']);
    final rows = database.select(\"SELECT body FROM smoke WHERE smoke MATCH 'ready'\");
    if (rows.length != 1 || rows.single['body'] != 'ready') {
      throw StateError('SQLite FTS5 readiness probe failed');
    }
    print(jsonEncode({'sqlite3': sqlite3.version.toString(), 'fts5': 'ready'}));
  } finally {
    database.close();
  }
}
"""
    probe=REPO/'packages/quds_mail_store/build/runtime-preparation/sqlite_probe.dart'
    probe.parent.mkdir(parents=True,exist_ok=True)
    probe.write_text(probe_source)
    (ROOT/'sqlite_probe.dart').write_text(probe_source)
    probe_log=run('sqlite-readiness',[dart,'run','build/runtime-preparation/sqlite_probe.dart'],REPO/'packages/quds_mail_store')
    sqlite=REPO/'.dart_tool/lib/libsqlite3.so'
    native_hash=sha(sqlite)
    if native_hash!='0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b':raise RuntimeError('SQLite artifact differs from the pinned default hook')
    shutil.copyfile(probe_log,ROOT/'sqlite-readiness.log')
    (ROOT/'sqlite-readiness.json').write_text(json.dumps({'status':'ready','exit_code':0,'log':'sqlite-readiness.log','log_sha256':sha(probe_log),'library_sha256':native_hash,'probe':'sqlite_probe.dart','probe_sha256':sha(probe),'native_assets_manifest_sha256':sha(REPO/'.dart_tool/native_assets.yaml')},indent=2)+'\n')
    if manifest_before!={str(path):sha(path) for path in manifests}:raise RuntimeError('Workspace manifests changed during runtime preparation')
    record['workspace_package_configuration_sha256']=sha(configuration)
    record['test_runner_kernel_sha256']=sha(runner_directory/'test-runner.dill')
    record['native_sqlite_sha256']=native_hash
    version_log=run('flutter-version',[flutter,'--version','--machine'],SDK)
    record['runtime']=json.loads(version_log.read_text())
    if record['runtime']['frameworkRevision']!='737ba8f885dc774b53b442759999a312c9461e4e' or record['runtime']['dartSdkVersion']!='3.13.7':raise RuntimeError('Unexpected SDK identity')
    record['workspace_lock_sha256']=sha(REPO/'pubspec.lock')
    record['workspace_package_count']=len(yaml.safe_load((REPO/'pubspec.lock').read_text())['packages'])
    record['environment_script']=str(ROOT/'env.sh')
    record['status']='ready'
    (ROOT/'runtime-ready').touch()
except BaseException as error:
    record['status']='failed';record['error']=repr(error);raise
finally:
    record['finished_at_utc']=datetime.now(timezone.utc).isoformat();save()
    print(json.dumps({'status':record['status'],'error':record.get('error'),'free_bytes':shutil.disk_usage(ROOT).free}),flush=True)
