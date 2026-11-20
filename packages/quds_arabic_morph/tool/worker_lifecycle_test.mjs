// Execute the real worker protocol with a controlled Wasm API and real Node
// structured-clone transfers. This is not a browser or native model test.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../web/arabic_morph_worker.mjs', import.meta.url), 'utf8');
const importLine = "import createArabicMorphModule from './quds_arabic_morph.mjs';";
assert.equal(source.split(importLine).length, 2);
const heap = new Uint8Array(65536);
const words = new Uint32Array(heap.buffer);
const files = new Map();
const encoder = new TextEncoder();
let next = 32;
let databaseOpens = 0;
let databaseFrees = 0;
let modelOpens = 0;
let modelFrees = 0;
let databaseOpen = false;
let modelOpen = false;
function allocate(length) {
  const pointer = next;
  next = (next + length + 3) & ~3;
  assert.ok(next < heap.length);
  return pointer;
}
function string(value) {
  const bytes = encoder.encode(`${value}\0`);
  const pointer = allocate(bytes.length);
  heap.set(bytes, pointer);
  return pointer;
}
const databaseInfo = string(JSON.stringify({keys: ['lex', 'pos']}));
const modelInfo = string(JSON.stringify({model: 'controlled'}));
const api = {
  HEAPU8: heap,
  HEAPU32: words,
  _malloc: allocate,
  _free() {},
  stringToNewUTF8: string,
  _quds_arabic_morph_adapter_version: () => 2,
  _crispembed_ar_morph_abi_version: () => 3,
  _quds_arabic_morph_enable_disambiguation: () => 1,
  FS: {
    mkdir() {},
    writeFile(path, bytes) { files.set(path, bytes); },
    unlink(path) { assert.ok(files.delete(path)); },
  },
  _crispembed_ar_morph_open() {
    assert.deepEqual([...files.get('/camel-morph/data.bin')], [1, 2, 3]);
    databaseOpen = true;
    databaseOpens++;
    return 101;
  },
  _crispembed_ar_morph_info(handle) {
    assert.equal(handle, 101);
    return databaseInfo;
  },
  _crispembed_ar_morph_free(handle) {
    assert.equal(handle, 101);
    databaseOpen = false;
    databaseFrees++;
  },
  _crispembed_ar_morph_disambig_open() {
    assert.ok(databaseOpen);
    assert.deepEqual([...files.get('/camel-morph-disambig/data.bin')], [4, 5, 6]);
    modelOpen = true;
    modelOpens++;
    return 201;
  },
  _crispembed_ar_morph_disambig_info(handle) {
    assert.equal(handle, 201);
    return modelInfo;
  },
  _crispembed_ar_morph_disambig_free(handle) {
    assert.equal(handle, 201);
    assert.ok(modelOpen);
    modelOpen = false;
    modelFrees++;
  },
  _crispembed_ar_morph_analyze_compact(handle, _text, _lengths, count, _flags, out, length) {
    assert.equal(handle, 101);
    assert.ok(databaseOpen);
    // Valid compact output with zero analyses for each input word.
    const size = 8 + count * 20;
    const pointer = allocate(size);
    const view = new DataView(heap.buffer, pointer, size);
    view.setUint32(0, 0x31434d41, true);
    view.setUint32(4, count, true);
    for (let i = 0; i < count; i++) view.setUint32(12 + i * 20, 12, true);
    words[out >> 2] = pointer;
    words[length >> 2] = size;
    return 0;
  },
  _crispembed_ar_morph_buffer_free() {},
};

const pending = new Map();
let sequence = 0;
const self = {
  postMessage(message, transfer = []) {
    const copy = structuredClone(message, {transfer});
    const complete = pending.get(copy.id);
    assert.ok(complete, 'every response belongs to a pending request');
    pending.delete(copy.id);
    complete(copy);
  },
};
const context = vm.createContext({
  self, TextEncoder, TextDecoder, Uint8Array, Uint32Array,
  createArabicMorphModule: async () => api,
});
vm.runInContext(source.replace(importLine, ''), context, {filename: 'arabic_morph_worker.mjs'});
async function request(op, fields = {}, transfer = []) {
  const id = ++sequence;
  let timer;
  const response = new Promise((resolve, reject) => {
    pending.set(id, resolve);
    timer = setTimeout(() => reject(new Error(`Timed out: ${op}`)), 2000);
  });
  self.onmessage({data: structuredClone({id, request: {op, ...fields}}, {transfer})});
  try {
    const result = await response;
    assert.equal(result.unavailable, undefined);
    assert.equal(result.fatal, undefined);
    if (result.response !== undefined) assert.equal(JSON.parse(result.response).status, 'success');
    return result;
  } finally { clearTimeout(timer); }
}
async function open(op, values) {
  const bytes = Uint8Array.from(values);
  const response = request(op, {
    manifestSha256: 'controlled', files: [{name: 'data.bin', bytes}],
  }, [bytes.buffer]);
  assert.equal(bytes.byteLength, 0, 'host input really becomes detached');
  await response;
}

await open('open', [1, 2, 3]);
await open('open_model', [4, 5, 6]);
await request('close_model');
assert.equal(databaseOpens, 1);
assert.equal(databaseFrees, 0);
assert.equal(modelFrees, 1);
assert.equal(modelOpen, false);
assert.equal(JSON.parse((await request('stats')).response).open, true);
const analyzed = await request('analyze', {words: ['كتب', 'كتاب']});
assert.equal(new DataView(analyzed.buffer).getUint32(4, true), 2);

await request('close_model');
assert.equal(modelFrees, 1, 'repeated removal does not free the model twice');
await open('open_model', [4, 5, 6]);
assert.equal(modelOpens, 2);
assert.equal(databaseOpens, 1);
assert.ok(modelOpen);
await request('close_model');
assert.equal(modelFrees, 2);
assert.equal(databaseFrees, 0);
assert.equal(files.size, 0, 'temporary transferred files were released');
assert.equal(pending.size, 0);
console.log(JSON.stringify({
  accepted: true,
  controls: [
    'model removal preserves the database after real buffer detachment',
    'ordinary analysis remains available without a second database transfer',
    'repeated removal is harmless and a new model can load',
  ],
  scope: 'real worker protocol and Node transfers; controlled Wasm API',
  worker_sha256: createHash('sha256').update(source).digest('hex'),
  databaseOpens, databaseFrees, modelOpens, modelFrees,
}));
