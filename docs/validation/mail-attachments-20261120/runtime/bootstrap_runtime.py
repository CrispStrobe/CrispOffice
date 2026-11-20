#!/usr/bin/env python3
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib, io, json, os, shutil, subprocess, tarfile, time, urllib.parse, urllib.request
from pathlib import Path, PurePosixPath
import yaml
ROOT=Path('/workspace/scratch/75dc9d25dfaf/runtime')
REPO=ROOT.parent/'quds_office_suite'
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
    # Current checkout is present and root coordinates any dependency changes.
    initial_lock_sha=sha(REPO/'pubspec.lock')
    record['workspace_lock_initial_sha256']=initial_lock_sha
    save()
    locks=[SDK/'packages/flutter_tools/pubspec.lock',REPO/'pubspec.lock']
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
    flutter.write_text('#!/bin/sh\nexec "'+str(dart)+'" "'+str(SDK/'bin/cache/flutter_tools.snapshot')+'" --no-version-check "$@"\n');flutter.chmod(0o755)
    dart_wrapper=ROOT/'bin/dart'
    dart_wrapper.write_text('#!/bin/sh\nexec "'+str(dart)+'" "$@"\n');dart_wrapper.chmod(0o755)
    env['PATH']=str(ROOT/'bin')+':'+env.get('PATH','')
    import shlex
    (ROOT/'env.sh').write_text('\n'.join('export '+key+'='+shlex.quote(value) for key,value in env.items() if key in ['PUB_CACHE','FLUTTER_ROOT','CI','DART_SUPPRESS_ANALYTICS','FLUTTER_SUPPRESS_ANALYTICS','DASH__SUPPRESS_ANALYTICS','XDG_CONFIG_HOME','XDG_CACHE_HOME','XDG_DATA_HOME','TMPDIR'])+'\nexport PATH='+shlex.quote(str(ROOT/'bin'))+':"$PATH"\n')
    if sha(REPO/'pubspec.lock')!=initial_lock_sha:raise RuntimeError('Workspace lock moved before resolution')
    run('workspace-pub-get',[dart,'pub','get','--offline','--enforce-lockfile'],REPO)
    if sha(REPO/'pubspec.lock')!=initial_lock_sha:raise RuntimeError('Workspace lock changed during resolution')
    version_log=run('flutter-version',[flutter,'--version','--machine'],REPO)
    record['runtime']=json.loads(version_log.read_text())
    if record['runtime']['frameworkRevision']!='737ba8f885dc774b53b442759999a312c9461e4e' or record['runtime']['dartSdkVersion']!='3.13.7':raise RuntimeError('Unexpected SDK identity')
    record['workspace_lock_sha256']=sha(REPO/'pubspec.lock')
    record['workspace_package_count']=len(json.loads((REPO/'.dart_tool/package_config.json').read_text())['packages'])
    record['environment_script']=str(ROOT/'env.sh')
    record['status']='ready'
    (ROOT/'runtime-ready').touch()
except BaseException as error:
    record['status']='failed';record['error']=repr(error);raise
finally:
    record['finished_at_utc']=datetime.now(timezone.utc).isoformat();save()
    print(json.dumps({'status':record['status'],'error':record.get('error'),'free_bytes':shutil.disk_usage(ROOT).free}),flush=True)
