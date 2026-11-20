// Local module worker for the optional Arabic morphology backend. Serve it
// next to the bundled quds_arabic_morph.mjs/.wasm (part of the app, never
// downloaded). The Camel Morph database bytes arrive from the host (the
// user's verified download); no text or data is fetched or posted elsewhere.
import createArabicMorphModule from './quds_arabic_morph.mjs';

let module;
let handle = 0;
let model = 0;
const BUNDLE = '/camel-morph';
const MODEL = '/camel-morph-disambig';

async function load() {
  const api = await createArabicMorphModule();
  if (api._quds_arabic_morph_adapter_version() !== 2 || api._crispembed_ar_morph_abi_version() !== 3) {
    throw new Error('Unsupported Arabic morphology ABI');
  }
  return api;
}

// Text out of the Wasm heap. Copies first, so decoding never depends on the
// kind of buffer behind the heap (current Chrome's TextDecoder rejects views
// of resizable buffers; the build also disables those).
const decoder = new TextDecoder();
function text(api, pointer, length) {
  if (length === undefined) {
    const end = api.HEAPU8.indexOf(0, pointer);
    length = (end < 0 ? api.HEAPU8.length : end) - pointer;
  }
  return decoder.decode(api.HEAPU8.slice(pointer, pointer + length));
}

function withString(api, value, body) {
  const pointer = api.stringToNewUTF8(value);
  try { return body(pointer); } finally { api._free(pointer); }
}

// files: [{name, bytes}] of one verified bundle, manifest.json among them.
function open(api, files, manifestSha256) {
  if (model) { api._crispembed_ar_morph_disambig_free(model); model = 0; }
  if (handle) { api._crispembed_ar_morph_free(handle); handle = 0; }
  try { api.FS.mkdir(BUNDLE); } catch (_) { /* exists */ }
  const written = [];
  const error = api._malloc(512);
  try {
    for (const {name, bytes} of files) {
      if (!/^[A-Za-z0-9._-]+$/.test(name)) throw new Error('Invalid bundle file name');
      // MEMFS keeps the (transferred) array itself; nothing is copied here.
      api.FS.writeFile(`${BUNDLE}/${name}`, bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes),
        {canOwn: true});
      written.push(`${BUNDLE}/${name}`);
    }
    handle = withString(api, `${BUNDLE}/manifest.json`, m => withString(api, manifestSha256,
      s => api._crispembed_ar_morph_open(m, s, 0, error, 512)));
    if (!handle) throw new Error(`The morphology database could not be opened: ${text(api, error)}`);
  } finally {
    api._free(error);
    // The analyzer keeps its own copy of the database; drop the in-memory files.
    for (const path of written) { try { api.FS.unlink(path); } catch (_) { /* gone */ } }
  }
  return text(api, api._crispembed_ar_morph_info(handle));
}

// files: [{name, bytes}] of one verified disambiguation model bundle. The
// disambiguator is default-off in CrispEmbed; the adapter enables it for
// this module (the Wasm module has its own environment).
function openModel(api, files, manifestSha256) {
  if (!handle) throw new Error('No Arabic morphology database is open');
  if (model) { api._crispembed_ar_morph_disambig_free(model); model = 0; }
  try { api.FS.mkdir(MODEL); } catch (_) { /* exists */ }
  const written = [];
  const error = api._malloc(512);
  try {
    for (const {name, bytes} of files) {
      if (!/^[A-Za-z0-9._-]+$/.test(name)) throw new Error('Invalid bundle file name');
      api.FS.writeFile(`${MODEL}/${name}`, bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes),
        {canOwn: true});
      written.push(`${MODEL}/${name}`);
    }
    api._quds_arabic_morph_enable_disambiguation();
    model = withString(api, `${MODEL}/manifest.json`, m => withString(api, manifestSha256,
      s => api._crispembed_ar_morph_disambig_open(m, s, error, 512)));
    if (!model) throw new Error(`The disambiguation model could not be opened: ${text(api, error)}`);
  } finally {
    api._free(error);
    for (const path of written) { try { api.FS.unlink(path); } catch (_) { /* gone */ } }
  }
  return text(api, api._crispembed_ar_morph_disambig_info(model));
}

