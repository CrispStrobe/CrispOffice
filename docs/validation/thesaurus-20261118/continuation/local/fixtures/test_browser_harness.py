#!/usr/bin/env python3
"""Local harness controls. These tests do not execute Flutter or a browser."""
import copy
import gzip
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from urllib.request import urlopen
import zlib

import build_binding
import install_offline
import run_browser


class OfflineFixtureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=Path.cwd())
        self.root = Path(self.temporary.name) / 'build'
        self.root.mkdir()
        self.evidence = Path(self.temporary.name) / 'compile-evidence'
        self.evidence.mkdir()
        self.compile_receipt = self.evidence / 'receipt.json'
        for name in ('index.html', 'flutter_bootstrap.js', 'main.dart.js'):
            (self.root / name).write_text('fixture ' + name)
        (self.root / 'flutter_bootstrap.js').write_text('_flutter.loader.load();\n')
        (self.root / 'assets').mkdir()
        (self.root / 'assets/data.bin').write_bytes(bytes(range(256)))
        self.original_asset = (self.root / 'assets/data.bin').read_bytes()
        self.write_compile_evidence()

    def write_compile_evidence(self):
        """Synthetic compiler output for negative controls; never release evidence."""
        inputs = {'__fixture__/' + name: {'sha256': build_binding.sha256(
                    (Path(__file__).parent / name).read_bytes())}
                  for name in build_binding.FIXTURE_FILES}
        inputs.update({'__helper__/' + name: {'sha256': build_binding.sha256(
                       (build_binding.repository_root() / name).read_bytes())}
                       for name in build_binding.SOURCE_HELPER_FILES})
        inputs['__workspace_binding__'] = {'schema': build_binding.WORKSPACE_SCHEMA}
        records = install_offline.file_records(self.root)
        (self.evidence / 'source-inputs.json.gz').write_bytes(gzip.compress(json.dumps(inputs).encode()))
        (self.evidence / 'browser-build-files.json.gz').write_bytes(gzip.compress(json.dumps(records).encode()))
        for name in ('stdout', 'stderr'):
            (self.evidence / name).write_bytes(b'')
        receipt = {
            'status': 'native_passed_web_compiled_browser_not_run',
            'base_commit': '0' * 40,
            'input_digest': build_binding.digest(inputs),
            'source_unchanged_during_tests': True,
            'source_unchanged_during_build': True,
            'compiled_browser_files': len(records),
            'compiled_browser_bytes': sum(record['bytes'] for record in records),
            'browser_build_binding': build_binding.binding_metadata(self.evidence),
            'runs': [{'name': 'browser-build', 'exit_code': 0,
                      'command': ['flutter', 'build', 'web', '--release', '--csp',
                                  '--no-web-resources-cdn', '--pwa-strategy=none',
                                  '--target=' + str(Path(__file__).parent / 'lib/main.dart')],
                      'stdout': 'stdout', 'stderr': 'stderr',
                      'stdout_sha256': build_binding.sha256(b''),
                      'stderr_sha256': build_binding.sha256(b'')}],
        }
        self.compile_receipt.write_text(json.dumps(receipt))

    def tearDown(self):
        self.temporary.cleanup()

    def test_inventory_is_repeatable_and_preserves_compiled_assets(self):
        first = install_offline.prepare(self.root, self.compile_receipt)
        records, identity, provenance = install_offline.validate_installation(self.root, self.compile_receipt)
        self.assertEqual(identity, first['cache_identity'])
        self.assertEqual(len(records), first['files'])
        self.assertEqual(install_offline.prepare(self.root, self.compile_receipt), first)
        self.assertEqual(provenance, first['compile_provenance'])
        self.assertEqual((self.root / 'assets/data.bin').read_bytes(), self.original_asset)

    def test_changed_missing_and_unlisted_build_assets_are_rejected(self):
        install_offline.prepare(self.root, self.compile_receipt)
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
                    install_offline.validate_installation(self.root, self.compile_receipt)
                asset.write_bytes(self.original_asset)
                (self.root / 'unexpected.txt').unlink(missing_ok=True)

    def test_changed_worker_is_rejected_even_with_unchanged_assets(self):
        install_offline.prepare(self.root, self.compile_receipt)
        worker = self.root / 'offline-test-worker.js'
        worker.write_text(worker.read_text() + '\n// changed\n')
        with self.assertRaisesRegex(ValueError, 'worker does not match'):
            install_offline.validate_installation(self.root, self.compile_receipt)

    def test_incomplete_build_and_symbolic_links_are_rejected_before_writing(self):
        index = (self.root / 'index.html').read_bytes()
        (self.root / 'main.dart.js').unlink()
        with self.assertRaisesRegex(ValueError, 'missing main.dart.js'):
            install_offline.prepare(self.root, self.compile_receipt)
        self.assertEqual((self.root / 'index.html').read_bytes(), index)
        (self.root / 'main.dart.js').write_text('restored')
        (self.root / 'linked.js').symlink_to(self.root / 'main.dart.js')
        with self.assertRaisesRegex(ValueError, 'symbolic link'):
            install_offline.prepare(self.root, self.compile_receipt)
        self.assertEqual((self.root / 'index.html').read_bytes(), index)

    def test_unrelated_build_is_rejected_before_entry_points_are_changed(self):
        index = (self.root / 'index.html').read_bytes()
        (self.root / 'main.dart.js').write_text('different compiled application')
        with self.assertRaisesRegex(ValueError, 'successful compile receipt'):
            install_offline.prepare(self.root, self.compile_receipt)
        self.assertEqual((self.root / 'index.html').read_bytes(), index)
        self.assertFalse((self.root / 'offline-install.js').exists())

    def test_resealed_installation_cannot_substitute_a_different_compiled_application(self):
        install_offline.prepare(self.root, self.compile_receipt)
        (self.root / 'main.dart.js').write_text('another application with rebuilt offline hashes')
        records = install_offline.file_records(self.root)
        identity = install_offline.cache_identity(records)
        (self.root / 'offline-files.json').write_text(json.dumps(records))
        (self.root / 'offline-test-worker.js').write_text(install_offline.worker_script(records, identity))
        with self.assertRaisesRegex(ValueError, 'successful compile receipt'):
            install_offline.validate_installation(self.root, self.compile_receipt)

    def test_failed_stale_or_inconsistent_compile_evidence_is_rejected(self):
        original = self.compile_receipt.read_text()
        for mutation in ('unfinished', 'changed-source', 'missing-pwa-setting',
                         'wrong-target', 'failed-command', 'missing-binding',
                         'inventory-total', 'source-digest'):
            with self.subTest(mutation=mutation):
                receipt = json.loads(original)
                if mutation == 'unfinished':
                    receipt['status'] = 'running'
                elif mutation == 'changed-source':
                    receipt['source_unchanged_during_build'] = False
                elif mutation == 'missing-pwa-setting':
                    receipt['runs'][0]['command'].remove('--pwa-strategy=none')
                elif mutation == 'wrong-target':
                    receipt['runs'][0]['command'][-1] = '--target=/unrelated/lib/main.dart'
                elif mutation == 'failed-command':
                    receipt['runs'][0]['exit_code'] = 1
                elif mutation == 'missing-binding':
                    receipt.pop('browser_build_binding')
                elif mutation == 'inventory-total':
                    receipt['compiled_browser_files'] += 1
                else:
                    receipt['input_digest'] = '0' * 64
                self.compile_receipt.write_text(json.dumps(receipt))
                with self.assertRaises(ValueError):
                    install_offline.prepare(self.root, self.compile_receipt)
                self.assertFalse((self.root / 'offline-install.js').exists())
        self.compile_receipt.write_text(original)

    def test_mutated_compile_members_and_stale_fixture_are_rejected(self):
        for member in ('source-inputs.json.gz', 'browser-build-files.json.gz', 'stdout', 'stderr'):
            with self.subTest(member=member):
                path = self.evidence / member
                original = path.read_bytes()
                path.write_bytes(original + b'changed')
                with self.assertRaisesRegex(ValueError, 'member hash differs'):
                    install_offline.prepare(self.root, self.compile_receipt)
                path.write_bytes(original)
        path = self.evidence / 'source-inputs.json.gz'
        inputs = json.loads(gzip.decompress(path.read_bytes()))
        inputs['__fixture__/lib/main.dart']['sha256'] = '0' * 64
        path.write_bytes(gzip.compress(json.dumps(inputs).encode()))
        receipt = json.loads(self.compile_receipt.read_text())
        receipt['input_digest'] = build_binding.digest(inputs)
        receipt['browser_build_binding'] = build_binding.binding_metadata(self.evidence)
        self.compile_receipt.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(ValueError, 'different acceptance fixture'):
            install_offline.prepare(self.root, self.compile_receipt)

    def test_unverified_workspace_and_changed_source_helpers_are_rejected(self):
        for mutation in ('workspace', 'helper'):
            with self.subTest(mutation=mutation):
                self.write_compile_evidence()
                path = self.evidence / 'source-inputs.json.gz'
                inputs = json.loads(gzip.decompress(path.read_bytes()))
                if mutation == 'workspace':
                    inputs.pop('__workspace_binding__')
                else:
                    inputs['__helper__/' + build_binding.SOURCE_HELPER_FILES[0]]['sha256'] = '0' * 64
                path.write_bytes(gzip.compress(json.dumps(inputs).encode()))
                receipt = json.loads(self.compile_receipt.read_text())
                receipt['input_digest'] = build_binding.digest(inputs)
                receipt['browser_build_binding'] = build_binding.binding_metadata(self.evidence)
                self.compile_receipt.write_text(json.dumps(receipt))
                with self.assertRaises(ValueError):
                    install_offline.prepare(self.root, self.compile_receipt)
                self.assertFalse((self.root / 'offline-install.js').exists())

    def test_competing_default_worker_bootstrap_is_rejected(self):
        index = (self.root / 'index.html').read_bytes()
        (self.root / 'flutter_bootstrap.js').write_text(
            '_flutter.loader.load({serviceWorkerSettings:{serviceWorkerVersion:"old"}});\n')
        self.write_compile_evidence()
        with self.assertRaisesRegex(ValueError, 'without service worker settings'):
            install_offline.prepare(self.root, self.compile_receipt)
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
        install_offline.prepare(self.root, self.compile_receipt)
        records, identity, _ = install_offline.validate_installation(self.root, self.compile_receipt)
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
const entries = clean.stores.get(cacheName).entries;
const dataUrl = clean.origin + '/assets/data.bin';
const originalEntry = entries.get(dataUrl);
const changed = [...input.assets['assets/data.bin']];
changed[0] ^= 1;
entries.set(dataUrl, new Response(new Uint8Array(changed)));
let corrupted;
await clean.event('message', {data: {type: 'quds-offline-status'},
  ports: [{postMessage(value) {corrupted = value;}}]});
