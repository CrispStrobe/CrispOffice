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

Implementation and local qualification are in progress. This initial checkpoint
does not claim tests have passed. The repository-pinned Flutter 3.47.8 / Dart
3.13.7 runtime is being restored for standard local tests. GitHub Actions are
not an acceptance dependency, as requested.

Subsequent checkpoints will retain the actual commands, outcomes, source hashes,
remaining limits and final merge receipt here.
