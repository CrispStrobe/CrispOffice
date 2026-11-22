# Mail cross-provider account navigation — 22 November 2026

## Intended increment

Extend the existing foreground mailbox workspace with an exact-account chooser across verified IMAP/SMTP, Exchange EWS, Gmail and Microsoft 365 identities. A transition must save the retained current draft, release the previous session and repository owner, and open explicit sign-in for the selected destination. Selecting an account does not authorize automatic provider work. Expected provider/endpoint/login/sender identity is checked before a connection can load folders, headers or local drafts.

The existing one-connection architecture is retained. Simultaneous connected accounts, a unified inbox, background synchronization and full Outlook/Thunderbird/eM Client parity remain separate milestones. The non-secret local directory is never used as credential storage; it cannot reconstruct missing SMTP routes, EWS authentication choices or OAuth registrations.

## Initial history reconciliation

Started from fork main `4621326a5a452da475f219353c298d0f9b12470e`. Archive PR #379 completed during intake; adopted merged main `b510b2dc0a39085097189e8ac96f87341db1eed3`. Enumerated all 42 fork branches and 379 PR heads plus all four upstream branches. At that main, 405 fork observations were ordinary ancestors and 14 historical replacements were independently reverified. The remaining two current branch heads were merged before Mail implementation:

- `d68df6d625d7f81163c502ed46dcfd97a806e95a`: physical RTL paragraph layout, DOCX/style persistence and ruler behavior.
- `9d4f48e9fa019130118dc78be2ed655599f8bbe6`: Variant substring operations and typed named collection selectors.

Integrated baseline: `982ea168` (full SHA and proofs in `initial-intake.json`). No branch or historical work was deleted and no force update was used. Incoming tests will be executed locally; old reports are not credited as fresh results.

## Validation plan and current status

Implementation and qualification are in progress. Use the repository-pinned, unmodified Flutter 3.47.8 / Dart 3.13.7 SDK and locked dependencies. Runtime provenance is in `runtime-provenance.json`. Test the real account-navigation paths, exact destination validation, draft-save failure, session/repository draining, cancellation and stale asynchronous results, then run existing Mail regressions and focused incoming Office tests. Retain actual commands, raw results, source hashes and failures.

The incoming Archive record documents a preexisting Word visual-golden mismatch. This continuation does not refresh that golden or represent its historical failure as passing. No GitHub Actions queue is queried or awaited; local qualification is the acceptance evidence.

## Incremental publication

Working branch: `work/mail-connected-navigation-20261122`. The reconciled baseline, implementation and final qualification will be pushed as separate checkpoints. Before publication, fetch and reconcile new remote work and verify the main update against its observed predecessor.
