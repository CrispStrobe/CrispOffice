# Independent German context rules and non-AOT Office integration

17 November 2026. The AOT.ru/RML analyzer, dictionaries, package, Studio
registration and transports are excluded. Their feature branches are retained;
none of that feature's DAG is merged for this work. Engine-only Office repairs
were selected from snapshots `b9bfe664` and `48b6998b`, then reconciled with
upstream main through `4c9d60cd`. In particular, the retained Office changes
cover ODF frame/hidden-story extraction, field results, paragraph decoration,
tab/style caching, valid column children/gaps and ODP preset shapes. A duplicated
column-section close caught in integration was repaired before qualification.

## Production behavior

The existing offline Dart checker gains bounded verb-governed noun case,
copula number, main-clause word order and irregular participle rules. The four
new categories have independent ignore/restore controls. Two small additions
reuse the existing pronoun-agreement and das/dass categories: complete
`ihr + haben + mass object` clauses, and three-word object relatives after a
finite list of neuter artifact heads. They abstain on unparsed tails, fronted
dative subjects and content-clause nouns such as Wissen and Problem.

Context grammar precedes spelling for competing edits on the same source range,
so `gelest` suggests `gelesen` before distance-only spelling guesses. Both
findings remain available. Explicit metalinguistic mentions are protected;
ordinary quoted speech remains eligible. Unknown governors and genuinely
ambiguous noun readings do not force a guessed nominative interpretation.

The first-party common-word supplement and the existing pinned MIT Wortliste /
Unicode-3.0 morphology inputs are regenerated twice and byte-compared. No new
third-party dictionary or model dependency enters the app. See the generated
manifests for exact inputs, output counts and hashes.

## Independent implementation boundary

The rules and finite verb/case/participle/noun facts were independently authored
from ordinary German language knowledge and the existing licensed Quds lexical
interfaces. No LanguageTool implementation, rule patterns, messages, test corpus
or dictionaries were used. This records provenance; it is not a formal legal
clean-room certification or a claim to recreate LanguageTool's full coverage.

The frozen test inputs precede the corresponding extensions (`dce5fbde`,
`3fbf22e9`, `756367b5`). The holdout is lexical recombination, not an independent
human-blind benchmark. Gold remains unchanged for the ambiguous masculine day /
neuter metadata Tag and singular/plural dative Lehrer cases. No credit is
awarded for an alternative grammatical answer that differs from frozen gold.

## Qualification scope

The original panel reaches **18/18 exact corrections with 0/12 valid controls
flagged in the default writing + spelling path**, without any model, daemon,
pipe, spaCy dependency or AOT/RML adapter. The context panels retain 21/23 and
45/46 exact corrections, with 0/60 and 0/58 valid controls flagged. The separate
completion panel contains 8 errors and 20 controls. The broader morphology
panel remains diagnostic: 71/81 exact, including 68/73 targeted cases and 3/8
broad challenges, with 0/175 valid controls flagged over 1,280 requests.
Misses are retained rather than removed to improve the reported score.

The QA-only native ONNX C API shim performs actual in-process F32 inference
inside the Quds worker and returns both classifier heads. There is no Python
inference child, daemon or pipe. Official ONNX Runtime 1.23.2 C headers and its
MIT/third-party notices are recorded alongside artifact hashes. No native
binary, weight file, Python environment or runtime registration is committed.
Dart JIT and compiled AOT produce identical original-panel lane outputs. This
is Dart ahead-of-time compilation, unrelated to AOT.ru/RML.

The model-only lane corrects 6/18 original errors and adds no coverage once the
new default rules are present. It also introduces false positives on the new
completion controls. It remains disabled by default. Observed native F32 memory
is roughly 0.75–1.02 GiB and varies between runs. The final AOT run used
828 MiB versus 1,043 MiB for JIT, exceeding the provisional 768 MiB target.
This does not qualify the
shipping Q4 CrispEmbed backend or establish a reliable 768 MiB budget. spaCy
remains a research-only syntax option, not an application dependency.

Compressed receipts preserve source/dependency/SDK hashes, corpus results,
JIT/AOT identity, live output, failed development attempts and final tests.
They contain synthetic text only. Test totals describe their respective suites
and must not be added as a unique coverage count.

## Reproduce native inference (macOS)

Obtain the official ONNX Runtime 1.23.2 headers, library and notices outside the
repository and verify their hashes. Build the local QA shim, then pass the
verified library identities explicitly:

```sh
clang -std=c11 -O2 -Wall -Wextra -Werror -dynamiclib \
  -I /path/to/ort-headers tools/proofing/german_model/native_ort_probe.c \
  /path/to/libonnxruntime.dylib -Wl,-rpath,/path/to/ort \
  -o /path/to/libquds_ort_probe.dylib
dart compile exe tools/proofing/german_model/evaluate_native_quality.dart \
  -o /path/to/native-quality
/path/to/native-quality /path/to/verified-bundle \
  /path/to/libquds_ort_probe.dylib SHIM_SHA256 \
  /path/to/libonnxruntime.dylib ORT_SHA256 \
  tools/proofing/german_model/cases.json /path/to/new-results.json
```

The model bundle is verified against the committed artifact manifest. Outputs
must be new paths. The same argument vector runs under Dart JIT. The retained
build receipts hash all source libraries, resolved package files and the actual
SDK compiler/runtime, comparing source and dependencies before/after compilation.

## Rules specification and future extensions

The lexical layer supplies all retained noun readings, case masks and finite
verb paradigms. Context checks operate on original UTF-16 ranges and only on a
bounded complete clause with protected spans excluded. They return suggestions,
never mutate text automatically. A known governor can select accusative/dative;
an unknown governor cannot resolve an ambiguous indefinite noun phrase. Copula
number requires one surviving number. Word-order repairs swap adjacent known
subject/finite pairs only after reviewed adverbs or a bounded preceding clause.
Irregular participles come from a finite first-party fact table, never a guessed
suffix transform. Referential relatives have a finite independently authored
neuter-head list and an agreeing known transitive verb, exactly two commas and
an explicit matrix copula. Context gaps outside those frames are abstentions.

Future independent extensions should first commit a prose linguistic
specification and independently authored positive/counterexample corpus, retain
all license/provenance records, and review false positives separately from
recall. A legally formal clean-room project would additionally need independent
specification/implementation personnel and legal review; this work does not
pretend that a single implementation session meets that process. There is no
LanguageTool import or translated rule-set substitute in this implementation.

## Final local checks

The source freeze `8ce23da119d4cbffcc5f92cc720a5efb262c2bec` passed 835 engine
proofing tests, 507 ODT/ODF/ODP export tests, 118 editor proofing tests and 193
optional GECToR tests (one external native fixture skipped). Engine, changed
editor files and GECToR analysis are clean. Live native inference is separately
recorded and does not rely on that skipped fixture. After adding the missing
nominal Wissen entry, the default completion lane is 8/8 with 0/20 controls
flagged; the optional model/combined lanes still flag four controls.

The actual CrispCloud consumer passed 120 native Flutter tests covering previews,
annotation privacy, bundled license attribution, review dialogs, correction and
undo/redo. Nine sync-guard tests, the 2,620-file tracked source fidelity check and
crypto/export-policy input checks passed. Its source pin names the tested runtime
freeze; subsequent canonical commits only add this documentation and receipts.

See [the evidence index](evidence/index.json) for uncompressed and gzip hashes
and `final-summary.json.gz` for the machine-readable totals. Older failures are
retained alongside final results; they are not counted as successful checks.
