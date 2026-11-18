# Offline thesaurus — reconciled continuation, 18 November 2026

The thesaurus branch now contains the observed current main and the latest
document-review/Zotero work. Incremental remote checkpoints preserve the work.
GitHub Actions, check-run and CI-status endpoints are not queried or awaited.

**Current checkpoint:** Python compiler, full-pack integrity/reproducibility and
offline-harness controls passed. The pinned Flutter runtime is being recovered
for fresh integrated execution. New Dart/Flutter cases are not yet recorded as
passing here. Actual browser, installed desktop and independent human language
review remain open release checks.

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

## Fresh completed checks at this checkpoint

| Check | Result | Evidence |
| --- | --- | --- |
| Compiler/parser controls | 5 passed | [Raw log](compiler-tests.log) |
| Complete installed-pack verification | 1,037 files; all hashes, source identities, memberships and bounded lexical checks passed | [Receipt](pack-verification.json), [log](pack-verification.log) |
| Isolated deterministic rebuild | All 1,037 files and generated Dart constants byte-identical | [Full file hashes](pack-rebuild.json), [log](pack-rebuild.log) |
| Harness controls | 10 passed, 0 skipped | [Raw log](harness-controls.log) |
| Source review | Merge/shortcut/IME paths and harness independently inspected | Findings and resolution described above; not a runtime result |

The harness controls execute generated worker JavaScript in Node with mocked
cache/fetch APIs, test real local HTTP serving/shutdown, and reject corrupted
inventories, missing notices, changed panels and invalid cache/timing receipts.
They are not actual-browser or Flutter execution.

The unchanged packs contain 107,519 English and 50,264 German meaning groups.
The old 155-case native/provider result remains tied to its historical source
at `315beeb3`; it is not counted as a fresh pass for this merged checkpoint.

## Runtime and remaining checks

[environment.json](environment.json) records the fresh prerequisite probes.
Flutter/Dart were absent initially. The official pinned SDK URL later responded
with HTTP 200, and restoration of Flutter 3.47.8 / Dart 3.13.7 plus the recorded
dependencies is in progress.

Actual Chromium startup fails before the application runs: creation of a Unix
socket is denied (`EPERM`). The probe log is retained in the environment
receipt. Linux packaging also lacks clang, CMake, Ninja and GTK development
metadata. These are distinct from headless Flutter testing.

Open checks are fresh integrated Dart/Flutter analysis/tests and web compile
(pending runtime recovery), actual offline-browser acceptance, installed native
desktop acceptance, and independent human linguistic review. No source corpus,
language coverage, grammatical agreement or reinflection claim was expanded.

## Replay

Restore the pinned runtime with the historical
[SDK recovery recipe](../../zotero-citation-workflow-20261118/runtime/README.md).
Keep the checkout, `zotero-toolchain` and `zotero-validation` as siblings below
the chosen task root; source paths in the validation workspace remain live links.
Run from that task root with new output directories:

```bash
source zotero-toolchain/env.sh
python quds_office_suite/docs/validation/thesaurus-20261118/continuation/local/fixtures/run_final_validation.py \
  --root "$PWD" --output thesaurus-resume-validation
python quds_office_suite/docs/validation/thesaurus-20261118/continuation/local/fixtures/install_offline.py \
  thesaurus-resume-validation/browser-build
python quds_office_suite/docs/validation/thesaurus-20261118/continuation/local/fixtures/run_browser.py \
  thesaurus-resume-validation/browser-build --output thesaurus-browser-acceptance
```

The runner selects the original thesaurus/controller/correction/review suites,
the new integration cases, three incoming keyboard-review suites, two incoming
text-proofing suites, and the real-pack/visual fixtures. Tests run serially.
The browser step needs a host that permits Chromium startup; pass
`--browser-executable` when its binary is elsewhere.

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

Writes use the connected GitHub plugin with the expected branch head and
fast-forward-only updates. Each remote tree is checked against the local tree;
local equivalent commit IDs may differ because GitHub creates the commit
metadata. Checkpoint messages use `[skip ci]`. No CI result is used as evidence.
