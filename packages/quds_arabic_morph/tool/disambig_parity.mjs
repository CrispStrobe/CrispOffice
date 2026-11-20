// Web half of the native/web context-model parity check. Drives the shipped
// web worker (build/web/arabic_morph_worker.mjs + the bundled Emscripten
// module) through its message protocol in Node, exactly as the browser does:
//   node tool/disambig_parity.mjs <build/web dir> <bundle dir> <model dir> <panel.json> <out.json>
// It opens the verified database and context model, disambiguates every panel
// sentence in one request and writes the worker's raw reply (the compact
// records plus the score section, base64) with the analyzer's key names.
// test/arabic_morph_web_parity_test.dart decodes that buffer with the same
// Dart decoder the web transport uses and compares it with the native path.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {pathToFileURL} from 'node:url';

const [webDir, bundleDir, modelDir, panelPath, outPath] = process.argv.slice(2);
if (!outPath) {
  console.error('usage: disambig_parity.mjs <web dir> <bundle dir> <model dir> <panel.json> <out.json>');
  process.exit(2);
}
const replies = new Map();
globalThis.self = {postMessage: message => replies.get(message.id)?.(message)};
await import(pathToFileURL(path.resolve(webDir, 'arabic_morph_worker.mjs')).href);
let sequence = 0;
const send = request => new Promise(resolve => {
  const id = ++sequence;
  replies.set(id, resolve);
  self.onmessage({data: {id, request}});
});
const fail = message => { console.error('FAIL', message); process.exit(1); };

function bundle(dir) {
  const manifest = fs.readFileSync(path.join(dir, 'manifest.json'));
  const names = ['manifest.json', ...JSON.parse(manifest).files.map(f => f.path)];
  return {
    manifestSha256: crypto.createHash('sha256').update(manifest).digest('hex'),
    files: names.map(name => ({name, bytes: fs.readFileSync(path.join(dir, name))})),
  };
}

const opened = await send({op: 'open', ...bundle(bundleDir)});
const openBody = JSON.parse(opened.response ?? '{}');
if (openBody.status !== 'success') fail(`open: ${opened.response ?? opened.unavailable}`);
const model = await send({op: 'open_model', ...bundle(modelDir)});
const modelBody = JSON.parse(model.response ?? '{}');
if (modelBody.status !== 'success') fail(`open_model: ${model.response ?? model.unavailable}`);

const sentences = JSON.parse(fs.readFileSync(panelPath, 'utf8')).sentences;
const words = sentences.flat();
const reply = await send({op: 'disambiguate', words, lengths: sentences.map(s => s.length)});
if (!reply.buffer) fail(`disambiguate: ${reply.response ?? reply.unavailable}`);
const buffer = Buffer.from(reply.buffer);
fs.writeFileSync(outPath, JSON.stringify({
  keys: openBody.info.keys,
  model_format: modelBody.info.model_format,
  words: words.length,
  sentence_lengths: sentences.map(s => s.length),
  buffer_sha256: crypto.createHash('sha256').update(buffer).digest('hex'),
  buffer_base64: buffer.toString('base64'),
}, null, 2) + '\n');
console.log(JSON.stringify({words: words.length, bytes: buffer.length, model_format: modelBody.info.model_format}));
