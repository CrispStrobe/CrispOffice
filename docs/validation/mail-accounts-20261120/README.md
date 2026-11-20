# Remembered Mail accounts — work record

## Scope

This increment advances M04W with a bounded remembered-account catalog and
explicit switching for native IMAP/SMTP accounts. The existing account-scoped
draft fingerprint remains the owner of local draft recovery. Unified inbox,
offline mailbox entry, durable commands, account-wide search, persistent cloud
tokens and concurrent connected accounts remain separate work.

Implementation and fresh local validation are in progress. No passing result
for this increment is claimed in this checkpoint.

## Incoming work

The captured main was `d95e814af9556dcea448ba5673e0ba4dc81007d0`.
All 25 then-current fork branches, the 100 latest pull requests and all 241
pull-request head refs were inventoried. The four upstream heads were already
ancestors of captured main. See [intake.json](intake.json).

The two maximal active heads were reconciled with Git's native merge:

- Zotero note targets: `586e53502701d2f568f38bdcfb4aa5fd64a53142`.
- Word/PowerPoint VBA continuation: `1ffc316931a95f2e41601fe767771b27f43da0bd`.

The resulting integration is saved remotely as
`174004c3cc192ac0202f2263a7c55ae7f4c5bd84`, with tree
`4328e9b4c47381baeb32f5b354652988d9c71c08`. It includes the current typing,
Downloads, and earlier Zotero continuation work. The integration did not alter
the mail package or Studio mail implementation paths from captured main.

Nine historical non-ancestor branch heads were already incorporated: eight
whole trees matched main ancestors; all 37 changed paths of the remaining ODT
head matched an incorporated ancestor by mode, type and blob. Historical
branches were not reapplied over newer source. Closed historical PRs retain
their original status and evidence.

The incoming VBA continuation and typing benchmark include unfinished
qualification work. Their documentation is retained as historical evidence;
it is not counted as a fresh passing test result for this integration.

## Publication and validation policy

Source is saved incrementally to `work/mail-accounts-20261120`. Connected
GitHub Git-data operations publish the native local trees with both merge
parents intact. Every update uses a non-forced expected-head lease, and the
returned tree is compared to the local committed tree before advancing the
branch. Checkpoint messages include `[skip ci]`.

GitHub Actions, workflow runs, check runs and status endpoints are not awaited
or used as an acceptance gate. Fresh focused local tests, source review and
honest platform/provider limits will be recorded here before final publication.
