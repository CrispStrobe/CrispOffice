# Qualification before concurrent integration

The saved Quds implementation `039c1e293052f548367f9ea3b0fa5ff56949ccaa`
passed 636 disjoint Dart/Flutter tests. The companion host implementation
`501c3a6667c7e295b3702a7d2857170eec6af416` passed 41 host tests and 28 Python
sync/verifier tests. Strict analysis, formatting and input-integrity checks
passed in both. This evidence has its own exact pins and is not added to the
later combined-source totals.

The final remote check found new ODS, proofing and host keychain/favorites
work. Those sources are reconciled separately before final delivery.

The complete canonical receipt and runner are in `pre-concurrent-canonical/`;
the companion repo contains `pre-concurrent-host/`. Large before/after maps are
stored as lossless `.json.gz` files. Decompress them with `gzip -dk *.json.gz`
to restore the exact original JSON filenames and hashes listed by the receipt
and artifact inventory. Runtime setup is the existing pinned bootstrap under
`../zotero-continuation-20261116/setup/`.

The behavioral controls in `behavioral-controls/` and `backoff-controls/`
compile identical fixtures against their old/new archived source pins. Their
expected failures are retained with nonzero exits and excluded from totals.
No GitHub Actions or CI status checks were queried, awaited, or rerun.

Raw negative-control output contains whitespace emitted by the test runner.
Those four `*-before.log` / `before.log` artifacts are saved losslessly as
`.log.gz` files; `gzip -dk` restores the original paths and bytes referenced
by the control receipts. Passing logs remain plain text.
