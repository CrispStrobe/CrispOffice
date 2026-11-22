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

## Validation plan and current status

Implementation and qualification are in progress. Use the repository-pinned, unmodified Flutter 3.47.8 / Dart 3.13.7 SDK and locked dependencies. Runtime provenance is in `runtime-provenance.json`. Test the real account-navigation paths, exact destination validation, draft-save failure, session/repository draining, cancellation and stale asynchronous results, then run existing Mail regressions and focused incoming Office tests. Retain actual commands, raw results, source hashes and failures.

The incoming Archive record documents a preexisting Word visual-golden mismatch. This continuation does not refresh that golden or represent its historical failure as passing. No GitHub Actions queue is queried or awaited; local qualification is the acceptance evidence.

## Incremental publication

Working branch: `work/mail-connected-navigation-20261122`.

| Remote checkpoint | Content |
| --- | --- |
| `ae72c31a234edd71f51de7688d18c8f7490422a6` | Reconciled baseline, initial intake and runtime provenance |
| `622d9fda2a6564638af153de887adea922bc26f8` | Shared chooser, native/provider routing and initial regressions |
| `0cb4057ae80162d754a2d5c3f145fc7f38bb0590` | Stale-admission and retained-owner fixes, incoming Word/Zotero continuation and local evidence |

Each remote tree was checked against its local checkpoint before moving the
branch with an expected-head lease and `force=false`. Final source and
qualification checkpoints follow separately. GitHub Actions are not awaited.
