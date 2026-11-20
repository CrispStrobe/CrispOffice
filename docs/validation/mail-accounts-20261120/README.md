# Remembered Mail accounts and integrated reply/forward workflows

> **Follow-up integration:** [PR #251](https://github.com/CrispStrobe/quds_office_suite/pull/251)
> incorporates later main `13be5046`, including durable Outbox workflows and
> the Word frame-cache repair. Scoped checks for that combined source are in
> progress. The 699-case record below remains bound to `625f4d76`; its
> documentation-only publication was `e1fd2e14`.


This report records the local qualification of committed source
`625f4d76d10ddf2144220f25ae8d867452eeed61` and the documentation-only
publication that preserves it. The original remembered-account implementation
merged through PR #243; follow-up PR #251 completes the remaining ownership
guards, injection boundary, regression fixtures and evidence.

## Delivered scope

This increment advances M04W with a remembered-account chooser and explicit
switching for native IMAP/SMTP accounts, including the existing Yahoo, iCloud
and Fastmail presets. Each selected credential backend holds up to **20
accounts**. Loading or selecting an account fills setup; the user explicitly
connects. A successful connection can save that identity or update its
password. **New account**, **Switch account** and **Forget selected account**
provide distinct operations. Switching first saves the retained local draft;
a save failure keeps the current session available for recovery. Forgetting
credentials does not delete server mail, another account, local drafts or
independently saved archive messages.

Credential storage can use the system store, a custom macOS keychain, an
encrypted vault with a master password, or session-only memory. Each backend
owns its catalog. Changing storage does not copy or delete accounts in other
stores, and an unavailable or locked selected backend reports failure without
falling back to another one. A remembered mode preference does not make
session-only credentials durable. Existing single-account store injection
remains supported. The [remembered-account guide](../../roadmaps/mail/remembered-accounts.md)
describes the workflow, identity rules and exact provider boundary.

The versioned catalog preserves complete login/sender case, normalizes hosts
and excludes passwords from identity. Migration writes and reads back the
complete v2 replacement before removing v1. Every v2 write checks the backend's
acknowledged contents; an empty v2 record remains authoritative. Unreadable or
invalid data blocks destructive replacement. The incoming keyed v2 form is
validated and migrated into the canonical list; the compatibility account-store
interface uses the same catalog rules. Transactions serialize across store
instances in the host isolate. This does not establish cross-process
coordination or installed-OS durability.

Delayed storage initialization stays owned by its original mode, path and
generation, including an A-to-B-to-A selection sequence. Changing storage clears
the previous selection and Forget target before reloading. **When disconnected,
it also clears the previous setup credentials.** An active connection stays
intact; session/settings guards preserve edits made while a catalog read is
pending. Busy connection, credential and initial draft-restore phases block
storage changes. Settings cannot be applied twice or dismissed during a commit.
The nine ownership regressions are retained alongside incoming selected-store
and race coverage. Account-scoped draft fingerprints are unchanged:
configurations differing only in SMTP settings still share the established
draft identity.

The combined source also retains the completed **safe HTML reply and attachment
forward workflows from PR #248** across native IMAP/SMTP, EWS, Gmail and
Microsoft 365. Reply, Reply all and Forward text only use authoritative plain
text, including an empty alternative, or bounded inert text from HTML-only
mail. HTML fallback requires a complete MIME result; the connected hosts pass
the reader's actual status. Active/resource content stays inert, Bcc and reader
chrome are not body fallbacks, and incomplete HTML cannot yield an apparently
complete quotation. Replies retain validated thread identifiers; forwards
start a new conversation. The existing Unicode-safe quotation limit and
localized truncation notice remain in force.

**Forward with attachments** explicitly admits the complete decoded set before
copying: at most ten files and 10 MiB total, with supported exact filenames and
types, preserved order and immutable bytes. Inline parts become ordinary files.
A complete attachment-only message can be forwarded with empty quotation plus
attribution; malformed HTML, incomplete MIME and unsupported attachment sets
are refused. Retained drafts take precedence over new reply/forward actions.
Review, local save/reopen and acknowledged uncertain-send recovery use the
existing composer; opening an action does not send mail. See the
[reply/forward guide](../../roadmaps/mail/reply-forward.md) for the complete
contract, including the `message/rfc822` and multipart container limitation.

Our eleven body API contracts remain in
`body_presentation_contract_test.dart` beside the incoming expanded body suite.
They retain selected-alternative budgets, explicitly empty HTML, exact byte
boundaries, partial-output rejection and incomplete-object coverage. Test
declarations describe scope; fresh execution is reported separately below.
The chooser and reply/forward labels cover English, German and Arabic; the
credential-storage settings/menu labels remain English.

## Source preservation and incoming work

The original intake captured main
`d95e814af9556dcea448ba5673e0ba4dc81007d0`, 25 named fork heads and all 241
then-fetched PR head refs. Later fixed captures were reconciled before the
validation freeze. Across those captures, the inclusion audit accounts for
**31 fork branch names / 45 observed branch-head pairs** and **247 PR numbers /
250 observed PR-head pairs**. These are cumulative observations, not one live
inventory. All four captured upstream heads are ancestors. No captured fixed
head is unresolved. See [intake.json](intake.json) and
[intake-addendum.json](intake-addendum.json).

The earlier native merges preserve the incoming Word/PowerPoint VBA and Zotero
continuations, newer main, Downloads/font inventory changes, credential-storage
and Mail chrome work, reader/body/reply-lane work, and incremental Word layout.
The saved merge checkpoints are `174004c3`, `0c2f09fa`, `33b2eba9`, `91645cd5`
and `cb7f8325`; the addendum records exact parents and trees. Downloads
resolutions retain main's busy/progress/error/Details and RTL behavior while
adding font descriptions, inventory coverage, optional host injection and
safe handling of stale inventory items.

The final fixed-main reconciliation adds
`c3df77d01ea9df4846e18131e69160d858f174ac` as a direct parent of the published
merge `625f4d76d10ddf2144220f25ae8d867452eeed61`; the other parent is our
tested checkpoint `7ef21fd1f6390ec46e89b1418eb7b06cc4c61224`. It retains PR
#248's complete reply/forward flows, the later Word layout continuation,
VBA arguments/paragraph-layout/PowerPoint margins and Zotero note-table work.
Reviewed resolutions preserve our credential ownership guards, explicit types,
catalog-backed fixtures, Connect readiness assertions and eleven body
contracts. The counts above describe the earlier captured inventories; this
additional fixed main is recorded separately in `main-refresh-c3df77d0`.

Fourteen historical heads have accepted equivalents: thirteen match whole
trees, and the ODT continuation matches mode/type/object on all 37 changed
paths. Every accepted counterpart is an ancestor of the frozen integration.
Ten old objects were rechecked locally; four absent PR-only objects retain
their exact committed proofs, with counterpart ancestry independently checked.
Old branches were not reapplied over newer source. Inclusion proves source
preservation, not identical bytes for every resolved file or new functional
qualification. The audit makes no claim about refs advanced after its captures.

The last captured main, `b42eca1db058f0def247b86c2f15dea90c11b4e8`
(PR #247), changes only the incremental-layout performance document relative
to `c3df77d0`. Its documentation is retained as a native merge parent after
qualification; product files, tests and dependency inputs are unchanged.
`main-refresh-b42eca1d.json` in the archive records this fixed comparison.

Work was saved incrementally to `work/mail-accounts-20261120` and reviewed in
[PR #243](https://github.com/CrispStrobe/quds_office_suite/pull/243). Remote
checkpoints preserve native merge parents and compare returned trees with local
committed trees; branch updates use non-forced expected-head leases.

- Validation source: `625f4d76d10ddf2144220f25ae8d867452eeed61`.
- Validation source tree: `8fef7e2e0621989e7e384f618e93a760594268ba`.
- Final publication commit and source-continuity receipt: [source-continuity.json](source-continuity.json) and [verify_publication.py](verify_publication.py) bind the tested source to its documentation-only descendants.
- Follow-up remote main/PR merge verification: [PR #251](https://github.com/CrispStrobe/quds_office_suite/pull/251) records the final merge SHA; run the publication verifier against `origin/main` to verify ancestry and unchanged protected files.

## Pinned local environment

Local qualification uses **Flutter 3.47.8 / Dart 3.13.7**. Framework revision
is `737ba8f885dc774b53b442759999a312c9461e4e`; engine revision is
`cf636b1dfb818dd6a3ff16e390e93b1a036969c8`. The restored native runtime came
from the [official Linux SDK archive](https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.8-stable.tar.xz),
verified at SHA-256
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.

Normal SDK-tool and workspace `dart pub get --offline --enforce-lockfile`
completed. Workspace resolution at `cb7f8325` preserved all 33 tracked
manifests/locks; later source receipts bind the resulting package configuration.
The cache contains 202 verified pinned hosted-package name/version pairs across
the tools and workspace. Genuine native test/compiler assets and supported
native precache were used. SDK source, lockfiles and integrity checks were not
altered to make the environment pass. Runtime receipts record exact hashes and
commands. Web compilers and production desktop build artifacts were outside
this restored test runtime's scope.

GitHub Actions, workflow/check/status endpoints were not awaited or used as an
acceptance gate. Checkpoints use `[skip ci]`. This record claims local evidence
only; it does not claim a GitHub CI pass.

## Local results on the combined validation source

All seven accepted cohorts completed on `625f4d76`. Each has zero process and
wrapper exit codes, one successful final event, no failed or skipped cases,
and unchanged source inputs, HEAD and runners. Counts below include only
substantive cases, excluding loading and hidden diagnostic entries.
[qualification.json](qualification.json) records the actual results and commands.

| Cohort / evidence directory | Observed substantive result | Scope |
| --- | --- | --- |
| `credential-ownership-625f4d76` | 84 passed; 0 failed/skipped | Selected stores and initialization races, account-store compatibility, ownership changes, session/draft safety and presets. |
| `accounts-625f4d76` | 97 passed; 0 failed/skipped | Chooser, catalog, migration/readback and legacy credential compatibility. |
| `workspace-downloads-625f4d76` | 56 passed; 0 failed/skipped | Mail workspace/chrome, web fixture paths and Downloads layout/manager. |
| `reader-625f4d76` | 71 passed; 0 failed/skipped | Incoming body suite, retained body contracts, presentation/message view and theme/scroll. |
| `builders-625f4d76` | 102 passed; 0 failed/skipped | Reply, complete attachment forwarding and outgoing attachment contracts. |
| `hosts-625f4d76` | 199 passed; 0 failed/skipped | Native IMAP/SMTP, EWS and Gmail/Microsoft 365 hosts, recovery and submission safety. |
| `engine-integration-budgeted-625f4d76` | 90 passed; 0 failed/skipped | Three engine layout suites plus four incoming integration suites, listed below. |

Final Mail total: **609**; targeted engine total:
**90**. Final accepted substantive total:
**699**;
failed/skipped totals: **0 failed / 0 skipped**.
The seven cohorts cover 35 distinct test files. The independent raw-event
review reconciles unique suite/case identities without counting reruns twice. The earlier 326 Mail passes belong
to `7ef21fd1` and are historical, not final-source acceptance.

Formatting and strict analysis with `--fatal-infos` pass for **all 19 Dart
files changed by the merged result against fixed incoming main**. The
`static-625f4d76/summary.json` receipt records format exit zero, all three
analysis groups exiting zero, unchanged inputs and unchanged HEAD. This is a
focused merge-delta gate, not whole-repository analysis. Earlier qualification
of 46 targets at `7ef21fd1`, including the eight reused `c30d8fc7` results and
551-file local dependency review, remains separately labelled historical.

The targeted engine selection is:

- `word_incremental_layout_test.dart`, `word_incremental_layout_prefix_test.dart`
  and `word_incremental_layout_differential_test.dart`: direct engine edits,
  fixed-height row/page-prefix behavior, differential edit sequences and
  fallback correctness.
- `office_vba_arguments_integration_test.dart`,
  `office_vba_word_paragraph_layout_integration_test.dart`,
  `office_vba_powerpoint_margins_integration_test.dart` and
  `word_zotero_note_tables_integration_test.dart`: the four incoming integration
  boundaries.

These seven files qualify their selected assertions only. They do not establish
full editor-corpus or complete Office acceptance.

Flutter cohorts run serially with `--no-pub --concurrency=1
--no-track-widget-creation --reporter=json`; engine cohorts use the pinned Dart
runtime with concurrency one. The supported no-track flag removes inspector
creation-location instrumentation; debug assertions remain enabled. Strict
runners reject missing/unsuccessful final events, nonzero process exits,
timeouts, failed or skipped completions, malformed/duplicate/incomplete event
streams, unexpected suite coverage and source/runner drift. The evidence binds
workspace libraries/assets, dependency manifests/configuration, selected tests,
their materialized helper/fixture closure and declared corpus inputs. This
binds the observed files. The committed source-continuity manifest protects
18,641 tracked paths outside three exact documentation areas; publication may
change those documented areas only.

## Historical results, rejected attempts and layout limits

Four completed Mail cohorts on `7ef21fd1` recorded 69 stores/drafts, 97 accounts,
120 workspace/Downloads and 40 reader cases: **326 passed**, with no failures or
skips and unchanged inputs/HEAD. These remain useful records of that checkpoint
and are excluded from the new combined-source total. Incoming PR #248 evidence
also remains bound to its own source and is not counted as a fresh local run.

The broad editor equivalence trial at `7ef21fd1` is **REJECTED**: 61 cases
passed, eight were skipped, and one `EQUIVALENCE_MODEL_ERROR` marker reported an
unmatched bookmark end after a scripted edit. The process exited zero and
emitted a successful Dart final event, but the strict wrapper exited one and
`gate_passed` is false. Its exact inventory was 62 corpus fixture cases plus
seven fixed cases. Neither registration nor a green containing test turns the
skips or marker into accepted coverage.

The incoming [incremental-layout record](../../performance/incremental-layout-20261120.md#equivalence-correctness-gate)
already documents image-only fixtures without paragraphs and bookmark-model
failures reached by cross-paragraph edits, including the later full relayout
refusal. Those are qualification limits, not waived passing cases. The fresh
selection above targets engine layout and incoming integrations; this work
does not claim the broad editor corpus passes. Any future complete corpus gate
must check exact fixture/case identities and reject skips and model-error
markers rather than relying on aggregate counts.

A remaining limit is `_script.step`'s `on UnsupportedError { return; }` in
`word_incremental_layout_equivalence_test.dart`. It can return before the
layout comparison, without a refusal marker or rollback assertion. A containing
case can therefore pass after some supported edits while an individual refused
edit remains unverified. The event runner cannot recover these silent refusals.
Any accepted result qualifies the comparisons actually completed; it does not
prove every scripted edit succeeded, complete operation-matrix coverage, or
that every refused edit left the model unchanged. This is separate from the
explicit model-error markers and fixture skips above. See `gate-review.json`.
No latency, throughput or typing-performance benefit is claimed.

The initial `engine-integration-625f4d76` cohort is also **REJECTED**:
88 cases passed and two VBA CLI cases hit their 30-second deadlines. Each CLI
case launches two fresh Dart source processes; the third format completed in
29.397 seconds. The resource record showed active compilation, stable OOM
counters and no remaining descendants. The unchanged seven-suite selection
then passed all 90 cases using package:test `--timeout=2m` and the same
600-second whole-cohort limit. The retry additionally binds the spawned macro
CLI and its two dynamically opened BAS fixtures. No assertion or source change
was made, and none of the rejected attempt's cases enlarges the accepted total.
See `engine-timeout-diagnosis-625f4d76.json` in the archive.

Other rejected records remain separate. The initial 43-target analyzer crashed
with exit 4; its root cause is not established. The `accounts-17732959` bulk
attempt timed out after 51 completed cases and lacked a final event. Its
cleanup process returned zero, but the strict wrapper rejected it. The earliest
ENOSPC attempt failed during test loading. Raw logs from the pre-reset workspace
were not recovered; [recovery.json](recovery.json) records the known historical
summary and source restoration, not a substitute raw test log. Earlier-source
observations remain historical. The monitored single-suite
`c30d8fc7` chooser qualification established a working no-track configuration;
changing source, suite grouping and instrumentation prevents assigning a
causal explanation for the unmonitored timeout. None enlarges the final total.

## Evidence packaging and replay

The archive retains accepted cohort summaries, raw events/stderr, commands and
exits, before/after input manifests, exact runner sources, case inventories,
strict static analysis, runtime/dependency receipts, process monitors and intake
reconciliation. Historical and rejected runs keep their original classifications
and contribute zero to the final total. Lost pre-reset raw logs are absent;
the recovery summary explicitly records that gap.

- Evidence archive and member manifest: [machine-evidence.tar.xz](machine-evidence.tar.xz) and [evidence-manifest.json](evidence-manifest.json), containing 303 retained files.
- Archive SHA-256 and byte size: `bdcff7ce1ad55e7025803a8b0173df37dc38d314901e655a3981f91bd52e8b90`; 896,648 bytes.
- Recorded replay command: `python3 validation/replay_evidence.py --repo /path/to/quds_office_suite --output replay-check.json` after extracting the archive.
- Replay outcome and source/manifest binding: [Archive verification](archive-verification.json) passed for all 303 members. [Replay from the extracted archive](evidence-replay-verification.json) verified 699 unique cases, 35 suites, 19 static-analysis targets and 2,242 tracked source bindings with no errors.

The separate checks verify archive/member hashes, replay the seven accepted
cohorts and rejected initial engine run under the strict acceptance rules,
validate source bindings, and compare publication
Git objects against the qualified source. Replay verifies recorded evidence;
it does not execute the Dart or Flutter tests again.

To check a published checkout from this report directory with Python 3.11 or newer:

```bash
python3 verify_archive.py
tar -xJf machine-evidence.tar.xz
python3 validation/replay_evidence.py --repo ../../.. --output replay-check.json
python3 verify_publication.py --repo ../../.. --ref origin/main
```

The repository must contain qualified commit `625f4d76`. The Git source check
uses that immutable commit; the publication check verifies its ancestry and
protected-file equality in the requested ref.

## Qualification limits and next increment

Fixture and Linux native-test results do not qualify installed OS keychain
permissions/unlocking, custom macOS keychains, encrypted-vault unlock and
durability, packaging, browser execution, or live IMAP/SMTP/cloud providers.
The `studio_mail_web_test.dart` fixture path does not establish a browser build.
No new OAuth-token persistence, simultaneous account connections, unified or
offline inbox, account-wide search, durable command queue, scheduled send,
Calendar/People workflow or complete desktop-client parity is claimed. Safe
HTML-to-text quotation is not rich HTML editing; inline-image composition,
signatures/templates, original-message attachment forwarding, multiple drafts
and server-side Drafts synchronization retain their separate roadmap scope.

**M04W remains open.** The next acceptance boundary is a repository-driven
mailbox session: persisted account/folder context, stable cached-header paging,
explicit cached/offline/sync states and recoverable durable commands. Then add
source-aware unified views, consistent move/delete, bulk triage and account-wide
search. The [ordered parity roadmap](../../roadmaps/mail/README.md#desktop-mail-parity-ordered-increments)
keeps queued sending, rich composition, organization and Calendar/People as
separate qualified increments. Outlook, Thunderbird and eM Client remain
workflow comparison targets, rather than a completed parity claim.
