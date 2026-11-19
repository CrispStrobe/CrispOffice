# Optional local Arabic morphology

This package implements the engine's `ArabicMorphology` interface with the
native Camel Morph analyzer from CrispEmbed, a C++ port of the camel_tools
1.6.0 analyzer. It reads the Camel Morph MSA v1.0 database, which the
**user downloads from inside the app**. Nothing is downloaded or enabled by
default.

- **Analyzer (part of the app):** the MIT adapter
  `native/src/quds_arabic_morph.cpp` compiled with CrispEmbed's
  `src/arabic_morph.cpp`. That file is MIT and keeps camel_tools' MIT notice.
  Its header-only helpers and Ryu (Apache-2.0 option) are compiled in too.
  The sources come from CrispEmbed commit `8e40ad88` (PR #254). Native
  platforms load it as a shared library in a persistent Dart isolate. The web
  build runs the same code as a bundled Emscripten WebAssembly module in a
  module Web Worker. No analyzer code is ever downloaded (App Store guideline
  2.5.2).
- **Database (downloaded data):** the `noprob` bundle of
  [`cstr/camel-morph-msa-v1.0`](https://huggingface.co/cstr/camel-morph-msa-v1.0/tree/b31cf4a83f8ad63bb1989cf2879e72f23fadbfb0/noprob),
  at the immutable revision `b31cf4a8…`. It has four files and 74.5 MB:
  `manifest.json`, the 78,083,392-byte database, `NOTICE` and `LICENSE`. The
  data is CC BY 4.0, © 2024 New York University Abu Dhabi. The app must show
  the attribution in `NOTICE` (`camelMorphMsaNoprob.attribution`).
- **Installation:** `MorphInstaller` (`package:quds_arabic_morph/installer_io.dart`)
  works like the Hunspell installer:
  - it streams each pinned file into private staging;
  - it admits a file only when its length and SHA-256 equal the compiled-in
    catalog (`camelMorphMsaNoprob`);
  - it publishes the tree as `<root>/arabic_morph/<revision>-<id>` with one
    rename and verifies it again;
  - `remove` renames the tree before deleting it.

  The analyzer then checks the manifest against the pinned SHA-256, and every
  listed file against the manifest, before it parses anything. On the web,
  the host fetches the four files itself and passes them through
  `MorphDatabaseBytes.verified`.

## Why `noprob`, and why no ranking

The `full` bundle also carries `lex_logprob`/`pos_lex_logprob` values, which
Camel Morph estimated on the Penn Arabic Treebank. That treebank is LDC data.
The owner chose `noprob`, which drops exactly those 351,926 values and keeps
every other byte. The analyses are the same: CrispEmbed's receipt shows
identical analysis sets for all 7,567 analyzable UD Arabic-PUD words.
Only out-of-context ranking changes. Without the probabilities, camel_tools'
order falls back to the diacritized form, and top-1 UPOS+lemma accuracy drops
from 73.0% to 47.0%.

Quds therefore never ranks: `analyzeWords` returns every analysis in no
particular order. Rules reason over the whole set, for example by reporting
only when **no** analysis of a word is compatible. The `*_logprob` features
appear as the constant `-99.0`.

## Use

```dart
import 'package:quds_arabic_morph/installer_io.dart';
import 'package:quds_arabic_morph/quds_arabic_morph.dart';

// After the user chose "Download" in the Dictionaries dialog:
final files = await MorphInstaller(applicationSupportDirectory)
    .install(camelMorphMsaNoprob, onProgress: report);
final morphology = CamelArabicMorphology(
  database: files,
  nativeLibraryPath: '/application/lib/libquds_arabic_morph.so',
);
await morphology.load(); // about 1.3 s; isAvailable turns true
final analyses = await morphology.analyzeWords(['كتبوا', 'والمدرسة']);
// analyses['كتبوا'] contains {lex: كَتَب, pos: verb, num: p, ...}
```

Keep one `CamelArabicMorphology` while the database is installed. Proofing
providers are recreated for each configuration, but this object is not.
Dispose it before `MorphInstaller.remove`.

The native library path can also come from the `QUDS_ARABIC_MORPH_LIBRARY`
Dart define. Otherwise the platform's library search looks for
`libquds_arabic_morph.{so,dylib}` / `quds_arabic_morph.dll`. On the web,
serve `arabic_morph_worker.mjs`, `quds_arabic_morph.mjs` and
`quds_arabic_morph.wasm` together (the default URL is
`proofing/arabic_morph_worker.mjs`). A missing library, worker or database,
or a tampered file, leaves `isAvailable` false (`failure` says why), and
`analyzeWords` then returns empty lists, like `UnavailableArabicMorphology`.

## Behaviour

- **Input:** words are passed as they appear, with harakat and tatweel.
  The analyzer applies camel_tools' normalization and backoff `NONE`.
  Diacritized input keeps only the compatible analyses.
- **Output:** every requested word is a key of the result. Unknown words,
  words the analyzer rejects (over 4,096 UTF-8 bytes) and the empty string
  map to an empty list.
- **Features:** analyses are read-only maps of camel_tools features (`lex`,
  `pos`, `gen`, `num`, `cas`, `stt`, `asp`, `per`, `vox`, `prc0`–`prc3`,
  `enc0`, `diac`, `bw`, `gloss`, …). `null` features are omitted, and
  numbers become decimal text. Analyses with the same feature layout share
  one key list, and repeated values are interned.
- **Batching and cache:** distinct words go to the worker in batches of 512.
  Results are cached for the session, with least-recently-used eviction
  after 4,096 distinct words (about 90 MB).

## Performance and memory

These figures were measured on an Apple M1 (macOS 26.2, Dart 3.13.7, a shared
machine with load 3–7). The corpus is the 1,000 UD Arabic-PUD r2.14 test
`# text` lines: 15,676 Arabic tokens and 7,419 distinct words, of which
7,144 are analyzed (215,212 analyses). Tools:
`tool/pud_benchmark.dart` (AOT), `tool/web_smoke.mjs` (Node 26) and
`tool/browser_smoke.{dart,py}` (headless Chrome 157, dart2js).

| | Load | Distinct words/s (cold) | Memory |
| --- | ---: | ---: | --- |
| Native (FFI isolate, 3 runs) | 1.19–1.41 s, incl. SHA-256 of all files | 1,240–1,360 | 250 MB RSS after load; 415 MB with all 7,419 words cached |
| Wasm worker in Node | 1.51–1.63 s | 1,075–1,460 | 320 MB Wasm heap (it does not shrink); about 340 MB process growth |
| Wasm worker in Chrome, via the Dart web transport | 1.50–1.97 s | 600–890 | 320 MB Wasm heap in the worker. The page heap holds 76 MB of bundle bytes before opening and 1–2 MB after (the buffers are transferred), then 200–340 MB with all 7,419 words' analyses alive |

Cached words return in about 1 ms for the whole corpus. The analyzer alone
runs at about 2,250 words/s natively. The Dart side adds JSON parsing of 190
MB of analyses (about 26 kB per word) and building the compact maps. A
custom byte-level parser could roughly double throughput, so this remains
open.

**Browser memory:** a tab needs roughly 320 MB of Wasm memory plus the
analyses it keeps. That is fine for desktop browsers. It is risky on phones
and low-memory tablets, where Safari and Chrome may kill the worker; the
analyzer then reports itself unavailable. The download is kept only for the
session, so a reload needs a new download.

## Build and package

```sh
python3 tool/build.py --native --wasm --output build      # host native + web
python3 tool/build.py --license-bundle                     # regenerate licenses/
```

Host packaging copies only receipt-verified outputs:

```sh
# Web: worker, module and wasm plus notices under licenses/arabic_morph/.
python3 tool/build.py --wasm --install-web ../quds_office_editor/example/web/proofing
# macOS: library into the app bundle, notices into Resources, then re-sign.
python3 tool/build.py --native \
  --install-native <App>.app/Contents/Frameworks \
  --install-licenses <App>.app/Contents/Resources/arabic-morph-licenses
codesign --force --sign <identity> <App>.app/Contents/Frameworks/libquds_arabic_morph.dylib
codesign --force --deep --sign <identity> --entitlements <Release.entitlements> <App>.app
# Android: arm64-v8a with the NDK (static libc++) into jniLibs.
python3 tool/build.py --android \
  --install-android ../quds_office_editor/example/android/app/src/main/jniLibs/arm64-v8a
# Licence-page assets of a Flutter host.
python3 tool/build.py --install-licenses ../quds_office_editor/example/assets/licenses/arabic_morph
```

`build.py` downloads exactly the 26 CrispEmbed files it needs from
`raw.githubusercontent.com` at commit `8e40ad88945ca2e0b5e22f311835664c67501fee`.
It admits each one only when its length and SHA-256 equal the pins in the
script, and refuses to build if any compiled file or notice differs from
`licenses/manifest.json`. It writes `build-receipt.json` with the hash of
every output. The web build needs Emscripten (`emcmake`, tested with 6.0.2).
It uses native Wasm exceptions and non-resizable heap views
(`GROWABLE_ARRAYBUFFERS=0`): with resizable views, Chrome 157's
`TextDecoder` rejects the heap, and the headless-Chrome smoke caught that.
Cross builds use the same CMake project, for example
`-DCMAKE_SYSTEM_NAME=iOS` or the Android NDK toolchain file.

## Licences

- **Code compiled into the app:**
  - the adapter and the Dart code: MIT (`LICENSE`);
  - CrispEmbed: MIT (`licenses/upstream/CrispEmbed-LICENSE`);
  - camel_tools 1.6.0: MIT (`camel_tools-LICENSE`), retained in
    `arabic_morph.cpp`;
  - Ryu: Apache-2.0 option (`Ryu-LICENSE-Apache2`);
  - generated Unicode 15.0.0 and CPython 3.12 character tables
    (`Unicode-LICENSE.txt`, `CPython-LICENSE`).

  `THIRD_PARTY_NOTICES` is CrispEmbed's own summary.
  `licenses/manifest.json` hashes every fetched file and notice. There is no
  GPL or LGPL code. camel_tools' GPL `calima-msa-r13` database and LDC
  resources are not used.
- **Data (downloaded, never compiled in):** Camel Morph MSA v1.0, CC BY 4.0.
  `licenses/data/` keeps the bundle's `NOTICE` (attribution, citation,
  provenance, the noprob change) and `LICENSE`, both pinned by SHA-256, so
  hosts can show them on their licence page before any download.

Hosts must ship the notices with the binary (`--install-licenses`).

## Verification

```sh
QUDS_ARABIC_MORPH_TEST_LIBRARY=build/native/libquds_arabic_morph.dylib \
QUDS_ARABIC_MORPH_TEST_BUNDLE=/path/to/verified/noprob \
QUDS_ARABIC_MORPH_LIVE_DOWNLOAD=1 dart test
dart run tool/pud_benchmark.dart <library> <bundle dir> pud.txt
node tool/web_smoke.mjs build/web <bundle dir> pud.txt
dart compile js -O2 tool/browser_smoke.dart -o out/smoke.js
python3 tool/browser_smoke.py --script out/smoke.js --web build/web \
  --bundle <bundle dir> --corpus pud.txt
```
