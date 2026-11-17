# Local AOT analysis and German grammar checking

Quds runs the real AOT/RML engine in a private local worker. **SynanDaemon is not
required.** The default client starts the worker only when analysis is requested,
reuses its dictionaries for later requests, and closes it on disposal. Document
text travels through stdin/stdout; no server, listening port, shell invocation or
automatic network fallback is involved.

The package provides two features:

- **Linguistic analysis:** tokens, lemma alternatives, grammatical readings,
  syntax variants, phrase groups, subject–predicate relations and inflected forms.
- **German grammar checking:** conservative, paradigm-verified suggestions through
  the existing Word review, correction, ignore-rule and undo workflow.

Here AOT means the linguistic analyzer from
[`sokirko74/aot`](https://github.com/sokirko74/aot), not Dart ahead-of-time
compilation. Engine binaries and dictionaries are built separately in one
explicit setup step. Runtime analysis does not download anything.

## Quick start: build, verify, use

Install C++17, CMake 3.24+, flex (including `FlexLexer.h`), bison, zlib development
files, Git and Python 3. On Debian/Ubuntu:

```sh
sudo apt-get install build-essential cmake flex libfl-dev bison zlib1g-dev git python3
```

From the repository root, after workspace dependency resolution:

```sh
python3 packages/quds_proofing_aot/tool/build_native.py --jobs 4
dart run packages/quds_proofing_aot/tool/aot.dart --mode doctor
dart run packages/quds_proofing_aot/tool/aot.dart --mode check --text 'Ich geht.'
```

The build obtains exact pinned AOT/nlp_base revisions, compiles the analysis
libraries and dictionaries without Qt, and assembles
`.dart_tool/quds_aot_native/runtime`. It verifies the assembled runtime before
replacing an existing installation. `doctor` uses synthetic text to check the
selected language's real dictionaries and syntax support. It accepts no document
input and returns JSON with `status: ready` when those probes succeed.

The CLI finds the built runtime relative to its own checkout. Applications can
use its executable path or put `runtime/Bin` on `PATH`. The executable discovers
its adjacent resource directory; `RML` is needed only to override that layout.

See [native setup and protocol](native/README.md) for a custom `--install`
destination, an existing pinned `--source` checkout, build-cache options,
packaging and native smoke commands. Linux x86-64 is locally built and tested.
macOS/Windows have source support but require platform validation. Browser and
mobile hosts explicitly report local-worker unavailability; they do not silently
switch to HTTP.

## Enable the Studio example

After the build, run from the repository root:

```sh
QUDS_WORKER="$PWD/.dart_tool/quds_aot_native/runtime/Bin/quds_aot_worker"
cd packages/quds_office_editor/example
flutter run --dart-define=QUDS_AOT_EXECUTABLE="$QUDS_WORKER"
```

**Review → AOT analysis** is always visible. Opening the dialog does not start
the worker; choose **Analyze** to run it. A missing installation produces a
setup message instead of hiding the feature. Setting the executable or resource
path also enables AOT in **Check document / F7**. If the worker is already on
`PATH`, use `--dart-define=QUDS_AOT_ENABLE=true` to enable these manual grammar
checks. Ordinary typing checks retain their existing providers.

| Studio setting | Meaning |
| --- | --- |
| `QUDS_AOT_EXECUTABLE` | Path to `quds_aot_worker`; defaults to its name on `PATH` |
| `QUDS_AOT_RML` | Optional separate resource root containing `Bin/rml.ini` |
| `QUDS_AOT_ENABLE=true` | Add local AOT to manual document checks when using the default executable |
| `QUDS_AOT_ENDPOINT` | Explicit legacy HTTP backend; cannot be combined with local paths |
| `QUDS_AOT_USE_GET=true` | Optional GET compatibility for an explicitly configured HTTP backend |

The dialog captures selected body, comment, header or footer text; without a
selection, it captures document body text. **Syntax** supports German and Russian.
Inspect alternate parses, groups and directed subject–predicate relations, then
select a token to look up its morphology.

**Word forms** is a separate mode for a selected single word and supports German,
Russian and English. English automatically uses this mode rather than attempting
unsupported syntax. Analysis language is independent of the document's grammar
locale. Repeated syntax and word-form actions share the dialog's private client
and morphology cache. Cancel, close or a document change invalidates pending
results and disposes that session; it does not interrupt the separate manual
grammar client. Reload the captured text when the document has changed.

## Library API

`AotClient()` and `AotClient.local()` select the local worker. Construction does
not launch a process. Dispose the client when the owning view or service closes:

```dart
import 'package:quds_proofing_aot/quds_proofing_aot.dart';

final client = AotClient.local(
  executable: '/absolute/path/to/runtime/Bin/quds_aot_worker',
);
try {
  final analysis = await client.analyze('Der kleine Hund schläft.');
  for (final token in analysis.tokens) {
    print('${token.text}: ${token.homonyms} [${token.start}, ${token.end})');
    if (token.isNormalized) print('Analyzer form: ${token.analysisText}');
  }
  final morphology = await client.morphology('Hund', withParadigms: true);
  for (final reading in morphology.readings) {
    print('${reading.lemma}: ${reading.grammar.raw}');
    for (final form in reading.forms) {
      print('${form.text}: ${form.grammar.raw}');
    }
  }
} finally {
  await client.dispose();
}
```

`AotLanguage.german` and `.russian` support syntax and morphology. `.english`
supports morphology only; English syntax reports `unsupportedLanguage` before
requesting engine work. Analysis-language support does not imply a grammar
provider for that language: diagnostics are qualified for modern **de-DE**,
including aliases normalized by the shared proofing contract. de-AT, de-CH and
other grammar locales explicitly report `unsupported`.

Successful morphology results use a bounded least-recently-used cache. Keys
include the **exact surface string**, language and paradigm mode; casing is not
folded. Concurrent identical lookups share one request. Defaults are 64 entries
and a retention budget of 524,288 UTF-16 code units, measured from re-encoded raw
JSON plus surface keys. This is a deterministic cache-admission estimate, not a
heap-memory cap. Oversized results are returned without retention. Syntax input
and failed requests are never cached. Set `maximumMorphologyCacheEntries: 0` to
disable retention; disposal clears retained entries.

### Connect manual Word grammar checks

```dart
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_aot/quds_proofing_aot.dart';

final aot = AotProofingProvider(
  analyzer: AotClient.local(), // quds_aot_worker on PATH
  vocabulary: controller.proofing.vocabulary,
  timeout: const Duration(seconds: 60),
);
controller.proofing.configureManual(
  OfficeProofingService(
    providers: [aot],
    timeout: const Duration(seconds: 90),
  ),
);
```

`configureManual` replaces that host's manual service. Hosts also using GECToR
should create one service containing both providers instead of configuring it
twice. Ordinary deterministic findings retain the editor's existing precedence
when reports are combined. The analyzer never edits text directly.

The provider owns its analyzer by default. A host sharing one can set
`ownsAnalyzer: false` and dispose it itself. The provider's library default
deadline remains 15 seconds; choose a provider/service budget appropriate to
the configured transport. Studio uses 60 seconds for the client and AOT provider,
with 90 seconds for the surrounding manual service.

Hosts can implement `AotAnalyzer` or inject `AotTransport`. `AotProcessTransport`
also exposes request, response, stderr and admission bounds. The supplied worker
is a direct executable that starts no descendants. An alternate executable must
honor that lifecycle contract.

## Diagnostic scope

| Rule ID | Checked pattern | Verified example |
| --- | --- | --- |
| `aot.de.subject-verb-agreement` | Clause-initial, unambiguous personal pronoun followed by an adjacent finite verb | `Ich geht.` → `Ich gehe.` |
| `aot.de.preposition-case` | Selected fixed-case preposition followed by a personal pronoun or simple article–noun phrase | `mit den Hund` → `mit dem Hund` |
| `aot.de.adjective-agreement` | Adjacent definite/indefinite article, adjective and noun, with weak/mixed declension | `Der kleines Hund` → `Der kleine Hund` |

These finite patterns do not establish general grammar accuracy. Every proposed
replacement must come from a recognized paradigm for the same lemma. Concrete
feature tuples remain separate; a union of possible features cannot justify a
correction that lacks a compatible form. Checks preserve source casing and an
adjective's comparison degree and do not cross a newline.

Unknown or predicted words, missing forms, a valid ambiguous reading, mixed parts
of speech, ambiguous `sie/Sie`, expletive `es`, compatible imperatives, quotations,
coordination and unsupported constructions lead to abstention. Rule contexts
containing a normalized analyzer token also abstain, even when its source span is
known. Missing groups, missing subject relations or a parser failure are never
treated as evidence of a grammar error. This is not a general German spelling,
punctuation or word-order checker.

Protected URL/email/backtick ranges, personal and ignored vocabulary, and
request-scoped ignored rule IDs suppress affected findings. Vocabulary changes
during a check invalidate its result. A successful empty finding list means these
configured rules found no supported issue; it does not certify the whole passage.

## Exact source mapping and normalized forms

Native results add optional `sourceStart`, `sourceEnd` and `sourceText` to the
existing syntax word shape. Offsets are in the untouched input's UTF-16 code
units. The worker verifies retained native word positions against an original
graphan token snapshot and the exact source substring. Dart independently checks
all three fields, ordering, whitespace-only gaps, grapheme boundaries and final
source coverage.

`AotToken.text` is the verified original text; `analysisText` retains the engine's
surface. For example, AOT emits `zu-helfen` for the original `helfen` in
`Wir versuchen, dir zu helfen.`. The native worker verifies the original `zu`
token and the engine's explicit infinitive reading, preserves the two original
spans, and provides fully aligned analysis. It does not blindly strip a prefix.
`isNormalized` exposes the distinction, and grammar rules abstain in affected
contexts.

Other transformations, unsupported characters or missing tokens can still make
coverage incomplete. Their analysis remains inspectable, but no correction is
attached to a guessed location. Without native metadata, including ordinary HTTP
responses, the existing exact sequential surface alignment remains in force:
only whitespace can be skipped. Thus the HTTP daemon's normalized infinitive
responses can still produce explicit incomplete alignment.

Syntax JSON contains sentences, clauses, words and variants. A variant's `homNo`
selects a word homonym and `grm` describes its readings. Group coordinates are
inclusive **clause-local token indexes**, not character positions. Subject
relations point from subject to predicate and can run backwards. Morphology's
`wordForm` is a lemma, `found` distinguishes dictionary matches from predictions,
and flattened concrete forms inherit grammar from their nested paradigm data.
Raw grammar strings and nested morphology remain available for inspection.

## Bounds, cancellation and outcomes

| Bound or deadline | Local default |
| --- | --- |
| Query text | 32,768 UTF-16 code units |
| Encoded request | 256 KiB |
| Response | 4 MiB |
| Admitted requests | 4, processed serially |
| Client request deadline | 60 seconds, including startup, queueing and response consumption |
| Worker stderr drain | 256 KiB for the worker lifetime; content is not exposed |
| Distinct morphology lookups per grammar check | 24 |
| Findings per grammar check | 100 |

A crash, malformed protocol, output-limit breach or active-request timeout
terminates the worker and fails pending requests. Disposal also terminates it.
Create a new client to retry; document text is not automatically resubmitted.
The provider separately invalidates itself after its own timeout. Limits report
failure rather than truncating text or returning partial success.

| Condition | Provider result |
| --- | --- |
| Fully covered analysis and completed rule pass | `success`, with zero or more findings |
| Unsupported grammar locale | `unsupported`, without requesting analysis |
| Missing/disposed analyzer or unavailable runtime | `unavailable` |
| Malformed data, incomplete alignment, timeout, exceeded bound or stale configuration | `failed` |

The headless build makes two exact, recorded changes in generated copies of
pinned upstream sources: it removes an unconditional `input.lem` document dump
and copies temporary group-description strings into owned JSON storage. Native
smokes verify no working-directory files and stable descriptions across clauses.
The pinned source checkout itself remains unchanged. See the runtime manifest
and [native notices](native/NOTICE.md) for the patch/source hashes and licenses.

## Command-line use

```sh
dart run packages/quds_proofing_aot/tool/aot.dart --mode doctor
dart run packages/quds_proofing_aot/tool/aot.dart --text 'Der kleine Hund schläft.'
dart run packages/quds_proofing_aot/tool/aot.dart --mode check --text 'Ich geht.'
dart run packages/quds_proofing_aot/tool/aot.dart --mode morphology --text children --language English
dart run packages/quds_proofing_aot/tool/aot.dart --file sample.txt --language Russian
cat sample.txt | dart run packages/quds_proofing_aot/tool/aot.dart --stdin
```

Choose exactly one of `--text`, `--file` or `--stdin`, except for `doctor`, which
uses only its built-in synthetic probes. Input files/stdin are bounded and decoded
as UTF-8. Use `--executable PATH`, `--rml PATH` and `--timeout SECONDS` for a custom
native setup. CLI environment defaults are `QUDS_AOT_EXECUTABLE` and
`QUDS_AOT_RML`; the built runtime is discovered next, then `PATH`. `--help` starts
no engine. Output is JSON with `schemaVersion` and `backend`; operational failures
use exit code 2, while findings are successful suggestions, never document edits.

## Optional legacy HTTP backend

To use a separately managed daemon, select HTTP explicitly:

```dart
final client = AotClient.http(
  endpoint: Uri.parse('http://127.0.0.1:17018/'),
);
```

Existing callers that relied on the old no-argument HTTP default should migrate
to `AotClient.http()` or an injected `AotHttpTransport`. Custom transport injection
continues to work. The native setup above does not need a daemon installation.

The CLI accepts `--endpoint URL` (selects HTTP), or `--backend http`. Studio
accepts a loopback `QUDS_AOT_ENDPOINT`. Older GET-only daemons require explicit
`--get`, `QUDS_AOT_USE_GET=true`, or
`requestMethod: AotRequestMethod.get`. POST is the default; GET places submitted
text in URLs. There is no automatic method fallback.

The library can opt into a non-loopback service with `allowRemote: true`. Endpoint
credentials, query strings, fragments and redirects are rejected. A web host also
needs the endpoint to satisfy its browser's CORS, mixed-content and local-network
policies. No browser policy is changed. An injected HTTP client is owned and
closed by the transport. The HTTP library default deadline is 15 seconds, with
the same query/request/response/admission limits as the local transport.

The inspected upstream contract uses form fields `action`, `langua` and `query`;
`langua` is `German`, `Russian` or `English`. `withparadigms` is sent only when
requested because the daemon tests the flag's presence. `TestSynan` produces a
different, lossy fixture format and is not substituted for this interface.
Pinned sources and interoperability details are recorded in [UPSTREAM.json](UPSTREAM.json).

## Validation and distribution

The real local native smoke passes 22 checks, including all supported syntax and
morphology languages, normalized German infinitives, strict request types, UTF-16
and byte limits, protocol recovery, missing dictionaries and no document-file
writes. The production Dart client/provider smoke independently passes 17 checks,
including the three grammar corrections above, grammatical/ambiguity controls,
native syntax, morphology and cache reuse.

The [current validation report](../../docs/validation/aot-daemon-free-20261117/README.md)
records the complete local Dart/JavaScript/editor cohorts, exact source revisions,
raw event logs and real native evidence. These finite results do not establish
general grammar accuracy or target-device performance. GitHub Actions are not
required for the documented local validation.

Upstream AOT uses LGPL-2.1; its engine and data retain their own notices. Generated
native binaries and dictionaries are not committed to this repository. The
explicit builder preserves the upstream license and records reproducible source
pins and patches. Read [native/NOTICE.md](native/NOTICE.md) before distributing a
built runtime; the Quds component policy does not replace upstream license terms.
