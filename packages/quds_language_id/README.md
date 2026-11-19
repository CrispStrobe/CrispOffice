# Bundled language identification (CLD3)

This package implements the engine's `LanguageIdentifier` interface with
Google's CLD3 language detector. Quds Office uses it to route each paragraph,
and each script run inside it, to the proofing providers of its detected
language. The policy and its thresholds live in the engine
(`language_identification.dart`); see
[docs/PROOFING.md](../../docs/PROOFING.md#automatic-language-detection-cld3--19-november-2026).

- **Runtime (part of the app):** the MIT adapter
  `native/src/quds_language_id.cpp` and the GGUF reader
  `native/src/gguf_shim.cpp` are compiled with CrispASR's
  `crisp_lid/src/lid_cld3.cpp`. That file is MIT, a port of Apache-2.0
  google/cld3, and is compiled unchanged from CrispASR commit `19d86f9b`
  (the last change to `crisp_lid/`).
  - **No ggml:** `lid_cld3.cpp` computes in plain C++ and uses ggml/gguf
    only to load weights. `native/shim/` supplies those few calls (`ggml.h`,
    `gguf.h` and `core/gguf_loader.h`) over a bounded GGUF v2/v3 reader that
    accepts F32 and F16 tensors only.
  - **Not compiled:** CrispASR's fastText backend and the
    `text_lid_dispatch` façade. CrispEmbed's `crispembed_lid_*` API links
    the same `crisp_lid` code with ggml; Quds does not need it.
- **Model (part of the app):** `assets/cld3-f16.gguf`, 439,712 bytes,
  Apache-2.0, Copyright 2016 Google Inc. It comes from `cstr/cld3-GGUF` at
  the immutable revision `56e8a57d479faa184dceede5f985d08d9816e999` and has
  SHA-256 `900813b6…f892`. It is a format conversion of the upstream weights.
  It is bundled because it is small and permissively licensed; users never
  download it. Flutter hosts load it as
  `packages/quds_language_id/assets/cld3-f16.gguf` (`Cld3Model.assetKey`).
  `Cld3LanguageIdentifier` refuses bytes that differ from the pin.

## Use

```dart
final data = await rootBundle.load(Cld3Model.assetKey);
final identifier = Cld3LanguageIdentifier(
  model: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  nativeLibraryPath: '/application/lib/libquds_language_id.so',
);
await identifier.load(); // about 20 ms; isAvailable turns true
await identifier.detect('Bonjour le monde'); // [fr 0.999, da 0.000, ...]
await identifier.detectBatch(['Привет мир', 'שלום עולם']); // ru…, he…
final detector = ParagraphLanguageDetector(identifier);
wordController.proofing.configureLanguageDetection(detector);
```

`detect` returns the top 5 `(language, probability)` pairs, best first.
CLD3's 109 labels map to BCP-47 tags (`cld3LabelToLanguage`):

- legacy codes are renamed: `iw` → `he`, `jw` → `jv`, `in` → `id`, `ji` → `yi`;
- romanized variants keep their script subtag (`zh-Latn`, `ru-Latn`,
  `bg-Latn`, `el-Latn`, `hi-Latn`, `ja-Latn`);
- `fil`, `haw`, `hmn`, `ceb` and `no` stay as they are.

Text without letters has no answer. Input beyond 4,096 bytes is cut at a
UTF-8 boundary.

The native library path can also come from the `QUDS_LANGUAGE_ID_LIBRARY`
Dart define. Otherwise the platform's library search looks for
`libquds_language_id.{so,dylib}` or `quds_language_id.dll`. On the web,
serve `language_id_worker.mjs`, `quds_language_id.mjs` and
`quds_language_id.wasm` together; the default URL is
`proofing/language_id_worker.mjs`. A missing library or worker, or a
tampered model, leaves `isAvailable` false and `failure` says why. `identify`
then returns empty lists, like `UnavailableLanguageIdentifier`.

## Build and package

```sh
python3 tool/build.py --native --wasm --output build      # host native + web
python3 tool/build.py --license-bundle                     # regenerate licenses/
python3 tool/build.py --verify-model                       # check assets/ against the pin
python3 tool/build.py --wasm --install-web ../quds_office_editor/example/web/proofing
python3 tool/build.py --native --install-native <App>.app/Contents/Frameworks
python3 tool/build.py --android --install-android <jniLibs>/arm64-v8a
python3 tool/build.py --install-licenses ../quds_office_editor/example/assets/licenses/language_id
```

`build.py` downloads exactly three CrispASR files (`lid_cld3.cpp`,
`lid_cld3.h` and `LICENSE`) from commit
`19d86f9b8c6b46bb35bef789c44ea403004f807c`. It admits each only when its
length and SHA-256 equal the pins, and refuses to build if a compiled file
or notice differs from `licenses/manifest.json`. `build-receipt.json` hashes
every output, and the adapter sources too. The web build needs Emscripten
(tested with 6.0.2) and uses non-resizable heap views, like the other Quds
workers.

Sizes (MinSizeRel):

| Output | Bytes |
| --- | ---: |
| macOS arm64 library | 103,272 |
| `quds_language_id.wasm` | 49,233 |
| `quds_language_id.mjs` | 9,604 |
| Worker | 3,775 |
| Model | 439,712 |

## Licences

- `quds_language_id`'s own adapter, shim and Dart code: MIT (`LICENSE`).
- CrispASR: MIT (`licenses/upstream/CrispASR-LICENSE`).
- The CLD3 model: Apache-2.0 (`licenses/model/CLD3-LICENSE`, from
  google/cld3 `b48dc465`), together with the GGUF model card
  (`licenses/model/cld3-GGUF-README.md`).

There is no GPL or LGPL code. Hosts must show the notices on their licence
page (`--install-licenses`); the Studio registers them in
`studio_licenses.dart`.

## Verification

```sh
QUDS_LANGUAGE_ID_TEST_LIBRARY=build/native/libquds_language_id.dylib dart test
node tool/web_smoke.mjs build/web assets/cld3-f16.gguf ud-sentences.txt
dart compile js -O2 tool/browser_smoke.dart -o out/smoke.js
python3 tool/browser_smoke.py --script out/smoke.js --web build/web --corpus ud-sentences.txt
dart compile exe tool/ud_evaluation.dart -o ud_eval
./ud_eval build/native/libquds_language_id.dylib <UD r2.14 test files> out.json
```
