# Local runtime restoration and Harper qualification

Local validation used **Flutter 3.47.8, Dart 3.13.7, Rust 1.100.0,
wasm-bindgen 0.2.130**, and the recorded Node runtime. No GitHub Actions were
queried, rerun, or waited on.

The [setup receipt](runtime-setup-receipt.json),
[official Flutter release entry](flutter-release.json), and
[Pub cache receipt](pub-cache-receipt.json) retain exact hashes and versions.
The official 1,581,444,364-byte Flutter archive matched SHA-256
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`, as published
in the [official release index](https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json).
All **162 pinned Pub archives** were SHA-256 verified before extraction.

The ignored workspace lock was restored from the prior checked-in
`docs/validation/proofing-en-de-20261117/integration/pubspec.lock` and retained
SHA-256 `344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.
Offline enforced resolution passed. The SDK's own Flutter-tools lock also
retained its prior recorded hash. No dependency constraints were changed.

The Rust installer was checked against its official SHA-256 file, and the
pinned wasm-bindgen archive matched its recorded upstream digest. Both Linux
native and `wasm32-unknown-unknown` targets were installed. Locked Cargo fetch
completed.

An initial offline Pub attempt rejected cache checksum files containing trailing
newlines. The checksum values and archives were correct; writing the exact
64-character format expected by Pub fixed resolution. The failed attempt is
retained in [flutter-tools-pub-get-first-attempt.log](flutter-tools-pub-get-first-attempt.log).

The initial Harper native/Web build compiled successfully and validated its
license graph, but correctly rejected a receipt when provider tests changed
during the build. [harper-build-source-race.log](harper-build-source-race.log)
retains that attempt. The subsequent incremental rebuild used stable sources
and passed, followed by the complete nine-stage
[Harper qualification](harper-qualified/receipt.json).

## Reproduction

Use the pinned versions, restore the exact workspace lock, and populate the
Pub cache from the recorded archive/version/SHA list. The
[cache preparation program](prepare_pub_cache.py) performs the verified
download/extraction procedure into an explicit destination. The
[activation script](activate.sh) records the original tool and
cache paths and environment settings.

With local equivalents of those paths on `PATH`:

```sh
python3 docs/validation/proofing-grammar-expansion-20261117/runtime/prepare_pub_cache.py \
  --repository . --output-root ../proofing-runtime
# Set PUB_CACHE to the absolute proofing-runtime/cache/pub path.
flutter pub get --offline --enforce-lockfile
cargo fetch --locked --manifest-path packages/quds_proofing_harper/native/Cargo.toml
python3 packages/quds_proofing_harper/tool/build.py --native --web
python3 packages/quds_proofing_harper/tool/verify.py --output ../harper-replay
```

Source receipts and command logs are saved; SDKs, caches and release
native/Wasm binaries are reproducible from those inputs and are not committed.
