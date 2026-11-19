// Drives the shipped web worker (build/web/arabic_morph_worker.mjs + the
// bundled Emscripten module) through its message protocol in Node:
//   node tool/web_smoke.mjs <build/web dir> <bundle dir> [corpus.txt]
// The bundle dir holds a verified bundle (proofing-bin); its manifest lists
// the files. The corpus (one sentence per line, e.g. the UD Arabic-PUD
// `# text` lines) is split into distinct Arabic words and analyzed in
// batches of 512, like the Dart transport; replies are compact buffers.
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
const read = name => fs.readFileSync(path.join(bundleDir, name));
const manifest = read('manifest.json');
const names = ['manifest.json', ...JSON.parse(manifest).files.map(f => f.path)];
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
// Decodes a compact batch buffer into arrays of {feature: value} objects
// (null for a rejected word).
const keys = openBody.info.keys;
const utf8 = new TextDecoder();
function decode(buffer, count) {
  const view = new DataView(buffer);
  assert(view.getUint32(0, true) === 0x31434D41 && view.getUint32(4, true) === count, 'compact header');
  let at = 8;
  const out = [];
  for (let w = 0; w < count; w++) {
    const status = view.getUint32(at, true);
    const length = view.getUint32(at + 4, true);
    at += 8;
    if (status !== 0) { out.push(null); at += length; continue; }
    const n = view.getUint32(at, true), strings = view.getUint32(at + 4, true), wide = view.getUint8(at + 8);
    let p = at + 12;
    const values = [];
    for (let i = 0; i < strings; i++) {
      const len = view.getUint32(p + 1, true);
      values.push(utf8.decode(new Uint8Array(buffer, p + 5, len)));
      p += 5 + len;
    }
    const analyses = [];
    for (let a = 0; a < n; a++) {
      const features = view.getUint16(p, true);
      p += 2;
      const analysis = {};
      for (let f = 0; f < features; f++) {
        const key = wide ? view.getUint16(p, true) : view.getUint8(p);
        const ref = wide ? view.getUint32(p + 2, true) : view.getUint16(p + 1, true);
        p += wide ? 6 : 3;
        if (ref !== (wide ? 0xFFFFFFFF : 0xFFFF)) analysis[keys[key]] = values[ref];
      }
      analyses.push(analysis);
    }
    assert(p === at + length, 'record length');
    out.push(analyses);
    at += length;
  }
  assert(at === buffer.byteLength, 'buffer length');
  return out;
}
const analyze = async words => decode((await send({op: 'analyze', words})).buffer, words.length);
const [katabu, walmadrasa, latin] = await analyze(['كتبوا', 'والمدرسة', 'xyzzy', '']);
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
  const results = [];
  for (let i = 0; i < words.length; i += 512) results.push(...await analyze(words.slice(i, i + 512)));
  const seconds = (performance.now() - started) / 1000;
  report.distinct_words = words.length;
  report.analyzed = results.filter(r => Array.isArray(r) && r.length).length;
  report.analyses = results.reduce((sum, r) => sum + (r?.length ?? 0), 0);
  report.seconds = seconds;
  report.words_per_second = Math.round(words.length / seconds);
  report.wasm_heap_mb_after = mb(JSON.parse((await send({op: 'stats'})).response).heapBytes);
  report.process_rss_growth_mb_after = mb(process.memoryUsage().rss - rssBefore);
}
console.log(JSON.stringify(report, null, 2));
