# Portable mail archive restoration

Scope date: 2026-11-19. Repository: `CrispStrobe/quds_office_suite`.

This increment restores CrispOffice bulk EML exports with their original
source/folder/source-message provenance. It builds on PR #205 and integrates the
current GUI, VBA control-flow and macOS branch frontier before new mail work.

## Implementation

- Read-only manifest inspection and a deliberate Studio preview/start workflow.
- Cross-profile restoration into the existing destination archive owner.
- Exact length and SHA-256 checks before MIME parsing, plus verification that
  the parser retained those original bytes.
- Atomic storage of an original, index and every recorded provenance entry.
- Idempotent reruns with distinct saved, duplicate, failed and origins-added
  counts; bounded failure details and content-free progress diagnostics.
- Cancellation and source-change checks that retain confirmed earlier work.
- Bounded manifest/input handling and observed symlink/ancestor rejection.
- English, German and Arabic controls, with narrow/RTL layout coverage.

The workflow and default limits are documented in the
[archive guide](../../roadmaps/mail/archive-search.md).

## Reconciliation

The starting `main` was `0c29b5d8a0a92148dcd95f3282b4d43c462be20d`.
The integrated frontier was `df7f4b4c8df63cbcf80d9087d06707d166a2c678`,
which contains the current heads of PR #206, PR #207 and the macOS integration
branch. [reconciliation.json](reconciliation.json) records the 235-reference
snapshot: 24 fork branches, all 207 PR heads and four upstream branch heads.
There are 212 fresh ancestor checks and 23 unchanged historical-equivalence
references using 14 previously recorded exact-SHA proofs. The reuse of those
historical proofs, including unavailable original PR-only commits, is explicit.

## Qualification status

This checkpoint preserves the implementation and regression fixtures. Final
local acceptance is in progress; its receipt and raw logs will be added before
merging. GitHub Actions are not an acceptance dependency for this increment,
as requested by the repository owner.

The new regression fixtures cover atomic provenance rollback, corruption,
missing originals, changed manifests, codec substitution, symlink replacement,
overlap exclusion, cancellation around commit, different-profile round trips,
and a real importer `SIGKILL` followed by owner recovery and repeat restoration.
Studio also exercises the genuine MIME codec and native SQLite after the old
source archive database has been removed.

## Boundaries

This restores exported messages and provenance. It does not restore a complete
archive database, saved searches, source-profile settings, credentials or a
provider mailbox. New originals receive the destination's current archive date;
existing originals keep their dates and verified projections. Attachment text
uses the existing opt-in bounded extractor.

The manifest is unsigned: hashes detect corruption and observed changes, not
authenticity. Portable filesystem checks do not atomically exclude hostile
path replacement between operating-system calls and do not create a filesystem
snapshot. Reruns begin at the start and deduplicate; there is no durable import
cursor or unattended scheduler. Process-interruption checks do not qualify all
power-loss, device, operating-system or installed-application scenarios.
