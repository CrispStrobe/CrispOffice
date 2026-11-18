# Native spelling continuation — 18 November 2026

Native spelling now handles words containing discretionary soft hyphens while
preserving exact Word source ranges. German spelling also offers existing
accented dictionary forms for short misspellings and protects marked identifier
prefixes. The qualified product is
`d6a9ca51b16daa9d3d54e163bc723b76659d70ac`.

**1,262 substantive tests pass**, with zero failures or skips. The 33 new tests
are included once. Identical final regression files reproduce 27 behavioral
nonpasses on unchanged integrated main. All 35 portable cases produce
byte-identical complete results on Dart VM, native code and JavaScript/Node.

Work is saved incrementally on
[codex/native-spelling-continuation-20261118](https://github.com/CrispStrobe/quds_office_suite/tree/codex/native-spelling-continuation-20261118).
No GitHub Actions, workflow, check or CI-status endpoint was queried, awaited,
dispatched or rerun.

## Incoming work integrated first

[PR #159](https://github.com/CrispStrobe/quds_office_suite/pull/159) was merged
with expected head `2292548eb69de2dbb5240ab9da59256f362137c6`, producing main
`1e07cb852766f8651815138785be74c64a09ddc0`. That integration includes spelling
PR #157, Zotero tag filters PR #158, native spaCy distribution and explicit
setup, and the retained Office continuation history/evidence. Both incoming
changelog additions and main's accepted common-parent frame implementation
remain. GitHub subsequently reports #157 and #158 as merged too.

Initial reconciliation accounts for **365 fork/upstream branch and PR
references, 235 distinct heads**. All active incoming source at that snapshot
is accounted for. The eleven historical patch-equivalence pairs and three
integration-tree pairs were independently recomputed. All upstream heads and
the previously integrated W7 work are contained. AOT/RML remains removed;
manual spaCy grammar remains an explicit, default-off option.

The final source cutoff, **13:16:57 CET / 12:16:57 UTC**, contains 366 references
and 239 heads. Three branches advanced after initial integration:

| Branch | Captured head | State at cutoff |
| --- | --- | --- |
| `codex/document-review-20261118` | `b0044f5a04ba71e58468a7a22297b56f926e4d39` | Checkpoint explicitly says dialog/comparison qualification continues. |
| `codex/zotero-workspace-20261118` | `b292ee94f8792df19e3758a2a271d40230e638ca` | Engine qualification recorded; complete editor/Studio qualification is not recorded at that head. |
| `integrate/native-spacy-distribution-20261118` | `8cd413c1e0454278abd703264bdda589a90f2d48` | New NER continuation after merged #159; no new qualification receipt or offered NER model yet. |

Their objects were fetched and inspected. They had no open PR at observation,
change neither spelling implementation, and are **not included in this qualified
spelling tree**. Already-contained stacked draft #153 remained open.
[Reconciliation](reconciliation.md), [initial refs](refs.json), and
[final frontier](final-frontier.json) preserve decisions, exact heads, timestamps
and validation provenance. The full final inventory is archived as
`integration/final-frontier.json`.

## User-visible changes

### Native checking across discretionary hyphens

`OfficePlatformSpellingProvider` omits only U+00AD from the text sent to
Flutter's native spelling service. It keeps a per-request UTF-16 map to the
unchanged original text. For example, `🙂 a\u00adlot.` reaches the checker as
`🙂 alot.`, while the finding owns original interval `(3, 8)` and original
text `a\u00adlot`.

Choosing `a lot` replaces exactly that original word. Undo restores its authored
soft hyphen; redo restores the correction. Leading/trailing controls outside
the word remain outside the edit. Checking alone never rewrites the document.

The adapter also:

- Requires complete graphemes in both checked and original text, including
  combining marks, emoji and regional-indicator pairs that regroup after a
  control is omitted.
- Protects URL, email and backtick spans in both representations. Projected
  digit/connector edges protect identifiers even when soft hyphens separated
  source characters.
- Filters suggestions that merely move/remove soft hyphens. Existing native
  order, eight displayed choices, 64 inspected candidates and 256-unit
  replacement bounds remain.
- Completes empty projected input without using the native lane, after disposal,
  availability and exact-locale checks.
- Preserves shared-channel serialization, deadlines, disposal and cache clearing.
  Equal projected texts retain independent original source maps.

Word review tests use Flutter's actual `DefaultSpellCheckService` with controlled
native-channel responses. They cover exact corrections, undo/redo, unchanged
documents during checks, and personal words across reopened documents, owners
and languages.

### Short accented German suggestions

The finite shipped dictionary already contains these accented forms. The new
index fallback makes them reachable for short misspellings outside the
direct-edit alphabet:

| Input | Before | After |
| --- | --- | --- |
| `Cafè` | `Cafe` | `Cafe`, `Café` |
| `Joêl` | No suggestions | `Joël` |
| `rosè` | No suggestions | `rosé` first, followed by dictionary alternatives |
| `CAFÈ` | `CAFE` | `CAFE`, `CAFÉ` |
| `Caf` | `Cafe` | `Cafe`, `Café` |

For three- and four-unit normalized words, the fallback permits only one edit,
retains the shared candidate budget and checks exact locale-specific dictionary
membership. Direct corrections remain first. At equal edit distance and length,
the new short fallback prefers matching lexical case. Longer-word ranking is
unchanged. Decomposed accents, uppercase and explicit hyphen compounds are
covered; no dictionary data or dependencies are added.

### Marked German identifiers

German spelling computes numeric and connector edges in its existing grapheme
pass. Digits or underscores followed by combining marks no longer expose a
trailing `Huas` inside an identifier to a partial `Haus` correction.
Supplementary digits and long marked clusters are covered. Separate prose,
marked punctuation and ordinary explicit hyphen compounds remain checkable.

## Local validation

| Final cohort | Files | Substantive passed | Failed | Skipped |
| --- | ---: | ---: | ---: | ---: |
| Engine proofing | 29 | 1,095 | 0 | 0 |
| Editor proofing | 11 | 167 | 0 | 0 |
| **Disjoint total** | **40** | **1,262** | **0** | **0** |

Hidden loading events are excluded. Focused runs and baseline controls are not
added to the total. Before implementation, unchanged source also passed the
1,078 pre-existing engine tests and 32 native editor tests.

### Identical final tests on unchanged main

An isolated Git archive of `1e07cb85` received only the four final test files
and the identical lock. Its 581 baseline library/manifest files match Git,
all final test bytes match delivery, and offline resolution reproduces the
110-package graph. All guarded inputs remain unchanged during execution.

| Baseline control | Cases | Passes | Behavioral nonpasses |
| --- | ---: | ---: | ---: |
| German continuation | 17 | 4 | 13 |
| Native projection | 10 | 0 | 10 |
| Native review guards | 4 | 2 | 2 |
| Native Word dialog | 4 | 2 | 2 |
| **Total** | **35** | **8** | **27** |

The 35 cases include 33 new tests and two existing dialog controls. All suites
compile/load. Cardinality errors reflect extra/missing findings, not compiler
or harness failures. Raw failure/error labels and the classification of each
nonpass are preserved in `baseline/final-controls/`. All final controls pass
after repair.

### Portability, static checks and source binding

The exact 35-case `tool/check_native_spelling.dart` runner passes under Dart VM,
a `dart compile exe` executable, and JavaScript compiled with `dart compile js
-O2` and executed by Node. Each complete output is 7,576 bytes with SHA-256
`1612397211d8ea5751e5a0502bbddd32a7ad815d59b860adf1a32e88e006ee5b`.
Both compilers and all executions exit zero. All 650 source/dependency inputs
and 504 runtime/SDK inputs remain unchanged. The before-run bindings cover all
756 compiler-reported dependencies.

Strict `dart analyze --fatal-infos` passes for changed engine source/test/tool,
the full editor library and each of the eleven selected editor tests.
All seven changed Dart files format without changes. Working and committed
whitespace checks pass.

The initial `flutter analyze` wrapper stopped before analysis because the
authenticated extraction omitted SDK `dev/`. Its failed preflight receipt is
preserved. Equivalent strict analysis then completed through the genuine
bundled Dart analyzer with unchanged Flutter package configuration. The SDK
was not altered and tests were not rerun.

Runtime: **Flutter 3.47.8, Dart 3.13.7, Node 24.22.3**. The complete
1,581,444,364-byte official Flutter archive was verified against SHA-256
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2` before use.
All 162 pinned hosted archives were verified. Offline resolution retained the
110-package graph and original lock hash.

All **535 distinct tracked workspace inputs** used by engine, editor and
portable checks match the qualified product. Three ignored dependency
configuration files are bound separately. The editor's full 5,527-input guard
also covers restored dependencies and actual runtime files.

## Evidence and reproduction

[verification.json](verification.json) is the concise machine-readable result.
[evidence.tar.xz](evidence.tar.xz) preserves **196 exact evidence files**, indexed
by size and SHA-256 in [evidence-index.json](evidence-index.json). All members
were read back and verified after packing. Contents include:

- Runtime restoration, pinned dependency receipts and original baselines.
- Final raw test events, commands, source/dependency/runtime bindings.
- Isolated final-test baseline control and failure classification.
- Complete VM/native/JavaScript outputs and compiler dependency coverage.
- Development attempts, the first lowercase-shortlist failure, analyzer
  preflight and the prior portable run with its SDK-binding refinement.
- Reference inventories, equivalence proofs and independent reviews.

Compiled executables and generated JavaScript remain reproducible scratch
outputs; their hashes are recorded. The source smoke runner is committed.
Earlier attempts do not add to final test totals.

With the pinned toolchain and resolved workspace, principal commands are:

~~~sh
cd packages/quds_office_engine
dart test test/proofing --reporter=json
dart analyze --fatal-infos lib/src/proofing/german_spelling.dart \
  test/proofing/german_spelling_continuation_test.dart \
  tool/check_native_spelling.dart
dart run tool/check_native_spelling.dart
~~~

~~~sh
cd packages/quds_office_editor
flutter test --no-pub --reporter json --concurrency=2 \
  test/platform_spelling_provider_test.dart \
  test/platform_spelling_projection_test.dart \
  test/platform_spelling_projection_review_test.dart \
  test/platform_spelling_dialog_test.dart \
  test/word_manual_proofing_test.dart \
  test/word_proofing_context_test.dart \
  test/word_proofing_correction_test.dart \
  test/word_proofing_dialog_test.dart \
  test/word_proofing_geometry_test.dart \
  test/word_proofing_navigation_test.dart \
  test/word_proofing_session_test.dart
dart analyze --fatal-infos lib
~~~

Exact compiler, Node and individual analyzer commands are archived.
Orchestration scripts retain original session paths; retarget workspace/output
paths when replaying elsewhere.

## Remote checkpoints and limits

| Checkpoint | Saved work |
| --- | --- |
| `2292548e` → `1e07cb85` | New remote branch, then integrated main merge. |
| `4b7a0798` | Native projection, Word regressions and initial reconciliation. |
| `d6a9ca51` | German shortlists/identifier guards, review tests and portable panel. |
| This evidence commit | Final validation, independent review and concurrent frontier. |

Writes use non-forced expected-head updates and `[skip ci]`.
[Independent review](review.md) covers mapping, protections, graphemes,
cache/ownership and Word interaction; a second review added independent
boundary/no-op/availability controls.

These finite authored cases do not estimate general spelling precision/recall.
Controlled mobile responses do not establish installed Android/iOS dictionary
quality or target-device latency. JavaScript was exercised in Node, not a browser.
No full application build or new spaCy/model acceptance is claimed. Sealed model
panels and default activation remain unchanged.
