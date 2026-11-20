# Foreground bulk mail flags: integration and local acceptance

20 November 2026 · [PR #275](https://github.com/CrispStrobe/quds_office_suite/pull/275)

**The bulk-mail implementation passed local acceptance at source checkpoint
[`3645e8a4`](https://github.com/CrispStrobe/quds_office_suite/commit/3645e8a4db535fc0ab5ab0923ee7385e5c4e5195).**
The retained branch is `work/mail-bulk-flags-20261120`. The
[publication-time main reconciliation](main-reconciliation.md) records the later
Word/font update, its separate qualification and final publication consistency.
The immutable evidence in this directory remains bound to the source where each
check actually ran; later results do not relabel an earlier failed run.

## Delivered mail increment

Connected IMAP, EWS, Gmail and Microsoft 365 mailboxes support explicit checked
selection followed by **Mark read**, **Mark unread**, **Flag** or **Unflag**.
Selection covers matching headers already loaded in the current folder, in
displayed order. **Select visible** never means all mail on the server. New pages
do not silently expand a selection. Filtering prunes hidden rows; sorting keeps
their identities; refresh, account and folder changes retire the selection.
The independently open message and its reader remain intact.

The host freezes one to 1,000 unique account/provider/folder identities before
the first asynchronous operation. IMAP uses mailbox, UIDVALIDITY and UID. One
portable execution engine serves both ordinary provider replies and the
single-use compatibility coordinator. Commands set an explicit desired state;
the engine does not retry or replay them.

| Receipt outcome | Meaning and next behavior |
| --- | --- |
| Confirmed | The provider acknowledged the requested state. Only that target flag is projected into the live view. |
| Failed | Explicit evidence certifies that this command caused no remote change. Independent later messages may continue, except for cancellation or stale-scope results. |
| Uncertain | The write may have reached the server, or the reply lacks reliable mutation evidence. Further dispatch stops and refresh is required. |
| Not attempted | No command was dispatched for this selected identity. |

During execution, **Pending** includes the in-flight message. **Stop after current
message** lets its reply settle before preventing the remaining commands.
Completed **Details** preserve the frozen subject and outcome for each message.
An unknown unrelated flag remains unknown. A certified stale-scope rejection
also blocks another batch until refresh while retaining its Failed outcome.

Selection, search, sorting and these bulk commands do not fetch message bodies
or send mail. Core and host guards reject retired leases, account/folder changes,
reconnects, mutable native identities, stale menu routes and disposed callbacks.
An acknowledged in-flight command is still recorded if its view retires, but it
cannot update a newer view. Stop and Dismiss callbacks also retain their owner.

Controls, progress and outcome details are translated into English, German and
Arabic. Keyboard selection supports Ctrl/Cmd+A, Space and Escape while the list
has focus; Enter opens the current message. Search-field editing shortcuts are
preserved. Compact panes keep controls scrollable and reserve space for rows.
The popup explicitly carries the surrounding text direction and scale.

The [feature contract](../../roadmaps/mail/bulk-flags.md) explains the public API,
failure evidence, interaction rules and next increments. The earlier
`bulk-actions.md` path remains a compatibility entry into that one contract.

### Foreground and cache boundary

The plan and receipt are in memory. This increment adds no durable command
journal, offline queue, restart recovery, automatic replay or undo guarantee.
Confirmed flags update the connected live view. A fresh folder observation is
needed to retain the latest state for reconnect and cached-mail views. Cached
mail remains read-only. Provider authentication, dependency versions and the
database schema are unchanged.

## Incoming sources and incremental preservation

Work began by integrating the recent fork and upstream histories into remote
checkpoint `0cc6316c`. The final frozen inventory covers **38 fork branches,
274 fork PR heads, four upstream branches and four upstream PR heads**. It has
**zero uncovered refs and zero missing objects**: 297 heads are ancestors and
23 references use 14 independently recomputed historical replacement proofs.
Thirteen replacements have identical whole trees; the ODT replacement matches
all 37 changed paths by mode, type and blob.

The complete API cutoff is **20 November 2026, 20:58:00.677 UTC**. Subsequent main
checks belong to the publication supplement. The [intake record](intake.md),
[frozen inventory](remote-refs.json), [machine result](intake.json) and replay
script make this boundary explicit. Ancestry preserves incoming history; it
does not claim every competing implementation was kept byte-for-byte.

The [reconciliation record](reconciliation.md) documents the combined mail API,
exact retained peer core suites, adapted UI and host scenarios, conservative
provider evidence and the separate Word fixtures. The captured Zotero branch
contributed intake/history records, not a new Zotero runtime feature. Its four
alternate Word fixture names were consolidated using the
[verified content mapping](zotero-intake-mapping.json).

| Remote checkpoint | Preserved work |
| --- | --- |
| [`0cc6316c`](https://github.com/CrispStrobe/quds_office_suite/commit/0cc6316c61efd8b39a9cb0cfed6b2879f7865d48) | Initial incoming fork/upstream and Word history before implementation |
| [`034d73d2`](https://github.com/CrispStrobe/quds_office_suite/commit/034d73d2d09245c4a151de37bf522664ea5b4a80) | Frozen core plans, mutation evidence, transport boundaries and initial selection UI |
| [`76926054`](https://github.com/CrispStrobe/quds_office_suite/commit/769260540f173a08be32b4a14165be4709956b9d) | Connected native/EWS/cloud hosts, shared status, contracts and regressions |
| [`fcc7bd27`](https://github.com/CrispStrobe/quds_office_suite/commit/fcc7bd27f7df6200ac7d3174f6e21097f931cca0) | Concurrent main Word measurements and named arguments |
| [`3b753b02`](https://github.com/CrispStrobe/quds_office_suite/commit/3b753b0251d5dffe1b5b3e1496748f39caba8587) | One combined core API, exact peer coordinator tests, native/UI scenarios and continuation regression |
| [`dee5baf1`](https://github.com/CrispStrobe/quds_office_suite/commit/dee5baf1c5fbf1bf6228434158ef32d49693ff94) | Peer `9109fcc6`, localized popup handling and the first main reconciliation |
| [`3645e8a4`](https://github.com/CrispStrobe/quds_office_suite/commit/3645e8a4db535fc0ab5ab0923ee7385e5c4e5195) | Complete captured union through peer `639ea75a`, main `b6657785`, named Word additions and qualified mail source |

Later evidence and main-reconciliation checkpoints are recorded on PR #275 and
in the publication supplement. Updates used the observed branch head as an
expected SHA and were non-forced. Original incoming heads remain ancestors or
are accounted for by the historical proofs. **GitHub Actions, workflow runs and
status endpoints were neither queried nor awaited. No synthetic check statuses
were created.**

## Accepted local checks

These cohorts overlap and must not be added into one unique-test total.
Archive member names below are paths inside [evidence.tar.gz](evidence.tar.gz).

| Cohort | Accepted result | Evidence |
| --- | --- | --- |
| Full portable mail core, Dart VM | **205 passed** | `core-provider-results/accepted/receipt.json`, `core-vm.log` |
| Four portable bulk suites, JavaScript/Node | **111 passed** | Same receipt; `bulk-node.log` |
| Native IMAP, EWS and cloud provider boundaries | **195 passed** | Same receipt; `transport-boundaries.log` |
| Full shared mail UI | **161 passed** | `ui/cutoff-peer-receipt.json`, `ui-cutoff-peer.log` |
| Native mailbox workspace | **42 passed**; also part of the Studio coverage below | Same receipt; `native-workspace-cutoff-peer.log` |
| Connected and cached Studio hosts | **374 accepted cases**, composed from six unchanged suites with 338 passes and a clean 36-case provider rerun | `hosts/late-intake-initial/receipt.json`, `hosts/receipt.json`; composition below |
| Localized visual probes | **10 passed**, producing 20 reviewed captures at 1.4 text scale | `ui/cutoff-peer-receipt.json`, `ui/cutoff-visual-review.json` |
| Incoming Word baseline, VM | **867 distinct cases**: original full 853 plus 14 additive cases | `word/qualification.json`; composition below |
| Incoming Word baseline, Node | **725 distinct cases**: original full 712 plus 13 additive cases | Same qualification and raw receipts |
| Two actual BAS drivers | Eight-operation and thirteen-operation examples pass on VM and compiled JavaScript, with identical JSON results | `word/*-vm-js-comparison.json` and raw driver logs |
| Analysis | Full core/transport and scoped UI, Studio and Word analysis clean | Per-domain analyzer logs and receipts |
| Formatting, whitespace and intake replay | **43 changed Dart files, zero formatter changes**; source diff and frozen source audit clean | `final-checks/receipt.json` |

The machine-readable [validation index](validation.json) and
[source applicability proof](source-applicability.json) identify the exact
commands, sources, diagnostics and composition. Twenty-nine receipt cohorts
were independently checked against the qualified source. The later Word/font
main advance is qualified separately in the publication supplement.

### Studio composition and diagnostic history

The final seven-suite invocation reported **338 passed and one loading failure**.
The new shared-provider test used a localized refresh extension without importing
its Dart library. Six other suites completed successfully. Adding that one
test-only import changed no assertion or production code. The entire provider
suite then passed **36 tests**, followed by clean analysis of all 12 scoped host
and test files.

The source proof reconstructs the failing test file by removing that one import
and matches its recorded SHA256. Every other recorded source/config hash is
unchanged. Acceptance therefore selects 338 unchanged passing cases plus 36
cases from the corrected provider suite. **The original invocation remains
failed; it is not represented as a successful 374-test command.** Earlier clean
343-host and 115-native runs remain historical evidence with their own source
bindings.

### Incoming Word qualification

The reconciled baseline compiler is Git blob
`07dc3c5737661abaf3b17db24439c71482de22ed`. It retains the physical-unit and
official named-argument work from the concurrent branches, including finite
scalar handling, exact native precision, source budgets and transaction guards.

The first Word VM run had **845 passes and eight failures**. An imported fixture
template assigned a Variant before declaring its result variable, so the
existing declaration-order rule rejected the source before its intended type
check. Moving the declarations ahead of the assignment preserved the expected
`vba_type_error`; no compiler implementation changed. Formatting also normalized
five incoming test/driver files.

The subsequent complete ten-suite VM cohort passed **853 tests**, and the five
portable Node suites passed **712**. Later captured work added 43 lines to the
named compiler fixture and 105 lines to its integration fixture, with zero
removed lines. Those additions passed **14 VM and 13 Node tests**. The source
proof shows every previous test line, production file, BAS example and portable
driver remained unchanged. Thus the baseline contains 867 distinct executed VM
cases and 725 Node cases, composed from separate invocations. All 14 Word run
receipts captured 412 scoped files before and after execution, unchanged within
each run.

Both committed portable BAS drivers also ran on the VM and as compiled
JavaScript. Their result JSON matched exactly. These checks exercise actual
macro sources and document transactions; they do not qualify browser/WASM UI or
an installed Microsoft Word process. Historical Word intake reports retain
their original source identities and runtime limitations.

### Corrections established before publication

- A real open-popup regression proved that a nested RTL mail pane lost its text
  direction through the outer Navigator. The menu now carries direction and
  scale explicitly, while preserving its frozen action/selection payload.
- A retained native callback after disposal reached `setState`. The entry guard
  now checks `mounted`; the original failing case and accepted rerun are kept.
- A certified stale-scope failure stops dispatch and blocks further changes
  until refresh, without mislabeling the unchanged message as uncertain.
- The imported cloud rejection whitelist accidentally changed existing send
  outcomes. The first transport run had 191 passes and four failures. Restricting
  that rule to `MailCloudOperation.apply` retained conservative 429/499 flag
  outcomes while preserving all existing submission/Retry-After assertions.
  The accepted transport cohort has 195 passes; no old send assertion changed.
- Earlier diagnostic attempts exposed progress-semantic labeling and test
  sequences invoking a row before the UI frame reflected its new filter. Their
  original failures and bounded corrections remain in the archive.

## Runtime and reproduction

Runtime: **Flutter 3.47.8, Dart 3.13.7, Node 24.22.3**. The pinned SDK archive's
SHA256 is `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
All 202 locked dependency archives were hash-verified and restored; offline
`pub get --enforce-lockfile` succeeded for Flutter tools and the workspace.
The workspace lock remains
`0d64a732cd7f6c7cc4e1e01255276f081b59e6f43039636c3d36f6785a958ce2`.
No dependency versions or package lockfiles changed for this increment.

The archive preserves setup/bootstrap manifests, exact argument arrays, working
directories, environment wrappers, stdout logs and source hashes. Pure Dart
cohorts used the locked `test-1.31.1/bin/test.dart` runner with the workspace
package configuration; Flutter cohorts used the pinned tool snapshot with
`--no-pub`. Runtime caches and compiled scratch outputs are excluded.

To verify archive integrity and its source checkpoint from a Git checkout:

```sh
python3 docs/validation/mail-bulk-flags-20261120/verify_evidence.py
python3 docs/validation/mail-bulk-flags-20261120/verify_intake.py
```

The evidence checker reads archive members without extracting them. Use
`--archive-only` when the referenced Git objects are unavailable. Source replay
checks the bound checkpoint, not an arbitrary later working tree. The intake
checker performs no network calls and refuses missing objects.

## Evidence integrity and limits

- [Raw evidence archive](evidence.tar.gz): **2,472,242 bytes**, 180 members,
  SHA256 `63e9efefcf3eb36ef3ae06483cd1d8da622560265494a3c8de9e0f8713d65074`.
- [Member manifest](evidence-members.json): every member's exact source mapping,
  mode, length and SHA256; includes all 20 final PNGs.
- [Validation index](validation.json), [source applicability](source-applicability.json),
  [source intake](intake.md) and [implementation reconciliation](reconciliation.md).
- [English progress](visuals/en-progress.png), [Arabic action menu](visuals/ar-menu.png)
  and [compact German progress](visuals/de-compact-progress.png) are representative
  captures. Compact controls intentionally scroll while retaining a usable row.

Fake providers, protocol fixtures and widget tests qualify the implementation
contracts. Live account authentication, real sends, native installation/release
packages, macOS font discovery, browser rendering and WASM parity are outside
these mail gates. The later main supplement identifies any additional focused
Office qualification without converting those limits into a broader claim.

The next mail increment is durable sessions and a remote-command journal with
restart, offline/reconnect, cancellation and conflict handling. Account-wide and
unified search, saved live views and conversations then need a durable index with
explicit cache completeness. Rules, richer authoring, signatures/templates,
Office attachment workflows and provider-specific Calendar/People, shared
mailboxes and security features remain on the ordered parity roadmap.
