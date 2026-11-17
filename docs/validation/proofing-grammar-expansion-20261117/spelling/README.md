# German spelling, English/German locale handling, and independent review

This directory preserves component development evidence for the 17 November
2026 proofing continuation. The final source freeze is
`3a2ada5a04395fd2fa01c7878f4df9f1b9215558`; the parent
[`integration/`](../integration/) directory owns qualification of that complete
frozen source. Earlier logs here are development checks and are **not**
retroactively presented as complete final-source acceptance.

## Delivered behavior

German spelling gains a bounded, dictionary-backed distance-two suggestion
fallback. Prefix, middle, and suffix anchors are indexed by word length and
interleaved during search, including first-character mistakes. Every visited
candidate shares the existing default limit of 6,000 candidate checks. Direct
corrections retain priority; adjacent transpositions count as one edit. The
fallback is an incomplete shortlist, not an exhaustive nearest-word search.
Acceptance of words is unchanged: this is not a productive morphology or closed
compound recognizer.

Verified examples include `interresant` → `interessant`, `Komunikazion` →
`Kommunikation`, `Rechschreibugn` → `Rechtschreibung`, `Wissenscahflt` →
`Wissenschaft`, `Scmetterlng` → `Schmetterling`, `Strasenbahnn` → `Straßenbahn`,
and `xnternehemen` → `unternehmen`.

Personal dictionary terms can become correction candidates, with their exact
declared capitalization and locale retained: `QudsClodu` → `QudsCloud`. Ignored
words do not become candidates. Personal phrases, controls, and excessively long
terms are excluded from single-word suggestion searches. Swiss dictionary
suggestions retain `ss` spelling. Each newly computed suggestion search yields
to the event loop; known words and repeated cached mistakes keep the ordinary
batch path. Disposal or vocabulary changes reject partial findings.

Proofing and both hyphenators share locale canonicalization for Latin script,
modern German `1996` orthography, and well-formed Unicode locale preferences.
For example, `de-Latn-DE-1996` resolves to `de-DE`, and
`en-Latn-GB-u-nu-latn` resolves to `en-GB`. Historical `de-1901`, non-Latin
scripts, unknown variants/regions, private-use tags, and malformed extensions
remain unsupported. This does not expand the set of dictionaries or patterns:
English hyphenation remains US/GB, and Harper retains its existing
US/GB/CA/AU/IN dialects. Canonical supported tags take an allocation-free fast
path during layout's repeated language queries.

No dictionary, pattern corpus, generated data, dependency manifest, native
Harper implementation, or license selection changed in this component work.
The implementation and tests are first-party code under the repository license.

## Recorded component checks

All `.log.gz` files are ordinary UTF-8 logs compressed with deterministic gzip.
The test groups overlap and must not be added together as independent coverage.

| Evidence | Recorded outcome | Scope |
| --- | --- | --- |
| [`logs/targeted-vm.log.gz`](logs/targeted-vm.log.gz) | 77 passed | Existing spelling; new correction and locale tests; English and German hyphenation |
| [`logs/harper-provider-vm.log.gz`](logs/harper-provider-vm.log.gz) | 10 passed | Harper provider contracts, including actual transport language dispatch |
| [`logs/targeted-node.log.gz`](logs/targeted-node.log.gz) | 87 passed | Combined initial component group compiled to JavaScript |
| [`logs/final-vm.log.gz`](logs/final-vm.log.gz) | 67 passed | Spelling/locale/Harper provider tests after scheduler hardening; excludes the hyphenation suites |
| [`logs/final-node.log.gz`](logs/final-node.log.gz) | 90 passed | Combined component group after scheduler hardening |
| [`logs/quality-final-vm.log.gz`](logs/quality-final-vm.log.gz) | 14 passed | Final correction-quality suite, including the last personal-term guard |
| [`logs/quality-final-node.log.gz`](logs/quality-final-node.log.gz) | 14 passed | Same final correction-quality suite in Node |
| [`logs/analyze.log.gz`](logs/analyze.log.gz), [`logs/analyze-final.log.gz`](logs/analyze-final.log.gz) | No issues | Focused strict analysis of changed sources/tests |

The 90-test Node run preceded only the last personal phrase/length guard. The
final 14-test VM and Node runs follow that guard. The early logs were recorded
while implementation was progressing; in particular, the canonical-language
fast path was added during the initial component-check period. Use the parent
integration receipt for exact final-source qualification.

The final quality suite contains behavioral scheduler tests for event-loop
progress, cancellation, and vocabulary changes. It does not impose millisecond
pass/fail thresholds. [`source-binding.json`](source-binding.json) verifies the
delivered source/test files against the frozen commit at packaging time; it does
not claim that every historical run used those final bytes.

## Timing diagnostic and separately generated typo probes

[`benchmark.dart`](benchmark.dart) is the exact probe used for the four retained
JSON measurements. It has two distinct parts:

1. A **49-token paragraph** with 25 mechanically generated misspellings and 24
   distinct nonsense words. Distinct tokens avoid the repeated-word suggestion
   cache. Three warm trials record elapsed checking time and a 5 ms heartbeat's
   observed maximum scheduling gap. This is a responsiveness diagnostic, not
   49 independent grammar cases or a broad accuracy metric.
