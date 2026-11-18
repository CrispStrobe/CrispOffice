# Offline thesaurus — reconciled continuation, 18 November 2026

This is the historical 606-case qualification. The later
[acceptance continuation](../acceptance/README.md) records the next captured
review/Mail integration, browser build/cache corrections and fresh checks.

The thesaurus branch now contains the observed current main and the latest
document-review/Zotero work. Incremental remote checkpoints preserve the work.
GitHub Actions, check-run and CI-status endpoints are not queried or awaited.

**Completed local result:** 606 targeted cases passed: 591 Dart/Flutter cases
across 37 distinct suites and 15 Python cases. Strict analysis and formatting of
58 selected Dart files, release web compilation, the JavaScript import check,
full-pack verification and deterministic regeneration also passed. All seven
new regression cases executed successfully. Actual offline-browser, installed
desktop and independent human linguistic acceptance remain open release checks.

The application source was frozen at
`af4971352fa14247e2de7be8c9b5733921e2ff30`. Subsequent commits preserve evidence
and documentation. [validation-summary.json](validation-summary.json) records
the counts and scope; [peer-audit.json](peer-audit.json) independently checks
the raw events, hashes, source inventories and execution-workspace files.

## Incoming work

[incoming-audit.json](incoming-audit.json) inventories all 207 fork branches,
169 PR heads and four upstream branches observed before feature work: 380 refs
and 247 distinct heads. Of those, 344 refs were ancestors of the supplied
`315beeb3` checkpoint, seven arrive through current document review, one through
current main, and 28 refs represent 14 historical equivalent heads. There are
zero unexplained refs.

- Main `4fbc8741f314af67592517595c760ba3036dedba` adds the shared Mail and
  standalone Office scope. Its new roadmap section is preserved alongside the
  implemented thesaurus section.
- Document review `eedf2aee03964329a2e4c7ee3c771d43b5df4991` adds 30 commits
  relative to the supplied thesaurus checkpoint, including the newer inline
  comment, text-language inheritance, keyboard review and Zotero work.
  PR #168 head `6c993f7406037ba462c6aea32e7e6afeebd28c03` and PR #167 head
  `a40a26663f7a2c6b7fb8de91540fd04b9875ed9c` are included. PRs #164 and #165
  were already contained and were not reapplied.
- All four upstream heads are already ancestors of `315beeb3`.
- Historical equivalence was checked again: ten patch-equivalence proofs,
  three identical-tree/ancestry proofs and 37 identical files for PR #140.

The integration preserves both sides of the five source conflicts and the
automatically merged Studio entry points. The engine retains its compressed
pack verification and 64-shard bound. The editor retains the guarded thesaurus
capture/replacement contract plus the incoming language and review controls.

### Final captured incoming work

A final bounded inventory, before source freeze, observed **210 fork branches,
170 PR heads and four upstream branches: 384 refs and 250 distinct heads**.
[incoming-final-frontier.json](incoming-final-frontier.json) records every ref,
new commit and disposition. No independent source change in this captured
inventory remains unexplained. Publications after that inventory are outside
this report's scope.

- Review head `b5d4df516db210a6f8ea566b290988dab5652630` contributes two
  evidence-only commits. Its author's 633-case result is retained as incoming
  evidence and is not added to this continuation's fresh test count.
- Zotero head `a4915a555f70919fc7c6cfae3eb31764195593b7`, also the captured
  draft PR #170 head, adds native citation insertion inside existing anchored
  notes. Its engine implementation and regressions are included. This is not a
  claim that Notes-pane/ribbon routing or live Zotero acceptance is complete.
- spaCy head `9a90262da555705758fa233f7d4e339ff453a0dc` includes those heads and
  the EN/FR analysis changes in `03f06f121db493010954e70234d1cd78477f0576`.
  The merge retains the stricter thesaurus modifier checks, Review-pane binding,
  bounded status layout and composition refusal. EN/FR analysis means local
  annotations/entities, not added grammar rules or thesaurus languages. The
  selected tests do not establish real model-download/runtime or Windows
  acceptance.
- Mail head `0e07d24714e6261123fcb835c36a592d6827982d` contains alternative
  baseline merge resolutions and no independent Mail application feature.
  Those resolutions were inspected rather than reapplied over the newer fixes.

