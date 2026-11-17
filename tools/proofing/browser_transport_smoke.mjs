#!/usr/bin/env node
// Run the existing compiled Dart acceptance program in a real local browser.
// Requires an existing Playwright installation and a sandbox-capable Chromium;
// it never installs tooling, substitutes Worker/fetch, or weakens the sandbox.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createServer} from 'node:http';
import {mkdir, mkdtemp, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import {dirname, isAbsolute, join, relative, resolve, sep} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {parseArgs} from 'node:util';

const repository = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const packageDirectory = join(repository, 'packages/quds_proofing_harper');
const {values: options} = parseArgs({options: {
  'build-output': {type: 'string', default: join(packageDirectory, 'build')},
  output: {type: 'string'},
  chromium: {type: 'string', default: '/usr/bin/chromium'},
  'playwright-module': {type: 'string', default: '/opt/codex/cua_node/lib/node_modules/playwright/index.mjs'},
  'timeout-ms': {type: 'string', default: '60000'},
  help: {type: 'boolean', default: false},
}});
if (options.help || !options.output) {
  console.log('Usage: node tools/proofing/browser_transport_smoke.mjs --output DIRECTORY [--build-output DIRECTORY] [--chromium PATH] [--playwright-module MODULE] [--timeout-ms 60000]');
  process.exit(options.help ? 0 : 2);
}
const buildDirectory = resolve(options['build-output']);
const outputDirectory = resolve(options.output);
const timeout = Number(options['timeout-ms']);
assert(Number.isSafeInteger(timeout) && timeout >= 1000 && timeout <= 300000, 'Invalid timeout');
await mkdir(outputDirectory, {recursive: true});
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const fileHash = async path => digest(await readFile(path));
const beneath = (directory, name) => {
  const path = resolve(directory, name);
  assert(path.startsWith(directory + sep), `Input escapes its source directory: ${name}`);
  return path;
};
const timestamp = () => new Date().toISOString();
const logs = [];
const record = message => logs.push(`${timestamp()} ${message}`);
const csp = "default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; worker-src 'self'; connect-src 'self'; img-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'";
const receipt = {
  schema_version: 1,
  started_at_utc: timestamp(),
  status: 'failed',
  mode: 'real Chromium module Worker over loopback HTTP with enforced CSP',
  scope: 'The unchanged compiled Dart smoke program uses browser-native Worker, fetch and WebAssembly; no Node Worker/fetch bridge is supplied.',
  content_security_policy: csp,
  chromium_sandbox_enabled: true,
  executable: resolve(options.chromium),
  playwright_module: options['playwright-module'],
  harness_sha256: await fileHash(fileURLToPath(import.meta.url)),
  build_directory: buildDirectory,
  server_requests: [],
  browser_requests: [],
  browser_responses: [],
  browser_request_failures: [],
  blocked_external_requests: [],
  console: [],
  page_errors: [],
  workers: [],
  errors: [],
  limits: [
    'Qualifies the supplied distribution in this Chromium/Linux runtime and this local HTTP/CSP configuration; it is not deployed-host, Firefox, Safari, or mobile acceptance.',
    'The compiled program retains its original Node-oriented scope label. The outer receipt records the actual browser execution environment.',
    'Consumer source hashes are a before/after snapshot of this run; compiled JavaScript and shipped Wasm hashes identify the exact bytes exercised.',
  ],
};

async function sourceSnapshot(buildReceipt) {
  const hashes = {};
  for (const [name, expected] of Object.entries(buildReceipt.source_sha256)) {
    const hash = await fileHash(beneath(packageDirectory, name));
    assert.equal(hash, expected, `Harper source differs from build receipt: ${name}`);
    hashes[`packages/quds_proofing_harper/${name}`] = hash;
  }
  // Dart imports the shared engine. Retain its entire library source snapshot,
  // rather than assuming a hand-maintained list covers transitive imports.
  async function visit(directory) {
    for (const entry of (await readdir(directory, {withFileTypes: true})).sort((a, b) => a.name.localeCompare(b.name))) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) await visit(path);
      else if (entry.isFile() && entry.name.endsWith('.dart')) {
        hashes[relative(repository, path).split(sep).join('/')] = await fileHash(path);
      }
    }
  }
  await visit(join(repository, 'packages/quds_office_engine/lib'));
  return hashes;
}

