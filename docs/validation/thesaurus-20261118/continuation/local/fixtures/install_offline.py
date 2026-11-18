#!/usr/bin/env python3
"""Add a test-only offline install worker to a compiled Flutter fixture."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('build', type=Path)
args = parser.parse_args()
root = args.build.resolve()
index = root / 'index.html'
index.write_text('''<!doctype html>
<html><head><base href="/"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Quds thesaurus offline acceptance</title>
</head><body>
<script src="offline-install.js"></script>
<script src="flutter_bootstrap.js" async></script>
</body></html>
''')
(root / 'offline-install.js').write_text('''
window.qudsOfflineInstallation = {ready: false};
(async () => {
  try {
    await navigator.serviceWorker.register('/offline-test-worker.js');
    await navigator.serviceWorker.ready;
    if (!navigator.serviceWorker.controller) {
      await new Promise(resolve => navigator.serviceWorker.addEventListener(
        'controllerchange', resolve, {once: true}));
    }
    window.qudsOfflineInstallation = {ready: true};
  } catch (error) {
    window.qudsOfflineInstallation = {ready: false, error: String(error)};
  }
})();
''')
files = sorted(p for p in root.rglob('*') if p.is_file()
               and p.name not in {'offline-test-worker.js', 'offline-files.json'})
records = [{'path': p.relative_to(root).as_posix(), 'bytes': p.stat().st_size,
            'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in files]
identity = hashlib.sha256(json.dumps(records, sort_keys=True).encode()).hexdigest()
(root / 'offline-files.json').write_text(json.dumps(records, indent=2) + '\n')
worker = "const CACHE_NAME = 'quds-thesaurus-test-" + identity + "';\n"
worker += 'const FILES = ' + json.dumps(['/' + r['path'] for r in records]) + ';\n'
worker += '''
self.addEventListener('install', event => event.waitUntil((async () => {
  const cache = await caches.open(CACHE_NAME);
  for (let start = 0; start < FILES.length; start += 12) {
    await cache.addAll(FILES.slice(start, start + 12));
  }
  await self.skipWaiting();
})()));
self.addEventListener('activate', event => event.waitUntil((async () => {
  for (const name of await caches.keys()) {
    if (name !== CACHE_NAME) await caches.delete(name);
  }
  await clients.claim();
})()));
self.addEventListener('fetch', event => event.respondWith((async () => {
  const cache = await caches.open(CACHE_NAME);
  const key = new URL(event.request.url).pathname === '/' ? '/index.html' : event.request;
  return await cache.match(key, {ignoreSearch: true}) || fetch(event.request);
})()));
'''
(root / 'offline-test-worker.js').write_text(worker)
print(json.dumps({'cache_identity': identity, 'files': len(records),
                  'bytes': sum(r['bytes'] for r in records)}, indent=2))
