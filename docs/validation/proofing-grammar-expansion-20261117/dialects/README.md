# Actual English dialect/runtime review

**Passed on Linux native and the shipped Wasm backend against source
`3a2ada5a04395fd2fa01c7878f4df9f1b9215558`.** The
[receipt](qualified/receipt.json) binds the built distribution, probe programs,
commands and all **337 consumed source inputs**, unchanged before and after
execution.

Each backend checked five canonical dialects (`en-US`, `en-GB`, `en-CA`,
`en-AU`, `en-IN`) and their explicit Latin-script/Unicode-preference aliases.
Ten requests ran sequentially and the same ten ran concurrently through the
same provider. Each response was successful and checked:

- Valid US `color/center` or GB/CA/AU/IN `colour/centre` spelling.
- The actual Harper `AnA` correction in surrounding prose.
- Original UTF-16 offsets after a preceding emoji and a nonzero text origin.
- Protection of a backtick span, URL and email address in the same paragraph.
- Correct canonical language routing.

Four unsupported requests (`en-NZ`, `en-Cyrl`, `en-GB-oxendict`, `de-DE`)
remained explicitly unsupported. The Wasm run created **one worker**, reused it
for all supported requests, and terminated it. These are 20 supported plus
four unsupported requests per backend, not 24 independent language examples.

The Wasm runner supplies Node Worker messaging and file fetch around the actual
shipped module; it does not replace the grammar engine. Browser/CSP acceptance
is separate and remains blocked, as recorded in [browser](../browser/README.md).
Native acceptance here covers Linux x86_64 only.

The existing full nine-stage Harper qualification also passed with **five Rust
tests, 33 Dart VM tests (zero skips), 29 JavaScript provider/source contracts,
five actual Wasm-worker checks and 11 compiled-Dart transport checks**. The VM
suite includes provider/source and lifecycle contracts as well as actual native
execution. See [its receipt](../runtime/harper-qualified/receipt.json).

To reproduce with the pinned runtime and a fresh audited native/Web build:

```sh
python3 packages/quds_proofing_harper/tool/build.py --native --web
python3 docs/validation/proofing-grammar-expansion-20261117/dialects/qualify_dialects.py \
  --repository . \
  --output ../proofing-dialects-replay
```
