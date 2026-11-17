# Optional German GECToR proofing

This package supplies an offline, manually enabled German grammar provider for
Quds Office. It contains the typed Dart tokenizer, iterative decoder, original
text edit mapping, a conservative guard policy, and a persistent worker. An
inference backend and a read-only German lexicon are required. No model is
downloaded or shipped by this package, and importing it does not enable proofing.

The implemented locale is **de-DE**. The provider explicitly returns
`unsupported` for de-AT and de-CH while their orthography and false-positive
controls remain unqualified. Raw reference cases containing Swiss text do not
constitute support for the Swiss locale.

The implementation is tied to Proofbird `gector-bert-de` revision
`8e3b50beef7d775cedb7b876009e88bcf2e8d6af`, whose original F32 ONNX model has SHA-256
`6d7b43b4bd95c7a00c02c8babc7569d28558df894afe4874d96c202e6ab9a464`.
See the [project roadmap](../../docs/roadmaps/german-gector-proofing.md) for
current qualification evidence and remaining release gates.

## Enable it explicitly

Install a reviewed model artifact, its twelve frozen metadata/source/license
files, and a separately pinned native library. The metadata basenames and exact
byte/hash pins are public in `gectorBundleAssetPins`; arbitrary files from a newer
model revision are rejected. The original `model.onnx` is required for original
reference replay, but a runtime bundle can replace it with an explicitly pinned
converted artifact that identifies the same original model.

The optional `quds_proofing_gector_native.dart` import exposes the CrispEmbed FFI
adapter. The core library does not import the native adapter. The host must start
the native experiment with `CRISPEMBED_GECTOR=1`, install the library directly
inside a directory named by its SHA-256, and retain immutable model/library
paths for the entire process lifetime. Different library builds need different
content-addressed paths. The adapter verifies both files, validates dual-head
dimensions, and owns the native context inside the worker isolate.

```dart
import 'dart:io';

import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'package:quds_proofing_gector/quds_proofing_gector_native.dart';

Future<GectorProofingProvider> loadManualGerman({
  required String bundleDirectory,
  required GectorModelArtifact reviewedArtifact,
  required String libraryPath,
  required String librarySha256,
}) async {
  final bundle = await GectorVerifiedBundle.load(
    read: (name) => File('$bundleDirectory/$name').openRead(),
    artifact: reviewedArtifact,
  );
  return GectorProofingProvider.load(
    bundle: bundle,
    backendFactory: GectorNativeBackendFactory(
      modelDirectory: bundleDirectory,
      libraryPath: libraryPath,
      librarySha256: librarySha256,
      threads: 2,
    ),
    lexiconFactory: const GectorGermanLexiconFactory(),
  );
}
```

Preload the provider before registering it with the editor. Bundle hashing,
dictionary loading, and native context creation are startup work and occur
outside the normal proofing request deadline. In the existing editor host:

```dart
controller.proofing.configureManual(
  OfficeProofingService(providers: [readyGectorProvider]),
);
await controller.proofing.checkNow();
```

The manual service runs on explicit checks, including F7. The editor's debounce
path excludes manually configured providers. This package does not alter the
default provider list or enable grammar checks on every keystroke. Dispose the
provider through its owning service when the feature or editor is closed.

`GectorGermanLexiconFactory` wraps Quds' existing German spelling provider through
a read-only word query. Custom hosts can supply `GectorLexiconFactory`; it must
create its lexicon inside the worker. `GectorWordSetLexiconFactory` supplies a
closed, immutable word set when that is appropriate for a host. An empty word
set deliberately blocks lexical replacements; it is not a permissive fallback.

## Backend contract and model identity

`GectorBackendFactory.open` receives the verified `GectorModelArtifact` and
returns a backend with matching `GectorBackendIdentity`. Factory state must be
sendable between isolates: pass paths and typed configuration, then create
native handles inside `open`. Identity includes the exact runtime artifact
hash, original source hash, model revision, vocabulary size, both classifier
widths, and the 512-token position limit.

