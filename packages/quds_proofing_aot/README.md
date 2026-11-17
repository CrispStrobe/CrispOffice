# Local AOT analysis and German grammar checking

This package connects Quds Office to the AOT/RML linguistic analyzer. The
default client selects a managed local native worker; an explicit HTTP client
supports separately running `SynanDaemon` services. It supplies two features:

The package provides two features:

- **Linguistic analysis:** tokens, lemma alternatives, grammatical readings,
  syntax variants, phrase groups, subject–predicate relations and inflected forms.
- **German grammar checking:** conservative, paradigm-verified suggestions through
  the existing Word review, correction, ignore-rule and undo workflow.

Here AOT means the linguistic analyzer from
[`sokirko74/aot`](https://github.com/sokirko74/aot), not Dart ahead-of-time
compilation. Native worker/build source is included, but executable binaries
and language dictionaries must be built and installed separately by the host.
Constructing a client does not start a worker or send a request. Runtime
analysis downloads nothing.

The local transport and client contracts have fixture coverage. The captured
native worker's complete live qualification, normalized-token source mapping
and local Studio integration remain unfinished; see [Validation](#validation).

## Local backend and explicit setup

`AotClient()` selects `AotProcessTransport`, whose executable defaults to
`quds_aot_worker` on `PATH`. It starts that executable on the first nonempty
request and reuses it for later requests. Communication uses bounded JSON lines
on stdin/stdout, with no listening port or automatic HTTP fallback. Process
support is limited to Linux, macOS and Windows desktop; browser/mobile hosts
report unavailable and require an explicitly supplied alternative transport.

The development build entry point is:

```sh
python3 packages/quds_proofing_aot/tool/build_native.py
```

It explicitly obtains pinned AOT and `nlp_base` source, builds the non-GUI
libraries and dictionaries, and assembles a runtime under
`.dart_tool/quds_aot_native/runtime`. It requires C++17, CMake 3.24+, flex
including `FlexLexer.h`, bison and zlib development files. Qt and an HTTP
server are not part of this build. `--source`, `--build-dir` and `--install`
select existing pinned source and explicit output locations. This build recipe
and its smoke script are implementation tooling; their presence is not a
completed native qualification receipt.

A library host should put the installed worker on `PATH` or use
`AotClient.local(executable: '/path/to/runtime/Bin/quds_aot_worker',
rmlDirectory: '/path/to/runtime')`. The resource argument overrides `RML` in
the child environment. Otherwise the worker inherits `RML`, or locates the
assembled resources beside its executable when `RML` is absent. The library
does not automatically search the repository's `.dart_tool` directory.

The separately built engine and data retain their upstream terms. See the
[native notice](native/NOTICE.md) for exact pins, build requirements and
distribution/source obligations. No generated native binary or dictionary is
committed to this package.

## Enable the Studio example through HTTP

The captured Studio integration still explicitly creates HTTP clients. The
library's new local default does not change that UI configuration. With a local
daemon running, start the example from its directory:

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

The analysis dialog captures selected body, comment, header or footer text. With
no selection it captures document body text. Choose German or Russian and press
**Analyze**. Inspect a clause's alternatives and select a token to request its
morphology and inflected forms. The analysis language is independent of the
document's proofing locale. Changing the document marks results stale; reload
the snapshot before another analysis. Cancel/close disposes that operation's
client without interrupting the separate grammar client. Each Analyze or
morphology action creates and disposes its own client; dialog-wide worker reuse
and shared morphology caching are not implemented in this captured UI.

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

// The host has already installed this worker and its language resources.
final client = AotClient.local(
  executable: '/path/to/runtime/Bin/quds_aot_worker',
  rmlDirectory: '/path/to/runtime',
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

The example above using `AotClient()` requires an installed worker on `PATH`.
The provider owns its analyzer by default. A host sharing an analyzer can pass
`ownsAnalyzer: false` and dispose it itself. The Studio example uses independent
clients so cancellation remains local to each operation.

HTTP compatibility is explicit. `AotClient.http()` defaults to the loopback
endpoint `http://127.0.0.1:17018/`, with POST requests. A custom endpoint is:

```dart
final client = AotClient.http(
  endpoint: Uri.parse('https://your-analysis-service.example/aot/'),
  allowRemote: true,
  timeout: const Duration(seconds: 20),
);
```

`AotClient.http(requestMethod: AotRequestMethod.get)` explicitly supports
older GET-only deployments. POST is preferred because it keeps submitted text
out of request URLs. Request-size limits and redirect rejection also apply to
GET. A server returning HTTP 400 does not trigger an automatic method change.

`allowRemote: true` allows the configured service to receive submitted text.
URLs with credentials, query parameters or fragments are rejected. Redirects
are disabled. Hosts may inject an `http.Client` or implement `AotTransport` /
`AotAnalyzer`; the transport owns and closes its injected HTTP client.
`AotClient(transport: ...)` continues to accept either transport or a test
implementation.

## Morphology cache and client lifetime

A reused `AotClient` retains successful immutable morphology results in a
bounded LRU cache. The key contains the exact input surface, language and
`withParadigms` mode. Identical concurrent lookups share one transport request.
Syntax document analyses, failed lookups and malformed responses are not cached.

The defaults are 64 entries and 512 Ki UTF-16 code units, measured by the
re-encoded raw JSON plus the surface key. This is a deterministic retention
estimate, not a heap-memory limit. An oversized result is returned without
being retained. `maximumMorphologyCacheEntries: 0` or
`maximumMorphologyCacheCodeUnits: 0` disables retention while preserving
in-flight coalescing. Disposal clears the cache and rejects late results.
Cache reuse is limited to the lifetime of that client; it does not imply reuse
across the Studio dialog's separately owned operations.

## Diagnostic scope

| Rule ID | Checked pattern | Verified example |
| --- | --- | --- |
| `aot.de.subject-verb-agreement` | Clause-initial, unambiguous personal pronoun followed by an adjacent finite verb | `Ich geht.` → `Ich gehe.` |
| `aot.de.preposition-case` | Selected fixed-case preposition followed by a personal pronoun or simple article–noun phrase | `mit den Hund` → `mit dem Hund` |
| `aot.de.adjective-agreement` | Adjacent definite/indefinite article, adjective and noun, with weak/mixed declension | `Der kleines Hund` → `Der kleine Hund` |

These are supported **pattern fixtures**, not measured production accuracy.
Actual suggestions depend on the analyzer's available dictionary readings and
paradigms. Unknown or predicted words, missing forms, ambiguous valid analyses,
mixed parts of speech, ambiguous `sie/Sie`, expletive `es`, quoted constructions,
coordination and unsupported
patterns lead to abstention. The provider does not treat missing syntax groups,
missing subject relations or parser failure as grammatical errors. It does not
provide a general German punctuation, spelling or word-order checker.

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

The upstream serializer provides no source character offsets. Without source
metadata, the client aligns surface tokens exactly and sequentially, skipping
only whitespace. If a token is omitted or normalized, later offsets remain
null. Analysis remains inspectable, but incomplete/mismatched coverage cannot
produce an apparently clean grammar result or a correction at a guessed
position. `fullyAligned` includes trailing source coverage. The CLI
`TestSynan` fixture shape differs from the HTTP format and is deliberately not
accepted by this parser.

The Dart consumer also accepts `sourceStart`, `sourceEnd` and `sourceText`
metadata, verifies exact original UTF-16/grapheme spans and complete sequential
coverage, and preserves the analyzer surface as `analysisText`. Grammar rules
abstain on normalized tokens and affected context. This path is covered with
injected fixtures. **The captured native worker at `0b4c0107` still calls the
unmodified upstream serializer and does not emit this metadata.** Live
normalized-token mapping, including `zu-helfen` versus source `zu helfen`, is
therefore not qualified or completed by those consumer tests.

Syntax JSON contains sentences, clauses, words and variants. A variant's `homNo`
selects a word homonym and `grm` describes its readings. Group coordinates are
inclusive **clause-local token indexes**, not character positions. Subject
relations point from subject to predicate and can run backwards. Morphology's
`wordForm` is a lemma, `found` distinguishes dictionary matches from predictions,
and flattened concrete forms inherit grammar from their nested paradigm data.
Raw grammar strings and nested morphology remain available for inspection.

## Bounds, cancellation and outcomes

Both transports default to 32,768 UTF-16 code units per query, 256 KiB encoded
request, 4 MiB response and four admitted requests, processed serially. The
local transport also bounds stderr consumption to 256 KiB. Its 60-second
deadline includes worker startup, queueing and response consumption. A worker
crash, protocol error or active-request timeout terminates the worker and fails
pending work; a new client is required to retry. Disposal terminates the owned
worker. The HTTP transport instead defaults to 15 seconds and uses HTTP abort
for cancellation, closing its client on disposal. Error messages exclude
document text and raw response bodies.

The grammar provider additionally bounds a check to 24 distinct morphology
lookups and 100 findings, and caches repeated word lookups within that check.
Its default complete-check timeout is 15 seconds, independently of transport
timeouts; the CLI explicitly configures both from `--timeout`. Hosts should
configure their service, provider and transport deadlines together. Limits
report failure instead of truncating text or returning partial success.
Provider timeout invalidates the provider; recreate it before retrying. No
automatic retry or background polling is added.

| Condition | Provider result |
| --- | --- |
| Successful, fully covered analysis and completed rule pass | `success`, with zero or more findings |
| Unsupported grammar locale | `unsupported`, no analyzer request |
| Unreachable/disposed analyzer | `unavailable` |
| HTTP error, malformed data, incomplete alignment, timeout, exceeded bound or stale configuration | `failed` |

## Command-line use

Run from the repository root after workspace dependency resolution and
explicit local worker/resource installation:

```sh
dart run packages/quds_proofing_aot/tool/aot.dart --mode doctor
dart run packages/quds_proofing_aot/tool/aot.dart --text 'Ich gehe nach Hause.'
dart run packages/quds_proofing_aot/tool/aot.dart --mode check --text 'Ich geht.'
dart run packages/quds_proofing_aot/tool/aot.dart --mode morphology --text children --language English
dart run packages/quds_proofing_aot/tool/aot.dart --file sample.txt --language Russian
cat sample.txt | dart run packages/quds_proofing_aot/tool/aot.dart --stdin
```

The CLI defaults to `--backend local`. `--executable` and `--rml` select the
installed worker and resources; it also reads `QUDS_AOT_EXECUTABLE` and
`QUDS_AOT_RML`. When run as this source tool, it can locate the repository's
default built runtime before falling back to `PATH`. A compiled CLI should use
explicit paths or a configured environment. `--mode doctor` accepts no document
input and checks synthetic dictionary/syntax examples for the chosen language.
`--timeout` accepts 1–600 seconds, with a default of 60. Input files and stdin
are bounded to 256 KiB and all text to 32,768 UTF-16 code units.

Use `--backend http` or an explicit `--endpoint URL` for a separately running
service. Add `--get` only for an explicit legacy GET endpoint; submitted text
then appears in the request URL. `--allow-remote` explicitly permits remote
processing. Local worker options and HTTP options cannot be mixed. `--help`
does not start an engine. Output is JSON; operational failures use exit code 2,
and findings remain reviewable suggestions.

## Optional separate HTTP daemon

To use a separately managed daemon, select HTTP explicitly:

```dart
final client = AotClient.http(
  endpoint: Uri.parse('http://127.0.0.1:17018/'),
);
```

Dictionary generation remains enabled. `--skipbigrams` omits optional bigram
data; the daemon still initializes its other language resources. The inspected
server supplies no authentication. Keep it on loopback for the local setup.
Upstream AOT uses LGPL-2.1; its separately installed engine and language data
retain their own notices. The Dart package does not redistribute compiled
engine or dictionary assets and does not change the existing component policy
for bundled Quds code/data. The local worker's separate distribution terms are
described in [native/NOTICE.md](native/NOTICE.md).

The CLI accepts `--endpoint URL` (selects HTTP), or `--backend http`. Studio
accepts a loopback `QUDS_AOT_ENDPOINT`. Older GET-only daemons require explicit
`--get`, `QUDS_AOT_USE_GET=true`, or
`requestMethod: AotRequestMethod.get`. POST is the default; GET places submitted
text in URLs. There is no automatic method fallback.

The package has source-authored contract fixtures and local tests for schemas,
Unicode positions, ambiguous/valid/error grammar cases, transport limits,
failure states, cancellation and provider integration. Studio widget tests
cover explicit invocation, token/word-form inspection and stale-result handling.
The earlier HTTP integration recorded 99 tests on both Dart VM and
JavaScript/Node. A separate production GET-transport smoke against the public demo confirmed the
three representative corrections and six clean/guard controls. Two infinitive
samples returned explicit incomplete alignment because the daemon rewrites
`helfen` to `zu-helfen`; their analysis can be inspected, but no correction is
attached to an invented range. The remote server revision is unknown; only
synthetic snippets were submitted. Its POST endpoint rejected the requests.

See the [historical integration report](../../docs/validation/aot-integration-20261117/README.md)
for exact local results, raw live responses, source reconciliation and the
smoke's extended timeout/cache configuration. Neither these finite examples nor
the source-authored fixtures establish general grammar accuracy, local native
packaging or target-device performance.

The captured [daemon-free continuation](../../docs/validation/aot-daemon-free-20261117/README.md)
at `0b4c0107` records a focused process/client cohort of 47 VM and 23 Node
passes, plus 78 mapping/rule/provider fixture passes. Those groups overlap
with earlier tests. Process tests launch a Dart fixture worker, not the native
AOT engine. The consumer mapping fixtures do not establish producer metadata
or live normalized-token alignment. Native build/smoke tooling and
`tool/qualify_cli.py` remain separate qualification work; the latter expects
normalized-token behavior that the captured native worker does not yet supply.
