# Optional local German analysis and guarded grammar

This package connects Quds to the separately installed, default-off CrispEmbed
spaCy text ABI. It exposes tokens, original spans, tags, POS, morphology, lemmas,
dependencies and sentences for the pinned `de_core_news_sm` 3.8.0 F32 profile.
The analysis API returns annotations. A separate, default-disabled grammar API
can turn a narrowly reviewed subset into manual correction suggestions. The
package registers neither API automatically; existing deterministic proofing
keeps its precedence.

The initial adapter supports **Linux x86-64/AVX2, de-DE, CPU/F32**, using the
qualified PCRE2 10.46 dependency. Other platforms,
regional locale profiles, NER, model release/distribution and mobile device
qualification remain separate work. The portable entry point and conditional
native entry point are safe to import from web; its native factory explicitly
reports unavailable. The engine has no Flutter or native dependency.

## Verified W7 package consumption

The [W7 package and consumer evidence](../../docs/validation/native-spacy-w7-20261118/README.md)
now includes the current installed-worker driver: 17 compiled model-free
controls and eight operational cases with source-coordinate, repeat/copy,
unsupported-locale, caller-cancellation, awaited disposal and reopen assertions.
The corrected source labels authenticate 38 source/configuration entries; all
342 sealed W6 sources remain unchanged. The first operational report and the
corrected-source report are both retained.

The paired Linux capsule reproduces the original 7,808,129-byte package SHA-256
`4e3b627a614cd21851e6e354335e2e08adeb4cedd4d7778df0cc68c1ce2edf01`.
Use its authenticated immutable installation for this accepted candidate.
A new binary build or changed dependency closure requires separate qualification.
The package is not yet hosted; [continuation instructions](../../docs/validation/native-spacy-w7-20261118/CONTINUE.md)
separate completed local gates from publication/download and target-device work.
This result does not establish Flutter UI behavior or native compute interruption.

## Hugging Face distribution and in-app installation

