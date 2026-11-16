#!/usr/bin/env python3
"""Check native GUI API readiness; this is setup, not product qualification."""
from datetime import datetime, timezone
import http.client
import json
import os
from pathlib import Path
import subprocess
import time

BASE = Path(__file__).resolve().parents[1]
LOGS = BASE / 'desktop-preparation'
LOGS.mkdir(exist_ok=True)
env = os.environ.copy()
env.pop('MOZ_HEADLESS', None)
env['MOZ_CRASHREPORTER_DISABLE'] = '1'
env['TMPDIR'] = str(BASE / 'tmp')
receipt = {'started_utc': datetime.now(timezone.utc).isoformat(),
           'setup_only': True, 'synthetic_only': True,
           'display_present': bool(env.get('DISPLAY')),
           'isolated_profile': str(BASE/'profile'),
           'isolated_data': str(BASE/'data')}

def query(path, timeout=3):
    connection = http.client.HTTPConnection('127.0.0.1', 23119, timeout=timeout)
    try:
        connection.request('GET', path, headers={
            'Zotero-Allowed-Request': 'true', 'Zotero-API-Version': '3'})
        response = connection.getresponse()
        return {'status': response.status, 'headers': dict(response.getheaders()),
                'body': response.read().decode()}
    finally:
        connection.close()

with (LOGS/'zotero-native.log').open('w') as log:
    process = subprocess.Popen([
        str(BASE/'binary/Zotero_linux-x86_64/zotero'), '-no-remote',
        '-profile', str(BASE/'profile'), '-datadir', str(BASE/'data')],
        cwd=BASE, env=env, stdout=log, stderr=subprocess.STDOUT)
    try:
        deadline = time.monotonic()+40
        while time.monotonic()<deadline:
            if process.poll() is not None:
                raise RuntimeError('Native app exited before readiness')
            try:
                result=query('/api/users/0/searches?format=json&limit=100')
                if result['status']==200:
                    receipt['saved_search_api']=result
                    assert len(json.loads(result['body']))==1
                    break
            except (OSError,http.client.HTTPException):
                pass
            time.sleep(.5)
        else:
            raise TimeoutError('Saved-search API readiness timed out')
        result=query('/api/users/0/items/top?format=json&include=data,csljson&limit=100',timeout=45)
        receipt['csl_api']=result
        assert result['status']==200 and len(json.loads(result['body']))==3
        receipt['result']='passed'
    except Exception as error:
        receipt.update(result='failed',error=str(error),error_type=type(error).__name__)
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.kill();process.wait(timeout=5)
        receipt['native_exit']=process.returncode
        receipt['finished_utc']=datetime.now(timezone.utc).isoformat()
        (LOGS/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
        print(json.dumps({k:receipt.get(k) for k in ('result','error','error_type','display_present')}))
        raise SystemExit(0 if receipt['result']=='passed' else 1)
