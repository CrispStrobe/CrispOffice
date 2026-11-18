# Runtime provenance for document review drafts

This directory preserves the runtime and dependency identities used for the frozen source `bfa88aab88a74028285619dfa07f3a81868fe59b` (tree `3418afd634efcaaa14c4712103f69ae5e817bffd`). It contains no SDK or Pub cache binaries. The runtime receipts are exact copies; compressed files decompress to the original bytes. `manifest.json` records both stored and uncompressed SHA-256 hashes.

## Recorded environment

- Flutter 3.47.8, Dart 3.13.7, Linux x64.
- Official archive: https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.8-stable.tar.xz
- Archive SHA-256: `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
- The archive was streamed and fully verified before any SDK executable was invoked. Selected runtime files were extracted; native platform build artifacts were not all retained.
- Executable hashes, exact archive size, Flutter framework/engine revisions and restoration commands are in `runtime.json`.

## Original and final dependency states

| State | Workspace packages | Verified hosted archives | Workspace lock SHA-256 |
| --- | ---: | ---: | --- |
| Before late Mail merge | 111 | 162 | `344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130` |
| Final frozen source | 121 | 168 | `43261dbd4acce9c423c8f19f5c86841a9f05aff3b3b968c94a7b48f94c9f8239` |

`original/` preserves the first runtime receipt, package configuration, hosted-archive receipt and workspace lock. The final equivalents are at this directory's root. Package configurations are historical machine-local evidence, not portable configuration to copy into a different checkout.

The late Mail integration added six hosted dependencies (`asn1lib`, `basic_utils`, `encrypter_plus`, `enough_convert`, `pointycastle`, `synchronized`) and the path package `enough_mail`. Existing locked entries did not change. The exact versions and archive hashes came from the incoming `third_party/enough_mail/DEPENDENCIES.json`, preserved here as `enough-mail-DEPENDENCIES.json`. Each new archive was downloaded and hash-verified before offline resolution. Both `dart pub get --offline` and `dart pub get --offline --enforce-lockfile` passed; logs are in `logs/`.

The update receipt names local commit `20090caada5d8309e30ec0065c5ce1853aaaf72d` because it was written before publication. Its recorded tree `3418afd634efcaaa14c4712103f69ae5e817bffd` equals the published frozen tree. The original receipt was preserved rather than edited to erase the dependency transition. `provenance.json` links the identities.

## Reproduce the final runtime

Use a clean checkout of `bfa88aab88a74028285619dfa07f3a81868fe59b`, Python 3.12 or newer with PyYAML, approximately 3 GB of free disk space, and access to `storage.googleapis.com` and `pub.dev`. Choose a fresh runtime directory outside the checkout.

```sh
python3 /path/to/this/runtime/restore_runtime.py \
  --repo /path/to/quds_office_suite \
  --runtime-root /path/to/fresh-review-runtime
. /path/to/fresh-review-runtime/env.sh
```

The adapter requires the recorded tracked tree, verifies the saved final lock and archived bootstrap, and substitutes explicit paths plus the final lock into that bootstrap. It then downloads the exact official SDK, verifies its full archive and executable hashes, restores the hash-pinned Pub archives, and runs offline lock enforcement. It regenerates package configuration and executable wrappers for the new location. The final lock automatically includes the six Mail archives, so replay does not need to repeat the historical two-stage dependency transition.

`restore_runtime.py` is a convenience adapter prepared during evidence packaging. It was syntax-checked and its string substitutions were verified, but it was **not executed as part of acceptance**. The scripts actually used during preparation are preserved unchanged as `scripts/bootstrap_runtime.py.gz` and `scripts/refresh_mail_runtime.py.gz`; their historical absolute paths are expected.

Run Dart/Flutter operations serially with test concurrency one in this resource-constrained environment. Concurrent test compilers and analyzers caused interrupted development attempts; those are indexed separately under `../attempts/` and do not count toward acceptance.

## Scope and handling

Only explicitly selected receipts, locks, scripts and logs are included. No process environment dump, credential store, SDK, package cache or unrelated configuration was copied. A scan of uncompressed contents found no common secret/token/private-key patterns, authenticated URLs, authorization values or credential assignments; no redaction was needed. The environment helper includes only runtime paths and analytics/CI settings.

This directory records runtime preparation, not an acceptance result. Final frozen-source test reports and visual verification are maintained separately. No GitHub Actions status was queried or awaited.
