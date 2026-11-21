# Mail keyboard triage continuation — 21 November 2026

## Scope and source

Repository: CrispStrobe/quds_office_suite.
Initial main: 3058d36c5354d46bde418555d59282116cce1e26.
Implementation branch: work/mail-keyboard-triage-20261121.
Formatted source: 0b38435e553d14cbea505477a473061b134e308e.
Formatted tree: 917f157fccdafc6adda8e2a802fcf95d94a136b1.

This continuation advances loaded-mailbox triage with contiguous checked
selection and corrects synchronized-view header search. It does not claim
complete Outlook, Thunderbird or eM Client parity.

## Intake and preservation

The initial fork inventory contained six heads including main. Every other
head was an ancestor of, or identical to, the captured main:

| Branch | Captured head | Result |
| --- | --- | --- |
| codex/word-vba-authoring-20261121 | cf06b018ec125ce3b5abfda41a7fbbdcf7d30a47 | Ancestor; 43 commits behind |
| codex/word-vba-compatibility-20261121 | 3058d36c5354d46bde418555d59282116cce1e26 | Identical |
| codex/zotero-note-layout-20261121 | 2089e1e35a8ba81ea7f0a077b348f93ca70953c8 | Ancestor; 22 commits behind |
| codex/zotero-odt-roundtrip-20261121 | 05072dc2d59d0fa4ea97de4d6a842700ef333fab | Ancestor; 37 commits behind |
| work/mail-live-search-20261121 | c3d55be30d91694b1a427d261cddbe47b1dd5eec | Ancestor; 22 commits behind |

The dedicated open-PR endpoint returned zero PRs. The latest 50 updated PRs
were inspected; their merged contents were inherited from main. Upstream
main 15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba and all three other published
canonical-upstream branches were also ancestors; no upstream-only work was
missing.

Concurrent work appeared during implementation. A second, finite snapshot
captured 14 fork heads. [intake.json](intake.json) records every captured head
and comparison: all 14 are ancestors of reconciliation checkpoint
00fbd252d659777dc85f886df150f23c7a76bf1e, with zero incoming-only commits.

That reconciliation preserves:

- main's README update and the subsequent overview/detail documentation split;
- the original Word StrComp and color checkpoint histories;
- both halves of the Zotero workspace/shortcut/host-generation recovery;
- the Zotero footnote-separator intake documentation checkpoint;
- both independently saved Mail implementation/test branches.

The footnote-separator checkpoint was planning/intake documentation. This Mail
continuation does not present it as a delivered separator implementation.
Later PRs #347 and #348 appeared after the captured branch cutoff. PR #347
subsequently merged into main as 2f7f5ffc668d7f6452facb13e006e6704c93f439,
which is retained as an additional publication parent. Its production changes
are byte-identical to the already formatted and tested source. Its additional
dispatch test was reviewed and freshly passed all 15 cases. Main's expanded
changelog and qualification records are preserved. The
[publication reconciliation](checks/late-main-reconciliation.json) records this
continuity. A finite branch cutoff prevents unrelated ongoing branches from
continually replacing the source being qualified; new main commits are retained.

All remote ref updates use the exact expected prior SHA and force=false.
Original commits are retained as merge parents. No branch was deleted and no
remote history was rewritten.

## Delivered behavior

- Shift+Up/Down/Home/End, Shift+Space and Shift+click on rows or checkboxes
  extend or contract an inclusive range in the currently visible ordering.
- Separately checked messages survive range contraction. A normal move or
  explicit checkbox/Space toggle establishes a new anchor.
- Query/filter edits, sorting, folding and host updates reset the active
  range. Hidden/collapsed/unloaded rows never enter action snapshots.
- Scope/revision checks, immutable visible-order bulk snapshots and stale
  interaction-generation guards remain in force.
- Selection alone does not open a message or submit a provider operation.
  Busy, disabled and read-only hosts do not gain mutation permission.
- English, German and Arabic selection help describes the controls.
- Synchronized-view From/To/Cc projections retain every display name and
  address, with empty-name fallbacks. Bcc and bodies remain excluded.

The new regression coverage comprises 43 range-selection cases, three
localized help cases and two connected/offline address-search cases. Existing
tests are included in broader regression cohorts; these 48 new cases are not
added again to those cohort totals.

## Runtime recovery and qualification

The executor initially failed before command execution with disk exhaustion,
then reported that its process server was unavailable. Early commits therefore
accurately recorded source-only review and unexecuted tests.

The executor later recovered. The original official Flutter 3.47.8 archive
was downloaded and matched SHA-256
baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2.
Its framework revision is 737ba8f885dc774b53b442759999a312c9461e4e and its
bundled Dart reports 3.13.7. Both the Flutter tool and workspace dependency
resolution passed with enforce-lockfile. The committed workspace lockfile
remained unchanged.

The [source/runtime manifest](checks/source-runtime-manifest.json) binds the
formatted source, dependency inputs, SDK identity and exact changed-file
hashes. Fresh results available at this evidence checkpoint:

