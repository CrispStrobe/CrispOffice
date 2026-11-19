// Drives the shipped web worker (build/web/arabic_morph_worker.mjs + the
// bundled Emscripten module) through its message protocol in Node:
//   node tool/web_smoke.mjs <build/web dir> <noprob bundle dir> [corpus.txt]
// The corpus (one sentence per line, e.g. the UD Arabic-PUD `# text` lines)
// is split into distinct Arabic words and analyzed in one batch.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {pathToFileURL} from 'node:url';

const [webDir, bundleDir, corpus] = process.argv.slice(2);
const replies = new Map();
globalThis.self = {postMessage: message => replies.get(message.id)?.(message)};
await import(pathToFileURL(path.resolve(webDir, 'arabic_morph_worker.mjs')).href);
let sequence = 0;
const send = request => new Promise(resolve => {
  const id = ++sequence;
  replies.set(id, resolve);
  self.onmessage({data: {id, request}});
});
const assert = (condition, message) => { if (!condition) { console.error('FAIL', message); process.exit(1); } };
const mb = bytes => Math.round(bytes / 1048576);

const before = await send({op: 'analyze', words: ['كتبوا']});
assert(before.unavailable, 'analyze before open is unavailable');
const names = ['manifest.json', 'NOTICE', 'LICENSE', 'camel_morph_msa_v1.0.noprob.db'];
const read = name => fs.readFileSync(path.join(bundleDir, name));
const manifest = read('manifest.json');
const manifestSha256 = crypto.createHash('sha256').update(manifest).digest('hex');
const badOpen = await send({op: 'open', manifestSha256: '0'.repeat(64),
  files: [{name: 'manifest.json', bytes: manifest}]});
assert(JSON.parse(badOpen.response).status === 'failed' && !badOpen.fatal, 'wrong manifest hash is rejected');
const rssBefore = process.memoryUsage().rss;
let started = performance.now();
const opened = await send({op: 'open', manifestSha256, files: names.map(name => ({name, bytes: read(name)}))});
const loadSeconds = (performance.now() - started) / 1000;
const openBody = JSON.parse(opened.response);
assert(openBody.status === 'success', `open: ${opened.response}`);
const analyses = JSON.parse((await send({op: 'analyze', words: ['كتبوا', 'والمدرسة', 'xyzzy', '']})).response);
const [katabu, walmadrasa, latin] = analyses.results;
assert(katabu.some(a => a.lex === 'كَتَب' && a.pos === 'verb' && a.num === 'p'), 'كتبوا: lex كَتَب verb plural');
assert(walmadrasa.some(a => a.pos === 'noun' && a.prc2 === 'wa_conj' && a.prc0 === 'Al_det'),
  'والمدرسة: noun with wa_conj and Al_det');
assert(Array.isArray(latin), 'a Latin word gets an analysis list');
const report = {
  protocol_checks: 6, load_seconds: loadSeconds, wasm_heap_mb: mb(openBody.heapBytes),
  process_rss_growth_mb: mb(process.memoryUsage().rss - rssBefore), info: openBody.info,
};
if (corpus) {
  const arabic = /[ؠ-يٮ-ۓ]/u;
  const words = [...new Set(fs.readFileSync(corpus, 'utf8').split('\n')
    .flatMap(line => line.match(/[\p{L}\p{M}]+/gu) ?? []).filter(word => arabic.test(word)))];
  started = performance.now();
  const results = JSON.parse((await send({op: 'analyze', words})).response).results;
  const seconds = (performance.now() - started) / 1000;
  report.distinct_words = words.length;
  report.analyzed = results.filter(r => Array.isArray(r) && r.length).length;
  report.analyses = results.reduce((sum, r) => sum + (r?.length ?? 0), 0);
  report.seconds = seconds;
  report.words_per_second = Math.round(words.length / seconds);
  report.wasm_heap_mb_after = mb(JSON.parse((await send({op: 'stats'})).response).heapBytes);
}
console.log(JSON.stringify(report, null, 2));
