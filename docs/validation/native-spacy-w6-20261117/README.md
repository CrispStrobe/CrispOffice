# W6: qualified guarded German grammar

The first sealed W6 qualification passes against Quds main
`6245a6956a76a38f925e1eb18851c0086730112d`: **22 of 30 error cases are corrected
exactly, compared with five for the current deterministic provider**. The
combined provider adds **17 exact corrections**, loses none of the baseline's
five corrections, and adds no findings on the 42 valid or ten guard controls.
All four unsupported locales remain explicit. This is a finite,
assistant-authored panel, not a human-annotated corpus or a population estimate
of German precision/recall.
The panel includes 24 paired error/valid controls; unique input counts do not
imply independently sampled natural-language observations.

The optional provider is available through the explicit manual API and defaults
off. The stock Studio German-analysis dialog displays annotations; it does not
register the grammar provider. Linux x86-64/AVX2, de-DE and CPU/F32 are the
qualified scope. Other platforms, device qualification, release/distribution
and automatic/background activation remain separate work.

## Result and evidence

The [first complete result](qualification-first.json),
[process/runtime receipt](qualification-first.json.runner.json),
[independent mechanical audit](qualification-audit.json) and
[case-level interpretation](qualification-case-review.json) preserve the outcome.
The raw result was saved remotely at
[3a8bca4f](https://github.com/CrispStrobe/quds_office_suite/commit/3a8bca4f8f8744bbb0fbd6809a700b5768d5ceba).

| Frozen subset | Deterministic exact | Native planner exact | Combined exact |
| --- | ---: | ---: | ---: |
| Subject with intervening prepositional modifier: 12 errors | 0 | 11 | 11 |
| Initial-adverb inversion: 12 errors | 0 | 6 | 6 |
| Baseline-overlap family: 6 errors | 5 | 5 | 5 |
| **All 30 errors** | **5** | **22** | **22** |

There are 22 raw native proposals. The existing merger suppresses the five
that duplicate deterministic findings, leaving 17 added corrections. No arm
has a finding or changed text on any of the 42 valid controls. Native findings
on all ten guards are zero. All 86 cases completed with zero operational
failures. The four unsupported cases are not counted as clean supported text.
All 22 corrected outputs were analyzed again and produced no further finding;
18 rechecks explicitly preserved a compatible lexical reading and four
abstained. A clean recheck is not a certificate that every parse is correct.
Repeated checks do not enlarge the 86-case denominator.

Examples of added exact corrections:

| Input | Reviewed replacement result |
| --- | --- |
| Die Katzen auf dem Sofa schläft. | Die Katzen auf dem Sofa schlafen. |
| Der Schüler aus dem Dorf lernen heute. | Der Schüler aus dem Dorf lernt heute. |
| Morgen arbeitet die Kollegen. | Morgen arbeiten die Kollegen. |
| Heute trinken der Mann. | Heute trinkt der Mann. |

Eight errors remain uncorrected. Four hit fixed vocabulary/shape bounds
(including two `offen` tails and unreviewed initial adverbs), three hit conflicting
or unsuitable native annotations, and one hits lexical spelling admission.
The raw decision label `multiple-prepositional-phrases` on the `Fenster im Flur`
case reflects a leftover unreviewed tail; the input does not contain two actual
prepositional phrases. These misses are retained without output-informed
planner changes. Of the 42 valid controls, 16 were explicitly preserved and
26 were handled by abstention. This conservative coverage is intentional.

The first development result and the post-main-refresh development replay each
score 2/10 deterministic versus 7/10 combined, with zero native findings on
18 valid and three guard controls. The replay uses the same 34 inputs and is
not an additional independent sample. See [the first run](development-first.json)
and [the latest-baseline replay](development-latest-baseline.json).

## Frozen order and the incoming baseline amendment

| Step | Verified remote commit | Meaning |
| --- | --- | --- |
| Initial protocol and reserved panel | [846fc037](https://github.com/CrispStrobe/quds_office_suite/commit/846fc0371b23bf4a84542db7a3f24eee2d8609dd) | Published before candidate outputs; 30 error, 42 valid, ten guard and four unsupported inputs |
| Current German main and protocol amendment | [ac9ea09c](https://github.com/CrispStrobe/quds_office_suite/commit/ac9ea09c377184f22f1c9b1a76610b9314c5a79a) | Adopts main `6245a695` before any qualification execution |
| Completed candidate and local controls | [da18e29c](https://github.com/CrispStrobe/quds_office_suite/commit/da18e29c20e2d42036cee911e85ff8bb22c328ae) | Source commit named by the seal |
| Source/runtime seal | [84b4120c](https://github.com/CrispStrobe/quds_office_suite/commit/84b4120ca29715d9b6f6555d1393f5fcb97e47cf) | Published before starting the one-shot qualification |
| First result and consumed claim | [3a8bca4f](https://github.com/CrispStrobe/quds_office_suite/commit/3a8bca4f8f8744bbb0fbd6809a700b5768d5ceba) | Complete outcome, including all misses and raw decisions |

The [original protocol](protocol-initial.json) is preserved byte-for-byte.
The [amended protocol](protocol.json) changes the deterministic baseline pin and
its four changed source hashes after new German phrase-completion work arrived.
The [amendment receipt](baseline-amendment.json) records the incoming commits
and refs. Inputs, expected answers, denominators, scorer and thresholds stayed
unchanged. The qualification panel SHA-256 remains
`52bede2f915db66489b45657d9b605f357d000b2024c8c734b57c10b3457a826`.
There is no exact locale/text overlap with either newly incoming morphology
corpus; see [the overlap receipt](incoming-corpus-overlap.json).

The baseline now supports complete phrase alternatives. The unchanged W6
scorer records multi-choice findings without selecting an oracle replacement.
On this particular reserved panel there are no unresolved multi-choice findings:
the baseline detects five error cases and all five have a single exact correction.
The updated baseline therefore does not lose credit through that scoring rule
on this panel. All 47 baseline dependency/source files match main after removing
only the additive shared-facts `part` directive. Seven reviewed shared-fact
source regions, the lexical data and all 57 verb paradigms remain unchanged.

The [candidate seal](candidate-seal.json) authenticates 342 source files,
package routing/configuration, five bundle files, the installed native files
and all six resolved native dependencies. The qualification runner and evaluator
independently enforce unchanged sources. Report reservation and the
[consumed claim](candidate-seal.json.consumed.json) are exclusive; incremental
reports use flushed writes and atomic replacement. **Do not rerun this consumed
qualification or tune against its outputs.** Any output-informed extension
requires a newly frozen independent qualification panel.

The root `pubspec.lock` is deliberately ignored by the repository. Its exact
sealed bytes were already published in W5 and are present in the candidate tree
at [workspace-pubspec.lock](../native-spacy-w5-20261117/workspace-pubspec.lock).
The [restoration map](source-restoration.json) resolves that one logical path;
the other 341 source-map entries are direct candidate-tree files. The audit
retains its initial missing-path finding and the verified resolution. No
dependency bytes or historical candidate were changed after qualification.

## Implementation and manual integration

The additive `GermanAgreementFacts` API exposes existing reviewed noun,
determiner, adjective and verb facts without replacing deterministic rule
behavior. `SpacyGermanGrammarPlanner` combines those facts with the accepted
native annotations. It supports a bounded one-sentence, common-noun,
third-person present-indicative agreement subset, including selected intervening
prepositional phrases and initial-adverb inversion. Unknown vocabulary, all
compatible lexical readings, quantity/partitive constructions, quotations,
protected literals, multiple sentences, unsupported syntax and unsafe source
boundaries cause preservation or abstention.

Each proposal has one reviewed replacement, stable rule ID
`de.spacy.noun-verb`, original-text evidence and exact UTF-16/grapheme boundaries.
The old `de.grammar.noun-verb` ignore also suppresses the optional rule. The
provider snapshots personal/ignored vocabulary, document/request/configuration
ownership and revisions, and rejects obsolete replies. Cancellation settles
callers while an active native call retains its context until safe completion.
Disposal joins cleanup; a transport is never shared with the analysis dialog.

See the [package API and setup instructions](../../../packages/quds_proofing_spacy/README.md).
A host explicitly loads `SpacyGrammarProvider` with `enabled: true` and installs
it through `controller.proofing.configureManual(...)`. Manual checking/F7 uses
that service; typing never does. Existing deterministic findings retain merger
precedence. Review, protection, correction, recheck and undo use the existing
editor paths. No Python interpreter or daemon is introduced into the app.

The real editor gate places the German text after an English emoji prefix at
UTF-16 origin 12. The `schläft` correction targets original paragraph range
33–40, changes it to `schlafen`, rechecks, and preserves undo/redo and language
formatting. Controls cover ignore/restore, vocabulary, delayed actual native
replies, locked content, field protection, unsupported locales, zero inference
while typing and awaited shutdown. These controls reuse one development error
and its correction; they are not ten independent linguistic cases.

## Local checks on the reconciled source

| Check | Result | Receipt |
| --- | ---: | --- |
| Complete spaCy package suite | 73 passed | [latest package](latest-package-controls/completion.json) |
| Deterministic German rules and shared facts | 869 passed | [latest baseline](latest-baseline-controls/receipt.json) |
| Existing editor proofing safety | 75 passed | [latest baseline](latest-baseline-controls/receipt.json) |
| Incoming German grammar editor integration | 36 passed | [latest baseline](latest-baseline-controls/receipt.json) |
| Existing word-run edit regression | 1 passed | [latest baseline](latest-baseline-controls/receipt.json) |
| Actual native editor integration | 10 passed | [latest native editor](editor-controls/latest-grammar-main.json) |
| Incoming icon rendering | 9 passed | [icon controls](main-refresh-controls/latest-icon-controls.json) |
| Browser grammar/native/Studio imports and capability execution | All three pass; native unavailable | [browser/package controls](package-refresh-controls/completion.json) |
| Static analysis | Zero issues in checked scopes | Package, editor and calendar receipts |

The 73 package tests include 19 planner, 16 provider and nine harness controls
alongside the existing 29 tests; do not add those subtotals again. The five
shared-facts controls are within the 869 German total. Browser probes prove
portable import/default-off behavior and execute no native calls. They were
retained across the later grammar-main merge, which changes no imports or
platform selection. Source/configuration/runtime before/after hashes are
recorded separately for every relevant run.

## Reconciliation, preserved failures and runtime

The [initial inventory](source-refresh.json), [Office main refresh](latest-main-refresh.json)
and [German baseline amendment](baseline-amendment.json) retain branch and PR
heads. The continuation includes Quds main through `6245a695`, late Office
repairs, incoming full-phrase formatting/tracked-history preservation and the
icon painter fix. CrispEmbed's original PR #236 was independently merged to
main `04e84458`; its owner review and merge are preserved on the continuation.
The separate worksheet/GECToR work is inventoried without importing unrelated
implementation into this native spaCy lane.

Review found a real date-only boundary defect in the incoming calendar feature:
UTC serial dates were compared with local-midnight instants. Berlin excluded
today from `last7Days`; Los Angeles shifted week boundaries. The two civil-date
constructors now use UTC while preserving the clock's calendar fields. Original
source and failures are retained. The [repair evidence](calendar-repair/final.json)
passes 178 UTC sheet tests, eight targeted tests in each of Berlin and Los
Angeles, and the unchanged twelve-case probe in all three zones. It changes no
German rule or native planner behavior.

The [runtime restoration](runtime/runtime-restoration.json) authenticates the
accepted library `ea89842ebf22c08508aff1cfbf18d78a107118af320523009616ff62b6e42977`
and bundle manifest `d599768375de3dc56abcca5cf1d49da0015857f9d3a10640aebb5317ef5d427e`.
The original native code/model were not rebuilt or tuned. The original eight-case
native acceptance stays consumed at CrispEmbed `2176c89`; it was not executed
again. [Hash-only preservation checks](frozen-integrity.json) authenticate all
56 original reference files and five retained native acceptance artifacts.

Initial analysis/test-only warnings, runner startup/temporary-directory errors,
and the calendar failure are retained alongside their exact source snapshots.
The [evidence index](evidence-index.json) hashes the retained artifacts; the
[completion record](completion.json) binds the current gate and required checks.
All checkpoints use `[skip ci]`. No GitHub Actions/status endpoint was queried,
awaited or rerun.

## Continuation

W6's bounded grammar-benefit and actual-editor exit is complete. Continue with
W7 target packaging/distribution and device qualification, retaining the exact
native/model identity and current default-off/manual-only policy. Broader
linguistic coverage needs new development cases and a new independently frozen
panel; the eight retained qualification misses must not become a silent tuning
set for another claim on this same panel.
