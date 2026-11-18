#!/usr/bin/env python3
"""Exercise the actual compiled Quds editor with a completely offline browser."""
import argparse
from datetime import datetime, timezone
import hashlib
import http.server
import json
import os
import platform
import re
import threading
import time
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument('build', type=Path)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--probe-only', action='store_true')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
temporary = args.output.resolve() / 'tmp'
temporary.mkdir(exist_ok=True)
os.environ['TMPDIR'] = str(temporary)
root = args.build.resolve()
report = {'started_at_utc': datetime.now(timezone.utc).isoformat(),
          'platform': platform.platform(), 'machine': platform.machine(),
          'browser_executable': '/usr/bin/chromium', 'steps': [],
          'requests': [], 'console': [], 'page_errors': []}
csp = ("default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; "
       "worker-src 'self' blob:; connect-src 'self'; "
       "img-src 'self' data: blob:; style-src 'self' 'unsafe-inline'; "
       "font-src 'self' data:; object-src 'none'; base-uri 'self'")
report['content_security_policy'] = csp

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=str(root), **k)

    def log_message(self, fmt, *a):
        pass

    def end_headers(self):
        self.send_header('Content-Security-Policy', csp)
        super().end_headers()

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
origin = f'http://127.0.0.1:{server.server_port}'
report['origin'] = origin

def record(name, **values):
    step = dict(name=name, **values)
    report['steps'].append(step)
    print(json.dumps(step), flush=True)

def state(page):
    return page.evaluate('JSON.parse(window.qudsSmokeState)')

def save_report():
    (args.output / 'browser-report.json').write_text(json.dumps(report, indent=2,
                                                              ensure_ascii=False) + '\n')

try:
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path='/usr/bin/chromium', headless=True,
                                   args=['--no-sandbox', '--disable-dev-shm-usage'])
        report['browser_version'] = browser.version
        context = browser.new_context(viewport={'width': 1280, 'height': 960},
                                      service_workers='allow', device_scale_factor=1)
        page = context.new_page()
        page.set_default_timeout(20000)
        offline = False
        page.on('request', lambda r: report['requests'].append(
            {'url': r.url, 'method': r.method, 'offline': offline}))
        page.on('console', lambda m: report['console'].append(
            {'type': m.type, 'text': m.text}))
        page.on('pageerror', lambda e: report['page_errors'].append(str(e)))
        context.route(re.compile(r'^https?://'), lambda route: (
            route.continue_() if urlparse(route.request.url).netloc ==
            urlparse(origin).netloc else route.abort()))
        page.goto(origin, wait_until='domcontentloaded')
        page.wait_for_function('window.qudsSmokeState && JSON.parse(window.qudsSmokeState).ready',
                               timeout=120000)
        page.wait_for_function('window.qudsOfflineInstallation?.ready === true', timeout=120000)
        record('local_app_and_packs_installed', state=state(page),
               cache=page.evaluate('caches.keys()'))
        context.set_offline(True)
        offline = True
        report['offline_enabled'] = True
        record('browser_network_disabled')
        page.get_by_role('button', name='English sample', exact=True).click()
        page.keyboard.press('Shift+F7')
        page.get_by_text(re.compile(r'\d+ meaning groups?')).first.wait_for(timeout=120000)
        report['english_dialog_semantics'] = page.locator('flt-semantics-host').inner_text()
        page.screenshot(path=str(args.output / 'english-offline.png'))
        record('english_shortcut_opened_without_network', document=state(page)['document'])
        if args.probe_only:
            report['probe'] = True
            report['final_state'] = state(page)
            report['status'] = 'probe-ready'
        else:
            candidate = page.get_by_text('depository financial institution', exact=True).first
            candidate.scroll_into_view_if_needed()
            candidate.click()
            assert state(page)['document'] == 'bank'
            page.get_by_role('button', name='Replace', exact=True).click()
            page.wait_for_function("JSON.parse(window.qudsSmokeState).document === 'depository financial institution'")
            record('english_replacement', state=state(page))
            page.get_by_role('button', name='Close', exact=True).click()
            page.get_by_role('button', name='Undo', exact=True).click()
            page.wait_for_function("JSON.parse(window.qudsSmokeState).document === 'bank'")
            assert not state(page)['canUndo']
            page.get_by_role('button', name='Redo', exact=True).click()
            page.wait_for_function("JSON.parse(window.qudsSmokeState).document === 'depository financial institution'")
            record('single_undo_redo_restored_source', state=state(page))
            page.get_by_role('button', name='German sample', exact=True).click()
            page.keyboard.press('Shift+F7')
            page.get_by_text(re.compile(r'\d+ meaning groups?')).first.wait_for(timeout=120000)
            page.screenshot(path=str(args.output / 'german-offline.png'))
            report['german_dialog_semantics'] = page.locator('flt-semantics-host').inner_text()
            record('german_cold_dialog_without_network', document=state(page)['document'])
            page.get_by_role('button', name='Sources and licenses', exact=True).click()
            page.get_by_text('Thesaurus sources and licenses', exact=True).wait_for()
            page.get_by_text('Close sources', exact=True).wait_for()
            page.screenshot(path=str(args.output / 'german-sources-offline.png'))
            report['source_semantics'] = page.locator('flt-semantics-host').inner_text()
            page.get_by_role('button', name='Close sources', exact=True).click()
            page.get_by_role('button', name='Close', exact=True).click()
            page.get_by_role('button', name='Run query panel', exact=True).click()
            page.wait_for_function('JSON.parse(window.qudsSmokeState).panel || JSON.parse(window.qudsSmokeState).failure',
                                   timeout=180000)
            final = state(page)
            assert final['failure'] is None, final['failure']
            assert final['document'] == 'Bank'
            results = final['panel']['queries']
            for entry in results:
                if entry['language'] == 'fr-FR':
                    assert entry['status'] == 'unsupportedLanguage', entry
                elif entry['text'].startswith('qudsxyz'):
                    assert entry['status'] == 'noEntry', entry
                else:
                    assert entry['status'] == 'ready', entry
            assert len(next(x for x in results if x['text'] == 'bank')['senses']) > 1
            assert len(next(x for x in results if x['text'] == 'Bank')['senses']) > 1
            assert (set(s['id'] for s in next(x for x in results if x['text'] == 'Maße')['senses']) !=
                    set(s['id'] for s in next(x for x in results if x['text'] == 'Masse')['senses']))
            report['final_state'] = final
            report['browser_memory'] = page.evaluate('performance.memory ? {usedJSHeapSize:performance.memory.usedJSHeapSize,totalJSHeapSize:performance.memory.totalJSHeapSize,jsHeapSizeLimit:performance.memory.jsHeapSizeLimit} : null')
            record('offline_query_panel', cases=len(results),
                   warm_p50_ms=final['panel']['warm_p50_ms'], warm_p95_ms=final['panel']['warm_p95_ms'])
            report['status'] = 'passed'
        report['external_requests'] = [r for r in report['requests'] if
                                       urlparse(r['url']).scheme in ('http','https') and
                                       urlparse(r['url']).netloc != urlparse(origin).netloc]
        assert not report['external_requests'], report['external_requests']
        assert not report['page_errors'], report['page_errors']
        browser.close()
except BaseException as error:
    report['status'] = 'failed'
    report['error'] = repr(error)
    raise
finally:
    report['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
    save_report()
    server.shutdown()