The decoder passes `GectorPreparedInput`: owned int64 token IDs, an all-ones
attention mask, and first-subword indices including the CLS row for `$START`.
The backend returns owned row-major `Float32List` data for **both** heads:

| Head | Shape for one unpadded input |
| --- | --- |
| Labels | `tokenCount × 5000` |
| Correct / incorrect | `tokenCount × 2` |

Wrong dimensions, missing rows, non-finite values, unsupported tokenizer
profiles, identity mismatches, or unknown label operations fail the check.
Model hash verification proves which bytes were supplied. It does not prove
that a conversion or quantization preserves inference quality; use the project
qualification tools and retain their receipts before admitting an artifact.

Hosts can implement another backend without importing ONNX Runtime or FFI into
the core decoder. `GectorProofingProvider.withTransport` also accepts a host
transport, but requires guarded, converged results whose original text and
edits agree exactly. It is not an unchecked route to successful empty reports.
The supplied persistent worker is supported on Dart VM. Web startup reports
unavailable; a browser backend/worker needs separate implementation and
qualification.

## Decoding and source safety

The cased WordPiece implementation validates the frozen BERT profile and the
complete 31,102-entry vocabulary. It preserves first-subword alignment across
punctuation, embedded special tokens, Chinese characters, Unicode normalization
controls, and words requiring multiple pieces. A word that vanishes during
normalization fails explicitly instead of shifting subsequent word/tag pairs.

The decoder applies the original label and detection heads, KEEP confidence,
error threshold, suffix and verb-form tables, case transforms, split/merge
operations, and repeated passes. Reference mode is available explicitly as
`GectorDecoder.reference` for upstream parity tooling. The Office provider uses
guarded mode and rejects reference-mode results.

All public source ranges are UTF-16 positions in the **original** text. Only the
model view normalizes curly apostrophes and strips one final terminator. The
original spacing, apostrophe glyphs, terminator, and trailing whitespace remain
in untouched text. Diff tie ordering and insertion/deletion spacing follow the
frozen quickstart algorithm, including its punctuation-insertion behavior; this
layer is not a general typography formatter. The provider adds a document
request's base offset exactly once.

Before exposing a finding, the provider verifies source substrings, edit order,
non-overlap, UTF-16 validity, and agreement between edits and corrected text.
Edits that split a grapheme cluster, overlap protected URL/email/code ranges,
or touch personal/ignored vocabulary are suppressed. A personal-vocabulary
revision change during inference invalidates that result. Unsupported inputs,
non-convergence, and backend failures are reported through proofing status;
they are never presented as a successful clean document.

## Guard policy and its limits

`gector-guards.json` contains both declarative rules and notes describing
Proofbird application built-ins. The application implementation was not supplied.
**This package implements Quds' conservative policy derived from that document;
it does not claim full Proofbird application guard parity.** Unknown rule types,
fields, scopes, or missing required fields fail worker initialization.

The implemented policy includes:

- Listed appended function words and content-word-to-function-word replacements
  are suppressed. Exact blocked replacements and contextual redirects are
  applied before the final lexical check.
- Mood changes need a declared cue in the current sentence; past-year cues and
  the simplified final-copula check cannot borrow evidence across `.`, `!`, or
  `?`. Sentence/clause detection is punctuation based and is not a syntax parse.
- Deletion is limited to adjacent duplicates. Demonstrative/article pairs,
  relative-pronoun/article pairs, and differing-case repetitions receive the
  declared protections. A pass cannot delete every member of a duplicate run.
- Person changes need a nearby pronoun or a conservative singular determiner
  cue. Singular changes in a clause with visible coordination are held because
  this policy cannot parse its subject. Ambiguous or distant constructions can
  therefore be left uncorrected.
- Declared `man` forms and plural endings after the listed determiners are held.
  Capitalization requires known-word evidence. Every lexical replacement must
  pass the required independent lexicon, including after a redirect.
