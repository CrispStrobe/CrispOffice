# Explicit provider Archive — work and qualification record

## Baseline and source preservation

Started 22 November 2026 from fork main
`3f3cb8508663dde917e913867908dbfd6c3efcf0` on remote checkpoint branch
`work/mail-connected-workspace-20261122`.

The initial intake fetched all 37 fork branch tips and checked all open PRs plus
the 100 most recently updated PRs. Every fetched branch tip was already contained
in main; the open PR collection was empty. All four upstream branch tips were
also already contained in fork main. Exact fork refs and recent PR dispositions
are preserved in [intake.json](intake.json). No history was discarded or rewritten.

## Selected increment

Implement an explicit connected-mail Archive workflow through the existing
durable foreground command journal. Gmail removes only the INBOX label;
IMAP uses an authoritative unique selectable `\\Archive` folder; Microsoft 365
resolves the ordinary well-known Archive folder. Folder-based actions freeze an
exact destination and reuse Move identity receipts. EWS and providers without
an authoritative ordinary Archive folder require an explicit reviewed destination.
Existing independent archive-copy workflows remain separate.

This is an organization increment on the existing workspace foundations.
Connected multi-account navigation, rules, body search, provider-side Drafts/Sent
reconciliation and live-provider/platform qualification remain open.

## Qualification status

Local qualification is in progress with the repository-pinned Flutter 3.47.8 /
Dart 3.13.7 runtime and unchanged workspace lockfile. The complete core package
suite has passed 648 cases. The native/HTTP/SOAP provider cohort has passed 336
cases. The new real-SQLite Archive/migration cohort has passed 20 cases. Strict
analysis and formatting of those changes are clean. Full store and affected
Flutter widget suites are still running; this checkpoint does not claim their
results. GitHub Actions are not an acceptance dependency, as requested.

## Remote source checkpoints

- `9d8758e5552f74ceb418b181d009e1ba96009350`: initial intake and typed Archive
  intent, before qualification.
- `dd00d169b8763994adda707ca16cd54c2f93c395`: provider implementation, receipt
  restoration, schema-16 journal support and protocol/workflow documentation.

The CLI has no GitHub write credential in this executor. Authorized source
checkpoints therefore use the connected GitHub Git-data API: each uploaded blob
SHA and the resulting complete tree SHA are compared with the staged local Git
objects; the remote branch is advanced with an expected-head lease and no force.
The exact remote commit is fetched back before continuing. No token is copied,
no source history is discarded, and ordinary local validation uses the checkout.

The final checkpoint will retain commands, outcomes, source hashes, remaining
limits and the publication receipt here.
