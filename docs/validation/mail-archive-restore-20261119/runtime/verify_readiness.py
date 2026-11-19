#!/usr/bin/env python3
import ctypes, hashlib, json, os, subprocess, tempfile
from datetime import datetime, timezone
from pathlib import Path
ROOT=Path('/workspace/scratch/f815a4ae580f/runtime')
REPO=ROOT.parent/'quds_office_suite'
record={'started_at_utc':datetime.now(timezone.utc).isoformat(),'status':'running','runs':[]}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save():(ROOT/'readiness-receipt.json').write_text(json.dumps(record,indent=2)+'\n')
def run(name,args,cwd):
 log=ROOT/'logs'/(name+'.log')
 with log.open('wb') as f:result=subprocess.run([str(a) for a in args],cwd=cwd,stdout=f,stderr=subprocess.STDOUT,timeout=300)
 record['runs'].append({'name':name,'command':[str(a) for a in args],'cwd':str(cwd),'exit_code':result.returncode,'log':str(log),'log_sha256':sha(log)})
 save()
 print(name,result.returncode,flush=True)
 if result.returncode:raise RuntimeError(log.read_text(errors='replace')[-12000:])
 return log
try:
 record['lock_before_sha256']=sha(REPO/'pubspec.lock')
 record['manifest_before_sha256']=sha(REPO/'pubspec.yaml')
 (REPO/'packages/quds_mail_store/.dart_tool').mkdir(exist_ok=True)
 with tempfile.TemporaryDirectory(prefix='runtime-native-smoke-',dir=REPO/'packages/quds_mail_store/.dart_tool') as temp:
  source=Path(temp)/'native_asset_smoke.dart'
  source.write_text("import 'package:sqlite3/sqlite3.dart';\nvoid main() { final db=sqlite3.openInMemory(); try { db.execute('CREATE VIRTUAL TABLE probe USING fts5(body)'); db.execute(\"INSERT INTO probe VALUES ('ready')\"); if (db.select(\"SELECT * FROM probe WHERE probe MATCH 'ready'\").length != 1) throw StateError('FTS5 failed'); print(sqlite3.version); } finally { db.close(); } }\n")
  run('native-sqlite-readiness',[ROOT/'bin/dart','run',source],REPO/'packages/quds_mail_store')
 run('flutter-readiness',[ROOT/'bin/flutter','test','--no-pub','--concurrency=1','--reporter=json','test/office_units_test.dart'],REPO/'packages/quds_office_editor')
 run('analyzer-readiness',[ROOT/'bin/dart','analyze','--fatal-infos','packages/quds_mail_core'],REPO)
 native=REPO/'.dart_tool/lib/libsqlite3.so'
 lib=ctypes.CDLL(str(native));lib.sqlite3_libversion.restype=ctypes.c_char_p;lib.sqlite3_compileoption_used.argtypes=[ctypes.c_char_p];lib.sqlite3_compileoption_used.restype=ctypes.c_int
 record['native_assets']={'manifest':str(REPO/'.dart_tool/native_assets.yaml'),'manifest_sha256':sha(REPO/'.dart_tool/native_assets.yaml'),'library':str(native),'library_sha256':sha(native),'version':lib.sqlite3_libversion().decode(),'fts5':bool(lib.sqlite3_compileoption_used(b'ENABLE_FTS5')),'provenance':'Unmodified sqlite3 3.9.1 default native build hook; library checksum matches package pinned asset'}
 if record['native_assets']['library_sha256']!='0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b' or not record['native_assets']['fts5']:raise RuntimeError('Native library identity failed')
 record['lock_after_sha256']=sha(REPO/'pubspec.lock');record['manifest_after_sha256']=sha(REPO/'pubspec.yaml')
 if record['lock_before_sha256']!=record['lock_after_sha256'] or record['manifest_before_sha256']!=record['manifest_after_sha256']:raise RuntimeError('Root dependency file changed')
 record['status']='ready'
except BaseException as e:
 record['status']='failed';record['error']=repr(e);raise
finally:
 record['finished_at_utc']=datetime.now(timezone.utc).isoformat();save()
