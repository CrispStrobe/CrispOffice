#!/usr/bin/env python3
"""Local harness controls. These tests do not execute Flutter or a browser."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from urllib.request import urlopen

import install_offline
import run_browser


class OfflineFixtureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=Path.cwd())
        self.root = Path(self.temporary.name)
        for name in ('index.html', 'flutter_bootstrap.js', 'main.dart.js'):
            (self.root / name).write_text('fixture ' + name)
        (self.root / 'assets').mkdir()
        (self.root / 'assets/data.bin').write_bytes(bytes(range(256)))
        self.original_asset = (self.root / 'assets/data.bin').read_bytes()

    def tearDown(self):
        self.temporary.cleanup()

    def test_inventory_is_repeatable_and_preserves_compiled_assets(self):
        first = install_offline.prepare(self.root)
        records, identity = install_offline.validate_installation(self.root)
        self.assertEqual(identity, first['cache_identity'])
        self.assertEqual(len(records), first['files'])
        self.assertEqual(install_offline.prepare(self.root), first)
        self.assertEqual((self.root / 'assets/data.bin').read_bytes(), self.original_asset)

    def test_changed_missing_and_unlisted_build_assets_are_rejected(self):
        install_offline.prepare(self.root)
        asset = self.root / 'assets/data.bin'
        for mutation in ('change', 'remove', 'extra'):
            with self.subTest(mutation=mutation):
                if mutation == 'change':
                    asset.write_bytes(b'changed')
                elif mutation == 'remove':
                    asset.unlink()
                else:
                    (self.root / 'unexpected.txt').write_text('new')
                with self.assertRaisesRegex(ValueError, 'Build changed'):
                    install_offline.validate_installation(self.root)
                asset.write_bytes(self.original_asset)
                (self.root / 'unexpected.txt').unlink(missing_ok=True)

    def test_changed_worker_is_rejected_even_with_unchanged_assets(self):
        install_offline.prepare(self.root)
        worker = self.root / 'offline-test-worker.js'
        worker.write_text(worker.read_text() + '\n// changed\n')
        with self.assertRaisesRegex(ValueError, 'worker does not match'):
            install_offline.validate_installation(self.root)

    def test_incomplete_build_and_symbolic_links_are_rejected_before_writing(self):
        index = (self.root / 'index.html').read_bytes()
        (self.root / 'main.dart.js').unlink()
        with self.assertRaisesRegex(ValueError, 'missing main.dart.js'):
            install_offline.prepare(self.root)
        self.assertEqual((self.root / 'index.html').read_bytes(), index)
        (self.root / 'main.dart.js').write_text('restored')
        (self.root / 'linked.js').symlink_to(self.root / 'main.dart.js')
        with self.assertRaisesRegex(ValueError, 'symbolic link'):
            install_offline.prepare(self.root)
        self.assertEqual((self.root / 'index.html').read_bytes(), index)

    def test_http_origin_serves_csp_then_really_closes(self):
        server = run_browser.LocalBuildServer(self.root)
        try:
            with urlopen(server.origin + '/assets/data.bin', timeout=3) as response:
                self.assertEqual(response.read(), self.original_asset)
                self.assertEqual(response.headers['Content-Security-Policy'], run_browser.CSP)
                self.assertEqual(response.headers['Cache-Control'], 'no-store')
            stopped = server.stop()
            self.assertNotEqual(stopped['socket_connect_errno'], 0)
            self.assertEqual(server.requests, [
                {'method': 'GET', 'path': '/assets/data.bin', 'after_shutdown': False}])
        finally:
            server.stop()

    @unittest.skipUnless(shutil.which('node'), 'Node is required for generated-worker control tests')
    def test_generated_worker_checks_bytes_cache_scope_and_offline_fetch(self):
        install_offline.prepare(self.root)
        records, identity = install_offline.validate_installation(self.root)
        assets = {record['path']: list((self.root / record['path']).read_bytes())
                  for record in records}
        worker = (self.root / 'offline-test-worker.js').read_text()
        harness = r'''
import vm from 'node:vm';
import {webcrypto} from 'node:crypto';
const input = INPUT;
async function makeWorker(tamper) {
  const callbacks = {}, stores = new Map(), origin = 'http://localhost:8123';
  const key = value => new URL(typeof value === 'string' ? value : value.url || value.href, origin).href;
  function makeCache() {
    const entries = new Map();
    return {entries, async put(url, response) { entries.set(key(url), response.clone()); },
      async keys() { return [...entries.keys()]; },
      async match(url, options) {
        let wanted = key(url);
        if (options?.ignoreSearch) wanted = wanted.split('?')[0];
        for (const [stored, response] of entries) {
          if ((options?.ignoreSearch ? stored.split('?')[0] : stored) === wanted) return response.clone();
        }
      }};
  }
  const caches = {async open(name) {
      if (!stores.has(name)) stores.set(name, makeCache());
      return stores.get(name);
    }, async keys() { return [...stores.keys()]; },
    async delete(name) { return stores.delete(name); }};
  let online = true, skipped = false, claimed = false;
  const fetches = [];
  const fetch = async url => {
    fetches.push(String(url));
    if (!online) throw Error('Origin is stopped');
    const path = new URL(key(url)).pathname.slice(1);
    let bytes = input.assets[path];
    if (!bytes) return new Response('', {status: 404});
    bytes = [...bytes];
    if (tamper && path === 'assets/data.bin') bytes[0] ^= 1;
    return new Response(new Uint8Array(bytes), {status: 200});
  };
  const context = {caches, fetch, crypto: webcrypto, URL, Uint8Array,
    clients: {async claim() {claimed = true;}},
    self: {location: {origin}, addEventListener(name, callback) {callbacks[name] = callback;},
      async skipWaiting() {skipped = true;}}};
  vm.runInNewContext(input.worker, context);
  async function event(name, extra = {}) {
    let promise;
    callbacks[name]({waitUntil(value) {promise = value;},
      respondWith(value) {promise = value;}, ...extra});
    return promise === undefined ? null : await promise;
  }
  return {event, stores, caches, fetches, stop() {online = false;},
    get skipped() {return skipped;}, get claimed() {return claimed;}, origin};
}
const clean = await makeWorker(false);
await clean.caches.open('unrelated-application-cache');
await clean.caches.open('quds-thesaurus-test-old');
await clean.event('install');
await clean.event('activate');
let status;
await clean.event('message', {data: {type: 'quds-offline-status'},
  ports: [{postMessage(value) {status = value;}}]});
clean.stop();
const fetchesBefore = clean.fetches.length;
const index = await clean.event('fetch', {request: new Request(clean.origin + '/')});
const data = await clean.event('fetch', {request: new Request(clean.origin + '/assets/data.bin?v=2')});
const offlineFetches = clean.fetches.length - fetchesBefore;
const unrelated = await clean.event('fetch', {request: new Request('https://example.invalid/external')});
let missingFailed = false;
try { await clean.event('fetch', {request: new Request(clean.origin + '/missing')}); }
catch (error) { missingFailed = error.message === 'Origin is stopped'; }
const damaged = await makeWorker(true);
let rejected = false;
try { await damaged.event('install'); }
catch (error) {rejected = /digest mismatch/.test(error.message); }
const cacheName = 'quds-thesaurus-test-' + input.identity;
clean.stores.get(cacheName).entries.delete(clean.origin + '/assets/data.bin');
let incomplete;
await clean.event('message', {data: {type: 'quds-offline-status'},
  ports: [{postMessage(value) {incomplete = value;}}]});
console.log(JSON.stringify({status, incomplete, skipped: clean.skipped, claimed: clean.claimed,
  cacheNames: [...clean.stores.keys()], index: await index.text(),
  bytes: [...new Uint8Array(await data.arrayBuffer())], offlineFetches, unrelated,
  missingFailed, rejected, damagedCaches: [...damaged.stores.keys()]}));
'''
        harness = harness.replace('INPUT', json.dumps(
            {'assets': assets, 'worker': worker, 'identity': identity}), 1)
        result = subprocess.run(
            [shutil.which('node'), '--input-type=module'], input=harness,
            text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        observed = json.loads(result.stdout)
        self.assertTrue(observed['status']['ready'])
        self.assertEqual(observed['status']['fileCount'], len(records))
        self.assertTrue(observed['skipped'] and observed['claimed'])
        self.assertEqual(set(observed['cacheNames']),
                         {'unrelated-application-cache', install_offline.CACHE_PREFIX + identity})
        self.assertEqual(observed['index'], install_offline.INDEX)
        self.assertEqual(bytes(observed['bytes']), self.original_asset)
        self.assertEqual(observed['offlineFetches'], 0)
        self.assertIsNone(observed['unrelated'])
        self.assertTrue(observed['missingFailed'])
        self.assertTrue(observed['rejected'])
        self.assertEqual(observed['damagedCaches'], [])
        self.assertFalse(observed['incomplete']['ready'])


class PanelReceiptTests(unittest.TestCase):
    def setUp(self):
        self.packs = {
            locale: {'identity': locale + ':fixture',
                     'notices': {'notices/LICENSE.txt':
                                 {'text': locale + ' notice',
                                  'sha256': run_browser.sha256((locale + ' notice').encode())}}}
            for locale in ('en', 'de')}
        queries = []
        for word, language in run_browser.QUERIES:
            unsupported = language == 'fr-FR'
            negative = word.startswith('qudsxyz')
            queries.append({'text': word, 'language': language,
                            'status': 'unsupportedLanguage' if unsupported else
                                      'noEntry' if negative else 'ready',
                            'pack': None if unsupported else language[:2] + ':fixture',
                            'senses': [] if unsupported or negative else
                                      [{'id': word + ':1'}, {'id': word + ':2'}],
                            'matches': [{'text': 'Haus'}] if word == 'Häusern' else []})
        self.panel = {'queries': queries, 'notices': [
            {'locale': locale, 'pack': pack['identity'],
             'notices': [{'path': path, 'text': notice['text']}
                         for path, notice in pack['notices'].items()]}
            for locale, pack in self.packs.items()],
            'warm_mode': 'result-cache', 'warm_ms': [0.01] * 75,
            'cached_shards': 64, 'cached_results': 14,
            'cache_limits': {'shards': 64, 'results': 64}}

    def test_complete_declared_panel_is_accepted(self):
        run_browser.validate_panel(self.panel, self.packs)

    def test_missing_cases_wrong_status_or_pack_cannot_pass(self):
        for mutation in ('case', 'status', 'pack'):
            with self.subTest(mutation=mutation):
                panel = copy.deepcopy(self.panel)
                if mutation == 'case':
                    panel['queries'].pop()
                elif mutation == 'status':
                    panel['queries'][0]['status'] = 'failedPack'
                else:
                    panel['queries'][0]['pack'] = 'stale'
                with self.assertRaises(AssertionError):
                    run_browser.validate_panel(panel, self.packs)

    def test_unread_or_tampered_notices_cannot_pass(self):
        for mutation in ('missing-locale', 'missing-notice', 'bytes'):
            with self.subTest(mutation=mutation):
                panel = copy.deepcopy(self.panel)
                if mutation == 'missing-locale':
                    panel['notices'].pop()
                elif mutation == 'missing-notice':
                    panel['notices'][1]['notices'].clear()
                else:
                    panel['notices'][0]['notices'][0]['text'] += 'changed'
                with self.assertRaises(AssertionError):
                    run_browser.validate_panel(panel, self.packs)

    def test_lost_distinctions_fallback_and_cache_bounds_cannot_pass(self):
        for mutation in ('polysemy', 'sharp-s', 'lemma', 'cache', 'timing', 'mode'):
            with self.subTest(mutation=mutation):
                panel = copy.deepcopy(self.panel)
                queries = {entry['text']: entry for entry in panel['queries']}
                if mutation == 'polysemy':
                    queries['bank']['senses'] = [{'id': 'one'}]
                elif mutation == 'sharp-s':
                    queries['Maße']['senses'] = queries['Masse']['senses']
                elif mutation == 'lemma':
                    queries['Häusern']['matches'] = []
                elif mutation == 'cache':
                    panel['cached_shards'] = 65
                elif mutation == 'timing':
                    panel['warm_ms'][0] = float('nan')
                else:
                    panel['warm_mode'] = 'unknown'
                with self.assertRaises(AssertionError):
                    run_browser.validate_panel(panel, self.packs)


if __name__ == '__main__':
    unittest.main(verbosity=2)
