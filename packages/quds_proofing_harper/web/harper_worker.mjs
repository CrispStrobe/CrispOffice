// Local module worker. Serve this next to the generated Harper .js/.wasm files.
// No text is fetched or posted: the only fetch loads the same-origin Wasm asset.
import init from './quds_proofing_harper.js';
let backend;
const encoder = new TextEncoder();
const decoder = new TextDecoder('utf-8', {fatal: true});

async function loadBackend() {
  const api = await init();
  if (api.quds_harper_abi_version() !== 1) throw new Error('Unsupported Harper ABI');
  return api;
}

function check(api, request) {
  const bytes = encoder.encode(request);
  const pointer = api.quds_harper_alloc(bytes.length);
  if (!pointer) throw new Error('Harper request exceeds its size limit');
  try {
    new Uint8Array(api.memory.buffer, pointer, bytes.length).set(bytes);
    const output = api.quds_harper_check(pointer, bytes.length);
    const length = api.quds_harper_result_len();
    if (!output || length < 1 || length > 16 * 1024 * 1024) throw new Error('Invalid Harper response buffer');
    return decoder.decode(new Uint8Array(api.memory.buffer, output, length));
  } finally {
    api.quds_harper_dealloc(pointer, bytes.length);
  }
}

// Serialize requests so output buffers and cached linter state have one owner.
let queue = Promise.resolve();
self.onmessage = event => {
  const {id, request} = event.data ?? {};
  if (!Number.isSafeInteger(id) || typeof request !== 'string') return;
  queue = queue.then(async () => {
    let api;
    try {
      api = await (backend ??= loadBackend());
    } catch (error) {
      backend = undefined;
      self.postMessage({id, unavailable: `Local Harper worker failed: ${error.message}`});
      return;
    }
    try {
      self.postMessage({id, response: check(api, request)});
    } catch (error) {
      self.postMessage({id, fatal: true, response: JSON.stringify({status:'failed',
        offsets:'unicode-scalar', findings:[], message:`Harper execution failed: ${error.message}`})});
    }
  });
};
