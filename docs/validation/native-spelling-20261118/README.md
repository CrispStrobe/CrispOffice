# Native spelling improvements — local validation

The spelling implementation is complete and locally validated at
`01e4b7223bf41ab589cbeeaada82cf2d6faee97d`. Later commits in this delivery
preserve evidence and review information. All **1,554 substantive tests** in
the selected proofing cohorts passed, with **zero skipped tests**. The same
**21 spelling smoke cases** passed in the Dart VM, a compiled native executable
and compiled JavaScript, producing identical complete result objects.

The [machine-readable verification](verification.json),
[independent review](review.md), [paired review probes](review-comparison.json)
and [closeout](review-closeout.json) give exact source identities and limits.

## User-visible changes

### German dictionary and suggestions

- Internal straight and typographic apostrophes share dictionary and personal
  vocabulary lookup. `Er darf’s.` no longer receives a finding solely because
  the dictionary stores `darf's`. Quotation delimiters, noun casing and locale
  distinctions remain significant.
- Suggestions preserve each source occurrence's apostrophes and hyphens, even
  when equivalent spellings share a suggestion cache. Findings keep the exact
  original text and UTF-16 coordinates, including text after emoji and combining
  marks. Personal-word restoration, removal and ignore controls use the same
  canonical comparison.
- Explicit hyphen compounds can correct multiple misspelled constituents:
  `Huas‑Türr` offers `Haus‑Tür`. Known constituents and declared personal terms
  keep their case and separators. Only complete, verified combinations are
  offered.
- Whole-token, personal and constituent searches share one candidate budget.
  Reconstruction is limited to eight explicit constituents within the existing
  64-code-unit suggestion bound; combination generation is bounded by the
  suggestion limit. This does not add unrestricted closed-compound parsing.
- Existing principal whole-word suggestions remain available. Independent
  review caught and repaired an intermediate regression affecting `Make-up`,
  `Arbeits-zimmer`, `Regierungs-zeit`, `Bür-ger` and `On-line`. Secondary
  alternatives can change under the shared budget; the search is not exhaustive.

### System spelling adapter

- Quds providers using Flutter's default spelling service coordinate access to
  its shared native channel across documents and replacement providers. An
  explicitly shared custom service also shares its queue; independent custom
  services remain independent.
- Every positive deadline includes queue time. Disposal settles callers
  promptly. Timeout retires the provider and its queued calls. Physical channel
  occupancy lasts until the underlying OS future settles, including late
  failures, so a replacement provider cannot collide with unfinished work.
- Representable scripts and numeric regions survive locale mapping, including
  `zh-Hant-TW` and `es-419`. Unrepresentable variants are unsupported instead of
  silently selecting another dictionary.
- Platform findings exclude protected URLs, email addresses and closed backtick
  spans, and invalid ranges that cut a grapheme fail the request.

The actual Word review dialog is exercised with both `🙂 Er draf’s.` and
`Ein Huas‑Türr.`. The tests choose the visible correction buttons and verify
the exact corrected source, undo and redo. Both scenarios run in one widget
clock because the provider shares its loaded dictionary future; this is a test
fixture arrangement, with no production workaround.

## Incoming work

Before spelling changes, all **193 branch heads and 154 PR heads** in the
captured remote snapshot were fetched and reconciled. Integration commit
`98a2a15056e55699b8ba5651fc79b26f94e5efd3` combines:

- Main `c8eca37d`, including Office qualification PR #154.
- Native spaCy reference PR #139 at `6df76a0d`.
- Stacked W7 packaging PR #153 at `2e013f26`.

The [reconciliation report](reconciliation.md) and [exact inventory](reconciliation.json)
account for ancestors, equivalent squash merges, equivalent integration trees
and superseded recovery branches. The intentional AOT/RML removal is retained;
native spaCy remains optional and disabled by default.

At closeout, main and both spaCy heads were unchanged. Concurrent Zotero work
had advanced after the original snapshot; its later SHA is recorded in the
closeout and is outside this spelling implementation and validation.

## Executed validation

Flutter **3.47.8** / Dart **3.13.7** came from the hash-verified official archive.
All **162** restored hosted-package archives matched their pinned SHA-256 values.
The live and baseline workspaces used the same resolved dependency lock. No
tracked dependency constraints or SDK identities were altered.

| Final cohort | Files | Substantive successes | Skips |
| --- | ---: | ---: | ---: |
| Engine proofing | 27 | 1,064 | 0 |
| Editor proofing | 8 | 140 | 0 |
| Harper adapter and source controls | 3 | 29 | 0 |
| GECToR adapter and source controls | 13 | 248 | 0 |
| Optional spaCy engineering | 6 | 73 | 0 |
| **Total** | **57** | **1,554** | **0** |

