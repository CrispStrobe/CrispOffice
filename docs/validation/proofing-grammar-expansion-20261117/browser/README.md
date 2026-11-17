# Real browser attempt

The existing real Chromium HTTP/CSP harness was attempted once with the sandbox
enabled. Chromium aborted during process-singleton initialization because
`socket()` returned `EPERM`. It never loaded the page.

The [receipt](receipt.json) records **zero page requests, zero workers and zero
browser acceptance checks**, plus the exact source/artifact hashes and browser
error. [browser-run.log](browser-run.log) retains the launch result. This is a
blocked attempt, not passing browser acceptance. The successful native and
Node/Wasm results are recorded separately.

In a sandbox-capable browser environment, after building and verifying Harper:

```sh
node tools/proofing/browser_transport_smoke.mjs \
  --output ../proofing-browser-replay \
  --timeout-ms 30000
```

The harness uses actual browser Worker/fetch/WebAssembly, loopback HTTP and an
enforced CSP. No sandbox relaxation was used in this attempt.
