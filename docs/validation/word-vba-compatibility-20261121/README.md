# Word VBA header/footer continuation — 21 November 2026

Work branch: `codex/word-vba-compatibility-20261121`.

This increment extends the bounded Word source compiler to paragraphs in
existing, independently owned headers and footers. All six primary, first-page
and even-page variants are supported. The source contract, examples and precise
exclusions are in [VBA_WORD_MACROS.md](../../VBA_WORD_MACROS.md#existing-header-and-footer-paragraphs).

## Implemented behavior

- `Section.Headers` / `Section.Footers`, their indexed and `.Item` forms, and the
  three `wdHeaderFooter*` constants select an explicit story in an existing section.
- Typed `HeadersFooters`, `HeaderFooter`, `Paragraph` and `Range` aliases work
  with required `ByVal` helpers, named helper calls and nested `With` blocks.
- `HeaderFooter.Range.Paragraphs(i).Range` supports the existing paragraph text
  insertion, font/highlight, paragraph formatting, spacing and tab-stop operations.
  The complete paragraph, section and story identity is retained in native plans.
- A native pre-edit guard rejects source/model ownership mismatches, shared
  mutable models, linked/shared story topology and content the current serializer
  cannot faithfully preserve. The macro runtime's detached transaction protects
  earlier operations, document bytes, revision and recording on a refusal.
- The committed [BAS example](../../../packages/quds_office_engine/example/macros/word_headers_footers.bas)
  selects all six story variants. Its fixture requires at least two independent
  sections with every variant present and at least two paragraphs in each story.

This remains a source-to-native-plan dialect, not a complete Word VBA runtime.
Whole-story writes, document reads, collection enumeration, page-number objects,
story creation, `Exists`, `LinkToPrevious` and nonbody list operations are outside
this increment. Embedded VBA projects remain inert.

## Incoming history and remote checkpoints

The [initial intake](intake.md), [snapshot](intake.json) and final
[reconciliation](reconciliation.md) / [machine-readable proofs](reconciliation.json)
account for the captured work without reapplying superseded historical branches.
Baseline main was `e2abbcda6d19f932bfbacc85e0dafd41a3c478f8`; there were no open
fork PRs at that initial capture.

| Captured population | Ancestors | Historical equivalents | Uncovered |
| --- | ---: | ---: | ---: |
| Initial 46 fork branch heads | 36 | 10 | 0 |
| Initial 100 recent PR heads | 98 | 2 | 0 |
| Initial 4 upstream branch heads | 4 | 0 | 0 |
| Initial 4 upstream PR heads | 4 | 0 | 0 |
| Later complete capture of 288 PR heads | 274 | 14 | 0 |
| Complete external snapshot of 338 references | 314 | 24 | 0 |

These populations overlap. Fifteen historical mappings were independently
recomputed: thirteen full-tree proofs and two changed-path proofs. The snapshot's
additional checkpoint is also retained by ancestry.

Work arriving during implementation was merged with its original ancestry:
Zotero table-cell replacement (`a6095c304`), durable Mail synchronization
(`278fa78d5`), saved-message Close correction (`9cfad3920`) and App Store
screenshots (`e8d23a3a7`). Their earlier checkpoints and original parents are
retained. The fixed combined application source is
`75f694d5e42049f356ba52b26329d199bfb7c2aa`.

Main subsequently advanced through PRs #290 and #291 to `4a1eaa69e7a068e354bdd851ec9b0323b89ae300`.
That main was merged into the work branch at
`fc9896f92710e01ab6c694eab93fefbc5e47efdc`. The additional 53 paths are exclusively
documentation/evidence: [main-reconciliation.json](main-reconciliation.json)
proves identical application trees, root dependency specifications and feature
source hashes. Earlier Word feature checkpoints had already reached main through
the Mail merge; this branch retains the later guard fixes and complete evidence.

Implementation and incoming merges were saved repeatedly to the remote branch
using non-forced, expected-head updates. No GitHub Actions runs, jobs, checks or
statuses are queried or awaited as an acceptance gate.

## Local qualification

All local acceptance gates passed. [qualification-summary.json](qualification-summary.json)
connects the cohort receipts, source applicability and archive identities. The
archives contain raw events, exact commands, result receipts, source manifests
and independent review notes; they omit SDKs, caches and generated JavaScript.

| Completed cohort | Visible passes | Qualification |
| --- | ---: | --- |
| Broad source-compiler regression, 36 files | 3,159 | Includes the 94 new header/footer source cases; compiler sources, selected tests, fixtures and operation catalog unchanged |
| Final native/integration/CLI regression, 46 files | 1,167 | Includes 72 new native guard cases and 15 header/footer integration cases; all 3,054 captured tracked inputs unchanged |
| Mail core, complete suite | 271 | Real Dart, 34 unchanged captured inputs; in-memory runner/provider fixtures |
| Incoming Zotero engine/protocol, 27 files | 884 | Includes 62 new table-cell cases; all 558 captured inputs unchanged |
| Incoming Flutter/SQLite local hosts | 991 | Complete store VM/Node coverage plus focused Mail and Zotero controller paths; all 6,076 present tracked inputs unchanged |
| Independent guard review | 7 probes | Every final adversarial case refused atomically; exact source hashes recorded |

The compiler run observed native dispatch edits and an added native guard while
it ran. Its archive records all changed paths and confirms an unchanged operation
catalog. It qualifies compiler behavior only; it does not claim a frozen native
runtime. The final native gate is separate. The seven independent review probes
are not added to test-suite totals. Earlier development findings in the guard
archive are explicitly labeled and are not passing evidence.

[final-native-index.json](evidence/final-native-index.json) and
[final-native.tar.gz](evidence/final-native.tar.gz) record the fixed-source native
gate. All 1,167 tests passed with no failures, skips or error events. Full engine
and Mail-core analysis passed with fatal infos; all seven changed feature Dart
files passed the format check without modification. Every command's 3,054
captured tracked inputs remained unchanged.

The actual committed BAS compiled to 11 operations addressing all six variants.
The VM and compiled-JavaScript receipts are byte-identical, SHA-256
`98a58a09cf92aa3982373fd6adc2f1d61c7836f2dc6fadfe5604edf7ae2a5c2f`.
They verify first and repeated execution, two additional reopens, untouched body
text, opaque payload preservation, and validation/run rollback with unchanged
recording. The final native archive also contains the exact runtime package
configuration captured after the gate and the executed commands.

The three new feature suites contribute **181 focused cases**: 94 compiler,
72 native and 15 integration. Those cases are already included in the broad
cohorts above. Counts are reported by cohort, not added into an inflated unique
grand total. The earlier compiler/Mail/Zotero/review archive identities remain
in [completed-index.json](evidence/completed-index.json).

### Incoming Flutter and SQLite qualification

[incoming-flutter-index.json](evidence/incoming-flutter-index.json) and
[incoming-flutter.tar.gz](evidence/incoming-flutter.tar.gz) preserve the separate
local application qualification. All selected tests passed without failures or
skips, and all three analysis commands passed with fatal infos/warnings.

| Cohort | Passes |
| --- | ---: |
| Mail store: all 34 VM/native test files | 825 |
| Mail store: the remaining Node-only test file | 3 |
| Four incoming Studio synchronization suites | 36 |
| Saved-mail suite | 14 |
| Connected saved-message navigation case | 1 |
| Independent whole-dialog Close probe, English/German/Arabic | 3 |
| Zotero multi-paragraph controller suite | 109 |
| Total for this separate qualification | 991 |

The store's entire 35-file test set is covered across VM and Node. Native tests
use the actual SQLite hook/library, including transaction and child-process
crash recovery; a separate FTS5 create/insert/query probe also passed. The Close
probe checks the whole dialog, avoiding the child-scoped finder that would miss
the duplicated toolbar button. Its source is included as an independent probe,
not inserted into the application checkout. The selected application worktree
and captured runtime hashes stayed unchanged throughout both runs.

### Environment and replay

The engine gates use genuine Dart **3.14.1**, official archive SHA-256
`759bed01e0aeb50e1a0b0a19474ba5c80c6087ce1d37b3214e475c81a44430e8`.
All 56 hosted versions and their downloaded archive hashes match the repository
lockfile. [runtime-environment.json](runtime-environment.json) and
[runtime-verification.json](runtime-verification.json) record the pins and actual
source-package roots. The initial two-suite, 97-test section baseline preceded
this feature and is not counted as final acceptance.

The incoming application gate independently uses genuine **Flutter 3.47.8** and
its embedded **Dart 3.13.7**, with 202 unique hosted archives verified against
the actual lockfile. The full official Flutter archive SHA-256 is
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
Offline enforced-lockfile resolution succeeded; ordinary assets and native hooks
remained enabled. SQLite 3.54.1 loaded from binary SHA-256
`0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b`.
The Node-only store test used Node 24.22.3 and real Dart JavaScript compilation.

Run from a fresh checkout with Python 3 and Node available. Use a fresh output
directory for each invocation:

```sh
python3 docs/validation/word-vba-compatibility-20261121/reproduce.py \
  --repo "$PWD" --runtime /tmp/quds-word-vba-runtime \
  --output /tmp/quds-word-vba-final --bootstrap --cohort final \
  --node "$(command -v node)"

python3 docs/validation/word-vba-compatibility-20261121/reproduce.py \
  --repo "$PWD" --runtime /tmp/quds-word-vba-runtime \
  --output /tmp/quds-word-vba-compiler --cohort compiler

python3 docs/validation/word-vba-compatibility-20261121/reproduce.py \
  --repo "$PWD" --runtime /tmp/quds-word-vba-runtime \
  --output /tmp/quds-word-vba-mail --cohort mail
```

The replay driver rejects failures, skipped tests, missing completion events and
changed tracked source inputs. `--cohort feature` runs the three new feature
suites; `--cohort native` runs the final native/CLI selection without repeating
analysis and portable checks. The Zotero archive includes its exact 27-file
selection and execution driver. Captured absolute workspace paths describe the
original run; adapt those roots when replaying an archived helper.
The Flutter archive includes its executed original qualifiers, setup scripts and
replay notes. Its consolidated `replay_setup.sh` was added after execution and
syntax-checked; it is not represented as an already executed end-to-end replay.

## Practical limits

Editable source stories contain native paragraph/run text, tabs and supported
breaks, with native preservation of paragraph/run property fragments. The guard
refuses fields, hyperlinks, graphics, structural wrappers, unpreserved attributes,
foreign structural lookalikes and ambiguous markup-compatibility projection in
any modeled story that saving regenerates. Unsupported content in an unselected
modeled header/footer can therefore block a selected edit. Independent opaque
parts can be preserved, but cannot themselves be selected.

Shared or inherited header/footer topology anywhere in the document is refused
because the current serializer rewrites all story parts. Dormant first/even
stories may be edited without enabling their display settings. Saving does not
promise byte-identical regenerated XML or stable generated story-part names.
The guard sees normalized OPC relationships; it cannot prove the authenticity
of raw `.rels` XML namespaces already discarded by the existing parser.

No installed Microsoft Word differential run, embedded-project execution, live
Zotero session or live Mail account is claimed. Incoming Flutter fixtures qualify
their selected local application paths, not every UI surface or provider host.
