// Node-only test harness for the exact shipped browser module worker.
import {parentPort, workerData} from 'node:worker_threads';
import {readFile} from 'node:fs/promises';

const originalFetch = globalThis.fetch;
globalThis.fetch = async (resource, options) => {
  const url = resource instanceof URL ? resource : new URL(String(resource));
  if (url.protocol === 'file:') {
    return new Response(await readFile(url), {headers: {'Content-Type': 'application/wasm'}});
  }
  return originalFetch(resource, options);
};
globalThis.self = {postMessage: message => parentPort.postMessage(message)};
await import(workerData.module);
parentPort.on('message', message => self.onmessage({data: message}));
