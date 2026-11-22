# Captured Mail head qualification

**Passed: 191 tests across eight suites, with zero failures or skips.** Analysis
of the four changed Mail source files and three new test files reported no
issues. No source changes were needed.

Exact head: `29fc72a0a7cffa7cfed2abdac2a3f82d2ff17f95`.
Execution used `/workspace/scratch/2437eaf6f35d/quds_mail_intake`, a detached sparse
worktree containing root files, `packages`, `apps` and `third_party`. Offline
`flutter pub get --enforce-lockfile` succeeded without changing tracked files.
All 21 workspace package roots resolve inside that worktree. The test command
ran from its Studio example; it did not use the parent Zotero source checkout.

## Executed coverage

- New retained-folder catalog validation, bounded counts, exact identities,
  duplicate/account/semantic rejection and deterministic ordering.
- New synchronized session selection, pagination, shrinking-page repair,
  revision fencing, invalid source rejection, cancellation and ownership drain.
- New retained-folder UI navigation including sync-only folders, explicit source
  choice, reader invalidation, local refresh, cleanup and localization.
- Existing mailbox-session, cached-reader and cached-host regressions, including
  actual local repository behavior and provider-identity-specific fake hosts.
- Existing workspace Mail shortcuts and saved-callback host ownership tests.

These are the eight suites recorded in
[targeted-tests.run.json](targeted-tests.run.json). The complete raw result is
[targeted-tests.log](targeted-tests.log). Changed-file analysis is recorded in
[analyze.run.json](analyze.run.json) and [analyze.log](analyze.log).

## Provenance and acceptance

[provenance.json](provenance.json) records the exact Git tree, runtime versions
and binary hashes, workspace package resolutions, lockfile/manifest hashes, and
changed-source/executed-test hashes. All 18 listed tracked files were checked
byte-for-byte against the captured head during qualification and rechecked
after execution; the complete tracked worktree remained clean. SDK: Flutter 3.47.8
with Dart 3.13.7. [summary.json](summary.json) indexes the result and raw log hashes.

The exact head is qualified for the bounded retained-folder milestone and can
be included with an ancestry-preserving merge. Preserve the final Word evidence
from captured main and both changelog additions. This is not a claim of live
provider-network or every-platform coverage. No GitHub Actions run was queried
or awaited. If integration changes the qualified Mail source blobs, rerun the
affected tests on that result; otherwise this execution remains applicable to
the unchanged implementation.
