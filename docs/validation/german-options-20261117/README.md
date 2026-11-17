# German grammar options and current Office integration — 17 November 2026

The tested runtime checkpoint is `6572e6588e2212cdd026ce8e2f90464cab483d04`.
This integration includes PRs #101 and #105, current morphology and optional
GECToR work, and main's ODT nested lists, sections, bookmarks/links, ODP links
and ODF metadata. Every canonical remote branch captured in
`evidence-index.json` is an ancestor of this checkpoint. Historical receipts
remain attributed to their original sources. Model weights are not committed,
bundled, downloaded automatically or enabled in CrispCloud.

## Fresh checks

- Engine analysis: clean. Selected proofing and ODF regressions: **816 passed**.
- Optional GECToR analysis: clean; **193 passed, one native-library fixture
  skipped**. The real inference below supplies separate model evidence; it
  does not turn the skipped CrispEmbed FFI fixture into a passing test.
- Editor grammar/context/dialog/manual tests: **57 passed**.
- CrispCloud preview/license/grammar/manual integration: **81 passed** on the
  reconciled vendor source. Host analysis of the changed services/tests is clean.
- Host source verifier: 2,597 managed files, consisting of 740 canonical files
  and the unchanged 1,857-file standalone legacy parser. Sync guard unit tests:
  nine passed. Existing crypto release-input check passed.

The first host run had six failures caused by incoming tests expecting raw XML
without its existing `<!-- content.xml -->` prefix. Expectations were corrected
while retaining all annotation-exclusion assertions. A subsequent integration
run exposed lost bookmark export and frame text; the bookmark mapping was
restored and the arriving qualified frame-extraction implementation retained.
The final selected engine and host runs pass. These are selected suites, not a
claim that every test in every repository was executed.

## Actual German results

All accuracy numbers describe small, synthetic diagnostic panels, not population
accuracy. Exact correction means the whole resulting sentence matches the
authored expectation. Misses and valid controls remain in the retained output.

| Panel | Earlier rules | Integrated rules |
| --- | ---: | ---: |
| Target morphology errors | 1/73 | 68/73 |
| Broader challenge errors in that corpus | 0/8 | 2/8 |
| Valid controls incorrectly flagged | 0/175 | 0/175 |

The actual earlier provider was executed from detached main `2277634a`; no
candidate implementation was substituted. The candidate made 1,280 requests
across 256 sentences, including Unicode offsets, soft hyphens, aliases,
protected ranges, ignore and recheck. There were zero operational, protection,
ignore or recheck failures. Dart VM and compiled JavaScript/Node results agreed.
Input hashes remained unchanged. A separately authored, frozen 28-case panel
gave **10/12 targeted corrections, 0/4 broader syntax corrections, 0/12 valid
controls flagged**, also identical on VM and Node. No rules were tuned to it.

The same 30-case model panel was executed with each option:

| Option | Exact errors corrected | Valid controls changed |
| --- | ---: | ---: |
| Integrated deterministic rules | 7/18 | 0/12 |
| Original Proofbird reference, without application guards | 9/18 | 1/12 |
| Actual Quds guarded provider | 6/18 | 0/10 supported; 2 Swiss controls unsupported |
| Actual shared deterministic-first merge policy | 9/18 | 0/12 |

The combined result was measured through `mergeOfficeProofingReports`, not
estimated by taking the union of two score lists. The raw model incorrectly
changes valid Swiss `heisse` to `heiße`. The guarded provider advertises de-DE
only; de-AT/de-CH remain unsupported. The combined ordinary rules still handle
the two Swiss controls. This small incremental benefit does not establish
readiness for default model activation.

Real inference ran locally on macOS arm64 with the publisher's pinned v2.1.0
ONNX model, revision `8e3b50beef7d775cedb7b876009e88bcf2e8d6af`, SHA-256
`6d7b43b4bd95c7a00c02c8babc7569d28558df894afe4874d96c202e6ab9a464`.
All 13 bundle artifacts were hash/size verified. The original reference ran in
6.13 seconds with about 680 MiB maximum resident memory. The guarded run uses
the unchanged Quds worker, tokenizer, decoder, lexicon and guards, with an
evaluation-only Python ONNX transport returning both real F32 classifier heads.
Its Dart JIT RSS excludes the separate Python process. These are neither
CrispEmbed macOS FFI nor shipping-precision/mobile-memory qualifications.

`NSSpellChecker.checkGrammar` was also called on this Mac using advertised
German language `de`: **no grammar findings on the 30-case panel**. German
spelling and English grammar positive controls worked. The API therefore did
not provide useful German grammar coverage on this machine; this is not a
claim about every macOS installation.

## Options within the repository license policy

The policy permits reviewed MIT/BSD/Apache/MPL resources and the individually
audited Unicode-3.0 assets; it excludes GPL/AGPL and LGPL-only language assets.
Code, dictionaries, rules, model weights and notices are checked separately.

1. **Keep expanding our own rules over Unicode morphology.** This is the most
   immediately useful option. The pinned Unicode Inflection data supplies
   67,492 noun lemmas and 186,607 surface forms; it is data, not imported grammar
   rules. The complete Unicode notice is included in CrispCloud's licenses.
   [Source and license](https://github.com/unicode-org/inflection).
2. **Keep Proofbird GECToR optional/manual.** The tested pinned distribution is
   Apache-2.0 with its NOTICE retained; corpus attribution is documented
   separately. The publisher now advertises v2.2.0. That newer release requires
   its own immutable artifact, notice, quality and runtime evaluation before
   replacing the tested v2.1.0 pin. The current result supports further work,
   not default activation. [Publisher](https://huggingface.co/proofbird/gector-bert-de).
3. **Evaluate spaCy's German syntax pipeline as an analysis layer.** Its model
   license is MIT. It offers syntax/morphology analysis, not ready-made grammar
   corrections. New independently authored rules could use it for noun-subject
   agreement and clause context, where our panels expose gaps. Pin and review
   model dependencies and `LICENSES_SOURCES` before implementation; no spaCy
   dependency has been added here.
   [Model](https://huggingface.co/spacy/de_core_news_sm),
   [license](https://huggingface.co/spacy/de_core_news_sm/blob/main/LICENSE),
   [source notices](https://huggingface.co/spacy/de_core_news_sm/blob/main/LICENSES_SOURCES).
4. **Native macOS checking** is available through the platform API, but the
   live German test above gives no reason to adopt it as the grammar engine.
   [Apple API](https://developer.apple.com/documentation/appkit/nsspellchecker).

LanguageTool's LGPL resources remain outside this project's selected policy;
an MIT wrapper does not relicense its imported rules. HORST is not cleared:
its own model card says its Apache label is provisional and the final license
is undecided. These were researched, not imported.
[LanguageTool license](https://github.com/languagetool-org/languagetool/blob/master/COPYING.txt),
[HORST model card](https://huggingface.co/Bayernator/horst-ai).

## Reproduction and evidence

`evidence.tar.gz` contains the actual corpus inputs/results, receipts, model
outputs, Apple probe and test logs. `evidence-index.json` binds its members,
archive and captured refs by SHA-256. It contains no model weights or venv.
For the real guarded model comparison use the evaluation-only adapter in
`tools/proofing/german_model/evaluate_guarded_onnx.dart`; its README documents
the required verified bundle and isolated Python dependencies. The host's
companion report records its exact source pin and final host test receipt.
