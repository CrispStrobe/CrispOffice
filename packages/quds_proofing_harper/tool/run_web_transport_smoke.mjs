// Execute compiled Dart web-transport code through the shipped Wasm worker.
import assert from 'node:assert/strict';
import {Worker as NodeWorker} from 'node:worker_threads';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

let created = 0;
let terminated = 0;
class BrowserWorker {
  constructor(url) {
    this.listeners = new Map();
    this.worker = new NodeWorker(new URL('./node_worker_bridge.mjs', import.meta.url), {
      workerData: {module: url},
    });
    created++;
    this.worker.on('message', data => this.dispatch('message', {data}));
    this.worker.on('error', error => this.dispatch('error', {error}));
  }
  addEventListener(name, listener) {
    const listeners = this.listeners.get(name) ?? [];
    listeners.push(listener);
    this.listeners.set(name, listeners);
  }
  dispatch(name, event) {
    for (const listener of this.listeners.get(name) ?? []) listener(event);
  }
  postMessage(value) {this.worker.postMessage(value);}
  terminate() {
    if (this.stopped) return;
    this.stopped = true;
    terminated++;
    void this.worker.terminate();
  }
}

globalThis.self = globalThis;
globalThis.Worker = BrowserWorker;
globalThis.qudsHarperWorkerUrl = pathToFileURL(resolve(process.argv[3] ?? 'build/web/harper_worker.mjs')).href;
const complete = new Promise(resolve => {
  globalThis.qudsHarperSmokeDone = result => resolve(JSON.parse(result));
});
const timer = setTimeout(() => {
  console.error('Compiled Dart web-transport smoke test timed out');
  process.exit(1);
}, 45000);
try {
  await import(pathToFileURL(resolve(process.argv[2] ?? 'build/web_transport_smoke.js')));
  const result = await complete;
  assert.equal(result.status, 'passed', result.error);
  assert.equal(result.checks, 8);
  assert.equal(terminated, created, 'Every created Worker must be terminated');
  console.log(JSON.stringify({...result, workers_created: created, workers_terminated: terminated}));
} finally {
  clearTimeout(timer);
}
