# Optional local Harper proofing

This package connects Quds Office's asynchronous proofing contract to real
Harper 3.2.0 English spelling, grammar and style checks. It uses the published
`harper-core` crate whose `.cargo_vcs_info.json` identifies upstream commit
`ea9ab1b8f95be99a5d4040c53be92a6c2ad7f7f3`. Cargo.lock pins the complete resolved
graph. The optional thesaurus and concurrent feature are disabled; the
dependency's normal curated grammar and English dictionary remain enabled.

The native transport owns a persistent Dart isolate and loads the small Rust
FFI wrapper there. The browser transport owns a separate module Web Worker
and a Wasm build of the same wrapper. Neither transport sends document text
to a server. The browser fetches its locally hosted code/Wasm assets only.

## Use

```dart
final english = HarperProofingProvider(
  nativeLibraryPath: '/application/lib/libquds_proofing_harper.so',
  workerUrl: Uri.base.resolve('proofing/harper_worker.mjs'),
);
final service = OfficeProofingService(providers: [english]);
```

The native path can also be supplied with the `QUDS_HARPER_LIBRARY` Dart define;
otherwise the platform's normal dynamic-library search looks for
`libquds_proofing_harper.so`, `libquds_proofing_harper.dylib`, or
`quds_proofing_harper.dll`. Native packaging is explicit. Missing or incompatible
libraries and missing worker assets report **unavailable**. The provider
accepts `en`, `en-US`, `en-GB`, `en-CA`, `en-AU` and `en-IN`; other language tags
report **unsupported** and never reach the English backend.

Harper's scalar offsets are converted to UTF-16 before constructing a finding;
the shared contract adds the request's segment origin. Suggestions include
replacement, deletion, and insert-after normalization. Findings keep upstream
rule names under `harper.` so rule ignores are request-scoped. Invalid data,
backend failures and timeouts report **failed**, with no fabricated clean
result. A timeout disposes the worker. Dispose the provider when its host
document/service closes.

A request is limited to 32,768 Unicode scalar characters and 2,000 findings.
Exceeding either bound is an explicit failure. This keeps oversized paragraphs
from starting unbounded background work; it does not silently truncate a check.
Results remain reviewable suggestions. Nothing changes the document directly.

## Build and package

The validated toolchain is Rust 1.100.0. Install its
`wasm32-unknown-unknown` standard library for browser builds. The Wasm glue
generator must match Cargo.lock: `wasm-bindgen-cli` 0.2.130.

```sh
rustup toolchain install 1.100.0 --profile minimal
rustup target add wasm32-unknown-unknown --toolchain 1.100.0
cargo +1.100.0 install wasm-bindgen-cli --version 0.2.130 --locked
python3 packages/quds_proofing_harper/tool/build.py --native --web
```

Build from the matching source checkout; the helper invokes Cargo with
`--locked`. Native output is under `build/native`. Serve all three files from
`build/web` together at the configured `proofing/` URL:
`harper_worker.mjs`, `quds_proofing_harper.js`, and
`quds_proofing_harper_bg.wasm`. The `.d.ts` declarations are optional development
output. The host's CSP must permit same-origin module workers and Wasm. This
package deliberately does not fall back to a CDN or an HTTP grammar service.

Ship `build/licenses/manifest.json` and
`build/licenses/notices-and-mpl-sources.tar.gz` with the binaries, and expose
them in the host's third-party notices. The build helper creates those files
only after the active dependency licenses and original notices pass the audit.
`build-receipt.json` records the compiler, lockfile and generated artifact hashes.

### License boundary

Harper itself is Apache-2.0. The wrapper follows this fork's MIT license.
The license audit selects MIT/BSD/Apache alternatives where available and
accepts MPL-2.0 with its exact unmodified source archives included. Original
copyright, permission and NOTICE files are copied byte for byte. Where a crate
omits the repository-root license from its published package, the fallback is
retrieved at that crate's exact recorded source revision and its digest is
preserved.

The actual transitive graph also contains reviewed ancillary **Unicode-3.0**,
**Zlib** and **CC0-1.0** terms. They are recorded individually, not relabeled
MIT or Apache. The audit also explicitly recognizes ISC for target-specific
permissive components. See [the manifest](licenses/manifest.json) for exact
expressions, selected branches, target membership, source checksums and notice
digests. Unknown expressions or missing original notices stop packaging;
GPL/AGPL/LGPL-only components are rejected. New platforms require the same
audit for their actual target graph.

## Validation

```sh
cargo test --locked --manifest-path packages/quds_proofing_harper/native/Cargo.toml
cd packages/quds_proofing_harper
QUDS_HARPER_TEST_LIBRARY="$PWD/build/native/libquds_proofing_harper.so" dart test
dart test --platform node test/harper_provider_test.dart
node tool/smoke_worker.mjs build/web/harper_worker.mjs
```

The native integration test deliberately skips when no explicit test library
is configured; the validation receipt must identify that skip. The recorded
Linux run supplies the real built library. The Node worker harness executes
the exact shipped worker and real Wasm; it substitutes only the Worker message
bridge and local file fetch. It is not evidence of browser CSP, HTTP hosting,
mobile OS dictionaries, or an end-user browser session. Those acceptance
boundaries are separate from the exercised native and Wasm engines.

## Mobile system spelling

`OfficePlatformSpellingProvider` lives in `quds_office_editor`, keeping Flutter
and `dart:ui` out of the engine. It wraps Flutter's `DefaultSpellCheckService`
on Android/iOS, queues calls because the system channel supports one pending
request, and clears the framework's text-only cache between languages. The
host supplies the installed `supportedLanguages`; Flutter does not offer a
reliable dictionary-availability enumeration. A null platform result is a
failed request; an empty successful list is distinct. Mobile runtime behavior
requires device acceptance in addition to the mock-channel adapter tests.

## Primary sources

- [Pinned Harper source](https://github.com/Automattic/harper/tree/ea9ab1b8f95be99a5d4040c53be92a6c2ad7f7f3)
- [Pinned Harper LICENSE](https://github.com/Automattic/harper/blob/ea9ab1b8f95be99a5d4040c53be92a6c2ad7f7f3/LICENSE)
- [Harper 3.2.0 crate](https://crates.io/crates/harper-core/3.2.0)
- [Flutter system spelling API](https://api.flutter.dev/flutter/services/DefaultSpellCheckService-class.html)
- [Flutter null-result contract](https://api.flutter.dev/flutter/services/DefaultSpellCheckService/fetchSpellCheckSuggestions.html)
