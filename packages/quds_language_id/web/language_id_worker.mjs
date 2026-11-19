// Local module worker for the bundled language identifier (CLD3). Serve it
// next to quds_language_id.mjs/.wasm. The host posts the app's bundled,
// SHA-256-verified model bytes once; texts are classified here and nothing
// is fetched from or posted to anywhere else.
import createLanguageIdModule from './quds_language_id.mjs';

let module;
let handle = 0;
const OUT = 1024;

async function load() {
  // stderr of the loader ("lid_cld3: loaded ...") is not shown to users.
  const api = await createLanguageIdModule({print: () => {}, printErr: () => {}});
  if (api._quds_language_id_abi_version() !== 1) throw new Error('Unsupported language identifier ABI');
  return api;
}

const decoder = new TextDecoder();
const encoder = new TextEncoder();

function cString(api, pointer) {
  const end = api.HEAPU8.indexOf(0, pointer);
  return decoder.decode(api.HEAPU8.slice(pointer, end < 0 ? api.HEAPU8.length : end));
}

function open(api, bytes) {
  if (handle) { api._quds_language_id_close(handle); handle = 0; }
  const data = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const model = api._quds_language_id_alloc(data.length);
  const error = api._quds_language_id_alloc(256);
  try {
    api.HEAPU8.set(data, model);
    api.HEAPU8[error] = 0;
    handle = api._quds_language_id_open(model, data.length, error, 256);
    if (!handle) throw new Error(`The language model could not be opened: ${cString(api, error)}`);
  } finally {
    api._quds_language_id_free_buffer(model);
    api._quds_language_id_free_buffer(error);
  }
}

// [[label, probability], ...] per text, in input order (CLD3 labels).
function detect(api, texts, k) {
  const out = api._quds_language_id_alloc(OUT);
  const results = [];
  try {
    for (const text of texts) {
      const bytes = encoder.encode(text);
      const pointer = api._quds_language_id_alloc(bytes.length);
      let n;
      try {
        api.HEAPU8.set(bytes, pointer);
        n = api._quds_language_id_detect(handle, pointer, bytes.length, k, out, OUT);
      } finally {
        api._quds_language_id_free_buffer(pointer);
      }
      if (n < 0) throw new Error('language identification failed');
      const guesses = [];
      for (const line of cString(api, out).split('\n')) {
        const space = line.indexOf(' ');
        if (space > 0) guesses.push([line.slice(0, space), Number(line.slice(space + 1))]);
      }
      results.push(guesses);
    }
  } finally {
    api._quds_language_id_free_buffer(out);
  }
  return results;
}

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
      self.postMessage({id, unavailable: `Local language identifier failed: ${error.message}`});
      return;
    }
    try {
      if (request.op === 'open') {
        open(api, request.model);
        self.postMessage({id, response: JSON.stringify({status: 'success',
          heapBytes: api.HEAPU8.buffer.byteLength})});
      } else if (request.op === 'detect' && handle) {
        const k = Number.isSafeInteger(request.k) ? request.k : 3;
        self.postMessage({id, response: JSON.stringify({status: 'success',
          results: detect(api, request.texts, k)})});
      } else if (request.op === 'detect') {
        self.postMessage({id, unavailable: 'The language model is not open'});
      }
    } catch (error) {
      self.postMessage({id, fatal: request.op !== 'open', response: JSON.stringify({status: 'failed',
        message: `Language identification failed: ${error.message}`})});
    }
  });
};
