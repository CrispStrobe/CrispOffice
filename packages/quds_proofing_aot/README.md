# Optional AOT analysis and German grammar checking

This package connects Quds Office to the AOT/RML `SynanDaemon` through its real
HTTP interface. It supplies two separate features:

- **Linguistic analysis:** typed tokens, lemma alternatives, grammatical
  readings, syntax variants, phrase groups and subject–predicate relations.
- **German grammar checking:** three conservative diagnostic families that
  verify suspected disagreements against recognized morphological paradigms
  and return reviewable suggestions through `OfficeProofingProvider`.

Here AOT means the linguistic analyzer from
[`sokirko74/aot`](https://github.com/sokirko74/aot), not Dart ahead-of-time
compilation. No native analyzer, language dictionaries or automatic downloads
are included. Install and run a daemon separately. The package defaults to
`http://127.0.0.1:17018/`; constructing a client does not send a request.

## Enable the Studio example

With a local daemon running, start the example from its directory:

```sh
flutter run --dart-define=QUDS_AOT_ENDPOINT=http://127.0.0.1:17018/
```

The define is empty by default. Setting it enables **Review → AOT analysis** and
adds the AOT provider to the Word editor's manual proofing service. **Check
document / F7** includes the configured provider. Typing checks keep the existing
ordinary providers. AOT suggestions use the existing review, apply and undo
flow; the analyzer never edits text directly.

The analysis dialog captures selected body, comment, header or footer text. With
no selection it captures document body text. Choose German or Russian and press
**Analyze**. Inspect a clause's alternatives and select a token to request its
morphology and inflected forms. The analysis language is independent of the
document's proofing locale. Changing the document marks results stale; reload
the snapshot before another analysis. Cancel/close disposes that operation's
client without interrupting the separate grammar client.

For an older daemon that accepts only GET, also pass
`--dart-define=QUDS_AOT_USE_GET=true`. GET puts submitted text in the request URL;
POST remains the default and there is no automatic fallback.

The example accepts loopback endpoints. Custom hosts can explicitly opt into
remote processing through the API below. A web host also needs an endpoint
reachable under its browser's CORS, mixed-content and local-network policies.
No browser permission policy is changed by this package.

## Library API

```dart
import 'package:quds_proofing_aot/quds_proofing_aot.dart';

final client = AotClient();
try {
  final analysis = await client.analyze('Der kleine Hund schläft.');
  for (final token in analysis.tokens) {
    print('${token.text}: ${token.homonyms} [${token.start}, ${token.end})');
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

`AotLanguage.german` and `.russian` support syntax and morphology.
`.english` supports morphology; English syntax reports `unsupportedLanguage`
without making a request. Analysis language does not imply a grammar-checking
provider for that language. The initial diagnostic provider supports modern
**de-DE**, including aliases normalized by the shared proofing contract.
de-AT, de-CH and other locales report **unsupported**.

To configure a Word host:

```dart
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_aot/quds_proofing_aot.dart';

final aot = AotProofingProvider(
  analyzer: AotClient(),
  vocabulary: controller.proofing.vocabulary,
);
controller.proofing.configureManual(
  OfficeProofingService(
    providers: [aot],
    timeout: const Duration(seconds: 30),
  ),
);
```

`configureManual` replaces that host's manual service. Hosts also using GECToR
should construct one service containing both distinct providers rather than
calling it twice. Ordinary deterministic findings retain the editor's existing
precedence when manual reports are combined.

The provider owns its analyzer by default. A host sharing an analyzer can pass
`ownsAnalyzer: false` and dispose it itself. The Studio example uses independent
clients so cancellation remains local to each operation.

Custom endpoints and test transports are explicit:

```dart
final client = AotClient(
  transport: AotHttpTransport(
    endpoint: Uri.parse('https://your-analysis-service.example/aot/'),
    allowRemote: true,
    timeout: const Duration(seconds: 20),
  ),
);
```

`AotHttpTransport(requestMethod: AotRequestMethod.get)` explicitly supports
older GET-only deployments. POST is preferred because it keeps submitted text
out of request URLs. Request-size limits and redirect rejection also apply to
GET. A server returning HTTP 400 does not trigger an automatic method change.

`allowRemote: true` allows the configured service to receive submitted text.
URLs with credentials, query parameters or fragments are rejected. Redirects
are disabled. Hosts may inject an `http.Client` or implement `AotTransport` /
`AotAnalyzer`; the transport owns and closes its injected HTTP client.

## Diagnostic scope

| Rule ID | Checked pattern | Representative fixture |
| --- | --- | --- |
| `aot.de.subject-verb-agreement` | Clause-initial, unambiguous personal pronoun followed by an adjacent finite verb | `Ich geht.` → `Ich gehe.` |
| `aot.de.preposition-case` | Selected fixed-case preposition followed by a personal pronoun or a simple article–noun phrase | `mit den Hund` → `mit dem Hund` |
| `aot.de.adjective-agreement` | Adjacent definite/indefinite article, adjective and noun, including weak/mixed declension | `Der kleines Hund` → `Der kleine Hund` |

These are supported **pattern fixtures**, not measured production accuracy.
Actual suggestions depend on the daemon's available dictionary readings and
paradigms. Unknown or predicted words, missing forms, ambiguous valid analyses,
mixed parts of speech, ambiguous `sie/Sie`, expletive `es`, quoted constructions,
coordination and unsupported
patterns lead to abstention. The provider does not treat missing syntax groups,
missing subject relations or parser failure as grammatical errors. It does not
provide a general German punctuation, spelling or word-order checker.

Every proposed replacement comes from a recognized paradigm for the same lemma.
Concrete feature tuples stay separate; a union of possible features cannot
justify a correction that has no concrete compatible form. Ambiguity work and
generated alternatives are bounded. Rules do not cross a newline and preserve
the source's casing and an adjective's comparison degree. Source offsets are validated against UTF-16/grapheme
boundaries, and a request's segment origin is added exactly once.

Shared protected URL/email/backtick ranges, personal and ignored vocabulary,
and request-scoped ignored rule IDs suppress affected findings. Vocabulary
changes during a check invalidate its result. A successful empty finding list
means these configured rules found no supported issue; it is not a claim that
the entire passage is grammatically correct.

## Real upstream response contract

The inspected revision and source links are recorded in [UPSTREAM.json](UPSTREAM.json).
The HTTP endpoint accepts form-encoded POST fields `action`, `langua`, and
`query`; `langua` uses `German`, `Russian` or `English`. `withparadigms` is
included only when requested because the daemon checks the flag's presence.

HTTP syntax responses are nested arrays: sentences contain clauses, each with
`words` and `variants`. A word has a surface `str` and string `homonyms`; a
variant selects a homonym through `homNo` and carries a `grm` string per word.
Grammatical alternatives are separated by semicolons. Group coordinates are
inclusive **clause-local token indexes**. A subject relation points from subject
to predicate and may run backwards. They are not character positions.

The daemon provides no source character offsets. The client aligns surface
tokens exactly and sequentially, skipping only whitespace. If a token is
omitted or normalized, later offsets remain null. Analysis remains inspectable,
but incomplete/mismatched coverage cannot produce an apparently clean grammar
result or a correction at a guessed position. `fullyAligned` includes trailing
source coverage. The CLI `TestSynan` fixture shape differs from the HTTP format
and is deliberately not accepted by this parser.

Morphology operates on one word. `wordForm` is a lemma, `found` distinguishes
dictionary matches from predictions, and `morphInfo` may contain unioned
features. Flattened concrete forms inherit grammar from their paradigm part,
form group and individual form. Original nested data and raw grammar strings
remain available for inspection.

## Bounds and operational outcomes

Default transport bounds are 32,768 UTF-16 code units per query, 256 KiB encoded
request, 4 MiB response and four admitted requests. Requests are serialized to
match the daemon's own serialized processing. A 15-second deadline includes
queueing and response consumption; cancellation uses the HTTP abort protocol.
Disposal cancels pending requests and closes the client. Error messages exclude
document text and raw response bodies.

The grammar provider additionally bounds a check to 24 distinct morphology
lookups and 100 findings, and caches repeated word lookups within that check.
Limits report failure instead of truncating text or returning partial success.
Provider timeout invalidates the provider; recreate it before retrying. No
automatic retry or background polling is added.

| Condition | Provider result |
| --- | --- |
| Successful, fully covered analysis and completed rule pass | `success`, with zero or more findings |
| Unsupported grammar locale | `unsupported`, no network request |
| Unreachable/disposed analyzer | `unavailable` |
| HTTP error, malformed data, incomplete alignment, timeout, exceeded bound or stale configuration | `failed` |

## Command-line use

Run from the repository root after workspace dependency resolution:

```sh
dart run packages/quds_proofing_aot/tool/aot.dart --text 'Ich gehe nach Hause.'
dart run packages/quds_proofing_aot/tool/aot.dart --mode check --text 'Ich geht.'
dart run packages/quds_proofing_aot/tool/aot.dart --mode morphology --text Hund
dart run packages/quds_proofing_aot/tool/aot.dart --file sample.txt --language Russian
```

Use `--endpoint URL` for another local port/path. Add `--get` only for an
explicit legacy GET endpoint; submitted text then appears in the request URL. `--allow-remote` is an explicit
remote-processing opt-in. `--help` does not connect. Output is JSON; operational
failures use exit code 2, and findings remain successful suggestions rather
than document modifications.

## Run a separate daemon

The inspected upstream build needs a C++17 compiler, CMake, zlib, flex/bison and
Qt6. Its HTTP server is disabled by default. Follow the pinned upstream
[build instructions](https://github.com/sokirko74/aot/blob/0d591d972c7bb2729f4764d3bc32611ea6fd142a/readme)
for your platform. A Linux checkout/build sequence is:

```sh
git clone https://github.com/sokirko74/aot.git RML
cd RML
git checkout --detach 0d591d972c7bb2729f4764d3bc32611ea6fd142a
git submodule update --init --recursive
export RML="$PWD"
printf 'set(BUILD_HTTP_SERVERS 1)\n' > CMakeLists.my
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel 2
DESTDIR="$RML" cmake --install build
"$RML/Bin/SynanDaemon" --host 127.0.0.1 --port 17018 --skipbigrams
```

Dictionary generation remains enabled. `--skipbigrams` omits optional bigram
data; the daemon still initializes its other language resources. The inspected
server supplies no authentication. Keep it on loopback for the local setup.
Upstream AOT uses LGPL-2.1; its separately installed engine and language data
retain their own notices. This independently authored HTTP client redistributes
neither the engine nor dictionaries and does not change the existing component
policy for bundled Quds code/data.

## Validation

The package has source-authored contract fixtures and local tests for schemas,
Unicode positions, ambiguous/valid/error grammar cases, transport limits,
failure states, cancellation and provider integration. Studio widget tests
cover explicit invocation, token/word-form inspection and stale-result handling.
The final local suite passes 99 tests on both Dart VM and JavaScript/Node. A
separate production GET-transport smoke against the public demo confirmed the
three representative corrections and six clean/guard controls. Two infinitive
samples returned explicit incomplete alignment because the daemon rewrites
`helfen` to `zu-helfen`; their analysis can be inspected, but no correction is
attached to an invented range. The remote server revision is unknown; only
synthetic snippets were submitted. Its POST endpoint rejected the requests.

See the [integration report](../../docs/validation/aot-integration-20261117/README.md)
for exact local results, raw live responses, source reconciliation and the
smoke's extended timeout/cache configuration. Neither these finite examples nor
the source-authored fixtures establish general grammar accuracy, local native
packaging or target-device performance.
