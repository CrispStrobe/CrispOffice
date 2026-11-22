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

| Original gate at `d53f30f1` | Passed | Failed | Skipped / incomplete |
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
source and the final affected-gate results are recorded in the recovery report;
accepted original engine/shared UI results are reusable only with exact unchanged
input and dependency checks.

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
cases. The combined engine gate reran the relevant closure after the later Word
changes. The ruler evidence is retained only through exact unchanged hashes of
its six captured test/source/model/helper inputs; its ten cases are not credited
as fresh final results.

Initial failed test attempts and their corrections remain in `development/`.
The first provider startup was rejected by automatic review because an
unsourced Flutter invocation attempted its Azure metadata bot-detection probe.
No cases ran in that attempt. Subsequent runs use the SDK's supported `BOT=true`
and `CI=true` settings to suppress that fallback, without SDK patches or changes
to network/approval controls. All final commands use that explicit environment.

The incoming Archive record documents a preexisting Word visual-golden mismatch. This continuation does not refresh that golden or represent its historical failure as passing. No GitHub Actions queue is queried or awaited; local qualification is the acceptance evidence.

## Incremental publication

Working branch: `work/mail-connected-navigation-20261122`.

| Remote checkpoint | Content |
| --- | --- |
| `ae72c31a234edd71f51de7688d18c8f7490422a6` | Reconciled baseline, initial intake and runtime provenance |
| `622d9fda2a6564638af153de887adea922bc26f8` | Shared chooser, native/provider routing and initial regressions |
| `0cb4057ae80162d754a2d5c3f145fc7f38bb0590` | Stale-admission and retained-owner fixes, incoming Word/Zotero continuation and local evidence |
| `d53f30f1874b38d36a791d1d3881583e4e42a2d6` | First frozen combined source, complete captured intake, observer-release recovery and focused regression evidence |
| `6d63c6e2a44848b4f2fb9d7177d2d605506f98cb` | Complete first combined run with its failures, restored cancellable Close and independent provider setup, and corrective regressions |

Each remote tree was checked against its local checkpoint before moving the
branch with an expected-head lease and `force=false`. The qualification
checkpoint follows the source checkpoint. GitHub Actions are not awaited.