| Cohort | Result | Evidence |
| --- | --- | --- |
| Full shared Mail UI package | 272 passed; zero failures/skips; 17 files | [case record](checks/shared-mail-ui-test-counts-final.json) |
| Changed Dart analysis | All 23 paths pass fatal-infos/fatal-warnings | [receipt](checks/changed-dart-analysis-final.json) |
| Changed Dart formatting | All 23 paths unchanged by the pinned formatter | [receipt](checks/changed-dart-format-final.json) |
| Late dispatch analysis/format | The additional test passes both checks; 24 Dart paths checked overall | [analysis](checks/late-dispatch-analysis.json), [format](checks/late-dispatch-format.json) |
| Incoming Word tests | 205 passed; zero failures/skips; four files | [summary](checks/incoming-word-validation-summary.json) |
| Incoming Word portable smokes | Both VM/JavaScript output pairs identical | [parity record](checks/incoming-word-smoke-parity-final.json) |
| Studio Mail regression cohort | 176 passed; zero failures/skips; seven files | [case record](checks/studio-mail-test-counts-final.json) |
| Incoming Zotero/shortcut runtime checks | 52 passed; zero failures/skips; three files | [case record](checks/incoming-zotero-test-counts-final.json) |
| Late main dispatch regression | 15 passed; zero failures/skips; one file | [case record](checks/incoming-dispatch-test-counts-final.json) |

The five final cohorts total 720 substantive cases across 32 distinct files,
with zero failures or skips. Of these, 448 cases are the Mail/Studio cohorts.
Initial runs, loaders, lifecycle events and portable smoke receipts are not
added to these totals. The incoming Zotero cohort covers 23 settings, 12
shortcut and 17 Zotero cases, including delayed host completion guards.

The shared UI count includes the 43 new range cases and the existing search,
conversation, bulk action and reader regressions. Word's 205 cases comprise
78 StrComp, 43 native-color, 74 VBA-color and 10 integration cases. The separate
portable smoke output is not included in that unit-test count.

Machine test counts exclude hidden lifecycle and suite-loader events. For the
Flutter run, known test.startedProcess notifications are separately recorded;
the retained strict Mail event parser validates the remaining test protocol.
Raw logs and command/exit receipts remain beside their summaries.

## Failed and incomplete attempts

- A first SDK-version command used a relative executable path with the wrong
  working directory and did not launch Dart. Its receipt is retained; the
  subsequent absolute-path version checks passed.
- The pre-resolution formatter check reported differences and unresolved
  lint includes. After locked resolution, the pinned formatter normalized four
  Mail paths. Four incoming Word/Zotero paths also needed formatting.
  Final formatting and strict analysis passed all 23 changed Dart paths.
- Initial shared UI and Word runs passed, then were repeated against the final
  formatted source. Their initial passes are not added to final totals.
- The first seven-file Studio cohort recorded 169 passed cases and one EWS
  host-startup timeout, then stopped making progress while loading the Boolean
  search locale suite. The owned process was interrupted with exit 130.
  Its original RUNNING wrapper receipt is preserved with a separate
  [interruption record](checks/studio-mail-tests-interruption.json). This run
  is incomplete and failed; it is not a qualification pass. The same seven-file
  cohort subsequently passed all 176 cases serially, with the original helper
  timeout unchanged. The rerun passed the EWS case and both remaining locale
  files; it does not establish the cause of the initial timeout or loader stall.

No new source behavior was changed to conceal a failing test. No GitHub
Actions workflow, job, status or check result was queried or awaited.

## Checkpoints

| Purpose | Commit |
| --- | --- |
| Initial intake and acceptance contract | 02ef9dc85ff7e716809ee2e0de03bfc3546821a0 |
| Shared range selection and localized help | db653565558eeb35ec221f0977a7c36ba6e00d02 |
| Synchronized address-search integration | 45379ff7b4b9ee4bb904c3cc29eb07100fbc8aa9 |
| Ordered parity roadmap | 5e2065adb236148aaeb9bd6f157cbb084f125c5d |
| Incoming main/Zotero intake reconciliation | b500d59eb4cb531eb8043409da1e4532b36edc33 |
| Word StrComp intake | 03f06730ea264ea1bdd9b028c8c28f0dd6a12c0a |
| Independent Mail test integration | 8858749fc4ffab56a8d429a15ab6625978dbd83f |
| Main documentation split reconciliation | c077c7ac5b348c0d75affd460e81d49754f1ec1e |
| Word colors and paired Zotero recovery | 00fbd252d659777dc85f886df150f23c7a76bf1e |
| Pinned formatting after runtime recovery | 0b38435e553d14cbea505477a473061b134e308e |

## Reproduction and remaining boundaries

Use the pinned SDK and committed lockfile. Command receipts retain exact
invocations, working directories, logs and exits. Set FLUTTER_ROOT to that SDK,
use a writable PUB_CACHE and TMPDIR, and place the SDK's Dart executable on PATH.
Resolve the SDK tool's own original dependencies and then the workspace with
enforce-lockfile. Run the shared UI package tests with Flutter's machine
reporter and concurrency 1; the Studio and incoming Word receipts list their
exact focused files. Retain new logs rather than overwriting this dated record.

Native widget/unit execution does not qualify installed-platform keyboard/IME
behavior, a live provider, browser persistence, OS background scheduling, or
complete mail-client parity. The next ordered feature is explicit saved-search
folder sets, followed by repository-observed unified navigation and durable
move/delete. See the [workflow and next boundaries](../../roadmaps/mail/keyboard-triage.md).
