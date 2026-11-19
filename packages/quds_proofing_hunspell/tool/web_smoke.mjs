// Drives the shipped web worker (build/web/hunspell_worker.mjs + the bundled
// Emscripten module) through its message protocol in Node:
//   node tool/web_smoke.mjs <build/web dir> <dictionary dir> [corpus.txt cli-flagged.txt]
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const [webDir, dictDir, corpus, cliFlagged] = process.argv.slice(2);
const replies = new Map();
globalThis.self = {postMessage: message => replies.get(message.id)?.(message)};
await import(pathToFileURL(path.resolve(webDir, 'hunspell_worker.mjs')).href);
let sequence = 0;
const send = request => new Promise(resolve => {
  const id = ++sequence;
  replies.set(id, resolve);
  self.onmessage({data: {id, request}});
});
const assert = (condition, message) => { if (!condition) { console.error('FAIL', message); process.exit(1); } };

const before = await send({op: 'check', words: ['الى'], suggest: [false]});
assert(before.unavailable, 'check before open is unavailable');
const opened = await send({op: 'open', aff: fs.readFileSync(path.join(dictDir, 'ar.aff')),
                           dic: fs.readFileSync(path.join(dictDir, 'ar.dic'))});
assert(opened.response && JSON.parse(opened.response).status === 'success', 'open');
const known = JSON.parse((await send({op: 'check', words: ['ذهب', 'الى', 'المدرسه', 'هاذا', 'كَتَبَ', 'الطالـــب'],
                                      suggest: [true, true, true, true, true, true]})).response);
const results = known.results;
assert(results[0].ok && results[4].ok && results[5].ok, 'correct words (with harakat/tatweel) accepted');
assert(!results[1].ok && results[1].suggestions[0] === 'إلى', 'الى -> إلى first');
assert(!results[2].ok && results[2].suggestions[0] === 'المدرسة', 'المدرسه -> المدرسة first');
assert(!results[3].ok && results[3].suggestions.includes('هذا'), 'هاذا -> هذا');
const report = {protocol_checks: 6};
if (corpus) {
  const arabic = /[ؠ-يٮ-ۓەۮۯۺ-ۼۿݐ-ݿࢠ-ࣉﭐ-ﷻﹰ-ﻼ]/u;
  const words = fs.readFileSync(corpus, 'utf8').split('\n')
    .flatMap(line => line.match(/[\p{L}\p{M}]+/gu) ?? []).filter(word => arabic.test(word));
  const started = Date.now();
  const checked = JSON.parse((await send({op: 'check', words, suggest: words.map(() => false)})).response).results;
  const flagged = new Map();
  checked.forEach((result, i) => { if (!result.ok) flagged.set(words[i], (flagged.get(words[i]) ?? 0) + 1); });
  const cli = new Map();
  for (const word of fs.readFileSync(cliFlagged, 'utf8').split('\n')) {
    if (word && arabic.test(word)) cli.set(word, (cli.get(word) ?? 0) + 1);
  }
  const keys = new Set([...flagged.keys(), ...cli.keys()]);
  report.arabic_words = words.length;
  report.flagged = [...flagged.values()].reduce((a, b) => a + b, 0);
  report.cli_flagged = [...cli.values()].reduce((a, b) => a + b, 0);
  report.multiset_differences = [...keys].filter(k => (flagged.get(k) ?? 0) !== (cli.get(k) ?? 0)).length;
  report.seconds = (Date.now() - started) / 1000;
}
console.log(JSON.stringify(report, null, 2));
