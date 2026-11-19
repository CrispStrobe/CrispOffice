# Mail UID discovery continuation — 19 November 2026

## Final integration qualification in progress

The first frozen implementation at `960fb72f` passed **1,000 application
executions** and **90 Python controls**. Its [complete historical checkpoint](checkpoint-960fb72f/README.md)
retains all raw results and the independent audit. That result predates the
subsequently discovered cursor reuse defect and does not qualify this new source.

The next bounded capture contains **421 actual refs**. All five incoming frontier
heads are reconciled: main `dc267fb4`, cursor/Arabic fixes `0669ac11`, decomposed
Arabic tests `05582479`, integration record `84aa6f96`, and complete evidence
`a4b73fe4`. The combined source adds v3 cursor revisions, preserves all Arabic
boundary and offset controls, and includes the optional native/Web Hunspell
package. Review reproduced and repaired a native dictionary-handle disposal leak and
freed-handle reuse after failed replacement. Eight deterministic lifecycle
regressions passed in development, and independent review found no remaining
blocking defect. Their [raw red/green evidence](development/hunspell-lifecycle.tar.xz)
is retained separately; the frozen combined gate will rerun the final source. Later main `b655b8a3`, including the Arabic
rule specification and macOS Studio runner, was also merged before this freeze.
Historical qualifications retain their source identities; no pending result is
represented as a pass. [PR #183](https://github.com/CrispStrobe/quds_office_suite/pull/183)
is the merge vehicle into remote main.

The continuation reconciles current incoming work before replacing the numeric
UID ceiling with bounded discovery and atomic range reconciliation. The
[incoming record](incoming/README.md) retains its exact captured references.
The [preflight refresh](preflight-incoming/README.md) preserves the subsequent
bounded capture, including concurrent Office reconciliation and AyaSpell work.
The [final capture and later-main review](final-incoming/README.md) preserve the
421-ref accounting and the subsequent 33-path main delta separately.

## Preserved combined attempt and reconciliation repair

The first expanded gate at `8dc76f0c` stopped before Dart execution: shared-runner
and restorer controls passed, but an incoming AyaSpell directory guard conflicted
with retained existing-directory publication controls (17 methods, 11 errors).
The [complete failed attempt](attempt-8dc76f0c/README.md) remains separate.

The repair restores safe existing-directory use while preserving the exact
verified-filename upload restriction and hash/readback checks. Its offline
17-control rerun passed. The generated card and two prose assertions now state
that the optional adapter exists while host registration/download UI remains
open. The next complete gate must execute the corrected frozen source; these
focused controls are not added to its totals.

## Later main and reporter-stream repair

Main advanced again to `b559f6c7` while the frozen `162f53c0` gate ran. The
[later-main record](late-main/README.md) preserves its Arabic T1 rules,
CrispOffice Studio and saved-message Mail module, with reviewed lifecycle and
Unicode fixes and updated label assertions.

The [162f53c0 attempt](attempt-162f53c0/README.md) remains **overall FAIL** because
native Hunspell standard error contaminated the strict JSON event stream. All
raw output is retained. The runner now records standard error separately while
keeping stdout and exit validation strict. An independent scoped audit accepts
**953 unchanged Mail executions**; the deferred Node plan and affected Office/
Hunspell checks will run on the final source. The earlier Arabic/Hunspell groups
are excluded from the final acceptance matrix rather than counted twice.

## Final captured heads and fresh replay

Later main `baf3dbd0` adds Studio's explicit dictionary setup, Word complex-script
language routing, default settings and artifact workflow. The final bounded
origin refresh at 09:05:31 UTC / 10:05:31 CET captures **424 actual origin refs**.
Its two new frontier heads, `293f4544` and `c0c71a26`, are retained as parents of
checkpoint `39444f0d`, including all their separate qualification archives and
unique regressions. The earlier four upstream refs keep their earlier capture
time. The [refresh and reconciliation record](merge-refresh/README.md) explains
all scope and conflict decisions.

Independent review repaired true-letter language detection, effective Word
language selection/reset and inherited default-on complex-script markers.
Dictionary cancellation now interrupts stalled headers and bodies; the
[Word and cancellation review](review/word-complex-script-review.md) preserves
failed reproductions and passing author checks. Delayed Mail picker and file
reads, three native ownership fixture families, all Arabic controls and the
current English/default-hidden-comments Studio behavior remain covered.

The incoming Mail analyzer exclusion changes one configuration input in the
previous exact closure. The final qualification therefore uses **fresh Mail
replay on the combined source**, not the historical 953-case acceptance subset.
That subset and the rejected overall attempt remain preserved separately.

The later merge guard captured main `00014577`: eight Studio About/German-label,
branding and macOS menu paths. It is also retained before qualification. The
added `url_launcher` edge uses the unchanged workspace lock. Eighteen malformed
German values were repaired without changing dictionary keys, and the two new
Dart files are included in strict checks. This later main observation is kept
separate from the bounded 09:05 ref snapshot.

## Implemented behavior

The native provider discovers existing UIDs with strict simple SEARCH and pages
by discovered messages. Large numeric gaps do not consume page slots or create
synthetic tombstones. A typed `MailImapSyncRange` lets SQLite remove only actual
cached memberships absent from the confirmed range, in the same mailbox and
UIDVALIDITY. Pending local edits enter reconciliation with their cached evidence
retained. Upserts, removals, pending state and the cursor commit atomically under
the existing cursor comparison and account lease.

Version 3 cursors retain a frozen sweep ceiling and accept saved version 1
and version 2 positions. Every returned page advances a monotonic revision,
including completed and empty sweeps and UIDVALIDITY resets. Repeated positions
cannot reuse a committed cursor token and admit stale pages. Exhaustion of the
JavaScript-safe revision range fails before vault or network access. Older clients
reject persisted v3 cursors; downgrades must not reset stored state. UIDVALIDITY
changes reset membership; newly arriving higher UIDs enter the next sweep. Discovery requires exactly one complete valid SEARCH response,
followed by successful tagged completion. Missing, malformed, duplicate,
extended or over-budget results cannot authorize a deletion or FETCH. A message
expunged between SEARCH and FETCH becomes absent; an unexpected fetched UID
rejects the page.

`maxDiscoveredUids` defaults to 10,000 existing UIDs per remaining-range SEARCH
and supports a maximum of 100,000. Protocol line/response budgets also apply;
the default 64 KiB line limit can bind first. This fallback repeats discovery
for each page and does not implement scalable ESEARCH/PARTIAL. An explicitly
supplied legacy `maxUidScan` retains its numeric meaning; it is unset by default.
The normal SELECT-derived sweep can reach UID `0xfffffffe` because UIDNEXT is
validated as a nonzero uint32. Raw discovery and stored identities admit
`0xffffffff`; exhausted-generation handling remains the server's responsibility.
Range reconciliation is bounded by stored account-message limits, independently
of the smaller fetched-page limit. No schema or dependency change is needed.

The incoming AyaSpell publication fix restricts uploads to verified bundle
filenames. The independently authored offline suites are retained under
distinct filenames, including integrity/readback refusal, exclusion of unrelated
output files and deterministic local builds. No live publication is performed
by this continuation or its tests.

## Native Hunspell ownership repair

Normal disposal rejects pending Dart requests, asks the worker to close after any
active native call, and waits for an explicit acknowledgement. Concurrent calls
share the same cleanup. Replacement clears ownership before allocation, so a
failed open cannot retain a freed pointer. Explicit close detaches a statically
rooted native finalizer before releasing the handle.

The deterministic C ABI fixture reproduced both original defects and exercises
normal/repeated/concurrent disposal, pending calls, startup cancellation, reopen
and allocation failure. Separate actual-library tests use the built Hunspell
backend and hash-verified AyaSpell files. A two-second shutdown fallback can
terminate a stuck worker, but prompt completion of an active C call or abnormal
finalizer execution is not established by these tests.

## Retained 162f53c0 expanded selection

The selections below describe the retained `162f53c0` attempt, including its
reported stream-accounting failure. The current bounded follow-up is described
below. GitHub Actions are not queried, awaited, dispatched or used as an
acceptance condition.

| Gate | Selection | Purpose |
| --- | --- | --- |
| Core and durable store | `tools/mail/check_store.py` discovers every current core/store suite | VM/Node contracts, atomic SQLite ranges, migrations/recovery, offline lock checks and browser entry/worker compilation |
| Native transport and TLS | 5 transport + 3 TLS suites | Sparse/high UID discovery, v3 cursor freshness, actual SQLite coordination, TLS/STARTTLS and connection lifecycle |
| Fork protocol regressions | 46 suites | Strict bounded UID SEARCH, FETCH/SEARCH/mailbox parsing, shared IMAP/POP/SMTP behavior |
| MIME and Mail reader consumers | 6 MIME + 4 UI suites | Regression coverage across changed shared dependencies |
| Arabic and shared proofing | 6 engine + 8 editor suites | Arabic combining marks, original offsets, mixed-script boundaries, default registration and shared editing behavior |
| Hunspell | 3 suites | Portable provider behavior, actual native library/dictionary/installer execution, deterministic native-handle lifecycle regression |
| Portable Node | 13 suites | Mail/cursors, MIME/fork portability, Arabic Unicode/text ranges and Hunspell provider behavior |
| Python controls | Shared runner, restorer, Mail launcher and three AyaSpell suites | Event accounting, process cleanup, runtime verification and bounded verified-file publication |
| Web compilation | Mail entry/worker and Hunspell public entry | Compilation only; actual browser/Wasm execution remains separate |

The [native plan](native-plan.json) selects 81 suites and lists 98 strict analysis
and formatting paths. The [Node plan](node-plan.json) selects 13 suites. These
are planned selections; final execution totals must come from successful raw
reporter events. Failed/skipped/unfinished cases and missing suites are rejected.
VM/Node repetitions remain separate executions, not additional distinct cases.

The wrapper binds all tracked packages/apps/vendor source, fixtures, workspace
manifests, launcher inputs, runtime artifacts and the native dictionary before
and after execution. Every changed Dart input must appear in both strict check
lists. The real native library and all eight immutable catalog files are
hash-bound; the public pinned-revision installer test is explicitly enabled.
The fake native ABI used by lifecycle regressions is identified separately from
the actual Hunspell backend. No fake backend result qualifies real spelling.

The incoming macOS runner is preserved and its structured assets parse. This
Linux-host qualification does not build or execute macOS, iOS, Android or Windows.

## Current committed qualification

The [tail native plan](tail-native-plan.json) selects **53 suites**: 13 Arabic,
Word and shared-engine suites, 11 editor suites, all 23 ordinary Studio suites
and six Hunspell suites. The [tail Node plan](tail-node-plan.json) selects
**19 suites**, including all ten Mail/MIME/fork suites, eight Arabic/Word/shared
suites and the portable Hunspell provider suite. Strict analysis and formatting
cover **150 Dart paths**, including all 64 extant Dart paths changed since the
retained `162f53c0` attempt.

Fresh replay additionally runs all current core/store suites and the
[64-suite native Mail plan](mail-replay-plan.json). The driver binds the exact
source, dependency inputs and runtime before and after execution. It enables
screenshot output, actual Linux Hunspell/AyaSpell checks, all three distinct
native fixture families and the pinned public dictionary download. Native
standard error is preserved separately from strict JSON reporter output.
Zero skips, failed cases, unfinished cases and malformed stdout are required.
No historical application execution is added to this fresh gate's totals.

The previous exact carryforward option remains reproducible for sources that
match its complete input closure. It is deliberately not used for this source.

## Reproduce

Use the [original runtime restoration](runtime/README.md), then the additional
[Hunspell preparation](runtime/combined-README.md) and
[Studio/Poppler preparation](runtime/tail-README.md), followed by the
[final installed-library/fixture preparation](runtime/final-README.md) and
[post-About workspace binding](runtime/about-README.md). All
source, tests, plans and drivers must be committed before execution. Keep runtime and output directories
outside the source checkout and use an empty output directory for every attempt.

The current gate executes the complete selected Mail and Office matrix afresh:

```bash
python3 docs/validation/mail-uid-pagination-20261119/run_tail_validation.py \
  --head FINAL_SOURCE_COMMIT \
  --base 162f53c0aff2314d88df912f9a64c0838e2a9da4 \
  --runtime /absolute/path/to/runtime \
  --output /absolute/path/to/empty-results --command-timeout 600 --replay-mail
```

`--replay-mail` runs current core/store and the five native Mail groups before
the tail gates. Every current case and diagnostic stream is preserved. The
historical failed attempt is not replayed or relabeled. Omitting this option
invokes the strict old carryforward checks, which correctly refuse this source's
changed Mail analyzer input.

## Acceptance boundaries

Controlled protocol and Linux loopback execution do not qualify real provider
accounts, OAuth/PKCE or refresh, host credential vaults, other operating systems,
SMTP/composition or the account-aware mailbox workspace. Browser compilation
and Node execution do not exercise actual browser persistence, quota/reload,
Web Locks or rendered browser UI. Final reporting must keep those boundaries
explicit.
