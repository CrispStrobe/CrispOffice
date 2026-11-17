# German agreement, syntax analysis and model comparison — 17 November 2026

## Implemented in the ordinary Dart rules

The separately ignorable `de.grammar.noun-verb` check handles simple noun
subjects: `Die Kinder spielt im Garten → spielen` and
`Das Kind spielen im Garten → spielt`. It uses the existing reviewed Unicode
noun readings and 57 first-party present-verb paradigms. No new dictionary,
Python runtime, parser or neural weights are added to an app.

The rule requires an initial determiner/noun phrase with unambiguous nominative
number and a modeled finite verb. Only a bounded simple predicate is admitted.
All competing noun readings remain: valid singular `Die Leiter steht …` is
preserved. Fronted objects, coordination, relative clauses, unknown words,
modeled nominalized-adjective ambiguity, quotation, exclamations/questions and unparsed tails
cause abstention. This is advisory grammar checking, not unrestricted parsing
or automatic rewriting. More complex noun subjects remain future work.

The editor exposes a readable ignore/restore label. Actual controller tests
exercise correction, recheck, undo and redo. Engine tests cover both number
directions, ambiguity, fronted objects, protection, three German regions,
nonzero offsets, soft hyphens inside nouns/verbs, combining marks and a long
rejected predicate.

## Fresh validation

- **865 selected engine/proofing/ODF tests passed**, including current upstream
  ODT page fields, paragraph shading/borders and table border/height work.
  All 13 writer tests also pass after the later tab-stop arrival.
- **47 focused noun-agreement cases passed**, including the final Unicode
  assertions; this is a subset rerun, not 47 additional unique engine tests.
- **59 editor tests passed**, including the new rule's ignore/restore label.
- Five candidate-admission tests passed: changed weights, same-size changed
  publisher code, path escape, duplicate artifacts and a missing notice are
  rejected before native imports or publisher code execution.
- Engine and changed Dart analysis are clean. The companion CrispCloud report
  records host tests and the final verified vendor pin.

The frozen 56-sentence syntax panel contains 20 errors and 36 valid controls.
The actual prior provider corrected **0/20**; the new bounded Dart rule gives
**10/20**, with **0/36 valid controls flagged** in both cases. VM and compiled
JavaScript/Node agree, with zero operational/protection/ignore/recheck failures.
The panel was committed at `b13e0c72` before syntax or v2.2 inference. It is a
development diagnostic, not a blind accuracy benchmark for the subsequently
authored rule. Expectations were not changed after viewing outputs.

The existing morphology panel retains **68/73 target fixes and 0/175 flagged
valid controls**; broader challenge fixes increase from 2/8 to 3/8. All 1,280
variant requests succeed identically on VM/Node. The earlier independent
28-case panel retains 10/12 targeted fixes, 0/4 broader syntax fixes and no
flagged valid controls. The first syntax-to-rule schema adapter mistakenly
used `clean` where the existing harness counts `control`; that run is retained
but excluded from qualified counts. The corrected schema preserves every
sentence and expected output and measures all 36 controls.

With the actual pinned v2.1 Quds worker, tokenizer, decoder and guards over a
real local F32 ONNX transport, the deterministic-first combined result on the
original panel improves from **9/18 to 10/18 exact corrections**, with **0/12
valid controls changed**. The model alone remains 6/18, 0/10 supported controls
changed and two Swiss controls unsupported. This transport is evaluation-only;
it does not qualify CrispEmbed macOS FFI, shipping precision or mobile memory.

## Actual spaCy experiment

The official German model wheel is `de_core_news_sm-3.8.0`, SHA-256
`fec69fec52b1780f2d269d5af7582a5e28028738bd3190532459aeb473bfa3e7`,
14,639,490 bytes, run with spaCy 3.8.18 on this Mac. Statistical annotations
feed an independently authored agreement planner using our finite verb facts.

The initial prototype gives **15/20 fixes, 1/36 valid controls changed**. It
wrongly treats singular `Leiter` (ladder) as plural. Corroborating noun number
with the actual Dart morphology removes this false correction while retaining
**15/20 fixes, 0/36 controls changed**. This guard was designed after observing
that failure, not independently validated on the same panel. On the separate
76-case panel it gives 0/32 fixes and 0/44 controls changed; the original
30-case panel gives 2/18 fixes and no changed controls. These panels expose
its narrow noun-agreement scope. Unsupported regional cases are recorded
separately; no finding does not imply full language coverage.

The model's distributed license is MIT. Its source notices separately list
TIGER as commercially licensed by Explosion, Tiger2Dep as citation-only with
no packaged code, and WikiNER under CC-BY-4.0. Original notices and the actual
Python dependency metadata/notices are retained in the evidence archive.
Examined Python distributions use MIT/BSD/Apache/MPL/ISC/PSF and reviewed
ancillary permissive terms; this is an evaluation environment, not a native
app binary dependency closure. No TIGER/WikiNER corpus is redistributed.
[Publisher model license](https://github.com/explosion/spacy-models/releases/tag/de_core_news_sm-3.8.0),
[source-notice explanation](https://huggingface.co/spacy/de_core_news_sm/blob/main/LICENSES_SOURCES).

## Pinned Proofbird v2.2 comparison

The newer candidate is pinned to `bfd30ed1668c675d2593c2b361adc6e67d278f7b`,
model SHA-256 `03dcb6ba128f42dc8b65c4b3b93f6e27297dd5aedb606789aa164202fbd76dd0`.
Every bundle artifact was size/hash verified. The publisher releases the
weights/files under Apache-2.0 with a retained NOTICE; the new notice includes
Europarl attribution. Training-source terms remain separate. The model,
metadata, labels and verb/vocabulary assets change; this is not a drop-in file
replacement for the approved bundle.

Both versions ran their unmodified pinned publisher reference, with two native
CPU threads and identical inputs. These references omit application guards;
v2.2 also includes its publisher's additional `schon/schön` text rule.

| Panel | v2.1 exact fixes | v2.2 exact fixes | v2.1 / v2.2 valid controls changed |
| --- | ---: | ---: | ---: |
| Original, 18 errors / 12 controls | 9 | 9 | 1 / 2 |
| Syntax, 20 errors / 36 controls | 16 | 15 | 3 / 3 |
| Earlier prospective, 32 errors / 44 controls | 12 | 11 | 2 / 3 |

In particular v2.2 deletes a valid `das` in `Ich sehe, dass das das richtige
Haus ist.` Both raw versions also change valid Swiss spelling. These results
do not measure the publisher app's guarded quality, nor prove that a migrated
Quds guarded decoder would regress. They provide no basis for automatic
promotion. The current Quds admission gate was also exercised against the
candidate and correctly rejects its unapproved metadata before starting a
backend. The approved v2.1 pin remains unchanged and no model is enabled by
default. [Pinned publisher release](https://huggingface.co/proofbird/gector-bert-de/tree/bfd30ed1668c675d2593c2b361adc6e67d278f7b).

## Reproduction and retained evidence

[SYNTAX_EVALUATION.md](../../../tools/proofing/german_model/SYNTAX_EVALUATION.md)
contains commands and isolated dependency pins. The artifact manifests retain
immutable URLs, sizes and hashes. `evidence-index.json` binds the archive and
each member. It contains actual outputs, receipts, test logs and original
license notices, but no model weights, wheel binaries or Python environments.
The tested runtime and corpus commits are identified in the index; later
documentation commits do not change the tested grammar implementation.
