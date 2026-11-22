# Saved-search folder sets — work and qualification record

## Repository intake

Work starts from fork `main` at
`c522851d165b395a7f60422a1be969dffc39c9ff` on 22 November 2026
(Europe/Berlin), on branch `work/mail-folder-search-20261122`.

The GitHub branch, pull-request and comparison endpoints were inspected before
implementation. There were **zero open pull requests**. All 16 non-main fork
branches had zero commits ahead of this main. Upstream
`MohammedAsaadAsaad/quds_office_suite:main` at
`15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba` was also already an ancestor.
There was consequently no unmerged incoming work to integrate at intake.
Existing branches are retained.

Recent Mail changes already included are saved-search foreground refresh
([#345](https://github.com/CrispStrobe/quds_office_suite/pull/345)), range
selection/address search
([#349](https://github.com/CrispStrobe/quds_office_suite/pull/349)), and its
combined-source qualification
([#352](https://github.com/CrispStrobe/quds_office_suite/pull/352)). Latest main
also contains Zotero desktop navigation
([#353](https://github.com/CrispStrobe/quds_office_suite/pull/353)). Earlier test
receipts are not treated as qualification of this new increment.

## Intended acceptance boundary

The next discovery milestone in the existing Mail roadmap is an explicit set
of saved-search folders across verified local accounts:

- Persist exact account and mailbox identities, with bounded immutable scope.
- Preserve existing all-folder definitions and revision-guarded updates.
- Filter before counting/paging, bind continuations to the chosen folder set,
  and deduplicate stored messages appearing under multiple selected labels.
- Retain missing-folder coverage and offer explicit scope repair; an empty or
  unavailable explicit selection must never fall back to every folder.
- Provide an actual local folder-selection, search, save, reopen and refresh
  path, with English, German and Arabic labels.
- Preserve exclusive repository ownership, stale-operation fencing, and the
  provider-free/body-free nature of retained-header discovery.

This does not complete Outlook/Thunderbird/eM Client parity. Shared unified
navigation, durable move/delete, indexed body/provider search, background
execution, richer composition and installed/live-provider acceptance remain
separate ordered milestones.

## Qualification and checkpoints

Implementation and fresh local qualification are in progress. The repository
pins Flutter 3.47.8; runtime preparation is being performed in the current
workspace. No test pass is claimed by this initial checkpoint.

Completed stages will be committed and pushed to the remote work branch.
Before merging, current main, branches and pull requests will be reconciled
again and actual local commands/results recorded here. GitHub Actions queue
completion is not an acceptance dependency and will not be awaited.
