# Mail uncertain-action recovery — 21 November 2026

## Delivered boundary

Native Studio now provides **Mail activity → Check current status** for saved
uncertain read/unread and flag/unflag actions. IMAP, EWS, Gmail and Graph read
the exact historical message identity. The app saves a dated observation beside
the unchanged original receipt, atomically updates only the requested cached
flag, and rejects stale owners, leases, revisions and concurrent profile writes.
It never replays the command. Completed, fully checked receipts release the
unresolved-batch allowance and become eligible for bounded cleanup.

The [recovery guide](../../roadmaps/mail/flag-recovery.md) describes the user path,
provider requests, schema-v7 migration, lifetime fences and remaining scope.
The [ordered roadmap](../../roadmaps/mail/README.md#desktop-mail-parity-ordered-increments)
continues with repository-driven sessions, account-wide/unified search and
conversations, then broader durable commands and rules.

## Incoming work and source checkpoints

The initial audit inspected all 40 fork branches, 280 fork PR heads and four
upstream branches. Of the fork branches, 29 were ancestors, ten had independently
verified historical equivalence, and one contained new additive work. Of the
PR heads, 266 were ancestors and 14 had verified historical equivalence. All
four upstream heads were ancestors. Counts include the newly created work
branch; equivalent refs overlap and are not extra independent features.

The only new initial head, `bbccae1bdead10951e2d7a23b33cf14c55382e02`, carried
28 Word/Mail validation evidence files and a reader API compatibility alias.
The integration retained newer foreground-journal and remote-image safeguards,
restored the exact evidence blobs, and added the missing `remoteImageUris`
alias/assertions. An earlier alternative merge contained superseded source
resolutions and was not allowed to replace current behavior. See
[intake-snapshot.json](intake-snapshot.json) and [intake-review.json](intake-review.json)
for exact refs and independently recomputed equivalence proofs.

Every checkpoint below was saved to GitHub branch `work/mail-parity-20261121`
using a non-forced, expected-head update. Remote tree hashes were compared with
the local staged tree before advancing the branch.

| Commit | Saved increment |
| --- | --- |
| `d6e8fddd08755fe84e82f2a7a0bce200f0c92826` | Reconciled initial incoming work and retained exact Word/Mail evidence; parents include current main and the new incoming head. |
| `71a9d73f86a30380d7fe3563f1a0048f1f7eb860` | Optional portable observation port, strict read-only IMAP/EWS/Gmail/Graph observations and provider tests. |
| `1df5e678906ff1def11deed085586dc733030595` | Schema v7, immutable resolution evidence, atomic flag/cache updates, concurrency fences, migration and recovery tests. |
| `c25a6ffb1b74673b567cc91eaba0d9d3a2a74345` | Connected Studio recovery flow, cached evidence display, English/German/Arabic controls and adapter/dialog/host/loader tests. |

## Executed local qualification

The genuine runtime is Flutter **3.47.8**, Dart **3.13.7**, Node **24.22.3** and
native Linux SQLite. The SDK archive and 202 hosted package archives were
SHA-256 verified. Workspace dependency resolution used the existing lockfile;
no dependency versions changed. Qualification uses real Flutter execution and
SQLite, with controlled protocol/provider fixtures. GitHub Actions were neither
queried nor awaited.

The accepted feature cohorts include:

| Cohort | Passing cases | What it establishes |
| --- | ---: | --- |
| Full native store inventory, 32 test files | 791 | Reconciliation plus drafts, Outbox, archives, mailbox views, quotas, journal, v1–v6 migrations, corruption rejection and actual SIGKILL transaction recovery. The earlier 154-case focused cohort overlaps this run. |
| Node-only store problem classification | 3 | Browser-related error classification, without a browser persistence claim. |
| Full portable core inventory, 13 test files | 235 VM + 235 Node | Existing providers remain compatible; bulk journal, compatibility aliases, cancellation, identities, search, Outbox and synchronization contracts remain portable. These are 470 executions of the same 235 cases. |
| IMAP observation, EWS provider/SOAP, Gmail/Graph provider tests | 186 | Strict fresh metadata, exact identities, explicit missing/generation outcomes, bounded response parsing, failures and cancellation. |
| Node provider stubs | 6 | Portable imports and explicit unsupported observation results. |
| Studio recovery adapter and dialog | 38 | All provider identity bindings, original outcome retention, explicit checks, cancellation, failure/retry, concurrent checks, offline history and compact localized layouts. |
| Actual connected hosts and native loader | 135 | All four host routes, exact history outside current folder, no write/body/send work, persistent observations, refresh requirement, close/retirement and late-result fencing. |

Counts are per cohort and must not be summed with overlapping broader regression
runs. Each accepted run has exit zero and a successful terminal event; source
and runtime hashes were unchanged during the source-bound feature runs. The
final evidence index records exact commands, test inventories, raw logs and
before/after manifests.

Six visual captures show English desktop plus German/Arabic compact check and
observed states. Compact fixtures use 360 logical pixels and 1.4 text scale;
close controls remain reachable and content scrolls. Fixture dates follow the
existing Material/device locale and are English. Review found no clipping or
lost recovery controls.

Fatal-info analysis passed for the complete core/store/transport packages and
all eight changed/new Studio library files. Full-store source/runtime manifests
contain 1,086 inputs; core and transport include their resolved dependency and
runtime closure. The final evidence index retains the exact manifest scope for
each gate.

Independent review checked account ownership, exact identity rebinding,
provider failure classification, cancellation into the final SQLite commit,
quota/cleanup behavior and the user-facing distinction between original
uncertainty and a later observation. No release blocker was found. The host
conservatively requires a folder refresh after a check attempt, even if that
attempt is canceled or fails before saving a result.

## Practical limits

These are controlled local qualifications, not live-account interoperability or
installed macOS/Windows/mobile acceptance. Browser provider factories reject
this native recovery capability; browser persistence remains unqualified.
Database contents are not encrypted, and process-crash tests do not establish
power-loss durability. An observation records the state when checked and cannot
prove which historical command caused it. Missing or replaced identities are
recorded without deleting cached content.

Repository-driven foreground sessions, background synchronization, unified
search/conversations, archive/move/delete workflows, rules, signatures/templates,
rich authoring and wider Calendar/People/shared-mailbox integration remain
separate roadmap boundaries. This increment does not claim full competitor parity.