// One disambiguation buffer: the compact records of every word, then the
// score section (crispembed_ar_morph_disambiguate, duplicate analyses dropped).
function disambiguate(api, words, lengths) {
  const parts = words.map(word => encoder.encode(word));
  const total = parts.reduce((sum, part) => sum + part.length, 0);
  const input = api._malloc(Math.max(total, 1));
  const wordLengths = api._malloc(4 * Math.max(parts.length, 1));
  const sentenceLengths = api._malloc(4 * Math.max(lengths.length, 1));
  const out = api._malloc(8);
  const error = api._malloc(256);
  try {
    let at = 0;
    parts.forEach((part, i) => {
      api.HEAPU8.set(part, input + at);
      api.HEAPU32[(wordLengths >> 2) + i] = part.length;
      at += part.length;
    });
    lengths.forEach((length, i) => { api.HEAPU32[(sentenceLengths >> 2) + i] = length; });
    const status = api._crispembed_ar_morph_disambiguate(handle, model, input, wordLengths, parts.length,
      sentenceLengths, lengths.length, 1, out, out + 4, error, 256);
    if (status !== 0) throw new Error(`disambiguation failed (${status}): ${text(api, error)}`);
    const pointer = api.HEAPU32[out >> 2];
    const length = api.HEAPU32[(out + 4) >> 2];
    const result = api.HEAPU8.slice(pointer, pointer + length);
    api._crispembed_ar_morph_buffer_free(pointer);
    return result.buffer;
  } finally {
    api._free(input);
    api._free(wordLengths);
    api._free(sentenceLengths);
    api._free(out);
    api._free(error);
  }
}

// One compact batch buffer (crispembed_ar_morph_analyze_compact, duplicate
// analyses dropped): magic, word count, then per word a status (0 or 5 for a
// rejected word) and its record. Returned as a transferable ArrayBuffer.
const encoder = new TextEncoder();
function analyze(api, words) {
  const parts = words.map(word => encoder.encode(word));
  const total = parts.reduce((sum, part) => sum + part.length, 0);
  const input = api._malloc(Math.max(total, 1));
  const lengths = api._malloc(4 * Math.max(parts.length, 1));
  const out = api._malloc(8);
  const error = api._malloc(256);
  try {
    // Read the heap views after every allocation: growth replaces them.
    let at = 0;
    parts.forEach((part, i) => {
      api.HEAPU8.set(part, input + at);
      api.HEAPU32[(lengths >> 2) + i] = part.length;
      at += part.length;
    });
    const status = api._crispembed_ar_morph_analyze_compact(handle, input, lengths, parts.length, 1, out, out + 4,
      error, 256);
    if (status !== 0) throw new Error(`analysis failed (${status}): ${text(api, error)}`);
    const pointer = api.HEAPU32[out >> 2];
    const length = api.HEAPU32[(out + 4) >> 2];
    const result = api.HEAPU8.slice(pointer, pointer + length);
    api._crispembed_ar_morph_buffer_free(pointer);
    return result.buffer;
  } finally {
    api._free(input);
    api._free(lengths);
    api._free(out);
    api._free(error);
  }
}

// Serialize requests: one analyzer handle, one owner.
let queue = Promise.resolve();
self.onmessage = event => {
  const {id, request} = event.data ?? {};
  if (!Number.isSafeInteger(id) || typeof request !== 'object' || request === null) return;
  queue = queue.then(async () => {
    let api;
    try {
      api = await (module ??= load());
    } catch (error) {
      module = undefined;
      self.postMessage({id, unavailable: `Local Arabic morphology worker failed: ${error.message}`});
      return;
    }
    try {
      if (request.op === 'open') {
        const info = open(api, request.files, request.manifestSha256);
        self.postMessage({id, response: JSON.stringify({status: 'success', info: JSON.parse(info),
          heapBytes: api.HEAPU32.buffer.byteLength})});
      } else if (request.op === 'analyze' && handle) {
        const buffer = analyze(api, request.words);
        self.postMessage({id, buffer}, [buffer]);
      } else if (request.op === 'open_model') {
        const info = openModel(api, request.files, request.manifestSha256);
        self.postMessage({id, response: JSON.stringify({status: 'success', info: JSON.parse(info)})});
      } else if (request.op === 'disambiguate' && handle && model) {
        const buffer = disambiguate(api, request.words, request.lengths);
        self.postMessage({id, buffer}, [buffer]);
      } else if (request.op === 'disambiguate') {
        self.postMessage({id, response: JSON.stringify({status: 'failed',
          message: 'No Arabic morphology database or disambiguation model is open'})});
      } else if (request.op === 'stats') {
        self.postMessage({id, response: JSON.stringify({status: 'success', open: handle !== 0,
          heapBytes: api.HEAPU32.buffer.byteLength})});
      } else if (request.op === 'analyze') {
        self.postMessage({id, unavailable: 'No Arabic morphology database is open'});
      }
    } catch (error) {
      self.postMessage({id, fatal: request.op !== 'open' && request.op !== 'open_model', response: JSON.stringify({status: 'failed',
        message: `Arabic morphology failed: ${error.message}`})});
    }
  });
};
