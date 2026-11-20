# Loaded mail header search: integration and local validation

20 November 2026 · [CrispStrobe/quds_office_suite](https://github.com/CrispStrobe/quds_office_suite) · [PR #270](https://github.com/CrispStrobe/quds_office_suite/pull/270)

**Local acceptance: passed, with eight documented image-only editor skips.** Qualified source checkpoint: [`1cf0c8e8`](https://github.com/CrispStrobe/quds_office_suite/commit/1cf0c8e86403df8e48094cb6275cd697094b8015). The machine-readable [validation record](validation.json) distinguishes exact-source checks, earlier applicable cohorts, and the composed editor result. The subsequent evidence commit changes documentation only. PR #270 records the observed publication transaction to remote `main`.

## Delivered increment

The shared connected and cached mailbox list supports bounded structured header queries, stable local sorting, and English, German and Arabic help and errors. IMAP, EWS, Gmail, Microsoft 365 and cached hosts project visible To/Cc headers and typed dates from already-loaded envelopes into one portable query contract.

Queries combine terms with AND and support quoted phrases, `from:`, `subject:`, `to:`, `cc:`, `is:read|unread|flagged|unflagged`, and strict `before:`, `after:` and `on:` dates. Limits are 1,024 UTF-16 code units and 32 terms. Invalid queries show an error and zero results. Oversized input remains editable and is rejected in full; predicates are never silently removed by truncation. Unknown flags and missing dates do not match their predicates. Dates use the displayed local calendar day, with exclusive before/after boundaries.

Search covers the current folder's loaded header window. It does not add body text, Bcc or private transport envelopes to the search document. Filtering and sorting perform no provider paging, body fetches, flag changes, sending or storage mutations. Explicit **Load more** remains available when another page exists. Stable row identities preserve focus; scope generations reject stale callbacks even across account/folder changes with overlapping IDs.

Compact panes keep search controls scroll-accessible and reserve row space. Arabic query examples retain left-to-right syntax inside right-to-left help. The [feature contract and next increments](../../roadmaps/mail/header-search.md) describe this completed slice and the remaining route toward desktop-client parity.

## Source intake and remote preservation

The initial main was `5ad4461a93c835479bf67acab63623944b3900a3`. Original incoming commit histories were retained, and work was saved repeatedly to `work/mail-parity-20261120`.

| Remote checkpoint | Change |
| --- | --- |
| [`bea51077`](https://github.com/CrispStrobe/quds_office_suite/commit/bea51077b93ac7e7cab94b96778d8639892166f2) | Integrate recent Word, CLI, macOS, Arabic web and release-document branches |
| [`7e3675fa`](https://github.com/CrispStrobe/quds_office_suite/commit/7e3675fa4b565cb759f972137495e21fcc8cf269) | mail: add bounded portable loaded-header search predicates |
| [`1059f096`](https://github.com/CrispStrobe/quds_office_suite/commit/1059f096ffe6ed098dee750c49d70021e00bbab2) | Harden incoming macOS guard and record complete source intake |
| [`b233d876`](https://github.com/CrispStrobe/quds_office_suite/commit/b233d876e020d4a33bd729e94cf23badbff7c83a) | mail: wire structured search and stable sorting across live and cached mailboxes |
| [`d219465a`](https://github.com/CrispStrobe/quds_office_suite/commit/d219465a581d8082efa6909b4005c64d7a7624a2) | Reconcile concurrent Word, settings, bookmark and Arabic continuation branches |
| [`33052393`](https://github.com/CrispStrobe/quds_office_suite/commit/3305239318981483d1b175db7b100f4ec69a1b1a) | Fix review findings in mail help, settings persistence and incoming CLI tests |
| [`d6ca66fc`](https://github.com/CrispStrobe/quds_office_suite/commit/d6ca66fcacfc299ae3f5284fc7ffc8b4403d35e4) | Keep mail search controls usable in compact localized panes |
| [`f4f0da73`](https://github.com/CrispStrobe/quds_office_suite/commit/f4f0da7379822d030e3549292696e76a6fd05526) | Integrate refreshed Word, Studio settings and release preparation branches |
| [`451ac48c`](https://github.com/CrispStrobe/quds_office_suite/commit/451ac48c65714fc6eeba78741b67e69ec1406556) | Resolve native style guards and finalize compact mail layout |
| [`bb46ebe8`](https://github.com/CrispStrobe/quds_office_suite/commit/bb46ebe88dc1303c4b58e6d4d41ee4386d8f9b57) | Qualify incoming note layout reuse and repair screenshot capture API calls |
| [`ee1812b2`](https://github.com/CrispStrobe/quds_office_suite/commit/ee1812b29d639ecabf203e3b594e74fb4f19468d) | Preserve marker-aware body invariants in incoming Zotero regression |
| [`1cf0c8e8`](https://github.com/CrispStrobe/quds_office_suite/commit/1cf0c8e86403df8e48094cb6275cd697094b8015) | Reconcile advanced main with already integrated Arabic web work |

The [source audit](intake.md), [ref inventory](intake.json), and replayable checker cover **33 fork branches, 270 fork PR heads, four upstream branches and four upstream PR heads, with zero uncovered refs**. The fork breakdown is 24 branch ancestors plus nine proven equivalents, and 256 PR ancestors plus 14 proven equivalents. Every upstream ref is already an ancestor.

Fourteen historical replacement proofs were independently recomputed from Git objects: 13 complete-tree identities and exact equality of the 37 changed ODT paths, including mode, type and object ID. Every accepted replacement is an ancestor. Replaying those older divergent branches would reintroduce replaced work, so their exact equivalents are recorded instead.

While validation ran, remote main advanced to `d1e9cbc0` by merging PR #267. Reconciliation commit `1cf0c8e8` incorporates that history with an identical source tree: the Arabic work was already present.

The last full remote branch/PR refresh was captured at **18:41:35 UTC**; the owned working branch was refreshed after each later checkpoint. The final audit verifies this fetched inventory against the qualified source. It is a source-inclusion audit, not a claim that every historical runtime gate was rerun.

The combined source includes Word spacing/controls/style identities, CLI cleanup, bookmarks and incremental layout, Studio settings persistence, macOS deployment requirements, Arabic worker packaging and fixtures, screenshot hooks, workflow fixes and release notes. The screenshot/settings conflict preserves both sets of constructor hooks and ordinary defaults. The explicitly temporary golden-regeneration workflow was removed before main. Authored App Store submission notes remain historical claims; this task did not submit an app or observe account state.

**GitHub Actions, workflow runs and status endpoints were neither queried nor awaited.** Local acceptance was used for this task, and no synthetic remote check statuses were created.

## Accepted local checks

Counts describe the separate cohorts below. They overlap and must not be added as distinct test scenarios.

| Cohort | Result | Evidence inside `evidence.tar.gz` |
| --- | --- | --- |
| Portable mail core, Dart VM | **94 passed**, including 27 new query cases; Europe/Berlin timezone | `records/core-validation-receipt.json`, `core-tests-direct.log` |
| Portable query tests, JavaScript/Node | **27 passed**, Node 24.22.3, no custom shim | `records/core-header-search-node.log` |
| Shared mail UI | **110 passed**, including 33 message-list cases | `records/mail-ui-validation-receipt.json`, `mail-ui-tests.jsonl` |
| Localized visual probes | **5 passed**: EN/DE/AR at 440×850 and DE/AR at 320×260, all at 1.4× text | `records/mail-visual-tests.jsonl`, `mail_visual_probe_test.dart` |
| Studio integration | **190 passed**: 170 across four mail suites, 19 settings tests, one compact-navigation test | `records/mail-host-input.json`, `mail-host-summary.json`, `mail-host-accepted.jsonl` |
| Word and incremental-layout engine | **486 passed** across nine files, zero skips/errors, 98.112 seconds | `records/incoming-engine-acceptance-summary.json` and associated input/raw logs |
| Editor coverage | **204 passed, 8 skipped**, composed as explained below | `records/editor-validation-summary.json`, original five-suite log and clean Zotero rerun |
| macOS minimum-version guard | **5 Python tests passed** | `records/macos-minimum-version-tests.log` |
| Static analysis | Clean core and UI; **19 Studio, 17 engine and 6 editor files** covered | Per-domain analysis receipts/logs |
| Strict formatting / whitespace | **22 owned Dart files, zero changes**; complete base-to-source whitespace check clean; corrected editor test formatted separately | `records/final-format.json`, `final-commit-whitespace.log` |

### Editor coverage and exact source applicability

The original five-suite editor run completed with **203 passed, eight skipped and one failed**. Its only failure was an incoming Zotero test expecting `Body` after fixture setup had already inserted a footnote reference, producing `Body1`. The correction snapshots the original body text and inline identities and proves both remain unchanged when opening the transaction. No application code changed for this correction.

Four complete, unchanged suites contribute **172 passing tests and eight skips**. The corrected entire Zotero suite contributes **32 passing tests** from a separate clean run. Coverage therefore contains **204 passes and eight skips**, selecting one result per test. **The original mixed run still has exit code 1 and is not represented as a successful five-suite invocation.** All nine unaffected source/config hashes from its launch inventory were rechecked. The eight skipped fixture documents contain images without editable paragraphs; they are not hidden failures.

The engine's 486-test run binds 19 source hashes to `bb46ebe8`. All remain identical in the qualified source. Of 17 engine analyzer results, two were rerun at that final production checkpoint and 15 earlier successful results were reused only after exact source-hash verification. The earlier 428-test Word/PowerPoint run at `33052393` is retained as historical evidence, separate from final engine acceptance.

The 190-test host run used `451ac48c`. All 22 recorded mail/settings-domain files still match. Later changes were limited to the independently analyzed screenshot test gate, note-layout invalidation qualified by the final engine/editor runs, and the final Zotero test correction. The host result does not claim execution of those unrelated later paths. UI's 110-test run was followed only by an analyzer-required brace addition before the successful final visual probes. Core, UI, host-domain, analysis and formatter hash rechecks are recorded in `validation.json` and `records/source-applicability-final.json`.

### Corrections found during qualification

The retained [diagnostic history](evidence.tar.gz) separates failed or interrupted attempts from acceptance. It records the compiler-contention cancellations, the original German compact-pane overflow, CLI timeout migration to the existing bounded helper, and the corrected screenshot controller calls. Review also found and corrected two incoming production issues:

- Native paragraph controls must resolve styles through the active document's styles relationship. Unreferenced styles cannot satisfy selectors, and lazy XML parts must be materialized before validation. Negative paragraph/table fixtures and a positive custom-path fixture verify the behavior.
- Dirty footnote/endnote paragraphs require full layout, including formatting changes inside nested note ownership. Unchanged notes still allow incremental body edits. Differential tests compare text and formatting changes against fresh full layouts.

The source updates also prevent oversized settings saves from replacing a valid persisted document. The new test covers refusal, unchanged stored bytes, reload and recovery on a later valid save.

## Runtime and reproducibility

Runtime: Flutter **3.47.8**, Dart **3.13.7**, Node **24.22.3**. No package versions or workspace locks were changed. The SDK archive's SHA-256 was `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.

The exact union of **202 locked dependency archives** for the workspace and Flutter tools was downloaded and hash-verified, then safely extracted. Offline `pub get --enforce-lockfile` succeeded for both. A setup-only hash-marker newline error was corrected and the original archive hashes reverified. The bootstrap manifest and script are retained.

| Runtime input | SHA-256 |
| --- | --- |
| Workspace `pubspec.lock` | `0d64a732cd7f6c7cc4e1e01255276f081b59e6f43039636c3d36f6785a958ce2` |
| Flutter-tools lock | `6a98afb61c0cc72f31631ab444932f072fd275aa04d56cde2bf6831ba02fc8f8` |
| Resolved workspace package config | `e7eeaad9df2a20236c31f56c19470c7846f883d553e9eaf1af87ef3458341083` |
| Actual SQLite native asset | `0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b` |

The SQLite asset came through the pinned package's native-asset hook; no substitute library or asset override was used. Ordinary Dart test startup stalled during bootstrap, so accepted pure-Dart runs invoked the locked `test-1.31.1/bin/test.dart` entrypoint with the resolved package configuration. Flutter runs invoked the pinned `flutter_tools.snapshot` directly. This avoids repeated bootstrap, preserves assertions and source-declared CLI timeouts, and does not relax global test timeouts. The cancelled bootstrap attempt is not a pass.

Fully expanded argument arrays, working directories, source hashes, captured environment declarations and process results are in the core, UI, host, engine and editor receipts. A compact example of the actual core invocation is:

```sh
source /workspace/scratch/f31e183d600e/runtime/env.sh
mail_repo=/workspace/scratch/f31e183d600e/quds_office_suite
mail_dart="$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart"
mail_runner="$PUB_CACHE/hosted/pub.dev/test-1.31.1/bin/test.dart"
cd "$mail_repo/packages/quds_mail_core"
TZ=Europe/Berlin "$mail_dart" --packages="$mail_repo/.dart_tool/package_config.json" \
  "$mail_runner" --reporter expanded
TZ=Europe/Berlin "$mail_dart" --packages="$mail_repo/.dart_tool/package_config.json" \
  "$mail_runner" --platform=node --concurrency=1 --reporter expanded \
  test/header_search_test.dart
```

To replay the source-inclusion audit after obtaining the referenced Git objects:

```sh
git fetch origin '+refs/heads/*:refs/remotes/origin/*' '+refs/pull/*/head:refs/remotes/pull/*'
git fetch https://github.com/MohammedAsaadAsaad/quds_office_suite.git \
  '+refs/heads/*:refs/remotes/upstream/*' '+refs/pull/*/head:refs/remotes/upstream-pull/*'
python3 docs/validation/mail-header-search-20261120/verify_intake.py
```

Without `--capture`, the checker verifies the committed ref snapshot and does not rewrite it or move Git refs. Unknown references fail a new capture.

## Evidence integrity and boundaries

- [Machine-readable validation](validation.json)
- [Raw logs, commands, source receipts, diagnostic history and reproducible probes](evidence.tar.gz): **193,574 bytes**, SHA-256 `dc8d4eca158a1a0e739063e36bcd39399727342c1f0c9a18a3efe4d008985f2f`
- [Archive member hashes](evidence-members.json): **88 members**
- [Localized help comparison](visuals/help-locales.png) and [compact German/Arabic comparison](visuals/compact-locales.png)

The two comparison sheets are representative reviewed captures. The retained probe recreates the 17 raw captures. Six comparison sheets were composed for review; the UI receipt records all original image hashes. The standalone parser-review receipt is explicitly a transcription of previously observed stdout: the same deterministic 10,000-input sequence was run in UTC, Berlin and Los Angeles, producing 349 accepted queries and 9,651 typed refusals per zone with no unexpected exceptions. These 30,000 executions are neither unique-input claims nor additional unit-test cases.

Fake-provider/widget tests do not qualify live IMAP, EWS, Gmail or Microsoft 365 accounts, authentication, real sends or deployed applications. This task did not build/install native platform releases, execute the macOS App Store screenshot workflow, or independently rerun incoming native Arabic/WASM and browser golden qualification. Node checks the portable query implementation compiled to JavaScript; it does not establish browser UI behavior. Screenshot-gate static analysis establishes compile compatibility, not a rendered native capture or proofing finding.

The roadmap next prioritizes foreground bulk read/flag commands with explicit outcomes, then durable sessions and a remote-command journal, account/unified search and conversations, followed by rules, authoring workflows and remaining provider-specific acceptance. This milestone improves discovery and triage while keeping those broader parity requirements explicit.