`quds_proofing_spacy_install.dart` (dart:io hosts only) downloads the published
artifacts from the immutable revision of
[`cstr/crispembed-spacy-de-core-news-sm-3.8.0`](https://huggingface.co/cstr/crispembed-spacy-de-core-news-sm-3.8.0)
only when the user explicitly asks. `distribution.dart` compiles in every pin:
the capsule SHA-256/length, its internal `distribution.json` digest and the
exact native library digest. The installer authenticates the complete archive
before decompressing, accepts only the closed canonical USTAR tree written by
CrispEmbed `tools/spacy/distribution.py`, verifies every member against the
authenticated manifest and the fixed bundle pins, stages privately, publishes
`packages/<archive sha256>` with one rename and re-verifies the closed tree.
`installBundle()` fetches only the five model files for hosts that ship a signed
native library inside the app (App Store, iOS, Android, and the sandboxed
Studio macOS build); downloading executable code is never offered there.
`tool/build.py --native` builds that library for macOS arm64 from the pinned
CrispEmbed v2 runtime source (static PCRE2, system libc++ only) with a
receipt. The build is reproducible: source paths are mapped, so the same
toolchain gives the same bytes in any directory.
`SpacyNativeBackendFactory(hostBundled: true)` opens it from the app's
`Contents/Frameworks` (the digest is still verified before loading).
The Studio macOS build installs the exact ad hoc signed library
`spacyGrammarMacosBundledSha256` (`ccc96620…`). Its bytes are pinned at an
immutable Hub revision, and analysis and manual German grammar are qualified
for it ([evidence](../../docs/validation/native-spacy-macos-bundled-20261119/README.md)).
Any other host build, including a `--rebuild-spacy` with another toolchain, is
a new binary. It has no recorded qualification, and the grammar planner
refuses it. A `mirror` can redirect transport but cannot change what is
accepted.

Claims are recorded per exact library digest (`spacyQualificationFor`). The
grammar planner independently refuses any build outside
`spacyGrammarNativeSha256s`, and a test keeps the catalog consistent with that
set. Grammar is qualified without named entities (capability mask 15), so hosts
open the grammar worker without NER.
Platform status: Linux x86-64/AVX2 published and qualified (analysis and manual
grammar). The macOS arm64 library bundled in the Studio app is qualified
(analysis and manual grammar). The downloadable macOS arm64 and Linux arm64/x86-64
v2 capsules are analysis only. Windows, Intel macOS, iOS, Android and web are
unavailable with stated reasons. `tool/install_from_hub.dart` performs a fresh-cache Hub
readback through the same installer.

## Explicit local installation

For the qualified Linux candidate, use the [W7 immutable package and installation
procedure](../../docs/validation/native-spacy-w7-20261118/CONTINUE.md). Its
original native/header/notices and five-file model bundle are authenticated by
external hashes, installed atomically, and verified as a complete immutable
tree. The actual installed worker is qualified on this exact candidate and six
external dependency builds. Portable rebuilds and other devices require separate
qualification; do not substitute rebuilt bytes into the retained result.

The native library lives inside a directory named by its SHA-256. The bundle's
original wheel/model/resource/manifest and notice hashes remain fixed in
`bundle.dart`; an adjacent manifest cannot change the trusted pins. Build and
conversion details remain in [CrispEmbed tools/spacy](https://github.com/CrispStrobe/CrispEmbed/blob/feat/native-spacy-w7-20261118/tools/spacy/README.md).

The host must set `CRISPEMBED_SPACY=1` before starting its process, or call
`enableSpacyNativeGateForProcess()` after the user explicitly enabled local
analysis. Opening a backend does not change environment variables, download files, start subprocesses,
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

## Manual Studio view

The example host exposes **Review → German analysis → Analyze text**. Opening
the dialog does not initialize a worker. The explicit analysis action uses a
selection within one body/table paragraph, or the current paragraph when the
caret is collapsed. It shows token, lemma, POS/tag, morphology and dependency
annotations and can select a current token in the original document. It does
not edit text or add grammar findings.

Ordinary users use **Review → Analysis setup** (or **Setup…** in the analysis
dialog). It shows the immutable source URL, size, SHA-256 and licenses, and
downloads only after **Download and install**. Installation enables the analysis
view; **Manual German grammar suggestions** stays off until switched on and is
offered only for a build with recorded grammar qualification. When on, the
provider is registered with `configureManual`, so it runs for **Check document**
and never while typing; switching it off releases its worker. Settings and the
verified installation live in the app's private data directory.

For development, the environment variables below keep precedence.
Before starting the Linux host, explicitly configure `CRISPEMBED_SPACY=1`,
`QUDS_SPACY_BUNDLE`, `QUDS_SPACY_LIBRARY` and
`QUDS_SPACY_LIBRARY_SHA256` with the verified immutable installation described
above. A missing/disabled installation remains visibly unavailable. Header,
footer, comment, frame and generated TOC text, multi-paragraph selections,
mixed locales and non-de-DE units are outside this view. Edits, language,
document or configuration changes invalidate visible results. Cancellation,
closing and retry after a failed worker preserve native resource ownership.

## Optional manual grammar API

`quds_proofing_spacy_grammar.dart` exports `SpacyGermanGrammarPlanner` and
`SpacyGrammarProvider`. The [W6 evidence and scope](../../docs/validation/native-spacy-w6-20261117/README.md)
describe the separate development panel, predeclared qualification protocol and
real editor controls. It started as a bounded experiment for noun/finite-verb
number agreement in `de-DE` on the exact accepted native library. Grammar v2
adds four rule families (below). It is not a general German grammar checker or
a released model/runtime distribution.

### Rule families (grammar v2)

`SpacyGrammarFamily` lists every family with a stable rule ID, German and
English labels and explanations, and the deterministic rule IDs whose ignore
also suppresses it. The [grammar v2 evidence](../../docs/validation/native-spacy-grammar-v2-20261120/README.md)
records a sealed per-family qualification on both qualified digests. The
macOS bundled run and the Linux replay are identical on all 1,221 rows.

| Family | Rule ID | State |
| --- | --- | --- |
| Subject/verb number (W6/W7) | `de.spacy.noun-verb` | qualified, on |
| Article/adjective/noun agreement | `de.spacy.np-agreement` | qualified, on |
| Case after fixed-case prepositions | `de.spacy.preposition-case` | qualified, on |
| Finite verb position (V3 after a fronted adverbial; V2 in dass/ob/wenn/… clauses) | `de.spacy.verb-position` | qualified, on |
| Subject/verb person | `de.spacy.subject-person` | failed one valid control; experimental, off |

`spacyGrammarQualifiedFamilies` is the provider's default. Pass
`families: {...}` to `SpacyGrammarProvider.load`/`.withTransport` to choose
others, and `englishMessages: true` for English explanations.
`SpacyGermanGrammarPlanner()` without arguments still plans only the original
noun/verb family, so the consumed W6/W7 replays are unchanged. The new
families are pure Dart. They take structure (heads, `nk`/`sb`/`cp` labels,
tags) from the native parse. Every corrected form comes from reviewed facts:
the noun lexicon, closed determiner and adjective-ending tables, the fixed-case
preposition list, and reviewed verb paradigms. Each family abstains on
ambiguity, coordination, quotations, protected text and personal words.

After an explicit user action, a host with a verified installation may load a
dedicated provider and attach it to the editor's **manual** proofing service:

```dart
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_grammar.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_native.dart';

final provider = await SpacyGrammarProvider.load(
  backendFactory: factory, // Verified factory configured as above.
  enabled: true,           // The default is false and opens no worker.
  vocabulary: controller.proofing.vocabulary,
);
try {
  controller.proofing.configureManual(
    OfficeProofingService(providers: [provider]),
  );
} catch (_) {
  await provider.dispose();
  rethrow;
}

// Explicit checking/F7 includes this manual service. Typing does not.
final summary = await controller.checkDocumentProofing();
```

`configureManual` replaces the session's previous manual service. The session
owns and disposes the installed service; do not share the provider's transport
with another provider or the Studio analysis view. Hosts that need a shutdown
barrier should await the provider's idempotent `dispose()` future after session
disposal or detachment. An active native call retains its context until it
finishes safely. The stock Studio analysis dialog remains an annotation view;
this change does not add a grammar toggle or register a grammar provider there.
Studio's **Analysis setup** lists the rule families under **Manual German
grammar suggestions**. Qualified families are ticked by default, and
experimental ones are marked and off. The choice is stored with the other
spaCy settings.

The planner accepts one bounded sentence with a reviewed common-noun subject
and third-person present-indicative finite verb, including selected intervening
prepositional phrases and initial-adverb inversion. It checks original spans
and all licensed noun/verb readings against the existing reviewed lexical
facts. Unknown words, compatible alternative readings, quantity/partitive
constructions, quotations, literals, multiple sentences and unsupported syntax
abstain. Native parses cannot override lexical ambiguity. Every edit is a
single reviewed replacement with exact original UTF-16/grapheme boundaries.

Use the stable rule ID `de.spacy.noun-verb` to ignore the optional rule; the
existing `de.grammar.noun-verb` ignore also suppresses it. The v2 families
are likewise suppressed by their own IDs or by `de.grammar.phrase-agreement`/
`adjective-ending`, `preposition-case`, `pronoun-verb` and `word-order`. Personal/ignored words
are captured with their vocabulary revision. Changed documents, requests,
configuration and vocabulary invalidate pending results. Unsupported locales
and missing/failed native execution remain explicit outcomes. Suggestions use
the existing review, protection, correction, recheck and undo paths, with
deterministic findings taking precedence when proposals overlap.

## Local validation

After resolving the workspace dependencies, run the model-free package suite
from the repository root with
`flutter test --no-pub packages/quds_proofing_spacy/test`. It checks source mapping, malformed
UTF-16, source reconstruction, sentence/dependency invariants, immutable results,
snapshot identity, explicit failures and worker lifecycle controls.

The separate actual-library driver requires all assets and fails when they are
absent; it does not skip model checks within a green unit suite:

```sh
CRISPEMBED_SPACY=1 dart run packages/quds_proofing_spacy/tool/replay_development.dart \
  --library "$QUDS_SPACY_LIBRARY" --library-sha "$QUDS_SPACY_LIBRARY_SHA256" \
  --bundle "$QUDS_SPACY_BUNDLE" --quds-root . --report "$QUDS_SPACY_REPORT"
```

Add `--mode worker` to run the same comparisons through the real persistent
isolate. Both modes record source hashes before and after execution and fail
if the imported source closure changes. Each invocation needs a new report
path. The separate `tool/native_fault_fixture.c` and
`tool/native_fault_probe.dart` exercise this binding against deliberately
malformed C ABI outputs, including counted NUL, bounded errors and exact frees.
They are test-only artifacts and perform no trained inference.

This driver replays the existing 16 **development** documents and authored API
controls through the actual Dart binding. It compares every exposed annotation
and sentence, including nonzero origins. It does not rerun or retune the frozen
eight-case native acceptance, and repeat development executions are not new
independent linguistic-quality evidence. Numerical native-stage evidence stays
in CrispEmbed's immutable acceptance receipt. No GitHub Actions query or wait is
needed for these checks.

The first Dart comparison rejected a correct whitespace-only source sentence
because it incorrectly required a self-headed token's label to be `ROOT`.
Original spaCy labels that whitespace root `dep`. The corrected validator uses
the ABI's own-index root contract and preserves same-sentence, single-root and
cycle checks. The first failing receipt and its exact hash-matched source
archive remain in `docs/validation/native-spacy-w5-20261117/`; goldens and the
native binary were unchanged. Its initial diagnostic sanitizer also replaced
the relative root argument `.` inside a message. Later reports sanitize
absolute paths; the original negative receipt is retained verbatim.
