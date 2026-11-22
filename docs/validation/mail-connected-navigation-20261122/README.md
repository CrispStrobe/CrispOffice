# Mail cross-provider account navigation — 22 November 2026

## Intended increment

Extend the existing foreground mailbox workspace with an exact-account chooser across verified IMAP/SMTP, Exchange EWS, Gmail and Microsoft 365 identities. A transition must save the retained current draft, release the previous session and repository owner, and open explicit sign-in for the selected destination. Selecting an account does not authorize automatic provider work. Expected provider/endpoint/login/sender identity is checked before a connection can load folders, headers or local drafts.

The existing one-connection architecture is retained. Simultaneous connected accounts, a unified inbox, background synchronization and full Outlook/Thunderbird/eM Client parity remain separate milestones. The non-secret local directory is never used as credential storage; it cannot reconstruct missing SMTP routes, EWS authentication choices or OAuth registrations.

## Initial history reconciliation

Started from fork main `4621326a5a452da475f219353c298d0f9b12470e`. Archive PR #379 completed during intake; adopted merged main `b510b2dc0a39085097189e8ac96f87341db1eed3`. Enumerated all 42 fork branches and 379 PR heads plus all four upstream branches. At that main, 405 fork observations were ordinary ancestors and 14 historical replacements were independently reverified. The remaining two current branch heads were merged before Mail implementation:

- `d68df6d625d7f81163c502ed46dcfd97a806e95a`: physical RTL paragraph layout, DOCX/style persistence and ruler behavior.
- `9d4f48e9fa019130118dc78be2ed655599f8bbe6`: Variant substring operations and typed named collection selectors.

Integrated local baseline: `982ea168` (full SHA and proofs in
`initial-intake.json`), published with the identical tree at remote checkpoint
`ae72c31a234edd71f51de7688d18c8f7490422a6`. No branch or historical work was
deleted and no force update was used. Old reports are not credited as fresh
results.

## Concurrent history reconciliation

The later capture covers 46 fork branch heads, 381 PR heads and four upstream
heads: 431 non-symbolic observations. After reconciliation, 417 are ordinary
ancestors and the same 14 historical replacement proofs remain verified.
`final-intake.json` retains both the observed state and the post-merge checks.