let corruptedFetchRejected = false;
try { await clean.event('fetch', {request: new Request(dataUrl)}); }
catch (error) {corruptedFetchRejected = /digest mismatch/.test(error.message); }
entries.delete(dataUrl);
entries.set(clean.origin + '/unexpected-entry', originalEntry);
let substituted;
await clean.event('message', {data: {type: 'quds-offline-status'},
  ports: [{postMessage(value) {substituted = value;}}]});
const beforeMissingAsset = clean.fetches.length;
let missingAssetRejected = false;
try { await clean.event('fetch', {request: new Request(dataUrl)}); }
catch (error) {missingAssetRejected = /unavailable/.test(error.message); }
const missingAssetNetworkFetches = clean.fetches.length - beforeMissingAsset;
entries.delete(clean.origin + '/unexpected-entry');
let incomplete;
await clean.event('message', {data: {type: 'quds-offline-status'},
  ports: [{postMessage(value) {incomplete = value;}}]});
console.log(JSON.stringify({status, incomplete, corrupted, substituted,
  corruptedFetchRejected, missingAssetRejected, missingAssetNetworkFetches,
  skipped: clean.skipped, claimed: clean.claimed,
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
        self.assertEqual(observed['status']['verifiedFileCount'], len(records))
        self.assertTrue(observed['status']['inventoryVerified'])
        self.assertTrue(observed['status']['contentVerified'])
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
        self.assertEqual(observed['corrupted']['fileCount'], len(records))
        self.assertTrue(observed['corrupted']['inventoryVerified'])
        self.assertFalse(observed['corrupted']['contentVerified'])
        self.assertFalse(observed['corrupted']['ready'])
        self.assertTrue(observed['corruptedFetchRejected'])
        self.assertEqual(observed['substituted']['fileCount'], len(records))
        self.assertFalse(observed['substituted']['inventoryVerified'])
        self.assertFalse(observed['substituted']['ready'])
        self.assertTrue(observed['missingAssetRejected'])
        self.assertEqual(observed['missingAssetNetworkFetches'], 0)


class PanelReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=Path.cwd())
        self.root = Path(self.temporary.name)
        records = {'en': {}, 'de': {}}
        queries = []
        for word, language in run_browser.QUERIES:
            unsupported = language == 'fr-FR'
            negative = word.startswith('qudsxyz')
            senses = []
            if not unsupported and not negative:
                for number in (1, 2):
                    source = {'id': word + ':' + str(number), 'source': language[:2],
                              'pos': 'n', 'gloss': 'Source meaning', 'labels': ['source label'],
                              'examples': ['source example'] if number == 1 else [],
                              'terms': [{'id': word + ':term-' + str(number),
                                         'text': word + ' alternative', 'labels': ['term label'],
                                         'note': 'Source-only term note'}],
                              'relations': [{'type': 'related', 'target': word + ':relation'}]}
                    records[language[:2]].setdefault(run_browser.shard(source['id']), {})[source['id']] = source
                    senses.append(run_browser.observed_sense(source))
            queries.append({'text': word, 'language': language,
                            'status': 'unsupportedLanguage' if unsupported else
                                      'noEntry' if negative else 'ready',
                            'pack': None,
                            'senses': senses,
                            'matches': [{'text': 'Haus'}] if word == 'Häusern' else []})
        for locale, shards in records.items():
            directory = self.root / 'assets/packages/quds_office_editor/assets/thesaurus' / locale
            (directory / 'notices').mkdir(parents=True)
            (directory / 'senses').mkdir()
            notice = (locale + ' notice').encode()
            (directory / 'notices/LICENSE.txt').write_bytes(notice)
            files = {'notices/LICENSE.txt': {'size': len(notice), 'sha256': run_browser.sha256(notice)}}
            for name, senses in shards.items():
                value = json.dumps(senses).encode()
                compressor = zlib.compressobj(wbits=-15)
                compressed = compressor.compress(value) + compressor.flush()
                path = 'senses/' + name + '.json'
                (directory / (path + '.deflate')).write_bytes(compressed)
                files[path] = {'size': len(value), 'sha256': run_browser.sha256(value),
                               'compression': 'deflate-raw', 'compressedSize': len(compressed),
                               'compressedSha256': run_browser.sha256(compressed)}
            (directory / 'manifest.json').write_text(json.dumps(
                {'packId': locale + ':fixture', 'noticePaths': ['notices/LICENSE.txt'], 'files': files}))
        self.packs = run_browser.expected_packs(self.root)
        for query in queries:
            if query['language'] != 'fr-FR':
                query['pack'] = self.packs[query['language'][:2]]['identity']
        self.panel = {'queries': queries, 'notices': [
            {'locale': locale, 'pack': pack['identity'],
             'notices': [{'path': path, 'text': notice['text']}
                         for path, notice in pack['notices'].items()]}
            for locale, pack in self.packs.items()],
            'warm_mode': 'result-cache', 'warm_ms': [0.01] * 75,
            'cached_shards': 64, 'cached_results': 14,
            'cache_limits': {'shards': 64, 'results': 64}}

    def tearDown(self):
        self.temporary.cleanup()

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
        for mutation in ('polysemy', 'sharp-s', 'lemma', 'cache', 'timing', 'mode',
                         'missing-examples', 'discarded-examples'):
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
                elif mutation == 'mode':
                    panel['warm_mode'] = 'unknown'
                elif mutation == 'missing-examples':
                    queries['bank']['senses'][0].pop('examples')
                else:
                    for sense in queries['bank']['senses']:
                        sense['examples'] = []
                with self.assertRaises(AssertionError):
                    run_browser.validate_panel(panel, self.packs)

    def test_empty_ready_duplicate_and_unsuccessful_senses_cannot_pass(self):
        for mutation in ('empty-ready', 'duplicate', 'negative-sense',
                         'unsupported-sense', 'unsupported-pack', 'negative-match'):
            with self.subTest(mutation=mutation):
                panel = copy.deepcopy(self.panel)
                queries = panel['queries']
                if mutation == 'empty-ready':
                    queries[1]['senses'] = []
                elif mutation == 'duplicate':
                    queries[0]['senses'][1] = copy.deepcopy(queries[0]['senses'][0])
                elif mutation == 'negative-sense':
                    queries[-3]['senses'] = copy.deepcopy(queries[0]['senses'])
                elif mutation == 'unsupported-sense':
                    queries[-1]['senses'] = copy.deepcopy(queries[0]['senses'])
                elif mutation == 'unsupported-pack':
                    queries[-1]['pack'] = self.packs['en']['identity']
                else:
                    queries[-2]['matches'] = [{'text': 'invented match'}]
                with self.assertRaises(AssertionError):
                    run_browser.validate_panel(panel, self.packs)

    def test_changed_source_projection_cannot_pass(self):
        for field in ('id', 'source', 'pos', 'gloss', 'labels', 'examples', 'terms', 'relations'):
            with self.subTest(field=field):
                panel = copy.deepcopy(self.panel)
                sense = panel['queries'][0]['senses'][0]
                sense[field] = ['invented value'] if isinstance(sense[field], list) else 'invented value'
                with self.assertRaises(AssertionError):
                    run_browser.validate_panel(panel, self.packs)

    def test_damaged_source_shard_cannot_validate_observed_senses(self):
        sense = self.panel['queries'][0]['senses'][0]
        path = self.packs['en']['directory'] / ('senses/' + run_browser.shard(sense['id']) + '.json.deflate')
        contents = bytearray(path.read_bytes())
        contents[0] ^= 1
        path.write_bytes(contents)
        with self.assertRaisesRegex(ValueError, 'Compressed source mismatch'):
            run_browser.validate_panel(self.panel, self.packs)


if __name__ == '__main__':
    unittest.main(verbosity=2)
