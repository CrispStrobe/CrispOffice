# Optional local Hunspell spelling

This package adds Hunspell spelling to Quds Office for languages whose
dictionary the **user downloads from inside the app**. The first dictionary is
Arabic: the AyaSpell bundle published unmodified at
[`cstr/ayaspell-ar-hunspell`](https://huggingface.co/cstr/ayaspell-ar-hunspell/tree/e9ace7cca3844bef906d8d9fc5431c4e15bd2740)
(immutable revision `e9ace7cc…`). Nothing is downloaded or enabled by default.

This package supplies the provider, installer and backend. App registration,
the download interface and packaging into each host target remain host work.

- **Engine (part of the app):** the MIT adapter `native/src/quds_hunspell.cpp`
  compiled with the unmodified Hunspell 1.7.2 library sources under their
  MPL 1.1 option. Native platforms load it as a shared library in a persistent
  Dart isolate; the web build runs the same code as a bundled Emscripten
  WebAssembly module in a module Web Worker. No engine code is ever downloaded
  (App Store guideline 2.5.2).
- **Dictionary (downloaded data):** `HunspellInstaller` (`package:quds_proofing_hunspell/installer_io.dart`)
  streams every pinned file into private staging, admits it only when length
  and SHA-256 equal the compiled-in catalog (`hunspellCatalog`), publishes the
  tree with one rename and verifies it again; `remove` renames before
  deleting. On the web the host fetches the two dictionary files itself and
  passes them through `HunspellDictionaryBytes.verified`.

## Use

```dart
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_hunspell/installer_io.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';

// After the user chose "Download Arabic spelling":
final installer = HunspellInstaller(applicationSupportDirectory);
final files = await installer.install(ayaspellArabic, onProgress: report);
final arabic = HunspellProofingProvider(
  bundle: ayaspellArabic,
  dictionary: files,
  vocabulary: sessionVocabulary, // personal + ignored words, shared
  nativeLibraryPath: '/application/lib/libquds_proofing_hunspell.so',
);
final service = OfficeProofingService(providers: [arabic, ...]);
```

The native path can also come from the `QUDS_HUNSPELL_LIBRARY` Dart define,
otherwise the platform's library search looks for
`libquds_proofing_hunspell.{so,dylib}` / `quds_proofing_hunspell.dll`. On the
web, serve `hunspell_worker.mjs`, `quds_proofing_hunspell.mjs` and
`quds_proofing_hunspell.wasm` together (default URL
`proofing/hunspell_worker.mjs`). A missing library, worker or dictionary
reports **unavailable**; malformed backend output reports **failed**, never a
clean result.

Dispose the provider when its session ends. Normal native disposal rejects
pending Dart requests immediately, then waits for the worker to finish its
active native call and close its dictionary handle. Concurrent disposal calls
share this cleanup. Reopening first releases the previous handle, including
when the replacement cannot be allocated. A native finalizer backs up abnormal
worker termination. If the worker cannot acknowledge shutdown within two
seconds, it is terminated; this fallback does not promise immediate completion
of a synchronous native call or immediate finalizer execution.

## Behaviour

- **Words** are maximal runs of letters and combining marks. Arabic harakat
  and tatweel stay inside the word with their original UTF-16 offsets; the
  dictionary's `IGNORE` line makes Hunspell disregard them. Digits,
  punctuation, spaces and format controls such as ZWNJ end a word.
  Right-to-left text needs no special handling because offsets are logical.
- For the Arabic dictionary only words containing an Arabic-script letter are
  checked; Latin words in Arabic prose belong to another language's provider.
- Links, e-mail addresses and closed backtick spans are skipped (shared
  `OfficeProofingTextRanges`). Personal and ignored words of the request's
  language (`OfficeProofingVocabulary`) are never reported; ignoring the rule
  `hunspell.spelling` turns the provider off for a request.
- Each distinct word is checked once per request. Suggestions are computed for
  the first 24 distinct misspellings (Hunspell's order, at most five each);
  later ones are still reported, without replacements. Arabic suggestions cost
  about 50 ms per word on an M-series Mac, so this bounds a paragraph to about
  1.2 s of background work. A request is limited to 32,768 characters.

The deterministic native ownership suite uses the real FFI/isolate transport
with an instrumented C ABI fixture. It checks handle closure, repeated and
concurrent disposal, failed replacement, pending calls and startup races:

```sh
c++ -std=c++14 -shared -fPIC -pthread \
  test/fixtures/lifecycle_hunspell.cpp -o /tmp/libquds_hunspell_lifecycle.so
QUDS_HUNSPELL_LIFECYCLE_LIBRARY=/tmp/libquds_hunspell_lifecycle.so \
  dart test test/native_lifecycle_test.dart
```

The fixture suite is separate from qualification against the real Hunspell
library and verified AyaSpell dictionary. Ordinary package tests skip this
optional suite when its compiled fixture is absent. Complete qualification
requires the hash-bound fixture and rejects skipped cases.

## Build and package

```sh
python3 tool/build.py --native --wasm --output build      # host native + web
python3 tool/build.py --license-bundle                     # regenerate licenses/
```

`build.py` downloads the Hunspell 1.7.2 release tarball, checks its SHA-256
(`11ddfa39…`) and length before extraction, compiles only the library files
listed in `licenses/manifest.json` (refusing to build if any differs) and
writes `build-receipt.json` with the hash of every output. The web build needs
Emscripten (`emcmake`). Cross builds use the same CMake project, for example
`-DCMAKE_SYSTEM_NAME=iOS` or the Android NDK toolchain file.

## Licences

The adapter and Dart code are MIT (`LICENSE`). The compiled Hunspell files are
used under MPL 1.1 (`licenses/upstream/COPYING.MPL`, `license.hunspell`;
MySpell-derived parts keep `license.myspell`). `licenses/manifest.json` lists
every compiled file's SHA-256 and records two notes: `phonet.cxx`'s header
says LGPL 2.1 while its changelog records the author's 2007 release under the
Hunspell tri-licence, and `hunvisapi.h` is a generated header. The exact
compiled sources ship as `licenses/hunspell-1.7.2-library-sources.tar.gz`
(MPL source availability). Hosts must ship `licenses/` with the binary. The
dictionary's own licence files are part of the downloaded bundle.

## Verification

```sh
QUDS_HUNSPELL_TEST_LIBRARY=build/native/libquds_proofing_hunspell.dylib \
QUDS_HUNSPELL_TEST_DICTIONARY=/path/to/verified/bundle \
QUDS_HUNSPELL_LIVE_DOWNLOAD=1 dart test
dart run tool/corpus_check.dart <library> <bundle dir> corpus.txt cli-flagged.txt
node tool/web_smoke.mjs build/web <bundle dir> corpus.txt cli-flagged.txt
```