- The note-only velar rule rejects inserted `h` except after `c`/`g` with lexical
  confirmation. The elision rule rejects a newly introduced apostrophe echo.
  The auxiliary rule blocks the noted Italian forms of `e` to `sono` change.
  These are explicitly bounded rejection rules; they do not reproduce the
  unpublished built-ins' complete linguistic behavior or collapse pre-existing
  elision echoes.

The first real native guarded run preserves 5/18 expected fixes on the frozen
error panel, compared with 9/18 for the original unguarded decoder. It holds the
noun-plural, `Wir ist`, demonstrative `Das sind`, and `Die Blumen ist` changes
because this bounded policy cannot establish the needed person/subject evidence.
All ten supported de-DE clean controls remain unchanged; the two Swiss controls
are explicitly unsupported. This is an experimental host opt-in, pending broader
precision/recall and incremental-benefit evaluation.

The policy favors retaining text when its evidence is insufficient. It can
miss valid corrections. A finite passing control panel does not establish a
broad false-positive rate or authorize automatic application of suggestions.

## Bounded worker behavior

The worker loads one backend and one lexicon, then serializes requests. The
default queue admits at most three outstanding requests; the configurable limit
is 1–8. A newer request for the same document/block/base-offset key supersedes
the older snapshot. Cancellation is checked between passes, after forwards,
and while applying guards. Synchronous native inference cannot be interrupted
mid-call, but its cancelled result is discarded before another pass.

Default bounds are five passes, 512 total WordPieces including CLS/SEP, 32,768
UTF-16 source units, a 60-second preload deadline, and a 15-second request
deadline. Callers can tighten decoder bounds. Input is never silently truncated.
Cycles and exhausted pass limits are incomplete results, and the provider
reports them as failed. A timed-out provider disposes its worker instead of
leaving background work eligible to publish a late result. Disposal completes
pending requests, allows a bounded shutdown, and terminates the isolate when
needed; native resources have a finalizer as well as explicit disposal.

## Reproduce local validation

From this package in the resolved repository workspace:

```sh
dart test
dart analyze lib test tool
```

Portable tests contain no model weights. Their compressed fixture preserves
the original small source files byte for byte and exercises the real bundle
hash pins. Tests cover failure reporting, cancellation, queue capacity,
multi-pass and cycle behavior, protected/personal text, UTF-16/grapheme ranges,
28 pinned-tokenizer Unicode cases, and 30 original decoder traces with 40 passes.
The trace unit tests replay selected labels with decisive synthetic logits, so
they do not claim to measure raw neural inference. Fixture provenance and
licensing are documented in [test/fixtures/README.md](test/fixtures/README.md).

To authenticate and replay the original raw F32 logits exported by the project
tooling:

```sh
dart run tool/replay_reference.dart \
  --assets /path/to/original-proofbird-bundle \
  --reference /path/to/reference-f32/reference.json \
  --output /path/to/dart-reference-replay.json
```

The replay verifies source bundle pins and every tensor's filename, shape,
size, and SHA-256. It compares prepared IDs/masks/first-subword indices, words,
tags, edited words, pass count, final text, and original UTF-16 suggestions. The
receipt records float32-versus-double probability drift separately from exact
decision agreement. Replay timings are not native inference timings.

The optional native adapter test requires all four `GECTOR_TEST_MODEL`,
`GECTOR_TEST_MODEL_SHA256`, `GECTOR_TEST_LIBRARY`, and
`GECTOR_TEST_LIBRARY_SHA256` environment variables, plus the native experiment
gate. Without explicit native fixtures it is skipped, not claimed as passing.
The full real-worker/provider path is exercised by the repository's separate
`tools/proofing/german_model/run_gector_dart.dart` tool. These checks run locally
without waiting for GitHub Actions.

## Licensing

Quds additions use the package MIT license. The translated/adapted Proofbird
decoder and source alignment, original metadata fixtures, and source assets
retain their Apache-2.0 provenance in `NOTICE` and `third_party/`. Native model
installation must retain the model's license and notice. Dependency and native
runtime notices remain the host distributor's responsibility.
