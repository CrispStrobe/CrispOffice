#!/usr/bin/env python3
"""Exercise the compiled editor after verified installation and server shutdown.

A passing receipt requires an offline reload and fresh-tab lookup with cold
Dart provider caches. This fixture's worker is test infrastructure; it does not
qualify a production site's install/update implementation.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import http.server
import json
import math
import os
from pathlib import Path
import platform
import re
import socket
import threading
from urllib.parse import urlparse

from install_offline import CACHE_PREFIX, validate_installation

CSP = ("default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; "
       "worker-src 'self' blob:; connect-src 'self'; "
       "img-src 'self' data: blob:; style-src 'self' 'unsafe-inline'; "
       "font-src 'self' data:; object-src 'none'; base-uri 'self'")
QUERIES = [
    ('bank', 'en-US'), ('run', 'en-US'), ('happy', 'en-GB'),
    ('ice cream', 'en-US'), ('children', 'en-US'), ('dogs', 'en-US'),
    ('Bank', 'de-DE'), ('Häusern', 'de-DE'), ('Maße', 'de-DE'),
    ('Masse', 'de-DE'), ('sich freuen', 'de-DE'), ('Straße', 'de-CH'),
    ('qudsxyzzynotaword', 'en-US'), ('qudsxyzzynotaword', 'de-DE'),
    ('banque', 'fr-FR'),
]


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


class LocalBuildServer:
    """Own the origin, log all HTTP requests, and close its listening socket."""

    def __init__(self, root):
        owner = self
        self.requests = []
        self.stopped = False

        class Handler(http.server.SimpleHTTPRequestHandler):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, directory=str(root), **kwargs)

            def log_message(self, fmt, *args):
                pass

            def do_GET(self):
                owner.requests.append({'method': 'GET', 'path': self.path,
                                       'after_shutdown': owner.stopped})
                super().do_GET()

            def do_HEAD(self):
                owner.requests.append({'method': 'HEAD', 'path': self.path,
                                       'after_shutdown': owner.stopped})
                super().do_HEAD()

            def end_headers(self):
                self.send_header('Content-Security-Policy', CSP)
                self.send_header('Cache-Control', 'no-store')
                super().end_headers()

        self.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(
            target=lambda: self.server.serve_forever(poll_interval=0.05), daemon=True)
        self.thread.start()
        self.origin = f'http://127.0.0.1:{self.server.server_port}'

    def stop(self):
        if not self.stopped:
            self.server.shutdown()
            self.server.server_close()
            self.thread.join(timeout=2)
            require(not self.thread.is_alive(), 'Local HTTP server did not stop')
            self.stopped = True
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            probe.settimeout(1)
            error = probe.connect_ex(('127.0.0.1', self.server.server_port))
        require(error != 0, 'Local HTTP origin is still reachable after shutdown')
        return {'socket_connect_errno': error, 'served_requests': len(self.requests)}


def expected_packs(build):
    base = build / 'assets/packages/quds_office_editor/assets/thesaurus'
    packs = {}
    for locale in ('en', 'de'):
        manifest_bytes = (base / locale / 'manifest.json').read_bytes()
        manifest = json.loads(manifest_bytes)
        notices = {}
        for path in manifest['noticePaths']:
            value = (base / locale / path).read_bytes()
            metadata = manifest['files'][path]
            require(len(value) == metadata['size'] and sha256(value) == metadata['sha256'],
                    f'Compiled notice does not match manifest: {locale}/{path}')
            notices[path] = {'text': value.decode('utf-8'), 'sha256': sha256(value)}
        require(notices, f'Compiled pack has no notices: {locale}')
        packs[locale] = {'identity': manifest['packId'] + ':' + sha256(manifest_bytes),
                         'notices': notices}
    return packs


def validate_panel(panel, packs):
    queries = panel['queries']
    require([(q['text'], q['language']) for q in queries] == QUERIES,
            'Query panel is incomplete or changed its declared cases')
    for entry in queries:
        expected = ('unsupportedLanguage' if entry['language'] == 'fr-FR' else
                    'noEntry' if entry['text'].startswith('qudsxyz') else 'ready')
        require(entry['status'] == expected, f'Unexpected lookup outcome: {entry}')
        if expected != 'unsupportedLanguage':
            locale = entry['language'].split('-')[0]
            require(entry['pack'] == packs[locale]['identity'], 'Lookup used a different pack')
    by_text = {entry['text']: entry for entry in queries}
    require(len(by_text['bank']['senses']) > 1, 'English polysemy was lost')
    require(len(by_text['Bank']['senses']) > 1, 'German polysemy was lost')
    require({s['id'] for s in by_text['Maße']['senses']} !=
            {s['id'] for s in by_text['Masse']['senses']}, 'German sharp-s distinction was lost')
    require(any(m['text'] == 'Haus' for m in by_text['Häusern']['matches']),
            'Qualified German noun fallback did not run')
    notices = panel['notices']
    require([record['locale'] for record in notices] == ['en', 'de'],
            'Both source-notice sets must be verified')
    for record in notices:
        expected = packs[record['locale']]
        require(record['pack'] == expected['identity'], 'Notices refer to another pack')
        actual = record['notices']
        require([notice['path'] for notice in actual] == list(expected['notices']),
                'Notice set is incomplete or reordered')
        for notice in actual:
            require(sha256(notice['text'].encode('utf-8')) ==
                    expected['notices'][notice['path']]['sha256'],
                    'Verified browser notice bytes differ from the compiled pack')
    require(panel['warm_mode'] == 'result-cache', 'Warm measurements must identify cache mode')
    require(len(panel['warm_ms']) == len(QUERIES) * 5, 'Incomplete warm-query panel')
    require(all(isinstance(value, (int, float)) and math.isfinite(value) and value >= 0
                for value in panel['warm_ms']), 'Invalid query timings')
    require(0 <= panel['cached_shards'] <= panel['cache_limits']['shards'],
            'Shard cache exceeded its bound')
    require(0 <= panel['cached_results'] <= panel['cache_limits']['results'],
            'Result cache exceeded its bound')


def state(page):
    return page.evaluate('JSON.parse(window.qudsSmokeState)')


def wait_ready(page, identity, count):
    page.wait_for_function(
        'window.qudsOfflineInstallation?.ready || window.qudsOfflineInstallation?.error',
        timeout=120000)
    installation = page.evaluate('window.qudsOfflineInstallation')
    require(installation.get('ready'), f'Offline installation failed: {installation}')
    require(installation['cacheName'] == CACHE_PREFIX + identity,
            'Page is controlled by a stale offline cache')
    require(installation['fileCount'] == installation['expectedFileCount'] == count,
            'Offline cache inventory is incomplete')
    page.wait_for_function(
        'window.qudsSmokeState && JSON.parse(window.qudsSmokeState).ready',
        timeout=120000)
    ready = state(page)
    require(ready['sharedCache'] == {'shards': 0, 'results': 0},
            'Fresh page did not start with cold thesaurus provider caches')
    require(ready['semanticsEnabled'], 'Browser accessibility fixture did not start')
    return ready, installation


def reveal_text(page, text, *, exact=True):
    """Scroll actual content so a lazy Flutter ListView can create the target."""
    locator = page.get_by_text(text, exact=exact).first
    for _ in range(60):
        if locator.count() and locator.is_visible():
            locator.scroll_into_view_if_needed()
            return locator
        viewport = page.viewport_size
        page.mouse.move(viewport['width'] * 0.5, viewport['height'] * 0.62)
        page.mouse.wheel(0, 440)
        page.wait_for_timeout(80)
    raise AssertionError(f'Could not reveal lazy dialog text: {text!r}')


def open_sample(page, language, source):
    revision = state(page)['sampleRevision']
    page.get_by_role('button', name=language + ' sample', exact=True).click()
    page.wait_for_function(
        '(before) => JSON.parse(window.qudsSmokeState).sampleRevision > before', arg=revision)
    ready = state(page)
    require(ready['document'] == source and not ready['canUndo'] and not ready['canRedo'],
            'Sample did not start from an unchanged document')
    page.keyboard.press('Shift+F7')
    page.get_by_text(re.compile(r'\d+ meaning groups?')).first.wait_for(timeout=120000)
    require(state(page)['document'] == source, 'Opening thesaurus modified the document')


def verify_sources(page, pack):
    page.get_by_role('button', name='Sources and licenses', exact=True).click()
    page.get_by_text('Thesaurus sources and licenses', exact=True).wait_for()
    names = [Path(path).name for path in pack['notices']]
    # These titles only materialize after service.notices has verified every file.
    for name in names:
        reveal_text(page, name).wait_for()
    # Return to the top of the scrollable sources dialog and expand attribution.
    viewport = page.viewport_size
    page.mouse.move(viewport['width'] * 0.5, viewport['height'] * 0.5)
    page.mouse.wheel(0, -100000)
    page.wait_for_timeout(100)
    reveal_text(page, names[0]).click()
    attribution = next(iter(pack['notices'].values()))['text']
    page.get_by_text(attribution, exact=True).first.wait_for()
    require(page.get_by_text('The bundled notices could not be verified.',
                             exact=False).count() == 0, 'Sources failed verification')
    page.get_by_role('button', name='Close sources', exact=True).click()
    return names


def exercise_replacement(page, source, replacement):
    reveal_text(page, replacement).click()
    require(state(page)['document'] == source and not state(page)['canUndo'],
            'Selecting an alternative changed the source or undo history')
    page.get_by_role('button', name='Replace', exact=True).click()
    page.wait_for_function('(text) => JSON.parse(window.qudsSmokeState).document === text',
                           arg=replacement)
    require(state(page)['canUndo'] and not state(page)['canRedo'],
            'Replacement did not create the expected history state')
    page.get_by_role('button', name='Close', exact=True).click()
    page.get_by_role('button', name='Undo', exact=True).click()
    page.wait_for_function('(text) => JSON.parse(window.qudsSmokeState).document === text',
                           arg=source)
    require(not state(page)['canUndo'] and state(page)['canRedo'],
            'Replacement was not one undo unit')
    page.get_by_role('button', name='Redo', exact=True).click()
    page.wait_for_function('(text) => JSON.parse(window.qudsSmokeState).document === text',
                           arg=replacement)
    require(state(page)['canUndo'] and not state(page)['canRedo'],
            'Redo did not restore the replacement')
    # Leave the source in place so the subsequent panel can prove it is read-only.
    page.get_by_role('button', name='Undo', exact=True).click()
    page.wait_for_function('(text) => JSON.parse(window.qudsSmokeState).document === text',
                           arg=source)
    return state(page)


def run_panel(page, packs):
    before = state(page)
    page.get_by_role('button', name='Run query panel', exact=True).click()
    page.wait_for_function(
        'JSON.parse(window.qudsSmokeState).panel || JSON.parse(window.qudsSmokeState).failure',
        timeout=180000)
    final = state(page)
    require(final['failure'] is None, final['failure'])
    require((final['document'], final['canUndo'], final['canRedo']) ==
            (before['document'], before['canUndo'], before['canRedo']),
            'Lookup panel modified the document or undo history')
    validate_panel(final['panel'], packs)
    return final


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--browser-executable', default='/usr/bin/chromium')
    parser.add_argument('--probe-only', action='store_true')
    args = parser.parse_args()
    root, output = args.build.resolve(), args.output.resolve()
    require(output != root and root not in output.parents,
            'Evidence output must be outside the immutable browser build')
    if (output / 'browser-report.json').exists():
        parser.error('The output already contains a receipt; choose an unused --output directory.')
    output.mkdir(parents=True, exist_ok=True)
    temporary = output / 'tmp'
    temporary.mkdir(exist_ok=True)
    os.environ['TMPDIR'] = str(temporary)
    report = {'started_at_utc': datetime.now(timezone.utc).isoformat(),
              'platform': platform.platform(), 'machine': platform.machine(),
              'browser_executable': args.browser_executable,
              'scope': 'compiled editor with a test-only verified offline installer',
              'content_security_policy': CSP, 'steps': [], 'requests': [],
              'console': [], 'page_errors': [], 'csp_violations': []}
    server = None
    offline = False

    def record(name, **values):
        step = dict(name=name, **values)
        report['steps'].append(step)
        print(json.dumps(step, ensure_ascii=False), flush=True)

    try:
        records, identity = validate_installation(root)
        packs = expected_packs(root)
        report['cache_identity'] = identity
        report['build_files'] = len(records)
        report['build_bytes'] = sum(item['bytes'] for item in records)
        report['fixture_inputs'] = {
            name: sha256((Path(__file__).parent / name).read_bytes())
            for name in ('run_browser.py', 'install_offline.py', 'lib/main.dart',
                         'run_final_validation.py', 'test_browser_harness.py')}
        (output / 'installed-build-files.json').write_text(json.dumps(records, indent=2) + '\n')
        from playwright.sync_api import sync_playwright

        server = LocalBuildServer(root)
        origin = server.origin
        report['origin'] = origin
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(
                executable_path=args.browser_executable, headless=True,
                args=['--no-sandbox', '--disable-dev-shm-usage'])
            report['browser_version'] = browser.version
            context = browser.new_context(
                viewport={'width': 1280, 'height': 960},
                service_workers='allow', device_scale_factor=1)
            context.add_init_script('''
              window.qudsCspViolations = [];
              document.addEventListener('securitypolicyviolation', event => {
                window.qudsCspViolations.push({directive: event.effectiveDirective,
                  blockedURI: event.blockedURI, disposition: event.disposition});
              });
            ''')
            context.on('request', lambda request: report['requests'].append(
                {'url': request.url, 'method': request.method, 'offline': offline,
                 'service_worker': bool(getattr(request, 'service_worker', None))}))
            context.route(re.compile(r'^https?://'), lambda route: (
                route.continue_() if urlparse(route.request.url).netloc ==
                urlparse(origin).netloc else route.abort()))
            pages = []

            def new_page():
                page = context.new_page()
                page.set_default_timeout(20000)
                page.on('console', lambda message: report['console'].append(
                    {'type': message.type, 'text': message.text}))
                page.on('pageerror', lambda error: report['page_errors'].append(str(error)))
                pages.append(page)
                return page

            page = new_page()
            page.goto(origin, wait_until='domcontentloaded')
            initial, installed = wait_ready(page, identity, len(records))
            record('verified_local_installation', state=initial, installation=installed)
            context.set_offline(True)
            offline = True
            report['offline_enabled'] = True
            report['origin_shutdown'] = server.stop()
            request_boundary = len(server.requests)
            record('network_disabled_and_origin_stopped', **report['origin_shutdown'])

            # Throw away all Dart/Flutter state and demand cached application startup.
            report['csp_violations'].extend(page.evaluate('window.qudsCspViolations'))
            page.reload(wait_until='domcontentloaded')
            reloaded, installed = wait_ready(page, identity, len(records))
            require(reloaded['session'] != initial['session'],
                    'Offline reload did not create a fresh fixture instance')
            record('offline_reload_with_cold_provider', state=reloaded, installation=installed)
            open_sample(page, 'English', 'bank')
            page.screenshot(path=str(output / 'english-offline.png'))
            record('english_shortcut_opened_without_origin', document=state(page)['document'])
            if args.probe_only:
                report['status'] = 'probe-ready'
                report['final_state'] = state(page)
            else:
                names = verify_sources(page, packs['en'])
                record('english_source_notices_verified_and_rendered', files=names)
                result = exercise_replacement(page, 'bank', 'depository financial institution')
                record('english_explicit_replacement_single_undo_redo', state=result)
                open_sample(page, 'German', 'Bank')
                page.screenshot(path=str(output / 'german-offline.png'))
                names = verify_sources(page, packs['de'])
                record('german_source_notices_verified_and_rendered', files=names)
                result = exercise_replacement(page, 'Bank', 'Geldinstitut')
                record('german_explicit_replacement_single_undo_redo', state=result)
                final = run_panel(page, packs)
                report['final_state'] = final
                record('offline_query_and_notice_panel', cases=len(final['panel']['queries']),
                       warm_mode=final['panel']['warm_mode'],
                       warm_p50_ms=final['panel']['warm_p50_ms'],
                       warm_p95_ms=final['panel']['warm_p95_ms'])

                fresh = new_page()
                fresh.goto(origin, wait_until='domcontentloaded')
                fresh_state, installed = wait_ready(fresh, identity, len(records))
                require(fresh_state['session'] not in {initial['session'], reloaded['session']},
                        'New tab reused an old fixture instance')
                report['fresh_tab_state'] = run_panel(fresh, packs)
                record('fresh_tab_offline_query_and_notice_panel',
                       session=fresh_state['session'], cases=len(QUERIES),
                       installation=installed)
                report['browser_memory'] = fresh.evaluate(
                    'performance.memory ? {usedJSHeapSize:performance.memory.usedJSHeapSize,'
                    'totalJSHeapSize:performance.memory.totalJSHeapSize,'
                    'jsHeapSizeLimit:performance.memory.jsHeapSizeLimit} : null')
                report['status'] = 'passed'

            for observed in pages:
                report['csp_violations'].extend(observed.evaluate('window.qudsCspViolations'))
            require(not report['csp_violations'], 'Browser reported CSP violations')
            report['external_requests'] = [
                request for request in report['requests']
                if urlparse(request['url']).scheme in ('http', 'https') and
                urlparse(request['url']).netloc != urlparse(origin).netloc]
            require(not report['external_requests'], 'Browser attempted an external HTTP request')
            require(not report['page_errors'], 'Browser reported page errors')
            require(len(server.requests) == request_boundary,
                    'Origin served a request during offline acceptance')
            report['server_requests_after_shutdown'] = len(server.requests) - request_boundary
            after, after_identity = validate_installation(root)
            require(after == records and after_identity == identity,
                    'Compiled build changed during acceptance')
            report['build_unchanged_during_acceptance'] = True
            browser.close()
    except BaseException as error:
        report['status'] = 'failed'
        report['error'] = repr(error)
        raise
    finally:
        try:
            if server is not None:
                server.stop()
                report['server_requests'] = server.requests
        except BaseException as error:
            report['status'] = 'failed'
            report['shutdown_error'] = repr(error)
            raise
        finally:
            report['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
            (output / 'browser-report.json').write_text(
                json.dumps(report, indent=2, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
