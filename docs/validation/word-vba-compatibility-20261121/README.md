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

The completed evidence index is [evidence/completed-index.json](evidence/completed-index.json).
The archives contain raw events, exact commands, result receipts, source manifests
and independent review notes; they omit SDKs, caches and generated JavaScript.

| Completed cohort | Visible passes | Qualification |
| --- | ---: | --- |
| Broad source-compiler regression, 36 files | 3,159 | Includes the 94 new header/footer source cases; compiler sources, selected tests, fixtures and operation catalog unchanged |
| Mail core, complete suite | 271 | Real Dart, 34 unchanged captured inputs; in-memory runner/provider fixtures |
| Incoming Zotero engine/protocol, 27 files | 884 | Includes 62 new table-cell cases; all 558 captured inputs unchanged |
| Independent guard review | 7 probes | Every final adversarial case refused atomically; exact source hashes recorded |

The compiler run observed native dispatch edits and an added native guard while
it ran. Its archive records all changed paths and confirms an unchanged operation
catalog. It qualifies compiler behavior only; it does not claim a frozen native
runtime. The final native gate is separate. The seven independent review probes
are not added to test-suite totals. Earlier development findings in the guard
archive are explicitly labeled and are not passing evidence.

The final 46-file native/integration/CLI gate, strict analysis, formatting and
VM/JavaScript parity replay are running against the fixed application source.
Independent Flutter/SQLite incoming gates are also in progress. Their final
receipts will be added before the requested main merge.

### Environment and replay

The engine gates use genuine Dart **3.14.1**, official archive SHA-256
`759bed01e0aeb50e1a0b0a19474ba5c80c6087ce1d37b3214e475c81a44430e8`.
All 56 hosted versions and their downloaded archive hashes match the repository
lockfile. [runtime-environment.json](runtime-environment.json) and
[runtime-verification.json](runtime-verification.json) record the pins and actual
source-package roots. The initial two-suite, 97-test section baseline preceded
this feature and is not counted as final acceptance.

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
