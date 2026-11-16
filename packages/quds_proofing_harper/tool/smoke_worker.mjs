import assert from 'node:assert/strict';
import {Worker} from 'node:worker_threads';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

const module = pathToFileURL(resolve(process.argv[2] ?? 'build/web/harper_worker.mjs')).href;
const worker = new Worker(new URL('./node_worker_bridge.mjs', import.meta.url), {workerData: {module}});
let sequence = 0;
const pending = new Map();
worker.on('message', message => {
  const handler = pending.get(message.id);
  pending.delete(message.id);
  if (message.unavailable) handler?.reject(new Error(message.unavailable));
  else handler?.resolve(JSON.parse(message.response));
});
worker.on('error', error => {for (const handler of pending.values()) handler.reject(error); pending.clear();});
function check(text, language = 'en-US', ignored_rules = []) {
  const id = ++sequence;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {pending.delete(id); reject(new Error('Harper worker timed out'));}, 30000);
    pending.set(id, {resolve: value => {clearTimeout(timer); resolve(value);}, reject: error => {clearTimeout(timer); reject(error);}});
    worker.postMessage({id, request: JSON.stringify({text, language, ignored_rules})});
  });
}
try {
  const text = '😀 This is an test.';
  const first = await check(text);
  assert.equal(first.status, 'success');
  assert.equal(first.offsets, 'unicode-scalar');
  const article = first.findings.find(finding => finding.rule === 'harper.AnA');
  assert.ok(article);
  assert.equal([...text].slice(article.start, article.end).join(''), 'an');
  assert.equal([...text].slice(0, article.start).join('').length, 11);
  assert.deepEqual(article.replacements, ['a']);
  const [ignored, unsupported, repeated] = await Promise.all([
    check(text, 'en-US', ['harper.AnA']), check('Das ist richtig.', 'de-DE'), check(text),
  ]);
  assert.equal(ignored.status, 'success');
  assert.ok(!ignored.findings.some(finding => finding.rule === 'harper.AnA'));
  assert.equal(unsupported.status, 'unsupported');
  assert.ok(repeated.findings.some(finding => finding.rule === 'harper.AnA'));
  const oversized = await check('a'.repeat(32769));
  assert.equal(oversized.status, 'failed');
  console.log(JSON.stringify({status:'passed', checks:5, worker:module,
    scope:'Exact shipped module worker and real Wasm; Node bridge substitutes file fetch and Worker messaging only.'}));
} finally {
  await worker.terminate();
}
