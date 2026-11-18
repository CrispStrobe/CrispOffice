#!/usr/bin/env python3
"""Install an integrity-checked, test-only offline worker in a Flutter build.

This is acceptance infrastructure, not the application's production installer.
The browser runner verifies this exact inventory before it starts a browser.
"""
import argparse
import hashlib
import json
from pathlib import Path

GENERATED = {'offline-test-worker.js', 'offline-files.json'}
CACHE_PREFIX = 'quds-thesaurus-test-'
INDEX = '''<!doctype html>
<html><head><base href="/"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Quds thesaurus offline acceptance</title>
</head><body>
<script src="offline-install.js"></script>
<script src="flutter_bootstrap.js" async></script>
</body></html>
'''
INSTALL_SCRIPT = '''
window.qudsOfflineInstallation = {ready: false};
(async () => {
  try {
    const workerUrl = new URL('/offline-test-worker.js', location.href).href;
    let registration = await navigator.serviceWorker.getRegistration('/');
    if (!registration || registration.active?.scriptURL !== workerUrl) {
      registration = await navigator.serviceWorker.register(workerUrl,
        {scope: '/', updateViaCache: 'none'});
    }
    await navigator.serviceWorker.ready;
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Offline worker control timed out')), 120000);
      const check = () => {
        if (navigator.serviceWorker.controller?.scriptURL === workerUrl) {
          clearTimeout(timeout);
          navigator.serviceWorker.removeEventListener('controllerchange', check);
          resolve();
        }
      };
      navigator.serviceWorker.addEventListener('controllerchange', check);
      check();
    });
    const status = await new Promise((resolve, reject) => {
      const channel = new MessageChannel();
      const timeout = setTimeout(() => reject(new Error('Offline worker receipt timed out')), 20000);
      channel.port1.onmessage = event => {
        clearTimeout(timeout);
        channel.port1.close();
        resolve(event.data);
      };
      navigator.serviceWorker.controller.postMessage({type: 'quds-offline-status'}, [channel.port2]);
    });
    if (!status.ready) throw new Error('Offline cache is incomplete');
    window.qudsOfflineInstallation = {...status, ready: true, workerUrl};
  } catch (error) {
    window.qudsOfflineInstallation = {ready: false, error: String(error)};
  }
})();
'''


def file_records(root):
    records = []
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise ValueError(f'Build contains a symbolic link: {path}')
        if path.is_file() and path.relative_to(root).as_posix() not in GENERATED:
            data = path.read_bytes()
            records.append({'path': path.relative_to(root).as_posix(),
                            'bytes': len(data),
                            'sha256': hashlib.sha256(data).hexdigest()})
    return records


def cache_identity(records):
    return hashlib.sha256(json.dumps(records, sort_keys=True).encode()).hexdigest()


def worker_script(records, identity):
    script = 'const CACHE_NAME = ' + json.dumps(CACHE_PREFIX + identity) + ';\n'
    script += 'const FILES = ' + json.dumps(records, ensure_ascii=True) + ';\n'
    return script + '''
const hex = bytes => Array.from(new Uint8Array(bytes), x => x.toString(16).padStart(2, '0')).join('');
self.addEventListener('install', event => event.waitUntil((async () => {
  const cache = await caches.open(CACHE_NAME);
  try {
    for (let start = 0; start < FILES.length; start += 12) {
      await Promise.all(FILES.slice(start, start + 12).map(async record => {
        const url = new URL('/' + record.path, self.location.origin);
        const response = await fetch(url, {cache: 'no-store'});
        if (!response.ok) throw new Error('Offline asset HTTP failure: ' + record.path);
        const bytes = await response.clone().arrayBuffer();
        if (bytes.byteLength !== record.bytes ||
            hex(await crypto.subtle.digest('SHA-256', bytes)) !== record.sha256) {
          throw new Error('Offline asset digest mismatch: ' + record.path);
        }
        await cache.put(url, response);
      }));
    }
  } catch (error) {
    await caches.delete(CACHE_NAME);
    throw error;
  }
  await self.skipWaiting();
})()));
self.addEventListener('activate', event => event.waitUntil((async () => {
  for (const name of await caches.keys()) {
    if (name.startsWith('quds-thesaurus-test-') && name !== CACHE_NAME) await caches.delete(name);
  }
  await clients.claim();
})()));
self.addEventListener('message', event => {
  if (event.data?.type !== 'quds-offline-status' || !event.ports[0]) return;
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    const count = (await cache.keys()).length;
    event.ports[0].postMessage({ready: count === FILES.length, cacheName: CACHE_NAME,
      fileCount: count, expectedFileCount: FILES.length});
  })());
});
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const key = url.pathname === '/' ? '/index.html' : event.request;
    return await cache.match(key, {ignoreSearch: true}) || fetch(event.request);
  })());
});
'''


def prepare(root):
    root = root.resolve()
    for name in ('index.html', 'flutter_bootstrap.js', 'main.dart.js'):
        if not (root / name).is_file():
            raise ValueError(f'Expected a compiled JavaScript Flutter build: missing {name}')
    # Inspect links before writing to avoid replacing a file outside the build.
    file_records(root)
    (root / 'index.html').write_text(INDEX)
    (root / 'offline-install.js').write_text(INSTALL_SCRIPT)
    records = file_records(root)
    identity = cache_identity(records)
    (root / 'offline-files.json').write_text(json.dumps(records, indent=2) + '\n')
    (root / 'offline-test-worker.js').write_text(worker_script(records, identity))
    return {'cache_identity': identity, 'files': len(records),
            'bytes': sum(record['bytes'] for record in records)}


def validate_installation(root):
    records = json.loads((root / 'offline-files.json').read_text())
    if file_records(root) != records:
        raise ValueError('Build changed after offline installation was prepared')
    identity = cache_identity(records)
    if (root / 'offline-test-worker.js').read_text() != worker_script(records, identity):
        raise ValueError('Offline worker does not match the installed build inventory')
    if (root / 'index.html').read_text() != INDEX or (root / 'offline-install.js').read_text() != INSTALL_SCRIPT:
        raise ValueError('Offline fixture entry points do not match this runner')
    return records, identity


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build', type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.build), indent=2))


if __name__ == '__main__':
    main()