The combined source incorporates main `a9bfc961` (including Archive PR #379,
Zotero PR #380 and Word PR #381), Word selector continuation `5949a298` and
qualification `d40e1a2c`, Mail workspace checkpoint `77f8ede7`, and Zotero
converter planning checkpoint `550abcef`. The latter two branches merge the
same three existing parents. Every Mail workspace file matches an existing
parent; the converter checkpoint adds two planning documents. Their ancestry
was merged without replacing the newer Mail fixes. Comparing `packages` and
`third_party` before and after these last three merges found no content changes.

The final open-PR response at that capture was empty. Branches remain intact.
Publication still uses a fresh expected-main check, so an advance cannot be
silently overwritten.

Before the corrected final freeze, main advanced again to
`4cc604810fb2f41ac7ba04cbed65cb76300bff59` through PR #382. The normal merge
incorporated its 12 previously unmerged commits and exactly matched the tree
predicted by `git merge-tree`. This adds atomic selected-account refresh before
owner adoption, VBA Split authoring, and Zotero/Word field, converter, style and
ODT changes. Our newer Close/dispatch fences, native held-owner recovery and
fixture corrections remain present. `late-main-intake.json` records the exact
delta and merge receipt.

Main then advanced to `b4f1150b18348f348489c93108158a397c922abe` through
PR #383. Its concurrent Mail work adds exact-port routing, timestamp checks,
dependency-replacement fencing, late-owner tracking and cache-boundary tests.
The Word change keeps invisible Zotero instruction-run formatting out of visible
results. Both sides' Mail regressions are retained during reconciliation.
The two textual conflicts were in the Mail status summary and provider test
teardown; neither was resolved by discarding one side's implementation.

## Local qualification and correction

The first combined source was frozen at remote commit
`d53f30f1874b38d36a791d1d3881583e4e42a2d6`, tree
`9cf78cd9b8a26b41f18e97ea147636acae8e8396`. The complete remote tree was verified
against the local source before qualification. The run uses the
repository-pinned, unmodified Flutter 3.47.8 / Dart 3.13.7 SDK and locked
dependencies. Runtime provenance is in `runtime-provenance.json` and the final
run's `runtime.json`.

The original combined run completed 110 Studio Mail suites, 18 shared Mail UI
suites and 14 incoming engine suites, plus strict analysis and formatting of
87 changed Dart paths. All 6,116 captured source/configuration inputs and the
generated package configuration/graph stayed unchanged after every gate and
matched the exact source commit. The runner itself stayed unchanged.

| Original reported gate at `d53f30f1` | Passed | Failed | Skipped / incomplete |
| --- | ---: | ---: | ---: |
| Incoming engine, 14 suites | 903 | 0 | 0 / 0 |
| Studio Mail, 110 suites | 2,203 | 18 | 0 / 0 |
| Shared Mail UI, 18 suites | 294 | 0 | 0 / 0 |

The original run is **not accepted**. Its complete raw reporters, assertions,
source manifests and checksums remain in `final/qualified-source/`; no failed
attempt was rewritten as passing. Analysis and formatting both exited zero.

The broad run exposed Close requests being ignored during busy provider work
and unrelated IMAP credential loading blocking explicit native provider setup.
Corrections restore cancellation while retaining saved drafts and operation
receipts, and fence delayed send dispatch after Close begins. Controlled catalog
tests cover all three provider setup entries while IMAP credentials are pending.

It also reached older fixture gaps: cached-delete fixtures did not advertise
Delete, sync-capable empty-cache views were checked against the older label, and
account-free lifecycle/preset tests entered controls before automatic catalog
restoration completed. These are corrected at the fixture boundary. A separate
cached-store teardown/open diagnostic is retained in `development/`. Corrected
source and final results are recorded in the recovery report. The later PR #382
intake invalidates reuse of the original engine result and ruler continuity;
those changed inputs require fresh qualification. Only the original shared Mail
UI gate is eligible for reuse, through exact package/input, import/dependency,
configuration and runtime checks.

Focused corrections passed 64 provider-navigation cases (including nine new
Close/marker/receipt regressions) and 79 cache/local-account/file-picker cases.
The cache timeout did not recur in the exact case or full cached-host sequence
when run from the Studio package directory, matching the original gate. Earlier
repository-root probes failed before storage admission because they did not
use the same native-asset package context; they receive no acceptance credit.
No timeout was increased and no production cleanup change was made on that
basis. Sanitized open/close-stage diagnostics remain in the fixture.

Development checks exercise the real IMAP → EWS → IMAP host route, exact
destination identity, ambiguous SMTP selection, draft-save failure, delayed
observer/store release, retained uncertainty, target removal at asynchronous
boundaries, stale callbacks, and explicit failed-release recovery. The final
focused native/release/router batch passed 21 cases; the provider batch passed
55. These development runs are not added to final fresh totals.

The earlier integrated baseline passed 792 incoming engine cases and ten ruler
cases. The first combined engine gate then passed 903 cases. Both earlier engine
counts remain historical after the latest Word changes. The expanded final
scope includes a fresh ruler run because its captured Word-properties input
changed; the earlier ten ruler cases are not added to final totals.

The revised final scope selects 92 incoming engine suites, 30 incoming editor
suites (including the ruler), four Studio Zotero suites, two account-store suites,
and all 110 Studio Mail suites. This is 238 fresh behavioral suites. The original
18-suite shared UI gate is retained only if its independent package closure and
all relevant inputs still match exactly. This is VM/widget qualification; new
JavaScript/browser Split acceptance is not claimed.

The expanded run is frozen at remote source
`9a371b616ae0fa0dbbecaed04708837125694d7c`, tree
`491fbf5892a6999629a0fdf887d631cc7bb8acb5`. It captures 6,151 source/configuration
inputs and checks 109 changed Dart paths. Shared UI retention was independently
reviewed: all 393 relevant package/root inputs, 79 actual local Dart imports,
the unchanged 18-suite selection, generated resolution, runtime identity and
original evidence checksums match. Only its 294 cases may enter the retained
total. Fresh results are recorded under `final/merged-source-recovery/`.

Every command in that expanded run exited zero. Its original summary nevertheless
reported `accepted: false`: the parser split valid JSON test names on Unicode
line separators and missed three starts. A separate, checksummed
[reporter re-analysis](final/REPORTER_REANALYSIS.md) uses physical LF-delimited
records, pairs every start and completion, and verifies the original artifacts,
captured inputs and exact archived runner. It establishes 6,893 fresh passes
(3,892 engine, 653 editor, 47 store, 48 Studio Zotero and 2,253 Studio Mail), with
zero failed, skipped or incomplete cases. The retained UI adds 294 cases, for
7,187 cases on source `9a371b61` only. The raw run and its original summary are
unchanged. The earlier `d53f30f1` reported Mail total also omitted three passed
Unicode-name cases; its 18 actual failures remain unchanged and all 18 pass in
the expanded run. Neither historical total qualifies subsequent source edits.

Independent review after that run identified a missing ownership boundary:
provider Close could return while an unadopted store factory, load or atomic
refresh was pending, and a late cleanup failure could lose its live retry path.
The incoming PR #383 adds related ownership barriers but also requires explicit
Close ordering and native local-entry reconciliation. Those corrections and
their targeted regressions precede the next frozen source. The final gates
requalify affected Studio and Word inputs; unchanged gates are retained only
with exact source, dependency, runtime and evidence continuity.

The reconciled lifecycle stages cached-mail setup before the selected-record
comparison and final draft-owner adoption. Retirement cancels transport
authority before awaiting admission. If a cache watcher has not produced its
first snapshot, retirement starts one retained observer-close attempt to release
that waiter; admission drains that exact attempt and every sibling cancellation
before closing the owner. Failed cleanup remains visible for explicit retry.
Native local-account/draft entry and Close cannot bypass pending or retained
ownership. Provider Close keeps its route alive until the same boundary settles.

The revised final scope contains 236 fresh suites: 92 engine, 30 editor, four
Studio Zotero and 110 Studio Mail. The engine/editor/Studio results from `9a371b61`
are not retained after the PR #383 and ownership changes. The only retained
cases are the original 294 shared UI cases and the 47 account-store cases from
`9a371b61`. Store retention checks all 170 relevant package/root inputs, 59 actual
local Dart imports, generated resolution, runtime identity and immutable raw
reporter/re-analysis checksums. Its dependency closure is limited to unchanged
store/core packages. Each retained gate has its own provenance; 341 retained
cases may be counted once alongside the new execution.

Focused qualification of this reconciled lifecycle passed 207 cases: 145 provider
navigation cases, two standalone EWS/Gmail late-store cases, 45 native navigation
cases, seven native release/admission cases and eight cross-provider router cases.
The provider suite includes 30 new cancellation/admission regressions. The native
cases also cover blocked local entry/Close, explicit failed-close retry and cache
watchers that have never emitted a first snapshot. Strict analysis is clean and
the captured source hashes remain stable. These focused passes are not added to
the final fresh total, which executes the containing suites again.

The first attempt at the two strengthened standalone cases failed only their
final route-absence assertions after owner release. Their fixed-duration wait
was replaced with a bounded wait for observable route removal; both then passed.
The earlier raw attempt stays in `development/provider-admission-standalone.jsonl`
with no acceptance credit. Provider production source did not change after its
145-case pass. Complete focused receipts are in `development/`.

Initial failed test attempts and their corrections remain in `development/`.
The first provider startup was rejected by automatic review because an
unsourced Flutter invocation attempted its Azure metadata bot-detection probe.
No cases ran in that attempt. Subsequent runs use the SDK's supported `BOT=true`
and `CI=true` settings to suppress that fallback, without SDK patches or changes
to network/approval controls. All final commands use that explicit environment.

The incoming Archive record documents a preexisting Word visual-golden mismatch. This continuation does not refresh that golden or represent its historical failure as passing. No GitHub Actions queue is queried or awaited; local qualification is the acceptance evidence.

## PR #383 source and fixture recovery

The reconciled source is remote commit
`604a939991f568e7c6ad3f13958c6a4e204cafe1`, tree
`982666d50720c4f5985619e7c6a70af5bd04956c`. The fetched remote tree exactly matches
the clean local checkout, and main `b4f1150b` is an ancestor. The final runner
captures all 6,151 source/configuration inputs, checks 111 changed Dart paths,
executes the 236-suite fresh selection and verifies each of the 341 retained
cases through its independent gate provenance. Results are recorded under
`final/reconciled-source-recovery/`. Source, configuration, selected tests and
the runner remained frozen throughout that execution.

That complete run passed 3,901 engine, 653 editor and 48 Studio Zotero cases.
Studio Mail passed 2,370 cases and failed four cases across two files, with zero
skipped or incomplete cases. Analysis and formatting passed for all 111 selected
Dart paths. Every reporter lifecycle is paired, and all 6,151 captured inputs and
generated configuration remain unchanged. The original run remains **not
accepted**, with its raw output, four failures and checksums preserved.

Two independent reviews traced the four failures to fixture ordering. The three
provider bulk-reconnect cases hold the previous mutation reply while requiring
the new provider to open before that reply is released. The native session case
holds the first draft-store factory while requiring the second client to open.
Both conflict with the owner-release barrier already present in incoming main:
the old receipt/admission and owner must settle before another owner is admitted.
More pumping cannot satisfy either ordering cycle.

Checkpoint `051b20c774929f25f424c73a5ca14c3b611bb59e` corrects only
`studio_mail_bulk_provider_test.dart` and `studio_mail_session_test.dart`. The original case names remain. Each case now asserts the pending
barrier, releases its own gate, waits for a usable replacement account, and keeps
its old-owner/stale-callback/draft-uncertainty assertions. The provider cases also
prove that a fresh callback succeeds. No production source changes accompany
this correction.

The proposed selective recovery would rerun both complete files: 39 bulk-provider
and 21 session cases. This plan was not executed before main advanced again. All 60 earlier results from those files are excluded from retained
credit. The other 108 Studio suites contribute 2,314 passing cases; engine,
editor, Studio Zotero and the independently retained UI/store gates contribute
4,943. Their combined 7,257 retained cases are eligible only after exact input,
runtime, immutable-evidence and transitive-import checks. The fresh 60 cases must
pass with unchanged case identities before a combined acceptance can be issued.

## PR #384 reconciliation

Before publication, main advanced to
`ab3457c98b6d9a0d1da8147db3048dfc50d174d3` through PR #384. Its Word/Zotero
changes preserve supported editable ODT table borders, logical DOCX cell-border
aliases and opaque revision history on field boundaries. Its Mail changes retain
failed ordinary observer shutdown, drain Disconnect and guard retained Refresh
callbacks. All of that work and its original evidence are retained.

The merge combines that ordinary shutdown contract with this branch's staged
admission, captured first observer-close attempt, conditional directory refresh,
cancellable Close, failed-owner retry and guarded native local-entry paths. It
does not replace either host wholesale. A cache candidate remains unadopted until
its staged observation and selected-record comparison finish, so the reconciled
native continuation checks the current admission token at that boundary.

Disconnect now drains the retiring account before another explicit connection
is available. The corrected bulk-provider and native-session fixtures first
assert that pending barrier, release their held reply or factory, wait for drain,
and then explicitly start the next connection. A Connect action issued while
cleanup is blocked cannot queue a later connection.

This production and Word delta supersedes the two-file selective-recovery plan.
Its preflight is retained as unexecuted planning evidence, with no passing credit.
Final acceptance requires fresh checks of the combined Mail hosts; incoming Word
results can be retained only with exact source, dependency, runtime and immutable
reporter provenance. The original runs with failures stay unchanged.

## Incremental publication

Working branch: `work/mail-connected-navigation-20261122`.

| Remote checkpoint | Content |
| --- | --- |
| `ae72c31a234edd71f51de7688d18c8f7490422a6` | Reconciled baseline, initial intake and runtime provenance |
| `622d9fda2a6564638af153de887adea922bc26f8` | Shared chooser, native/provider routing and initial regressions |
| `0cb4057ae80162d754a2d5c3f145fc7f38bb0590` | Stale-admission and retained-owner fixes, incoming Word/Zotero continuation and local evidence |
| `d53f30f1874b38d36a791d1d3881583e4e42a2d6` | First frozen combined source, complete captured intake, observer-release recovery and focused regression evidence |
| `6d63c6e2a44848b4f2fb9d7177d2d605506f98cb` | Complete first combined run with its failures, restored cancellable Close and independent provider setup, and corrective regressions |
| `4015d7544ec3aa392ce2f375a35f00a4c3d4c5a3` | Corrected fixtures, all focused recovery evidence and the source immediately before the final main advance |
| `9a371b616ae0fa0dbbecaed04708837125694d7c` | Latest main reconciled, atomic reconnect retained with the corrected lifecycle, and expanded final qualification frozen |
| `93cc695d8e96774a5bc5f8b1498fb7144db1aa62` | Complete expanded local run, original reporter results, source manifests and raw evidence preserved |
| `893cca7a17b6bcda966f44248fa966084c5f1a74` | PR #383 reconciled with both Mail histories, immutable reporter correction, and aligned continuation plan |
| `604a939991f568e7c6ad3f13958c6a4e204cafe1` | Final reconciled source with late-admission/observer release recovery, 207 focused passing cases and the exact final qualification plan |
| `051b20c774929f25f424c73a5ca14c3b611bb59e` | Complete PR #383-source run with its four original failures, the two fixture corrections |

Each remote tree was checked against its local checkpoint before moving the
branch with an expected-head lease and `force=false`. The qualification
checkpoint follows the source checkpoint. GitHub Actions are not awaited.
