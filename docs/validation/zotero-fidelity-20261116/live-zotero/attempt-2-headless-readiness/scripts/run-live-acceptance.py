#!/usr/bin/env python3
"""Compile the actual Quds integration, then execute it against isolated Zotero."""
from datetime import datetime, timezone
import hashlib
import http.client
import json
import os
from pathlib import Path
import subprocess
import time
import xml.etree.ElementTree as ET
import zipfile

BASE = Path(__file__).resolve().parents[1]
WORKSPACE = BASE.parent
SOURCE = WORKSPACE / 'quds_office_suite'
TOOLCHAIN = WORKSPACE / 'zotero-toolchain'
SDK = TOOLCHAIN / 'flutter-sdk'
DART = SDK / 'bin/cache/dart-sdk/bin/dart'
CONFIG = TOOLCHAIN / 'harness/quds_office_studio/.dart_tool/package_config.json'
LOGS = BASE / 'logs'
KERNEL = BASE / 'fidelity-live.dill'
NS = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def source_fingerprint():
    files = set()
    for name in ('quds_office_engine', 'quds_office_editor', 'quds_reports', 'legacy_doc_parser'):
        root = SOURCE / 'packages' / name
        files.update((root / 'lib').rglob('*.dart'))
        files.update(p for p in (root / 'pubspec.yaml', root / 'pubspec.lock') if p.exists())
    files.update((SOURCE / 'packages/quds_office_editor/example/lib').rglob('*.dart'))
    files.add(SOURCE / 'packages/quds_office_editor/example/pubspec.yaml')
    files.add(BASE / 'scripts/fidelity-live.dart')
    files.update(BASE.glob('*.csl'))
    files.update((TOOLCHAIN / 'harness/quds_office_studio').glob('pubspec.*'))
    files.add(CONFIG)
    return {str(p.relative_to(WORKSPACE)): digest(p) for p in sorted(files)}

def query(path, timeout=3):
    connection = http.client.HTTPConnection('127.0.0.1', 23119, timeout=timeout)
    try:
        connection.request('GET', path, headers={
            'Zotero-Allowed-Request': 'true', 'Zotero-API-Version': '3',
        })
        response = connection.getresponse()
        return response.status, dict(response.getheaders()), response.read().decode()
    finally:
        connection.close()

def check_docx(path, lines, caps):
    with zipfile.ZipFile(path) as archive:
        document = ET.fromstring(archive.read('word/document.xml'))
        notes = ET.fromstring(archive.read('word/footnotes.xml'))
    body = document.find('w:body', NS)
    paragraphs = body.findall('w:p', NS)
    code = document.findall('.//w:instrText', NS)
    assert len(code) == 1 and 'ZOTERO_BIBL' in code[0].text
    begins = [i for i,p in enumerate(paragraphs)
              if any(e.get('{'+NS['w']+'}fldCharType') == 'begin' for e in p.findall('.//w:fldChar',NS))]
    ends = [i for i,p in enumerate(paragraphs)
            if any(e.get('{'+NS['w']+'}fldCharType') == 'end' for e in p.findall('.//w:fldChar',NS))]
    assert len(begins) == len(ends) == 1 and ends[0] == begins[0] + 1
    entries = paragraphs[begins[0]:ends[0]+1]
    for p in entries:
        indent = p.find('w:pPr/w:ind', NS)
        spacing = p.find('w:pPr/w:spacing', NS)
        assert indent is not None and spacing is not None
        assert indent.get('{'+NS['w']+'}left') == '720'
        assert indent.get('{'+NS['w']+'}hanging') == '720'
        assert spacing.get('{'+NS['w']+'}line') == str(lines * 240)
        assert spacing.get('{'+NS['w']+'}after') == '240'
        assert not p.findall('.//w:br',NS)
    note_codes = notes.findall('.//w:instrText',NS)
    assert len(note_codes) == 4
    small_caps = notes.findall('.//w:smallCaps',NS)
    enabled = [e for e in small_caps if e.get('{'+NS['w']+'}val','1') not in ('0','false','off')]
    if caps:
        assert enabled
        assert any(p.findall('.//w:smallCaps',NS) for p in entries)
    return {'path': path.name, 'sha256': digest(path), 'native_bibliography_fields':1,
            'bibliography_paragraphs':2, 'citation_fields':4,
            'indent_twips':720, 'hanging_twips':720, 'line_twips':lines*240,
            'entry_spacing_twips':240, 'small_caps_runs':len(enabled),
            'no_inline_breaks_between_entries':True}

