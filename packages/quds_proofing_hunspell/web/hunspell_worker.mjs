// Local module worker for the optional Hunspell backend. Serve it next to the
// bundled quds_proofing_hunspell.mjs/.wasm (part of the app, never downloaded).
// Dictionary bytes arrive from the host (the user's verified download); no
// text or dictionary is fetched or posted elsewhere.
import createHunspellModule from './quds_proofing_hunspell.mjs';

let module;
let handle = 0;

async function load() {
  const api = await createHunspellModule();
  if (api._quds_hunspell_abi_version() !== 1) throw new Error('Unsupported Hunspell ABI');
  return api;
}

function withString(api, text, body) {
  const pointer = api.stringToNewUTF8(text);
  try { return body(pointer); } finally { api._free(pointer); }
}

function open(api, aff, dic) {
  if (handle) { api._quds_hunspell_close(handle); handle = 0; }
  api.FS.writeFile('/dictionary.aff', aff);
  api.FS.writeFile('/dictionary.dic', dic);
  handle = withString(api, '/dictionary.aff', a => withString(api, '/dictionary.dic', d => api._quds_hunspell_open(a, d)));
  // The engine keeps its own copy; drop the in-memory files.
  api.FS.unlink('/dictionary.aff');
  api.FS.unlink('/dictionary.dic');
  if (!handle) throw new Error('The dictionary could not be opened (UTF-8 .aff/.dic required)');
}

function check(api, words, suggest) {
  const length = api._malloc(4);
  try {
    return words.map((word, index) => withString(api, word, pointer => {
      const state = api._quds_hunspell_spell(handle, pointer);
      if (state < 0) throw new Error('Hunspell rejected a word');
      if (state === 1) return {ok: true};
      if (!suggest[index]) return {ok: false, suggestions: []};
      const out = api._quds_hunspell_suggest(handle, pointer, length);
      if (!out) throw new Error('Hunspell suggestion failed');
      const size = api.HEAPU32[length >> 2];
      const text = size ? api.UTF8ToString(out, size) : '';
      return {ok: false, suggestions: text ? text.split('\n') : []};
    }));
  } finally {
    api._free(length);
  }
}

// Serialize requests: one engine handle, one owner.
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
      self.postMessage({id, unavailable: `Local Hunspell worker failed: ${error.message}`});
      return;
    }
    try {
      if (request.op === 'open') {
        open(api, new Uint8Array(request.aff), new Uint8Array(request.dic));
        self.postMessage({id, response: JSON.stringify({status: 'success', results: []})});
      } else if (request.op === 'check' && handle) {
        const results = check(api, request.words, request.suggest);
        self.postMessage({id, response: JSON.stringify({status: 'success', results})});
      } else {
        self.postMessage({id, unavailable: 'No Hunspell dictionary is open'});
      }
    } catch (error) {
      self.postMessage({id, fatal: true, response: JSON.stringify({status: 'failed', results: [],
        message: `Hunspell execution failed: ${error.message}`})});
    }
  });
};
