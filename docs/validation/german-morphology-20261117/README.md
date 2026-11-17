# German morphology continuation — 17 November 2026

The [completion report](continuation/README.md) records the final 233-reference
integration, fresh local checks, annotation fixes and recovered evidence audit.
The results below retain their original frozen-source scope.

## Delivered result

The offline German phrase analyzer now uses **67,492 noun lemmas, 127,987
readings and 186,607 surface forms** derived from pinned Unicode Inflection
data under **Unicode-3.0**. It replaces the 60-noun vocabulary bottleneck for
article, case and adjective checks while retaining conservative ambiguity
handling. The engine remains pure Dart, with the same implementation on native
and compiled JavaScript. No Python server, C++ runtime or NLP model is required.

The implementation is saved remotely at
[`8649b79efe0f2ad57d8f187233ed3f8b8177b3a0`](https://github.com/CrispStrobe/quds_office_suite/commit/8649b79efe0f2ad57d8f187233ed3f8b8177b3a0)
on `codex/german-morphology-20261117`. Later commits contain documentation and
qualification evidence only through recovered checkpoint
[`286bdeb73e4ee0e88f1b4a2e6ecf462c78082c86`](https://github.com/CrispStrobe/quds_office_suite/commit/286bdeb73e4ee0e88f1b4a2e6ecf462c78082c86).
This report qualifies the frozen source; subsequent branch integrations have
their own continuation evidence. GitHub Actions was not queried, awaited, or
used as a validation gate for this morphology qualification.

The unchanged comparison corpus improves **1/73 to 68/73 exact targeted
morphology corrections**, with **0/175 valid controls flagged** before and
after. A separate review set reaches **24/24 exact corrections and 0/60 flagged
controls**. Both corpora produce identical results on Dart VM and compiled
JavaScript. These targeted sets establish a bounded improvement; they are not
an estimate of unrestricted German grammar accuracy.

## Incoming work and incremental recovery

The earlier session started from combined fork main `8a778f18` and recorded
206 references / 138 distinct heads in [incoming.json](incoming.json). This
resume recovered the actual remote checkpoint `5ea6f798`; the handoff's planned
Unicode implementation had not yet been saved there.

The new inventory, observed **17 November 2026 at 09:42:29 CET / 08:42:29 UTC**,
contains **213 fork/upstream branch and PR references, 144 distinct heads**.
All are ancestors of the integration. It includes main through `ee725946`,
ODT lists, ODT paragraph and merged-table work, ODP table fidelity, and Zotero
recovery. The original heads behind squash-merged PRs #95 and #96 are retained
as parents as well. [incoming-resume.json](incoming-resume.json) records every
reference and the ancestor check.

| Remote checkpoint | Purpose |
| --- | --- |
| `7bc1c088228445e3d2d47d4dbfbe8a223c017b12` | Integrate the recovered branch with recent main, fidelity and Zotero work. |
| `be465bfba548006cc5fd5c3798cd166cdbcc5c63` | Retain original PR #95/#96 histories; all 213 captured references are ancestors. |
| `3fe1937984a3e5421efefa98dd550694cdcd6156` | Save the initial licensed implementation before resolving eager web initialization and remaining source-data issues. |
| `8649b79efe0f2ad57d8f187233ed3f8b8177b3a0` | Freeze the reviewed lazy resource, grammar safeguards, spelling supplement and regression tests. |
| `b70999ad9d5a1c6df12be4c27010ce77a097b84a` | Preserve corpus results, initial final receipts, source binding and implementation documentation while web packaging completes. |

The authenticated GitHub tree API was used for remote saves. The local test
commit `153012a92ec5fcbd8911d06f16c20cf8e254b256` and remote `8649b79e` have the
**same complete Git tree**, `efa8c68569f579e5ff63452eeed0b3607a54fe9c`; only commit
metadata differs. [source-binding.json](source-binding.json) checks the source
hashes from the final receipts against the saved remote tree. The ignored
workspace `pubspec.lock` is bound separately to an identical
[tracked historical copy](../proofing-grammar-expansion-20261117/integration/pubspec.lock);
it is not a file in that Git tree. The old
[continuation-checkpoint.json](continuation-checkpoint.json) is historical and
explicitly describes an unqualified intermediate implementation.

## Implementation and source quality

The new independently ignorable `de.grammar.noun-case` rule handles required
noun endings, including weak nouns. The existing preposition/article,
dative-plural and adjective-ending rules now use the broader lexical readings.
Examples include `mit dem Kunde → mit dem Kunden`,
`mit den Bänder → mit den Bändern`, and the disjoint article/adjective repairs
in `für unseren neuen Krankenhaus → für unser neues Krankenhaus`.

The resource includes 189 compact suffix patterns and preserves distinct
readings, genuine gender ambiguities and alternative case forms. Incomplete
paradigms are omitted; known contextual or gender-incomplete alternatives cause
abstention. In particular:

- Candidate lemmas must already belong to the modern spelling vocabulary.
  Generated inflections require corroboration by the actual source surface,
  case, number and pattern reference; a row's combined tags are insufficient.
- Context-dependent declension and unknown singular genders are not flattened
  into fixed paradigms. **2,885 unresolved surface keys** veto confident
  corrections, including the small first-party fallback. This protects forms
  such as nominalized `Armen` that also resemble ordinary noun inflections.
- Each proposed noun replacement must pass a separate standard/Swiss modern
  spelling mask. Morphology does not enlarge the spelling dictionary. It can
  retain additional analyses solely to avoid unwanted corrections.
- Seven bounded factual adjustments cover weak `Assistent` and `Architekt`,
  optional `Herz/Herzen`, strong/weak `Nachbar`, and the additional genders of
  `Teil`, `Bonbon` and `Stift`. Their sources are linked in the manifest.
  No Duden dictionary, external checker rule table or example corpus was copied.
- Valid nominalized-adjective alternatives such as `für die Junge` and
  `mit der Jungen` are preserved. `mit dem Junge` still suggests `Jungen`.
  Literary dative safeguards only abstain; they do not invent new spellings.

The spelling supplement adds 14 explicit basic noun forms, including
`Band`, `Junge`, `Amt` and `Vogel` forms. Seven were already present, so the
standard accepted vocabulary grows by seven to **444,130 forms**. The
unchanged 443,925-form upstream selection and 9,451 Swiss additions retain
their original provenance. A locale regression covers the supplement in
`de-DE`, `de-AT` and `de-CH`.

The 57 finite verb families, English Harper backend and English/German
hyphenation remain in place. Original UTF-16 source coordinates, grapheme
boundaries, soft hyphens, protected text, locale aliases, rule-ignore behavior
and correction/undo integration are exercised by the checks below.

The detailed [resource documentation](../../../packages/quds_office_engine/third_party/proofing/MORPHOLOGY.md)
and [manifest](../../../packages/quds_office_engine/third_party/proofing/morphology_manifest.json)
cover the schema, generation policy, masks, license notices and reproduction.

## Generic libraries and the license decision

**Unicode Inflection was adopted as a data source.** Its pinned revision is
`346cf8916249eddc3d5918cfbc27d2b24826ca37`. The actual 55,993,784-byte dictionary,
1,857,558-byte XML and 2,033-byte license all match their pinned SHA-256 values.
The generator rejects Git LFS pointer files. Unicode License V3 permits use,
modification and redistribution, including commercial distribution, with its
required copyright and permission notice. The original notice is retained in
every generated shard, a standalone license/notice pair, and the root and
engine package licenses. See the [pinned upstream license](https://github.com/unicode-org/inflection/blob/346cf8916249eddc3d5918cfbc27d2b24826ca37/LICENSE).

**spaCy remains a plausible later syntax layer.** The engine is
[MIT licensed](https://github.com/explosion/spaCy/blob/master/LICENSE), and the
specific [`de_core_news_sm` 3.8.0 metadata](https://github.com/explosion/spacy-models/blob/master/meta/de_core_news_sm-3.8.0.json)
declares the trained package MIT and lists a morphologizer, parser and
lemmatizer. The code and that specific model license were checked separately;
this does not assert that every model or training corpus has the same license.
It supplies linguistic analysis, so dependable corrections would still require
rule design and error-tolerant evaluation. A required Python service would also
leave the pure-Dart offline web path unresolved. It is not bundled in this pass.

**LanguageTool was excluded** because its
[LGPL license](https://github.com/languagetool-org/languagetool/blob/master/COPYING.txt)
is outside the accepted no-GPL/AGPL/LGPL-only policy. No LanguageTool-derived
rules or language resources were imported.

[continuity.json](continuity.json) confirms unchanged dependency manifests
(21 tracked files), Harper package contents (41 files), hyphenation sources and
notices (16 files), and base modern spelling shards (15 files) against incoming
main `ee725946`. No new package dependency or forbidden licensed component was
added. This is a source/license continuity check, not a fresh execution of
Harper's native Rust library on every platform.

## Independent corpus qualification

The original [256-sentence corpus](../../../tools/proofing/german_morphology_cases.json)
is unchanged from the recovered checkpoint. The preserved baseline receipt
records source `7dc17c9718b60844c4a8a888c77014aecbb57c0d`. Its saved compiled
JavaScript was replayed during recovery and reproduced all 1,280 recorded
requests exactly. It was not silently relabeled as a new baseline source run.

| Measure | Saved baseline | Frozen candidate, VM and Node |
| --- | ---: | ---: |
| Exact targeted morphology corrections | 1 / 73 | **68 / 73** |
| Exact broader sentence-grammar challenges | 0 / 8 | 1 / 8 |
| All exact errors, including challenges | 1 / 81 | 69 / 81 |
| Valid controls flagged | 0 / 175 | **0 / 175** |
| Operational, protection, ignore and correction-recheck failures | 0 | **0** |

The separately authored [84-sentence review set](../../../tools/proofing/german_morphology_review_cases.json)
covers source alternatives, weak/strong nouns, gender ambiguity, literary
forms and Swiss orthography. It is **24/24 exact errors, 0/60 flagged controls**
on both runtimes. It was used to expose and fix the `Stift` false positive, so
its final score is a regression result, not a held-out population benchmark.
The original comparison set was also used diagnostically during implementation.

Each set runs base, emoji/nonzero-source-offset, authored-soft-hyphen,
locale-alias and protected-code variants: **1,700 recorded requests per
runtime** across the two sets, with additional ignore and correction rechecks.
All four prose variants retain the same correction counts and clean controls;
all 340 protected-code requests stay clean. See
[accuracy-and-variant-check.json](qualification/accuracy-and-variant-check.json),
[frozen-corpus-summary.json](qualification/frozen-corpus-summary.json) and
[independent-review-summary.json](qualification/independent-review-summary.json).

The harness's `passed` status means successful operation with stable source
and cross-runtime equality. Exact corrections and false findings were assessed
separately; a successful process alone is not a grammar accuracy gate.

### Remaining cases are retained in the score

| Example | Actual outcome and reason |
| --- | --- |
| `mit dem Mensch` | Abstains because the selected lexical source retains a secondary neuter reading. The conservative rule does not discard it to force the expected masculine repair. |
| `bei den Computer` | Suggests `bei den Computern`, a valid plural correction. The frozen corpus expects singular `bei dem Computer`, so exact matching still counts this as a miss. |
| `bei jenes Gebäude` | Abstains where retained readings do not support a unique repair. |
| `für diesem Schlüssel` | Abstains because singular/plural analyses compete. |
| `mit dem Strassenpolizist` | The compound is not covered by the selected finite resource; unrestricted compound morphology was not added. |

Seven of the eight broader challenges remain uncorrected, including verb-governed
case, noun-subject/verb agreement, contextual genitive phrases and governed
`auf` complements. The analyzer does not become a full dependency parser by
adding lexical morphology. Unknown compounds, broad clause structure, tense,
mood and unrestricted adjective/verb analysis remain limitations. Internally
consistent upstream mistakes can still escape source corroboration; the
spelling guard does not prove every case label linguistically correct.

## Local verification

The official pinned toolchain is Flutter **3.47.8**, Dart **3.13.7**, Node
**24.22.1**. The SDK archive and all 162 required Pub archives were checked
against their recorded hashes. The workspace lockfile is unchanged. Final
source snapshots remained stable throughout each run; the component and editor
receipts bind 1,070 tracked source, test, tool, license and example inputs, plus
the separately preserved workspace lockfile.

| Local check | Result |
| --- | --- |
| Strict engine, editor and Harper analysis | All three passed, no issues. |
| Entire engine `test/proofing` directory | **503 VM + 503 compiled-Node tests passed.** |
| Selected English/German hyphenation regression files | **43 VM + 23 compiled-Node tests passed.** |
| Eleven focused editor proofing/hyphenation files | **156 tests passed.** |
| Both independent corpora | VM/Node identical; source and runtime inputs unchanged. |
| Every morphology bucket | All **256 buckets / 127,987 readings** validated on VM and Node. |
| Exact regeneration | **20 morphology files and 18 spelling files verified.** |
| Release web build and license collection | **Passed**; complete Unicode license and Inflection attribution retained in packaged `assets/NOTICES`. |

The focused 247-test grammar/loading run is a subset of the 503 proofing tests,
not an additional unique test count. Earlier in this same continuation,
unchanged Harper contracts passed 29 tests on each runtime, its source-projection
probe passed 28 checks over 2,000 ranges, and incoming ODT/ODP regressions passed
48 tests. Their earlier receipts remain separately identified. No repository-wide
test count, new native Rust/Wasm-library execution, actual browser interaction,
or Android/iOS device qualification is claimed by this continuation.

The release web build succeeded with unchanged source. The output manifest
records 117 files / 64,615,057 bytes; the complete Unicode-3.0 license and
Inflection attribution appear verbatim in packaged `assets/NOTICES` (with a
formatting blank line between attribution and license). The build emitted a
CupertinoIcons font-asset warning, retained in its log. Compilation and notice
packaging do not establish browser interaction or startup behavior. See
[web-license-collection.json](qualification/web-license-collection.json).

### Cold-start behavior and bounded lazy decoding

An intermediate eager implementation exceeded the service's 10-second default
timeout in a local Node cold run. The frozen implementation stores descriptors
in 256 hash buckets and prewarms only actual noun-phrase candidates. It yields
between newly decoded buckets. A warm call returns a future belonging to the
current zone, fixing the earlier widget-test initialization hang. Exposed
readings are immutable and each bucket is validated before publication.

The actual `OfficeProofingService` checks use its **default 10-second timeout**
and register only `GermanWritingRulesProvider`. They measure the changed grammar
path; spelling initialization, rendering and whole-application startup are
outside this timing scope.

| Input / runtime | Cold check | Median of 40 warm checks | Buckets / readings cached |
| --- | ---: | ---: | ---: |
| 78-character paragraph, Dart VM | 286.815 ms | 1.081 ms | 3 / 2,332 |
| 78-character paragraph, Node | 144 ms | 2 ms | 3 / 2,332 |
| 2,015-character passage, Dart VM | 866.785 ms | 10.122 ms | 68 / 47,883 |
| 2,015-character passage, Node | 1,094 ms | 10 ms | 68 / 47,883 |

The long input concatenates the 60 valid review controls. All 41 checks per
input/runtime completed successfully and stayed clean. The maximum measured
16-ms timer gap/tail was about 181 ms (short VM), 46 ms (short Node), 217 ms
(long VM) and 97 ms (long Node). These are local measurements, not a frame-time
or device-wide responsiveness guarantee. The full 256-bucket format validator
intentionally decodes everything and is not a typical paragraph benchmark.

Repeating descriptors across buckets increases the standalone optimized probe
size to about 4.85 MB of JavaScript. This trades shipped bytes for much less
cold initialization work; it is not the size of the complete web application.

## Evidence and reproduction

[morphology-corpora.tar.gz](morphology-corpora.tar.gz) retains full VM/Node result
JSON, receipts, package configuration, compile logs, exact-generation logs and
selected exploratory failures. Its
[index](morphology-corpora-index.json) contains every member hash and the archive
hash. Reproducible generated JS/maps are omitted; their hashes and exact
compilation commands remain in receipts. The checked-in harness and corpora
recreate them with the recorded toolchain.

The [final runtime archive](final-validation.tar.gz) contains
component/editor/analyzer/build logs, source snapshots, runtime and dependency
receipts, performance results, and exact runner copies; its
[index](final-validation-index.json) records every member hash.
The [recovery audit](recovery-audit.json) independently verifies the three
archive digests, their 131 member digests, the recorded command-log digests and
the source bindings against the frozen source. It also records the historical
lockfile mapping and the correction to the external final-archive index, which
had omitted its internal `CONTENTS_SHA256.json` member. Archive and historical
test-log bytes are unchanged. This audit is an integrity check of prior runs,
not a new execution of those tests or a qualification of later merged source.
The [exploratory archive](exploratory-evidence.tar.gz) and its
[index](exploratory-evidence-index.json) retain earlier failed tests,
eager loading measurements and the successful baseline replay. These are
historical evidence and are not represented as passing final-source runs.
Notable failures include incorrect source inflections and ambiguity,
a retained completed future crossing Flutter test zones, a wrapper stamp-file
collision between sandbox processes, and a harness-only compiler argument
failure from a raw trailing newline. The final timing runner transports text
as escaped JSON; product source did not change for that harness fix.

From a checkout with the recorded SDK, Node and resolved lockfile:

```sh
python packages/quds_office_engine/tool/proofing/generate_german_lexicon.py --download --check
python packages/quds_office_engine/tool/proofing/generate_german_morphology.py --download --check

python tools/proofing/run_morphology_qualification.py \
  --target . --output /tmp/quds-morphology-corpus --dart /absolute/path/to/dart
python tools/proofing/run_morphology_qualification.py \
  --target . --output /tmp/quds-morphology-review --dart /absolute/path/to/dart \
  --corpus tools/proofing/german_morphology_review_cases.json

dart --packages=.dart_tool/package_config.json tools/proofing/validate_morphology_buckets.dart
dart compile js --packages=.dart_tool/package_config.json \
  tools/proofing/validate_morphology_buckets.dart -o /tmp/quds-buckets.js
node -e 'globalThis.self=globalThis; require(process.argv[1]);' /tmp/quds-buckets.js

cd packages/quds_office_engine
dart analyze --fatal-infos lib test tool
dart test --reporter=expanded test/proofing
dart test --reporter=expanded --platform=node test/proofing
```

Use `--source /path/to/wortliste` and `--source-directory /path/to/unicode-inputs`
for already downloaded exact resources. The manifest pins every download;
no network is needed by the application. Compression uses the recorded Python
zlib version (1.3.2); other versions may change compressed bytes while retaining
logical data, so review hashes when deliberately changing the generator toolchain.
Complete selected editor, hyphenation and build commands are in the receipts.
