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

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'package:quds_proofing_gector/quds_proofing_gector_native.dart';

Future<GectorProofingProvider> loadManualGerman({
  required String bundleDirectory,
  required GectorModelArtifact reviewedArtifact,
  required String libraryPath,
  required String librarySha256,
  required OfficeProofingVocabulary vocabulary,
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
    vocabulary: vocabulary,
  );
}
```

Preload the provider before registering it with the editor. Bundle hashing,
dictionary loading, and native context creation are startup work and occur
outside the normal proofing request deadline. In the existing editor host:

```dart
final readyGectorProvider = await loadManualGerman(
  bundleDirectory: bundleDirectory,
  reviewedArtifact: reviewedArtifact,
  libraryPath: libraryPath,
  librarySha256: librarySha256,
  vocabulary: controller.proofing.vocabulary,
);
controller.proofing.configureManual(
  OfficeProofingService(providers: [readyGectorProvider]),
);
await controller.proofing.checkNow();
```

Share the session's vocabulary object so its personal and ignored words also
protect model suggestions and changes invalidate in-flight grammar results.

The manual service runs on explicit checks, including F7. The editor's debounce
path excludes manually configured providers. This package does not alter the
default provider list or enable grammar checks on every keystroke. Dispose the
provider through its owning service when the feature or editor is closed.

`GectorGermanLexiconFactory` wraps Quds' existing German spelling provider through
a read-only word query. Custom hosts can supply `GectorLexiconFactory`; it must
create its lexicon inside the worker. `GectorWordSetLexiconFactory` supplies a
closed, immutable word set when that is appropriate for a host. An empty word
set deliberately blocks lexical replacements; it is not a permissive fallback.

For the exact qualified Linux development build, the repository provides an
[offline pack builder and verifier](../../tools/proofing/german_model/NATIVE_PACK.md).
It supplies the verified paths and retains all model/native notices; it does
not activate the provider or establish a release for other platforms.

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

### Opt-in long paragraphs

Hosts can enable sentence segmentation on the existing manual provider:

```dart
final options = GectorDecodeOptions(
  segmentation: GectorSegmentationOptions(
    targetTokens: 64,
    maximumSegments: 32,
    maximumTotalTokens: 4096,
  ),
);
// Pass options: options to GectorProofingProvider.load(...).
```

Without this option, the existing 512-token whole-input limit remains in
effect. Reference decoding rejects segmentation, preserving its frozen oracle.
With the option, inputs fitting the preferred 64-token size retain the same
single source slice and prepared input. Longer paragraphs are greedily grouped
at conservative sentence boundaries. An individual sentence may exceed the
preferred size up to the hard 512-token limit. An ambiguous or unsplittable
sentence above that hard limit fails; no words are dropped or cut into windows.

Planning preserves a contiguous partition of every original UTF-16 source unit,
including all whitespace, quotation marks and punctuation. It excludes breaks
inside protected URLs, email addresses and code, and conservatively handles
abbreviations, initials, numbers, ellipses and paired delimiters. This bounded
heuristic is not a complete German sentence parser. Each segment has its own
model-only final-terminator handling, so longer-input neural decisions can
differ from a whole-paragraph check and need separate language evaluation.

All segments and admission budgets are checked before the first forward. The
default 4,096 initial-token budget counts each segment's CLS/SEP tokens. Across
all subsequent passes, the decoder also caps actual forwarded tokens at that
budget multiplied by the maximum passes (20,480 by default). The existing
32,768 UTF-16 source ceiling and one 15-second provider deadline still apply to
the complete request; the deadline is not restarted for each segment.

Each segment's edits are rebased directly to its original location. A new
paragraph-wide diff cannot relocate edits among repeated phrases. Later
segments do not acquire `$START` insertions or the original-start exception for
case-differing duplicate deletion. The provider still validates and filters
edits against the whole source, its protected ranges and personal vocabulary.

Any segment failure, non-convergence, deadline or cancellation prevents partial
suggestions from being published. `GectorDecodedText.segmentCount` records the
planned count. Its flat `passes` list contains decoding passes across all
segments, each with a request-relative `sourceStart`; it is no longer a
paragraph-wide iteration count. `forwardTokens` and `forwardCount` record
actual backend forwards in the retained passes. Cancellation continues between
native forwards; an active native call cannot be interrupted mid-call.

### Optional reuse within a request

Repeated boilerplate can produce identical model inputs in different segments.
Hosts may explicitly opt in to request-local prediction reuse:

```dart
final options = GectorDecodeOptions(
  segmentation: GectorSegmentationOptions(
    inferenceReuse: GectorInferenceReuseOptions(
      maximumCachedInputs: 32,
      maximumCachedTokens: 2048,
    ),
  ),
);
```

Reuse is off by default and requires the backend's explicit
`GectorDeterministicBackend` capability. The native adapter implements that
contract for its fixed opened model and profile. Stateful, scripted and replay
backends remain supported with reuse disabled; enabling reuse for an ordinary
`GectorBackend` is rejected at decoder construction. Reference mode remains
unaffected and continues to reject segmentation.

The cache exists only for one complete `correct` call. It retains immutable
selected raw tags after validation, keyed by exact source words and the
prepared IDs, mask and alignment. It retains no logits, source offsets,
guarded edits or complete segment results. Guards, personal-word decisions,
source projection and the provider's global filtering run independently for
each occurrence, so a later segment cannot inherit original-start privileges.
Words that happen to share an unknown-token ID do not share a cache entry.

The default cache retains at most 32 inputs and 2,048 tokens. Hard option limits
are 128 inputs and 4,096 tokens. Reaching either limit stops retaining new
entries and continues ordinary inference. Every original segment still counts
towards initial admission budgets, and every decode pass still checks its
hard sequence limit, yields for cancellation and applies convergence limits.
The whole request remains atomic on failure or cancellation. Only actual
backend calls consume the actual-forward token budget.

`GectorPass.reusedInference` identifies passes using cached raw tags; their
`inferenceMicroseconds` is zero. `reusedPassCount` counts those passes and
`decodedTokens` includes all logical decoding passes, while `forwardCount` and
`forwardTokens` exclude reuse. No cache survives between separate requests or
timed samples. This optimization targets repeated inputs; its existence alone
does not establish a latency improvement on unique prose.

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

The first real native guarded run preserved 5/18 expected fixes on the frozen
error panel, compared with 9/18 for the original unguarded decoder. The
[compiled continuation](../../docs/validation/german-gector/2026-11-17-continuation/README.md)
now preserves **6/18**: authenticated same-number verb-person aliases allow
`Wir ist zufrieden.` to become `Wir sind zufrieden.` even when the model selects
the third-person-plural label for the shared surface form `sind`. All previous
fixes remain. The verb-plural `Die Kinder spielt`, demonstrative `Das sind`, and
`Die Blumen ist` changes remain held because the bounded policy cannot establish
the needed subject evidence. Cross-number ambiguity is not relaxed.
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
the older snapshot. Superseding a caller retains the old remote slot until the
worker acknowledges it; only the latest unsent snapshot for each key is kept
locally. This bounds both unacknowledged requests and waiting snapshots even
while synchronous inference blocks the worker's message loop. Over-limit text
is rejected before it can cancel existing valid work or cross the isolate.
Cancellation is checked between passes, after forwards,
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

For a paired reuse measurement, run the same compiled runner with
`--segment-target-tokens 64 --reuse-identical-inputs false` and then
`--segment-target-tokens 64 --reuse-identical-inputs true`, keeping every other
input identical. The runner records actual worker passes, their source starts,
prediction-input fingerprints, native-forward counts and reuse counts for each
timed sample. Complete-check timing still includes the real worker, provider and
Office service; evidence serialization follows timing. The repeated-sentence
probes are accompanied by separate varied, unique-input paragraph controls.
Their operational coverage and stability are checked; their full findings are
retained for language review and paired comparison rather than assumed correct.

When compiling that tool to an executable outside the checkout, pass
`--source-root /path/to/quds_office_suite` so its input hashes refer to the
reviewed source. The report records the actual executable path and SHA-256
alongside Dart product mode; retain the compilation command and input hashes
with the measurement. Compiled measurements do not replace earlier JIT results.

## Licensing

Quds additions use the package MIT license. The translated/adapted Proofbird
decoder and source alignment, original metadata fixtures, and source assets
retain their Apache-2.0 provenance in `NOTICE` and `third_party/`. Native model
installation must retain the model's license and notice. Dependency and native
runtime notices remain the host distributor's responsibility.

## Ambiguous repeated grammatical roles

The guarded Dart path conservatively retains adjacent repeated personal
pronouns and demonstrative/article homographs: `Wenn sie sie sehen, winken sie.`
can use the two `sie` tokens for different roles. This first-party safeguard
also preserves ambiguous triples and runs again for every reused prediction.
It may leave an accidental repetition uncorrected. The existing original-start
case-differing two-token exception remains; later segments do not acquire it.
The pinned publisher JSON and unguarded reference path are unchanged.
