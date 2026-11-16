#!/usr/bin/env python3
"""Prepare only a disposable synthetic Zotero profile using its real connector."""
import http.client
import json
import os
from pathlib import Path
import subprocess
import time

BASE = Path(__file__).resolve().parents[1]
binary = BASE / 'binary/Zotero_linux-x86_64/zotero'
logs = BASE / 'logs'
env = os.environ.copy()
env['MOZ_HEADLESS'] = '1'
env['MOZ_CRASHREPORTER_DISABLE'] = '1'
env['TMPDIR'] = str(BASE / 'tmp')
(BASE / 'tmp').mkdir(exist_ok=True)

def request(method, path, body=None):
    connection = http.client.HTTPConnection('127.0.0.1', 23119, timeout=3)
    headers = {'Zotero-Allowed-Request': 'true', 'Zotero-API-Version': '3',
               'Zotero-Connector-API-Version': '3'}
    if body is not None:
        headers['Content-Type'] = 'application/json'
        body = json.dumps(body).encode()
    try:
        connection.request(method, path, body=body, headers=headers)
        response = connection.getresponse()
        return response.status, dict(response.getheaders()), response.read().decode()
    finally:
        connection.close()

receipt = {'isolated_profile': str(BASE / 'profile'), 'isolated_data': str(BASE / 'data'),
           'synthetic_only': True, 'uses_private_account': False, 'headless_attempt': True,
           'official_version': '10.0.8'}
with (logs / 'headless-startup.log').open('w') as log:
    process = subprocess.Popen([str(binary), '-no-remote', '-headless', '-profile',
        str(BASE / 'profile'), '-datadir', str(BASE / 'data'), '-debug-text'],
        env=env, stdout=log, stderr=subprocess.STDOUT)
    try:
        deadline = time.monotonic() + 40
        last = None
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError(f'Zotero exited during startup: {process.returncode}')
            try:
                status, headers, data = request('GET', '/api/users/0/items?format=json&limit=100')
                last = {'status': status, 'headers': headers, 'body': data}
                if status == 200:
                    break
            except (OSError, http.client.HTTPException) as error:
                last = str(error)
            time.sleep(.5)
        else:
            raise TimeoutError(f'Local API did not initialize: {last}')
        receipt['initial_catalog'] = last
        items = [
            {'itemType': 'book', 'title': f'Synthetic Native Fidelity {name}',
             'creators': [{'creatorType':'author', 'firstName': first, 'lastName': surname}],
             'date': str(year), 'publisher':'Acceptance Test Publisher',
             'tags':[{'tag':'fidelity-acceptance'}], 'attachments': []}
            for name,first,surname,year in [
                ('Alpha','Anna','Beispiel',2024), ('Beta','Bert','Muster',2023),
                ('Gamma','Carla','Probe',2022)]
        ]
        status, headers, data = request('POST', '/connector/saveItems',
            {'sessionID':'quds-fidelity-20261116-fixture', 'uri':'https://example.invalid/synthetic-fixture',
             'items':items})
        receipt['save_items'] = {'status':status, 'headers':headers, 'body':data}
        if status not in (200,201):
            raise RuntimeError(f'Synthetic fixture save failed: {status}: {data}')
        deadline = time.monotonic()+10
        while time.monotonic()<deadline:
            status, headers, data=request('GET','/api/users/0/items?format=json&limit=100')
            if status==200 and len(json.loads(data))>=3:
                break
            time.sleep(.5)
        receipt['catalog_after_seed']={'status':status,'headers':headers,'body':data}
        if status!=200 or len(json.loads(data))!=3:
            raise RuntimeError('The isolated catalog does not contain exactly three synthetic items')
        receipt['result']='passed'
    except Exception as error:
        receipt['result']='failed'
        receipt['error']=str(error)
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        receipt['process_exit']=process.returncode
        (logs/'headless-bootstrap-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
        print(json.dumps({'result':receipt['result'],'error':receipt.get('error'),'process_exit':process.returncode}))
        if receipt['result']!='passed':
            raise SystemExit(1)