def main():
    env = os.environ.copy()
    env.update({'FLUTTER_ROOT':str(SDK), 'PUB_CACHE':str(TOOLCHAIN/'pub-cache'),
        'TMPDIR':str(BASE/'tmp'), 'XDG_CONFIG_HOME':str(TOOLCHAIN/'config'),
        'MOZ_HEADLESS':'1', 'MOZ_CRASHREPORTER_DISABLE':'1',
        'CI':'true', 'FLUTTER_SUPPRESS_ANALYTICS':'true', 'DART_SUPPRESS_ANALYTICS':'true'})
    before = source_fingerprint()
    (LOGS/'source-before.json').write_text(json.dumps(before,indent=2)+'\n')
    receipt = {'started_utc':datetime.now(timezone.utc).isoformat(),
        'source_commit':subprocess.check_output(['git','-C',str(SOURCE),'rev-parse','HEAD'],text=True).strip(),
        'source_status':subprocess.check_output(['git','-C',str(SOURCE),'status','--porcelain'],text=True),
        'source_files':len(before), 'source_before_sha256':digest(LOGS/'source-before.json'),
        'runtime':json.loads((SDK/'bin/cache/flutter.version.json').read_text()),
        'dart_sha256':digest(DART), 'runner_sha256':digest(Path(__file__)),
        'zotero_archive_sha256':digest(BASE/'binary/Zotero-10.0.8_linux-x86_64.tar.xz'),
        'zotero_application_ini':(BASE/'binary/Zotero_linux-x86_64/app/application.ini').read_text(),
        'uses_github_actions':False,'personal_account_connected':False,
        'synthetic_sources_only':True,'full_native_application_build':False,
        'microsoft_word_or_libreoffice_interoperability_tested':False}
    process = None
    try:
        command=[str(DART),'compile','kernel','--packages='+str(CONFIG),
                 '--output='+str(KERNEL),str(BASE/'scripts/fidelity-live.dart')]
        receipt['compile_command']=command
        with (LOGS/'kernel-compile.log').open('w') as log:
            compiled=subprocess.run(command,cwd=WORKSPACE,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=90)
        receipt['compile_exit']=compiled.returncode
        assert compiled.returncode==0,'Kernel compilation failed; see kernel-compile.log'
        assert source_fingerprint()==before,'Production inputs changed during compilation'
        receipt['kernel_sha256']=digest(KERNEL)
        receipt['kernel_bytes']=KERNEL.stat().st_size
        native_command=[str(BASE/'binary/Zotero_linux-x86_64/zotero'),'-no-remote','-headless',
             '-profile',str(BASE/'profile'),'-datadir',str(BASE/'data'),'-debug-text']
        receipt['native_command']=native_command
        with (LOGS/'zotero-native.log').open('w') as native_log:
            process=subprocess.Popen(native_command,cwd=BASE,env=env,stdout=native_log,stderr=subprocess.STDOUT)
            deadline=time.monotonic()+40
            last=None
            while time.monotonic()<deadline:
                if process.poll() is not None:
                    raise RuntimeError('Native Zotero exited before API readiness')
                try:
                    status,headers,data=query('/api/users/0/searches?format=json&limit=100')
                    last={'status':status,'headers':headers,'body':data}
                    if status==200:
                        searches=json.loads(data)
                        assert len(searches)==1 and searches[0]['key']=='QUDSABCD',searches
                        break
                except (OSError,http.client.HTTPException):
                    pass
                time.sleep(.5)
            else:
                raise TimeoutError('Native saved-search readiness failed: '+str(last))
            receipt['native_readiness']=last
            # New profiles asynchronously install bundled translators after
            # the plain API begins serving. Wait for the actual CSL-export
            # dependency before measuring the production client's operations.
            status,headers,data=query('/api/users/0/items/top?format=json&include=data,csljson&limit=100',timeout=45)
            receipt['native_csl_readiness']={'status':status,'headers':headers,'body':data}
            assert status==200 and len(json.loads(data))==3,'Native CSL export did not become ready'
            assert digest(KERNEL)==receipt['kernel_sha256'],'Executed kernel no longer matches compiled artifact'
            command=[str(DART),str(KERNEL),str(BASE)]
            receipt['execution_command']=command
            with (LOGS/'client-run.log').open('w') as client_log:
                executed=subprocess.run(command,cwd=WORKSPACE,env=env,stdout=client_log,stderr=subprocess.STDOUT,timeout=240)
            receipt['execution_exit']=executed.returncode
            assert executed.returncode==0,'Live client acceptance failed; see client-run.log'
            receipt['client_result']=json.loads((LOGS/'result.json').read_text())
            assert receipt['client_result']['result']=='passed'
            verification=[]
            for name,lines,caps in [('chicago',1,False),('smallcaps',2,True)]:
                for stage in ('first','repeat'):
                    verification.append(check_docx(BASE/f'{name}-{stage}-refreshed.docx',lines,caps))
            (LOGS/'independent-docx-verification.json').write_text(json.dumps(verification,indent=2)+'\n')
            receipt['independent_docx_verification']=verification
        receipt['result']='passed'
    except Exception as error:
        receipt['result']='failed'
        receipt['error']=str(error)
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.kill();process.wait(timeout=5)
        receipt['native_exit']=process.returncode if process is not None else None
        after=source_fingerprint()
        (LOGS/'source-after.json').write_text(json.dumps(after,indent=2)+'\n')
        receipt['source_after_sha256']=digest(LOGS/'source-after.json')
        receipt['source_unchanged']=before==after
        if before!=after:
            receipt['result']='failed'
            receipt['error']='Production/script inputs changed during acceptance'
        if KERNEL.exists() and 'kernel_sha256' in receipt:
            receipt['kernel_unchanged']=digest(KERNEL)==receipt['kernel_sha256']
            if not receipt['kernel_unchanged']:
                receipt['result']='failed'
        receipt['finished_utc']=datetime.now(timezone.utc).isoformat()
        receipt['artifact_hashes']={str(p.relative_to(BASE)):digest(p)
            for p in sorted([*LOGS.glob('*.log'),*LOGS.glob('*-result.json'),*LOGS.glob('*-protocol.jsonl'),*BASE.glob('*.docx')])}
        (LOGS/'acceptance-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
        print(json.dumps({k:receipt.get(k) for k in ('result','error','compile_exit','execution_exit','source_files','source_unchanged','kernel_unchanged')}))
        return 0 if receipt['result']=='passed' else 1

if __name__=='__main__':
    raise SystemExit(main())
