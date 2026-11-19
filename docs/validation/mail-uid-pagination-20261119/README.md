# Mail UID discovery continuation — 19 November 2026

## Combined qualification in progress

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

## Expanded local qualification plan

All gates execute sequentially on one committed source. GitHub Actions are not
queried, awaited, dispatched or used as an acceptance condition.

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

## Reproduce

Restore the pinned runtime using the checked-in
[restorer](../document-review-notes-20261118/runtime/README.md). The current
[runtime record](runtime/README.md) preserves this session's fresh restoration.

Commit all product changes, tests, plans and the driver before qualification.
Use the reconciled baseline as `BASE_COMMIT`, and the committed implementation
and plan as `SOURCE_COMMIT`. Both arguments must be full known Git commit IDs.
Keep runtime and output directories outside the source checkout. The expanded
[runtime record](runtime/combined-README.md) also records the pinned CMake/native build,
immutable AyaSpell catalog download and explicit test environment.

```bash
source /absolute/path/to/runtime/env.sh
python3 docs/validation/mail-uid-pagination-20261119/run_validation.py \
  --head SOURCE_COMMIT --base BASE_COMMIT \
  --runtime /absolute/path/to/runtime \
  --output /absolute/path/to/empty-validation-output
```

The wrapper runs shared-runner, restorer and AyaSpell controls, the Hunspell web
entry compilation, the complete core/store gate, the native plan and then the
Node plan. It preserves each child receipt,
raw output and command log, records the final source/runtime snapshots, and
stops after a failed gate. Use a different empty output directory after repairs;
do not overwrite an earlier failed attempt.

## Acceptance boundaries

Controlled protocol and Linux loopback execution do not qualify real provider
accounts, OAuth/PKCE or refresh, host credential vaults, other operating systems,
SMTP/composition or the account-aware mailbox workspace. Browser compilation
and Node execution do not exercise actual browser persistence, quota/reload,
Web Locks or rendered browser UI. Final reporting must keep those boundaries
explicit.
