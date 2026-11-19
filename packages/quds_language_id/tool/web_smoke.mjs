// Drives the shipped web worker (build/web/language_id_worker.mjs + the
// bundled Emscripten module) through its message protocol in Node:
//   node tool/web_smoke.mjs <build/web dir> <cld3-f16.gguf> [sentences.txt]
// With a corpus (one paragraph per line, e.g. UD `# text` lines) it reports
// the per-paragraph latency of one request per paragraph and of one batch.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {pathToFileURL} from 'node:url';

const [webDir, modelPath, corpus] = process.argv.slice(2);
const replies = new Map();
globalThis.self = {postMessage: message => replies.get(message.id)?.(message)};
await import(pathToFileURL(path.resolve(webDir, 'language_id_worker.mjs')).href);
let sequence = 0;
const send = request => new Promise(resolve => {
  const id = ++sequence;
  replies.set(id, resolve);
  self.onmessage({data: {id, request}});
});
const assert = (condition, message) => { if (!condition) { console.error('FAIL', message); process.exit(1); } };

const before = await send({op: 'detect', texts: ['Bonjour le monde'], k: 3});
assert(before.unavailable, 'detect before open is unavailable');
const bad = await send({op: 'open', model: new Uint8Array(64)});
assert(JSON.parse(bad.response).status === 'failed' && !bad.fatal, 'a malformed model is rejected');
const model = fs.readFileSync(modelPath);
assert(crypto.createHash('sha256').update(model).digest('hex') ===
  '900813b635fa7f472beac213f521d57dd12378099b0623a8a36de0310b6bf892', 'model is the pinned one');
const rssBefore = process.memoryUsage().rss;
let started = performance.now();
const opened = JSON.parse((await send({op: 'open', model: new Uint8Array(model)})).response);
const loadMs = performance.now() - started;
assert(opened.status === 'success', 'open');
const smoke = JSON.parse((await send({op: 'detect', k: 3, texts: [
  'Bonjour le monde', 'Привет мир', 'שלום עולם', 'این یک متن فارسی است',
  'Das ist ein ganz normaler deutscher Satz über das Wetter.', '12345 !?', '']})).response).results;
const top = smoke.map(r => r[0]?.[0] ?? '-');
assert(JSON.stringify(top) === JSON.stringify(['fr', 'ru', 'iw', 'fa', 'de', '-', '-']), `top labels ${top}`);
assert(Math.abs(smoke[0][0][1] - 0.999403) < 1e-4, `fr probability ${smoke[0][0][1]}`);
const report = {protocol_checks: 5, load_ms: loadMs, wasm_heap_bytes: opened.heapBytes,
  process_rss_growth_bytes: process.memoryUsage().rss - rssBefore,
  wasm_bytes: fs.statSync(path.join(webDir, 'quds_language_id.wasm')).size,
  module_bytes: fs.statSync(path.join(webDir, 'quds_language_id.mjs')).size};
if (corpus) {
  const lines = fs.readFileSync(corpus, 'utf8').split('\n').filter(l => l.trim());
  const times = [];
  for (const line of lines) {
    started = performance.now();
    await send({op: 'detect', k: 5, texts: [line]});
    times.push(performance.now() - started);
  }
  times.sort((a, b) => a - b);
  started = performance.now();
  await send({op: 'detect', k: 5, texts: lines});
  report.paragraphs = lines.length;
  report.single_mean_ms = times.reduce((a, b) => a + b, 0) / times.length;
  report.single_p50_ms = times[Math.floor(times.length / 2)];
  report.single_p95_ms = times[Math.floor(times.length * 0.95)];
  report.batched_per_paragraph_ms = (performance.now() - started) / lines.length;
}
console.log(JSON.stringify(report, null, 2));
