# Optional local German analysis

This package connects Quds to the separately installed, default-off CrispEmbed
spaCy text ABI. It exposes tokens, original spans, tags, POS, morphology, lemmas,
dependencies and sentences for the pinned `de_core_news_sm` 3.8.0 F32 profile.
It does not register a grammar provider or generate corrections. Existing
deterministic proofing remains independent.

The initial adapter supports **Linux x86-64, de-DE, CPU/F32**. Other platforms,
regional locale profiles, NER, model release/distribution and mobile device
qualification remain separate work. The portable entry point and conditional
native entry point are safe to import from web; its native factory explicitly
reports unavailable. The engine has no Flutter or native dependency.

## Explicit local installation

Build/install the standalone target as documented in
[CrispEmbed tools/spacy](https://github.com/CrispStrobe/CrispEmbed/blob/feat/native-spacy-20261117/tools/spacy/README.md).
Use the frozen model converter to create the five-file bundle. Keep the native
library and its dependencies/notices installed immutably, placing the library
inside a directory named by its SHA-256. Supply that hash from a trusted build
receipt. The bundle's original wheel/model/resource/manifest and notice hashes
are fixed in `bundle.dart`; an adjacent manifest cannot change the trusted pins.

The host must set `CRISPEMBED_SPACY=1` before starting its process. This adapter
does not change environment variables, download files, start subprocesses,
embed Python or provide a network fallback. The bundle and runtime are verified
before the worker becomes ready. Missing files, changed bytes, missing notices,
unsupported ABI and disabled gates fail explicitly.

```dart
import 'package:quds_proofing_spacy/quds_proofing_spacy_native.dart';

final factory = SpacyNativeBackendFactory(
  bundleDirectory: verifiedBundleDirectory,
  libraryPath: immutableLibraryPath, // Parent directory is librarySha256.
  librarySha256: trustedLibrarySha256,
);
```

Use the worker entry point in `transport.dart` to open this factory. Its native
context belongs to the worker; do not call synchronous native inference on the
Flutter UI isolate. The worker's returned result owns immutable Dart strings
and lists, so it remains valid after the native document/context is freed.

## Source and lifetime contract

Every request identifies its document, block, revision, exact text, locale,
UTF-16 origin, generation and configuration. Token `start`/`end` are half-open
UTF-16 offsets **relative to request.text**. Add `request.startOffset` once when
navigating the original block. Byte and scalar coordinates are retained as
independent checks. The binding validates UTF-16 before encoding, passes counted
UTF-8 including embedded NUL, and checks each native coordinate against maps
built from the unnormalized input. It never searches for token text or rounds
offsets to repair alignment. Analysis spans need not be safe correction spans.

Results cover the complete supplied unit or fail. The native limits are 1 MiB
UTF-8 and 2,048 tokens; the worker can impose smaller input/queue limits. The
binding checks string bounds, complete source reconstruction, exact surface
text, complete sentence boundaries, one root per sentence, head bounds and
dependency cycles before exposing a success. It releases owned native results
in `finally`, including malformed and non-null error outputs.

Worker cancellation immediately settles the caller and rejects stale results.
It does not interrupt a synchronous FFI call in progress. That call retains its
slot and context until it returns; disposal joins safe cleanup. The saved native
binary is unchanged, and this package supplies no new native cancellation shim.
Do not describe caller cancellation as a measured compute-interruption budget.

## Local validation

Run the model-free package suite with `dart test` from this package after the
workspace dependencies are installed. It checks source mapping, malformed
UTF-16, source reconstruction, sentence/dependency invariants, immutable results,
snapshot identity, explicit failures and worker lifecycle controls.

The separate actual-library driver requires all assets and fails when they are
absent; it does not skip model checks within a green unit suite:

```sh
CRISPEMBED_SPACY=1 dart run packages/quds_proofing_spacy/tool/replay_development.dart \
  --library "$QUDS_SPACY_LIBRARY" --library-sha "$QUDS_SPACY_LIBRARY_SHA" \
  --bundle "$QUDS_SPACY_BUNDLE" --quds-root . --report "$QUDS_SPACY_REPORT"
```

This driver replays the existing 16 **development** documents and authored API
controls through the actual Dart binding. It compares every exposed annotation
and sentence, including nonzero origins. It does not rerun or retune the frozen
eight-case native acceptance, and repeat development executions are not new
independent linguistic-quality evidence. Numerical native-stage evidence stays
in CrispEmbed's immutable acceptance receipt. No GitHub Actions query or wait is
needed for these checks.
