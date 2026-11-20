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
  The sources come from CrispEmbed commit `3bab3248` (PR #261, ABI 3). Native
  platforms load it as a shared library in a persistent Dart isolate. The web
  build runs the same code as a bundled Emscripten WebAssembly module in a
  module Web Worker. No analyzer code is ever downloaded (App Store guideline
  2.5.2).
- **Database (downloaded data):** the `proofing-bin` bundle of
  [`cstr/camel-morph-msa-v1.0`](https://huggingface.co/cstr/camel-morph-msa-v1.0/tree/d5364e04af7a40b0c9044ed127606e585be15272/proofing-bin),
  at the immutable revision `d5364e04…`. It has four files and 11.6 MB:
  `manifest.json`, the 12,166,992-byte binary database, `NOTICE` and
  `LICENSE`. The database is the `noprob` one (see below) converted to
  CrispEmbed's memory-mapped binary format and reduced to the proofing
  features. The data is CC BY 4.0, © 2024 New York University Abu Dhabi. The
  app must show the attribution in `NOTICE`
  (`camelMorphMsaProofingBin.attribution`).
- **Installation:** `MorphInstaller` (`package:quds_arabic_morph/installer_io.dart`)
  works like the Hunspell installer:
  - it streams each pinned file into private staging;
  - it admits a file only when its length and SHA-256 equal the compiled-in
    catalog (`camelMorphMsaProofingBin`);
  - it publishes the tree as `<root>/arabic_morph/<revision>-<id>` with one
    rename and verifies it again;
  - `remove` renames the tree before deleting it;
  - `removeOtherBundles` deletes earlier bundles. The Studio host calls it
    on every refresh, so an install of the previous 78 MB `noprob` text
    bundle is removed and the user downloads the binary bundle once.

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

`analyzeWords` therefore returns every analysis in no particular order, and
rules reason over the whole set, for example by reporting only when **no**
analysis of a word is compatible.

## Context model (optional second download)

`camelMorphMsaDisambig` is a licence-clean replacement for the dropped
probabilities: a bigram hidden Markov model over the database's own analyses,
trained without annotations on Arabic Wikipedia (CC BY-SA 4.0) by CrispEmbed's
`tools/arabic_morph/disambig_train.py`. With it loaded,
`CamelArabicMorphology` is an `ArabicContextMorphology`: `disambiguate`
ranks each token's analyses in its sentence (tokens from the engine's
`arabicContextSentences`, punctuation included). On UD Arabic-PUD the best
reading's UPOS is right for 77.9% of tokens, the same as the `full`
ranking, and its lemma for 90.4% (`full`: 88.2%). The grammar rules use a
reading only when it leads the second by at least 0.9
(`ArabicGrammarReading.contextual`); see `docs/roadmaps/arabic-proofing.md`
for the A/B. The model is 4.5 MB, CC BY-SA 4.0 (Wikipedia contributors;
Camel Morph MSA v1.0 © 2024 NYU Abu Dhabi, CC BY 4.0), pinned by SHA-256 like
the database; `licenses/data/camel-morph-msa-disambig-{NOTICE,LICENSE}` hold
its attribution. CrispEmbed's disambiguator is default-off
(`CRISPEMBED_AR_MORPH_DISAMBIG`); the adapter enables it for the process when
a model is opened, unless the variable is already set.

## The proofing feature profile

The rules (`arabic_grammar_rules.dart`) read `pos`, `lex`, `cas`, `stt`,
`num`, `gen`, `per`, `asp`, `mod`, `form_gen`, `form_num`, `prc0`–`prc3` and
`enc0`. The `proofing-bin` database keeps those plus `diac`, `root`, `vox`,
`rat`, `prc1.5`, `enc1`, `enc2` and `source`, which is `spvar` for
spelling-variant readings.

It drops `gloss`, `bw`, `caphi`, `pattern`, `pattern_abstract`, the `cm_*`
ids, the tokenization features, `catib6`/`ud`, `stem*` and the constant
`*_logprob` features. Those made up most of the 78 MB.

CrispEmbed's receipt shows that analyses and the kept feature values are
exactly camel_tools'. A repeated analysis of a word, one that differs only in
dropped features, is returned once (about 6% of them). Rules only ask
whether any or every analysis matches, so they are unaffected. On all 1,000
UD Arabic-PUD sentences, the rules report the same 673 findings as with the
previous backend and the full database.

## Use

```dart
import 'package:quds_arabic_morph/installer_io.dart';
import 'package:quds_arabic_morph/quds_arabic_morph.dart';

// After the user chose "Download" in the Dictionaries dialog:
final files = await MorphInstaller(applicationSupportDirectory)
    .install(camelMorphMsaProofingBin, onProgress: report);
final morphology = CamelArabicMorphology(
  database: files,
  nativeLibraryPath: '/application/lib/libquds_arabic_morph.so',
);
await morphology.load(); // about 0.2 s; isAvailable turns true
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
- **Features:** analyses are read-only maps of the profile features above.
  `null` features are omitted.
- **Transport:** the worker isolate (native) or Web Worker (browser) calls
  CrispEmbed's batched `crispembed_ar_morph_analyze_compact` (ABI 2). It
  sends back one buffer per batch, with no JSON: per word, a table of unique
  value strings and the analyses as (key id, string index) pairs.
- **Batching and cache:** distinct words go to the worker in batches of 512.
  Each word keeps its compact record (about 1–2 KB). The maps read features
  from that record on demand, and decoded values are interned across words.
  Results are cached for the session, with least-recently-used eviction
  after 4,096 distinct words (a few MB).

## Performance and memory

These figures were measured on an Apple M1 (macOS 26.2, Dart 3.13.7), a
machine shared with other agents (load average 4–26). Before and after were
run back to back or interleaved; absolute speeds vary by up to 3× with load.

The corpus is the 1,000 UD Arabic-PUD r2.14 test `# text` lines: 7,419
distinct Arabic words, of which 7,144 are analyzed. That gives 201,930
analyses after deduplication (215,212 before). Tools:
`tool/pud_benchmark.dart` (AOT), `tool/web_smoke.mjs` (Node 26) and
`tool/browser_smoke.{dart,py}` (headless Chrome 157, dart2js). The raw
numbers are in CrispEmbed's
`docs/validation/camel-morph-binary-20261119/performance.json`.

| | Load | Distinct words/s (cold) | Memory |
| --- | ---: | ---: | --- |
| Native (FFI isolate), before: JSON, noprob | 1.5–2.5 s | 709–921 | 230–250 MB RSS after load; 373–415 MB with all words cached |
| Native (FFI isolate), now | 0.16–0.26 s, incl. SHA-256 of all files | 1,750–2,955 (interleaved medians: 429 before, 1,802 now) | 30 MB RSS after load (the process starts at 18 MB); 90–100 MB after all words, mostly uncollected garbage (Dart old space about 40 MB, was 180 MB) |
| Wasm worker in Node, before / now | 1.4–1.8 s / 0.13 s | 1,725–1,785 / 3,270–3,297 | Wasm heap 320 MB / 16 MB after load and 19 MB after all words |
| Wasm worker in Chrome via the Dart web transport, before / now | 1.4 s / 0.15 s | 916–948 / 3,493–3,523 | worker heap 320 MB / 16–19 MB; page heap with all analyses 203 MB / 41 MB |

Cached words return in about 1 ms for the whole corpus.

**Browser memory:** a tab needs about 20 MB of Wasm memory plus the analyses
it keeps, so low-memory mobile browsers are no longer a concern for the
analyzer. The download (12 MB) is kept only for the session, so a reload
needs a new download.

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
`raw.githubusercontent.com` at commit `3bab324832ea911c2b1260a0d50f0ed898f47950`.
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
  provenance, and the noprob and proofing-profile changes) and `LICENSE`,
  both pinned by SHA-256, so
  hosts can show them on their licence page before any download.

Hosts must ship the notices with the binary (`--install-licenses`).

## Verification

```sh
QUDS_ARABIC_MORPH_TEST_LIBRARY=build/native/libquds_arabic_morph.dylib \
QUDS_ARABIC_MORPH_TEST_BUNDLE=/path/to/verified/proofing-bin \
QUDS_ARABIC_MORPH_TEST_MODEL=/path/to/verified/bigram-v1 \
QUDS_ARABIC_MORPH_LIVE_DOWNLOAD=1 dart test
dart run tool/pud_benchmark.dart <library> <bundle dir> pud.txt
dart run tool/pud_rule_findings.dart <library> <bundle dir> pud.txt > findings.jsonl
dart run tool/pud_rule_findings.dart <library> <bundle dir> pud.txt --model <model dir> > contextual.jsonl
node tool/web_smoke.mjs build/web <bundle dir> pud.txt [<model dir>]
dart compile js -O2 tool/browser_smoke.dart -o out/smoke.js
python3 tool/browser_smoke.py --script out/smoke.js --web build/web \
  --bundle <bundle dir> --corpus pud.txt
```
