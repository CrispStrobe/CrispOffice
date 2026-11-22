# Durable Mail move/delete — intake and local qualification

## Remote intake

The 22 November 2026 intake starts from
`a5b4eb7d329b0700768b1fc72bb63cf58a9f5cd6` on
`CrispStrobe/quds_office_suite/main`. The workspace was initially empty; a new
checkout was acquired without overwriting prior local work.

- All 24 fork branches were inspected. The other 23 tips were ancestors of
  `main`, with no commits ahead of it.
- All four branches of the upstream `MohammedAsaadAsaad/quds_office_suite`
  repository were ancestors of fork `main`.
- Neither repository had an open pull request. All 30 recently updated closed
  fork pull requests inspected were merged.
- The latest integrated work includes #359 (Word VBA cell text), #360 (Mail
  retained-folder navigation and reconciled Office work), and #361 (Zotero
  selected-field context). No additional intake merge was necessary.
- The remote checkpoint branch is `codex/mail-durable-mutations-20261122`.
  Publication uses incremental commits with `[skip ci]`; local verification
  does not wait for the starved GitHub Actions queue.

## Selected increment

The ordered continuation in
[retained-folder-navigation](../../roadmaps/mail/retained-folder-navigation.md)
is durable foreground Move/Delete. Extend the existing command execution and
journal contract: commit frozen intent, then an applying marker, before any
provider mutation; retain typed outcomes; recover interrupted dispatch as
uncertain; never replay it automatically.

Move destinations retain exact account/folder identities. Read/flag observation
recovery must not be presented as move/delete membership reconciliation.
Existing provider semantics remain distinct: IMAP marks `\Deleted` without
expunging; EWS, Gmail and Microsoft 365 use their existing trash/deleted-items
paths. A generic acknowledgement does not establish a new destination identity
or synchronized membership. Cached sources remain dated observations until an
explicit browse or sync refresh.

## Remote checkpoints and acceptance in progress

- `ecfc7ae65cbd0904d6d38b9c8d76158d031a457a`: initial remote intake and scope.
- `cd6aa8044a7c6fb0738758a4038cdbd626b5721d`: schema 13, existing-runner
  extension, provider capabilities, connected controls and first regressions.
- A subsequent checkpoint preserves host hardening, journal/recovery tests and
  the updated roadmap before final connected acceptance and integration.

Locally accepted checks already include 521 core VM tests, 1,010 unique store
cases (975 ordinary plus 35 native process fixtures), 250 provider-adapter
cases, 131 native-loader cases, 47 journal adapter/dialog cases, 273 shared UI
cases, and 573 genuine Node cases (521 core, 52 portable store). The browser
store entry and worker compile successfully. Final host, analysis and incoming
branch qualification are still in progress at this checkpoint.

The full Flutter store run cannot execute the 35 subprocess fixtures because
its test isolate does not implement `Isolate.resolvePackageUri`; all 35 pass
when rerun under the native Dart VM. The Chromium test attempt failed before
test execution because this environment denies its Unix-domain socket setup.
Neither limitation is reported as accepted browser runtime behavior.

Review hardened native behavior so retiring the cache observer retains the
remaining rows' known or unknown read/flag metadata. Confirmed IMAP Deleted
preserves independent nullable flags, and the new organization port works
without requiring older flag setters. Separate destination/confirmation paths
remain required even if a generic checked-message callback is invoked directly.

The refreshed intake found active Word VBA and Zotero recovery branches after
the initial audit. Their histories will be retained and their focused local
qualification recorded before final main publication. CI is not an acceptance
gate for this run. No live-account, installed-platform or complete parity
claim is made.