async function artifactSnapshot(buildReceipt) {
  const hashes = {};
  for (const [name, expected] of Object.entries(buildReceipt.files)) {
    const hash = await fileHash(beneath(buildDirectory, name));
    assert.equal(hash, expected, `Distribution differs from build receipt: ${name}`);
    hashes[name] = hash;
  }
  hashes['web_transport_smoke.js'] = await fileHash(join(buildDirectory, 'web_transport_smoke.js'));
  hashes['build-receipt.json'] = await fileHash(join(buildDirectory, 'build-receipt.json'));
  return hashes;
}

let server;
let context;
let profileDirectory;
let temporaryDirectory;
const originalTemporaryDirectory = process.env.TMPDIR;
let buildReceipt;
const liveWorkers = new Set();
try {
  buildReceipt = JSON.parse(await readFile(join(buildDirectory, 'build-receipt.json'), 'utf8'));
  assert.equal(buildReceipt.schema_version, 2, 'Expected source-bound build receipt');
  assert.equal(buildReceipt.source_unchanged_during_build, true);
  for (const name of ['web/harper_worker.mjs', 'web/quds_proofing_harper.js', 'web/quds_proofing_harper_bg.wasm']) {
    assert(Object.hasOwn(buildReceipt.files, name), `Missing web artifact binding: ${name}`);
  }
  receipt.source_sha256 = await sourceSnapshot(buildReceipt);
  receipt.artifacts_sha256 = await artifactSnapshot(buildReceipt);
  const bootstrap = Buffer.from(`globalThis.__qudsHarperCspViolations = [];
globalThis.addEventListener('securitypolicyviolation', event => {
  globalThis.__qudsHarperCspViolations.push({blockedURI: event.blockedURI, effectiveDirective: event.effectiveDirective, violatedDirective: event.violatedDirective});
});
globalThis.qudsHarperWorkerUrl = new URL('/assets/harper_worker.mjs', location.href).href;
globalThis.qudsHarperSmokeDone = result => { globalThis.__qudsHarperBrowserResult = JSON.parse(result); };
`);
  const html = Buffer.from('<!doctype html><meta charset="utf-8"><title>Local Harper browser acceptance</title><link rel="icon" href="/favicon.ico"><script src="/bootstrap.js"></script><script defer src="/smoke.js"></script>');
  const files = new Map([
    ['/', {bytes: html, type: 'text/html; charset=utf-8'}],
    ['/bootstrap.js', {bytes: bootstrap, type: 'text/javascript; charset=utf-8'}],
    ['/smoke.js', {bytes: await readFile(join(buildDirectory, 'web_transport_smoke.js')), type: 'text/javascript; charset=utf-8'}],
  ]);
  for (const name of ['harper_worker.mjs', 'quds_proofing_harper.js', 'quds_proofing_harper_bg.wasm']) {
    files.set(`/assets/${name}`, {
      bytes: await readFile(join(buildDirectory, 'web', name)),
      type: name.endsWith('.wasm') ? 'application/wasm' : 'text/javascript; charset=utf-8',
    });
  }
  receipt.served_sha256 = Object.fromEntries([...files].map(([path, file]) => [path, digest(file.bytes)]));
  assert.equal(receipt.served_sha256['/smoke.js'], receipt.artifacts_sha256['web_transport_smoke.js']);
  for (const name of ['harper_worker.mjs', 'quds_proofing_harper.js', 'quds_proofing_harper_bg.wasm']) {
    assert.equal(receipt.served_sha256[`/assets/${name}`], receipt.artifacts_sha256[`web/${name}`]);
  }
  server = createServer((request, response) => {
    const path = new URL(request.url, 'http://127.0.0.1').pathname;
    const file = files.get(path);
    const status = request.method !== 'GET' ? 405 : file ? 200 : path === '/favicon.ico' ? 204 : 404;
    const expectedMissingWorker = path === '/assets/missing_worker.mjs' && status === 404;
    receipt.server_requests.push({at_utc: timestamp(), method: request.method, path, status, content_type: file?.type ?? null, expected_missing_worker: expectedMissingWorker});
    record(`HTTP ${request.method} ${path} ${status}`);
    response.writeHead(status, {
      'Content-Type': file?.type ?? 'text/plain; charset=utf-8',
      'Content-Security-Policy': csp,
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      'Cross-Origin-Resource-Policy': 'same-origin',
    });
    response.end(status === 200 ? file.bytes : status === 204 ? undefined : 'Not found');
  });
  await new Promise((resolveListen, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolveListen);
  });
  const origin = `http://127.0.0.1:${server.address().port}`;
  receipt.origin = origin;
  // Playwright creates internal artifacts through os.tmpdir(). Keep those
  // real files inside the explicitly writable output directory as well.
  temporaryDirectory = await mkdtemp(join(outputDirectory, 'browser-tmp-'));
  process.env.TMPDIR = temporaryDirectory;
  const moduleSpecifier = isAbsolute(options['playwright-module'])
    ? pathToFileURL(options['playwright-module']).href : options['playwright-module'];
  const {chromium} = await import(moduleSpecifier);
  profileDirectory = await mkdtemp(join(outputDirectory, 'chromium-profile-'));
  context = await chromium.launchPersistentContext(profileDirectory, {
    executablePath: resolve(options.chromium),
    chromiumSandbox: true,
    headless: true,
    timeout,
    serviceWorkers: 'block',
  });
  receipt.browser_version = context.browser().version();
  const page = context.pages()[0] ?? await context.newPage();
  await context.route('**/*', async route => {
    const url = route.request().url();
    if (new URL(url).origin !== origin) {
      receipt.blocked_external_requests.push(url);
      await route.abort('blockedbyclient');
    } else {
      await route.continue();
    }
  });
  context.on('request', request => receipt.browser_requests.push({url: request.url(), method: request.method(), resource_type: request.resourceType()}));
  context.on('response', response => receipt.browser_responses.push({url: response.url(), status: response.status()}));
  context.on('requestfailed', request => receipt.browser_request_failures.push({url: request.url(), failure: request.failure()}));
  page.on('console', message => {
    const row = {type: message.type(), text: message.text(), location: message.location()};
    receipt.console.push(row);
    record(`CONSOLE ${row.type} ${row.text}`);
  });
  page.on('pageerror', error => {
    receipt.page_errors.push({name: error.name, message: error.message, stack: error.stack});
    record(`PAGE ERROR ${error.stack ?? error}`);
  });
  page.on('worker', worker => {
    const row = {url: worker.url(), created_at_utc: timestamp()};
    receipt.workers.push(row);
    liveWorkers.add(worker);
    record(`WORKER created ${row.url}`);
    worker.on('close', () => {
      row.closed_at_utc = timestamp();
      liveWorkers.delete(worker);
      record(`WORKER closed ${row.url}`);
    });
  });
  const response = await page.goto(origin, {waitUntil: 'load', timeout});
  assert.equal(response.status(), 200);
  receipt.observed_document_csp = await response.headerValue('content-security-policy');
  assert.equal(receipt.observed_document_csp, csp);
  await page.waitForFunction(() => globalThis.__qudsHarperBrowserResult !== undefined, null, {timeout});
  receipt.compiled_smoke_result = await page.evaluate(() => globalThis.__qudsHarperBrowserResult);
  receipt.csp_violations = await page.evaluate(() => globalThis.__qudsHarperCspViolations);
  receipt.user_agent = await page.evaluate(() => navigator.userAgent);
  assert.equal(receipt.compiled_smoke_result.status, 'passed', receipt.compiled_smoke_result.error);
  assert.equal(receipt.compiled_smoke_result.checks, 11, 'All 11 acceptance checks must execute');
  const passes = receipt.console.filter(row => row.text.startsWith('PASS '));
  assert.equal(passes.length, 11, 'Every acceptance check must report its assertion');
  receipt.passed_checks = passes.map(row => row.text.slice(5));
  const workerDeadline = Date.now() + 5000;
  while (liveWorkers.size && Date.now() < workerDeadline) await new Promise(resolveWait => setTimeout(resolveWait, 25));
  receipt.live_workers_after_smoke = liveWorkers.size;
  assert.equal(liveWorkers.size, 0, 'The Dart transport must terminate all browser workers');
  assert(receipt.workers.some(worker => worker.url === `${origin}/assets/harper_worker.mjs`), 'A real browser module Worker must start');
  assert(receipt.server_requests.some(request => request.expected_missing_worker), 'The actual missing-worker 404 path must execute');
  for (const path of ['/assets/harper_worker.mjs', '/assets/quds_proofing_harper.js', '/assets/quds_proofing_harper_bg.wasm']) {
    assert(receipt.server_requests.some(request => request.path === path && request.status === 200), `Missing real HTTP load: ${path}`);
  }
  assert.deepEqual(receipt.blocked_external_requests, [], 'Application attempted an external request');
  assert.deepEqual(receipt.csp_violations, [], 'CSP blocked application behavior');
  assert.deepEqual(receipt.page_errors, [], 'Unexpected browser runtime errors');
  const unexpectedHttp = receipt.server_requests.filter(request => request.status >= 400 && !request.expected_missing_worker);
  assert.deepEqual(unexpectedHttp, [], 'Unexpected HTTP errors');
  receipt.unexpected_console_errors = receipt.console.filter(row => row.type === 'error' && !row.location.url?.endsWith('/assets/missing_worker.mjs') && !row.text.includes('missing_worker.mjs'));
  assert.deepEqual(receipt.unexpected_console_errors, [], 'Unexpected browser console errors');
  receipt.status = 'passed';
} catch (error) {
  receipt.errors.push({name: error.name, message: error.message, stack: error.stack});
  record(`FAIL ${error.stack ?? error}`);
} finally {
  if (buildReceipt && receipt.source_sha256 && receipt.artifacts_sha256) {
    try {
      receipt.source_sha256_after = await sourceSnapshot(buildReceipt);
      receipt.artifacts_sha256_after = await artifactSnapshot(buildReceipt);
      receipt.source_unchanged_during_run = JSON.stringify(receipt.source_sha256) === JSON.stringify(receipt.source_sha256_after);
      receipt.artifacts_unchanged_during_run = JSON.stringify(receipt.artifacts_sha256) === JSON.stringify(receipt.artifacts_sha256_after);
      assert(receipt.source_unchanged_during_run, 'Source changed during browser acceptance');
      assert(receipt.artifacts_unchanged_during_run, 'Artifacts changed during browser acceptance');
      assert.equal(await fileHash(fileURLToPath(import.meta.url)), receipt.harness_sha256, 'Harness changed during browser acceptance');
    } catch (error) {
      receipt.status = 'failed';
      receipt.errors.push({name: error.name, message: error.message, stack: error.stack});
      record(`INTEGRITY FAIL ${error.stack ?? error}`);
    }
  }
  if (context) await context.close();
  if (server) {
    server.closeAllConnections();
    await new Promise(resolveClose => server.close(resolveClose));
  }
  if (profileDirectory) await rm(profileDirectory, {recursive: true, force: true});
  if (temporaryDirectory) await rm(temporaryDirectory, {recursive: true, force: true});
  if (originalTemporaryDirectory === undefined) delete process.env.TMPDIR;
  else process.env.TMPDIR = originalTemporaryDirectory;
  receipt.finished_at_utc = timestamp();
  const logPath = join(outputDirectory, 'browser.log');
  await writeFile(logPath, logs.join('\n') + '\n');
  receipt.log = 'browser.log';
  receipt.log_sha256 = await fileHash(logPath);
  await writeFile(join(outputDirectory, 'receipt.json'), JSON.stringify(receipt, null, 2) + '\n');
  console.log(JSON.stringify({status: receipt.status, checks: receipt.compiled_smoke_result?.checks ?? 0, browser: receipt.browser_version ?? null, output: outputDirectory, errors: receipt.errors.map(error => error.message)}));
  process.exitCode = receipt.status === 'passed' ? 0 : 1;
}