These final cohorts are counted once. The 73-test focused engine run, 21-test
platform subset and 23-test dialog subset overlap the table and are not added
again. Loading events are excluded from substantive counts.

| Same focused tests against reconciled baseline | Baseline passed | Baseline failed | Repaired passed |
| --- | ---: | ---: | ---: |
| Apostrophe controls | 2 | 7 | 9 |
| Compound controls | 4 | 7 | 11 |
| Final platform controls | 10 | 11 | 21 |

The compiled smoke panel contributes 63 additional case executions across its
three targets. Complete VM/native/JavaScript result objects match, including
source ranges and ordered suggestions. Build logs, executable hashes and source
maps are retained; generated executables, SDKs and compiler caches are omitted.

Strict analysis passed for engine proofing plus the smoke runner, the entire
editor library plus the eight editor proofing files, and optional spaCy `lib`
and `test`. Formatting checked eight changed Dart files with zero changes.
Relevant source hashes remained unchanged during each accepted run and were
rechecked against the delivered source.

### Retained inherited diagnostics

The entire optional spaCy package still produces **nine pre-existing lint
infos** in its W7 developer packaging consumer: eight `avoid_slow_async_io`
notices and one braces notice. Its full-package strict analysis exits 1.
Independent review reproduced the exact same diagnostic log on baseline
`98a2a150`; the consumer blob is unchanged. The library/test analysis above is
a narrower passing scope, not a claim that this inherited CLI is lint-clean.
The sealed consumer was not rewritten to change its prior qualification identity.

### Practical limits

System adapter tests use the actual Flutter service with a mocked native channel.
They do not qualify installed Android/iOS dictionaries, and coordination covers
Quds adapters rather than unrelated host widgets calling Flutter's channel.
Flutter does not provide physical cancellation of the outstanding OS operation.

The German dictionary is still a finite word list. These explicit regressions
and smoke cases do not measure population-level German accuracy or intended-device
latency. Harper/GECToR physical-native suites were excluded from their adapter
cohorts; their external runtime/model binaries were not rebuilt. SpaCy engineering
tests do not rerun its consumed native/model acceptance panels or activate it.

## Reproduction

Resolve the workspace with its pinned Flutter toolchain and dependency lock.
Run package tests from the package directory; the editor directory is required
for its bundled fonts. In a restricted workspace, set `TMPDIR` to a writable
task-owned directory. See archived command receipts for the exact file lists,
environment and compiler paths used here.

```sh
# From the repository root, after dependency resolution:
dart analyze --fatal-infos packages/quds_office_engine/lib/src/proofing \
  packages/quds_office_engine/test/proofing \
  packages/quds_office_engine/tool/check_native_spelling.dart

# From packages/quds_office_engine:
dart test test/proofing --reporter json --concurrency=2

# From packages/quds_office_editor:
flutter test --no-pub --concurrency=2 test/platform_spelling_provider_test.dart \
  test/word_manual_proofing_test.dart test/word_proofing_context_test.dart \
  test/word_proofing_correction_test.dart test/word_proofing_dialog_test.dart \
  test/word_proofing_geometry_test.dart test/word_proofing_navigation_test.dart \
  test/word_proofing_session_test.dart
```

The portable smoke runner is
[`packages/quds_office_engine/tool/check_native_spelling.dart`](../../../packages/quds_office_engine/tool/check_native_spelling.dart).
From the repository root:

```sh
dart run packages/quds_office_engine/tool/check_native_spelling.dart
dart compile exe packages/quds_office_engine/tool/check_native_spelling.dart \
  -o /path/to/output/spelling-smoke
/path/to/output/spelling-smoke
dart compile js -O2 packages/quds_office_engine/tool/check_native_spelling.dart \
  -o /path/to/output/spelling-smoke.js
node -e 'globalThis.self=globalThis;require(process.argv[1]);' \
  /path/to/output/spelling-smoke.js
```

## Saved evidence

[evidence.tar.gz](evidence.tar.gz) retains 133 members with accepted raw test
events, baseline failures, source bindings, compiler outputs, runtime restoration
receipts, source snapshots and earlier attempts. Every member was reread and
verified against [evidence-index.json](evidence-index.json). Earlier unavailable
temporary-directory, concurrent compilation, timer-order and widget-fixture
attempts are preserved separately and are not counted as accepted runs. The
editor's initial root-directory attempt also retains its font-asset setup error.

All newly authored checkpoint commits use `[skip ci]` and non-forced,
expected-head remote updates. No GitHub Actions, workflow, check or status
endpoint was queried, awaited, dispatched or rerun.
