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

### Initial implementation and qualification

The first completed source was preserved remotely at
`b0d5f867b3bdc0ee61549a09c09f942db0f68ee1`, preceded by the intake checkpoint
`34358000669d52a3f18664586aa4c3223d7b9caf`, core/store checkpoint
`b4fd1ac4ffb2c65bd0805306781ce1406ddfb905`, and host/session checkpoint
`cb6dbcdcdb6dfbcd2aa186cf0d1a98b2953b526e`.

That pre-reconciliation tree had passing coverage for 1,609 distinct native
cases: 499 core, 962 storage, 82 host/session, 63 dialog and three additional
manual-publication lifecycle cases. Focused subsets and reruns are not added
again. The full storage run initially passed 960 and found two old schema-v7
fixture failures; deleting the newly added child table when reconstructing
that old fixture corrected them, and all 23 synchronization cases then passed.
Initial UI fixture/virtualized-row/navigation failures were likewise corrected
in tests, with actual hit testing retained. This historical result does not
qualify the later combined source by itself.

### Concurrent integration

The final intake found main had advanced to
`bcc55cb6e86e796056e2d75c3fdca50857dbf6e7` through
[PR #354](https://github.com/CrispStrobe/quds_office_suite/pull/354), an
independent implementation of exact folder scopes. Its source was preserved
and incorporated; overlapping APIs and migrations are being reconciled into
one implementation. In particular, its already-published schema 11 must remain
valid. The continuation uses additive schema 12, preserves the published
200-folder limit and old public scope APIs, and keeps stronger missing coverage
on the new typed path. Incoming regression tests are retained and executed.

New Word VBA cell-formatting and Zotero parity branches were also discovered
after the initial clean intake. Their exact integrated heads and fresh combined
qualification will be recorded in the completion section below. The worktree
is not considered merge-qualified while this reconciliation is in progress.

The genuine local runtime is repository-pinned Flutter 3.47.8 / Dart 3.13.7,
with lock-enforced dependencies and SQLite 3.54.1 / FTS5. Runtime provenance and
raw command logs will accompany the completed record.

Completed stages will be committed and pushed to the remote work branch.
Before merging, current main, branches and pull requests will be reconciled
again and actual local commands/results recorded here. GitHub Actions queue
completion is not an acceptance dependency and will not be awaited.
