// Local module worker for the optional Arabic morphology backend. Serve it
// next to the bundled quds_arabic_morph.mjs/.wasm (part of the app, never
// downloaded). The Camel Morph database bytes arrive from the host (the
// user's verified download); no text or data is fetched or posted elsewhere.
import createArabicMorphModule from './quds_arabic_morph.mjs';

let module;
let handle = 0;
const BUNDLE = '/camel-morph';

async function load() {
  const api = await createArabicMorphModule();
  if (api._quds_arabic_morph_adapter_version() !== 1 || api._crispembed_ar_morph_abi_version() !== 1) {
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
    // The analyzer keeps its own parsed copy; drop the in-memory files.
    for (const path of written) { try { api.FS.unlink(path); } catch (_) { /* gone */ } }
  }
  return text(api, api._crispembed_ar_morph_info(handle));
}

// One JSON document: {"status":"success","results":[<analyses array>|null, ...]}
// in input order; null marks a word the analyzer rejected (input error).
function analyze(api, words) {
  const out = api._malloc(8);
  const error = api._malloc(256);
  const parts = [];
  try {
    for (const word of words) {
      const status = withString(api, word, pointer => api._crispembed_ar_morph_analyze(
        handle, pointer, api.lengthBytesUTF8(word), out, out + 4, error, 256));
      if (status === 0) {
        const json = api.HEAPU32[out >> 2];
        const length = api.HEAPU32[(out + 4) >> 2];
        parts.push(text(api, json, length));
        api._crispembed_ar_morph_string_free(json);
      } else if (status === 5) {
        parts.push('null');
      } else {
        throw new Error(`analysis failed (${status}): ${text(api, error)}`);
      }
    }
  } finally {
    api._free(out);
    api._free(error);
  }
  return `{"status":"success","results":[${parts.join(',')}]}`;
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
        self.postMessage({id, response: analyze(api, request.words)});
      } else if (request.op === 'stats') {
        self.postMessage({id, response: JSON.stringify({status: 'success', open: handle !== 0,
          heapBytes: api.HEAPU32.buffer.byteLength})});
      } else if (request.op === 'analyze') {
        self.postMessage({id, unavailable: 'No Arabic morphology database is open'});
      }
    } catch (error) {
      self.postMessage({id, fatal: request.op !== 'open', response: JSON.stringify({status: 'failed',
        message: `Arabic morphology failed: ${error.message}`})});
    }
  });
};