No dependency manifest or runtime pin changed in this final integration.
[PR feedback](incoming-final-pr-feedback.json) and
[the captured PR #170 metadata](incoming-final-pr170.json) preserve the review
context without querying GitHub Actions or check-run status.

## Corrections after integration

### Keyboard and narrow review chrome

Shift+F7 is available from the document and the Review pane. The pane owns a
separate focus subtree, so its shortcut must be registered there explicitly.
Alt+F7 and Alt+Shift+F7 keep their forward/backward writing-finding behavior;
the covered-modal guard remains in place. Plain F7 retains writing review.

The status bar retains its language control and thesaurus action. The Changes
label has a bounded width and ellipsis, with the full count in its tooltip.
Three added integration cases exercise English and Arabic RTL at 390 pixels
and 1.5x text, both thesaurus buttons, selected-text language/undo, keyboard
navigation and modal separation.

### Active composition refusal

Previously, an invalid composing capture still opened an error dialog. Closing
that modal restored document focus, reattached the input bridge and could clear
the composing range. The dialog helper now checks captured and current live
composition before creating a route. The host returns before modal focus
restoration on this refusal path. A Scaffold host shows a non-focus-taking
notice; a host without a Scaffold returns without opening a dialog.

Three added widget cases cover Shift+F7, an earlier ready capture followed by
composition, and a host without a Scaffold. They assert unchanged input value,
composing range, attachment, focus, selection, content revision and undo state,
with no lexical asset reads. A controller case checks that the incoming text
language control and its undo retire earlier lookups; a fresh lookup is required.
These cases do not constitute installed OS/IME acceptance.

## Stronger offline browser replay

The old browser script disabled network without restarting the already loaded
application. It could also close Sources before the verified notices arrived,
and it tried to locate an English alternative before its lazy list row existed.
The revised fixture now requires all of the following before reporting success:

1. Verify the size and SHA-256 of every compiled file while installing its
   test-only offline cache, then verify the cache identity and complete inventory.
2. Disable browser network, stop the actual HTTP origin and confirm its
   listening socket is unreachable.
3. Reload offline into a new fixture session with empty provider caches.
4. Scroll real dialog content to the requested alternative; perform explicit
   English and German replacement, one-step undo and redo.
5. Wait for verified source notice titles and rendered attribution. Compare
   every notice returned by the query panel with the compiled pack bytes.
6. Run the complete 15-query panel again in a fresh offline tab and retain
   requests, CSP violations, page errors, cache counts and timing observations.

The worker is acceptance infrastructure. It does not add or qualify the
production application's install/update mechanism. Browser fixture source
hashes alone do not prove which source compiled `main.dart.js`: retain the
successful compile receipt and build inventory with the later browser receipt.

Both runners refuse to overwrite an existing receipt. The native runner now
requires exactly the selected suites, a complete successful event stream,
nonzero substantive passes, no skipped/failed cases, and no layout/tap
diagnostics. It records browser execution as `not_run` until the separate
browser runner actually executes.

## Fresh completed checks

| Counted cohort | Passed cases | Suites | Evidence |
| --- | ---: | ---: | --- |
| Thesaurus and merged review integration, native headless | 208 | 14 | [Receipt](native/receipt.json), [event audit](native/native-test-audit.json) |
| Engine, provider, language inheritance and Zotero notes | 171 | 8 | [Receipt](checks/engine/receipt.json), [event audit](checks/engine/test-audit.json) |
| Editor Zotero and notes | 51 | 4 | [Receipt](checks/editor-zotero/receipt.json), [event audit](checks/editor-zotero/test-audit.json) |
| spaCy contracts | 67 | 6 | [Receipt](checks/spacy/receipt.json), [event audit](checks/spacy/test-audit.json) |
| Studio review, analysis, setup and Zotero transport | 94 | 5 | [Receipt](checks/studio/receipt.json), [event audit](checks/studio/test-audit.json) |
| Python compiler/parser controls | 5 | — | [Raw log](compiler-tests.log) |
| Python browser-harness controls | 10 | — | [Raw log](harness-controls.log) |
| **Total** | **606** | **37 Dart/Flutter suites** | **Zero failed or skipped cases** |

The 208-case native cohort includes dialog (21), controller (52), existing
correction/capture/context (42), Review pane (11), new integration (3), incoming
keyboard review (31), text-proofing controls/pane (44), one real-pack panel and
three visual cases. The panel contains 15 queries but counts as one test.

All selected suites ran, every started case finished exactly once and each
machine-event stream ended successfully. Lifecycle/loading events are excluded
from case counts. There were no recorded layout/tap diagnostics or event-parser
errors. The independent audit reconstructs these results from the raw logs,
not just the runners' summary fields.

| Other check | Result | Evidence |
| --- | --- | --- |
| Dart formatting and strict analysis | 58 selected targets; zero formatting changes; analysis with fatal infos passed | [Receipt](checks/static/receipt.json), [target list](dart-final-targets.json) |
| Complete installed-pack verification | All 1,037 files, hashes, source identities, memberships and bounded lexical checks passed | [Receipt](pack-verification.json), [log](pack-verification.log) |
| Isolated deterministic rebuild | All 1,037 files and generated Dart constants byte-identical | [Full file hashes](pack-rebuild.json), [log](pack-rebuild.log) |
| Release web fixture | Compilation passed with CSP and no web-resources CDN; 1,155 files, 87,384,043 bytes | [Receipt](native/receipt.json), [compiled inventory](native/browser-build-files.json.gz) |
| Test-only offline installation | Inventory and installation recorded; adds the worker bootstrap and changes index.html | [Installation](native/offline-installation.json), [1,156-file installed inventory](browser-attempt/installed-build-files.json.gz) |
| Studio spaCy web import | Dart-to-JavaScript compilation and Node execution passed; native capability reported unavailable | [Receipt](checks/web-import/receipt.json) |
| Source binding | 2,825 native and 3,308 supplemental inventoried inputs match; all 3,292 package/application files in the execution workspace match the checkout | [Independent audit](peer-audit.json) |

The release build retains its wider-library missing `CupertinoIcons` font
notice in [stdout](native/browser-build.stdout.gz); the thesaurus uses Material
icons. An earlier analysis attempt included the documentation fixture under the
root package and reported three dependency-declaration infos. The final 58-file
analysis targets actual product packages; the fixture separately compiled in
the resolved Flutter example workspace. The initial attempt is retained in
[analysis-initial.json](analysis-initial.json), with no analyzer suppression or
product dependency-manifest change.

The harness controls execute generated worker JavaScript in Node with mocked
cache/fetch APIs, test real local HTTP serving/shutdown, and reject corrupted
inventories, missing notices, changed panels and invalid cache/timing receipts.
They are not actual-browser or Flutter execution.

The unchanged packs contain 107,519 English and 50,264 German meaning groups.
The old 155-case native/provider result remains tied to its historical source
at `315beeb3`; it is not counted as a fresh pass for this merged checkpoint.

The three saved headless renders are
[English desktop](native/visuals/english-desktop.png),
[German desktop](native/visuals/german-desktop.png) and
[German narrow layout with large text](native/visuals/german-narrow-large-text.png).
They do not represent an installed desktop or browser session.

### Evidence storage and source binding

[checks/evidence.tar.gz](checks/evidence.tar.gz) contains the complete six
supplemental output directories: receipts, raw logs, before/after source
inventories and compiled import artifacts. [checks/index.json](checks/index.json)
provides the archive hash and every member's original byte hash; all members
were read back and verified after packaging. See [checks/README.md](checks/README.md)
for extraction and log mapping. Compact receipts and event audits are also
available as ordinary JSON beside the archive.

The native source inventory and raw logs are stored under `native/`; compressed
logs preserve the exact uncompressed bytes named in the original receipts.
`native/test-receipt.json` is the earlier tests-only checkpoint, while
`native/receipt.json` is the completed native-plus-web-build receipt. The later
browser attempt has its own receipt, so the build runner's `browser_not_run`
status is not mistaken for a successful browser result.

The native tests/build ran against source `af497135`; supplemental checks ran
at `b9e8c159`, whose changes since that freeze are documentation/evidence only.
Before/after inventories stayed equal. The independent audit also compares the
recorded inputs to the current checkout and separate execution workspace.
Its original read-only [audit script](audit_final_validation_receipts.py) is
retained with the recorded task-root paths; it never executes tests.

## Runtime and remaining checks

[environment.json](environment.json) records the fresh prerequisite probes.
Flutter/Dart were absent initially. The official pinned SDK was subsequently
restored and all completed checks above used **Flutter 3.47.8 / Dart 3.13.7**.
The 1,581,444,364-byte official archive matches SHA-256
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
The recovery also verified 162 hosted dependency archives, both offline enforced
lock resolutions and all 11 workspace manifests. SDK tracked files remained
unchanged. [runtime/runtime-ready.json](runtime/runtime-ready.json),
[the recovery archive](runtime/setup.tar.gz) and [its index](runtime/index.json)
retain provenance; the setup receipt's zero product-test count describes setup
only, before the separately recorded validation runs.

Actual Chromium startup fails before the application runs: creation of a Unix
socket is denied (`EPERM`). The attempt against this compiled and installed
fixture is preserved in [browser-report.json](browser-attempt/browser-report.json)
and [the launcher log](browser-attempt/launcher.log.gz): **zero browser steps
completed and zero requests were recorded**. Linux packaging also lacks clang,
CMake, Ninja and GTK development metadata.

The three open release checks are:

- Actual offline-browser acceptance, including origin shutdown, a fresh offline
  session, replacement/undo/redo, source notices, CSP and performance.
- Installed native desktop packaging and acceptance, including real OS/IME
  behavior. Headless Flutter tests cannot establish this.
- Independent human linguistic review. Source-identified query results and
  deterministic corpus checks cannot establish lexical appropriateness.

These remain unchecked in draft PR #169. No source corpus, thesaurus language
coverage, grammatical agreement or reinflection claim was expanded. Alternatives
remain literal source terms without automatic contextual sense selection.

## Replay

Restore the pinned runtime with the historical
[SDK recovery recipe](../../zotero-citation-workflow-20261118/runtime/README.md).
The current [runtime/setup.tar.gz](runtime/setup.tar.gz) contains this
continuation's 24-member recovery evidence and scripts. If replaying it elsewhere,
replace its recorded task-root path `/workspace/scratch/a686c23de6c7` in `env.sh`
and `restore_flutter.py`; the historical recipe uses an older task-root path.
Keep the checkout, `zotero-toolchain` and `zotero-validation` as siblings below
the chosen task root; source paths in the validation workspace remain live links.
Run from that task root with new output directories:

```bash
source zotero-toolchain/env.sh
python quds_office_suite/docs/validation/thesaurus-20261118/continuation/local/fixtures/run_final_validation.py \
  --root "$PWD" --output "$PWD/thesaurus-resume-validation"
for cohort in static engine editor-zotero spacy studio web-import; do
  python quds_office_suite/docs/validation/thesaurus-20261118/resume/run_selected.py \
    --root "$PWD" --cohort "$cohort" \
    --output "$PWD/thesaurus-supplemental-replay/$cohort" || exit
done
python quds_office_suite/docs/validation/thesaurus-20261118/continuation/local/fixtures/install_offline.py \
  thesaurus-resume-validation/browser-build \
  --compile-receipt thesaurus-resume-validation/receipt.json
python quds_office_suite/docs/validation/thesaurus-20261118/continuation/local/fixtures/run_browser.py \
  thesaurus-resume-validation/browser-build \
  --compile-receipt thesaurus-resume-validation/receipt.json \
  --output thesaurus-browser-acceptance
```

The runner selects the original thesaurus/controller/correction/review suites,
the new integration cases, three incoming keyboard-review suites, two incoming
text-proofing suites, and the real-pack/visual fixtures. Tests and supplemental
cohorts run serially. The default web build destination is `<output>/browser-build`;
`--browser-build-output` optionally chooses another empty directory.
The browser step needs a host that permits Chromium startup; pass
`--browser-executable` when its binary is elsewhere. Its output must be outside
the compiled build and contain no existing browser receipt.
The current fixture also requires a fresh compile with its exact source/build
binding and `--pwa-strategy=none`. The historical receipts above remain evidence
for their recorded source, rather than qualification of the later fixture.

Local harness controls can run independently of Flutter:

```bash
python quds_office_suite/docs/validation/thesaurus-20261118/continuation/local/fixtures/test_browser_harness.py -v
```

## Remote checkpoints

| Remote commit | Contents |
| --- | --- |
| `2f4e0908b3a0e740386449ce13352c425dc15a47` | Reconcile current main and preserve both roadmap sections |
| `c10e03e02967eb0ddf8b417f8919ccfdf6ef711c` | Integrate latest review/Zotero source and resolve shared editor conflicts |
| `1850c3374fca997e9cf375be4a5d95c940759782` | Review shortcut/layout regressions and fresh pack evidence |
| `eb1ff4dddbf65384bc61e2e7a0973360f76729ce` | Composition refusal, four additional regressions and stronger offline replay |
| `f39175b2b0eee3e3f9ab6c31bd97ddc1ca343be2` | Verified recovered runtime, formatting and initial analysis evidence |
| `af4971352fa14247e2de7be8c9b5733921e2ff30` | Final captured review/Zotero/spaCy integration; application-source freeze |
| `b9e8c159cea315aa0a044c4b0a6fc2cd35d11055` | 208 passing native cases, source inventory, screenshots and supplemental runner |

The commit containing this final report additionally preserves all 606 passing
case results, release-build receipts, the failed browser launch, complete
supplemental outputs and the independent receipt audit. Its commit identity is
available directly from this file's Git history and the PR evidence link.

Writes use the connected GitHub plugin with the expected branch head and
fast-forward-only updates. Each remote tree is checked against the local tree;
local equivalent commit IDs may differ because GitHub creates the commit
metadata. Checkpoint messages use `[skip ci]`. No CI result is used as evidence.