2. A **25-target correction diagnostic**. Each target loses its second
   character and transposes two later characters. Of these 25 targets, 24 are
   present in the existing dictionary; all 24 listed targets appear in the top
   five suggestions in these runs. `Texterkennung` is absent from the finite
   dictionary, so its corrupted form receives no useful correction. This small,
   deliberately constructed set does not establish general correction recall.

| Compiled Node diagnostic | Before per-search yielding | After per-search yielding |
| --- | ---: | ---: |
| Total paragraph check across three trials | 147–305 ms | 224–333 ms |
| Maximum heartbeat gap across trials | 66–165 ms | 12–18 ms |
| Heartbeat ticks per measured trial | 5–6 | 34–44 |

The additional yields trade some throughput for scheduler progress. Cold
initialization remained significant: approximately 1.4–2.0 seconds in VM and
4.0–4.4 seconds in Node across these observations. The existing `warmUp()` API
can move initialization out of an interactive check. Cold initialization itself
still has observable pauses; these measurements are not a latency guarantee.
The in-memory suggestion index also has a memory cost that this probe does not
measure.

VM warm trials contained an approximately 339 ms heartbeat outlier while other
compilation/tests were active. The complete result is retained rather than
excluded. Host scheduling, JIT compilation, garbage collection, and concurrent
work can influence these values. No browser was used for this diagnostic, so
Node results are not real-browser acceptance.

Measurements:

- [`benchmark-vm-before.json`](benchmark-vm-before.json)
- [`benchmark-node-before.json`](benchmark-node-before.json)
- [`benchmark-vm-after.json`](benchmark-vm-after.json)
- [`benchmark-node-after.json`](benchmark-node-after.json)

The after measurements precede only the final personal phrase/length guard. The
paragraph has no personal vocabulary, so that guard does not affect the behavior
exercised by this probe. Hashes and provenance of the generated JavaScript are
recorded in [`compiled-snapshots.json`](compiled-snapshots.json); the generated
dictionary/runtime bundles are intentionally omitted from this deliverable.
Compilation logs are in `logs/`. Reproduction can rebuild from repository
history, with the intermediate-source limits above kept explicit:

| Checkpoint | Scope |
| --- | --- |
| `93a8950aee4aa013b34e4e20a43d6a694168148d` | Initial spelling/locale implementation, before per-search yielding |
| `466298ff97d98342ae7e5f5e97e60967bd7664b9` | Responsive search and lexical personal-term guard; the timing probe preceded the personal-term guard |
| `3a2ada5a04395fd2fa01c7878f4df9f1b9215558` | Complete source freeze qualified by the parent integration gate |

The first unshimmed `node benchmark.js` attempt exited with status zero but
produced no benchmark JSON. It is **not** counted as a successful run. The
[`attempt receipt`](attempts/direct-node-entry-no-output.json) records the
observation and explicitly states that its original empty destination was
overwritten. Supplying the Dart JavaScript host alias produced the retained
Node results.

## Reproduction

Use the repository's pinned SDK and resolved dependencies. Commands below run
from the repository root; the runtime versions observed during this work are in
[`runtime-versions.log`](runtime-versions.log).

```sh
dart test packages/quds_office_engine/test/proofing/german_suggestion_quality_test.dart \
  packages/quds_office_engine/test/proofing/proofing_locale_test.dart \
  packages/quds_proofing_harper/test/harper_provider_test.dart --reporter expanded

dart test packages/quds_office_engine/test/proofing/german_suggestion_quality_test.dart \
  packages/quds_office_engine/test/proofing/proofing_locale_test.dart \
  packages/quds_proofing_harper/test/harper_provider_test.dart \
  --platform node --reporter expanded

dart --packages=.dart_tool/package_config.json \
  docs/validation/proofing-grammar-expansion-20261117/spelling/benchmark.dart

dart compile js --packages=.dart_tool/package_config.json \
  docs/validation/proofing-grammar-expansion-20261117/spelling/benchmark.dart \
  -o /tmp/quds-spelling-benchmark.js
node -e 'globalThis.self=globalThis;require(process.argv[1]);' \
  /tmp/quds-spelling-benchmark.js
```

For a historical comparison, use a separate checkout of the corresponding
checkpoint, resolve its pinned dependencies, and run the same saved benchmark
source with that checkout's package configuration. The later personal-term
guard means the responsive checkpoint is not the byte-exact intermediate
JavaScript snapshot; its unchanged behavior for this diagnostic is explained
above. Timing values vary by host and are not asserted by these commands. The earlier
[`exploratory spelling script`](review/exploratory-spelling-probe.dart) is retained
for transparency; it is not counted as another automated test suite.

## Independent German grammar review

The read-only review is documented in [`review/README.md`](review/README.md).
It found and confirmed fixes for subordinate infinitive false positives, a
comma-boundary error in the first fix, and role predicates incorrectly treated
as equality comparisons. Before, intermediate, and final outputs are retained.
No production code was changed by the reviewer; the grammar implementation
owner made the fixes and added the corresponding regressions.
