# Durable foreground mail command journal

Native Studio Mail now saves read/unread/flag/unflag commands and their results
for IMAP, Exchange EWS, Gmail and Microsoft 365. Both single-message controls
and checked-message actions use the same journal. This continues the
[foreground bulk contract](bulk-flags.md) and advances M04W/M05; it does not
complete background synchronization or a general offline command queue.

## User workflow

Use the existing read or flag controls in a connected folder. The host freezes
the selected remote identities and subjects, saves the intent, then runs the
explicit desired-state assignments sequentially. The visible receipt retains
Confirmed, Failed, Uncertain and Not attempted results. Stop waits for the
current request and prevents later dispatches. An uncertain result, stale
scope or persistence failure requires a fresh folder observation before further
mutations in that view.

Open **Mail activity** in a connected account or its **Cached mail** workspace
to inspect saved actions after reconnect or restart. History lists twenty
actions at a time, newest first, and opens the frozen per-message receipt.
English, German and Arabic controls support compact layouts. Reading history
does not create a provider, read credentials, fetch bodies or send commands.
Cached mail remains read-only.

**Clear completed history** requires confirmation and removes only completed
receipts without an in-flight or uncertain item. Running and uncertain work is
retained. An interrupted batch with no dispatched command is safe to clear:
all its messages are definitely Not attempted. History has no Retry or Resume
action. Refreshing a folder observes current flags; it does not rewrite the
historical evidence or prove which earlier command changed them.

## Persistence and dispatch ordering

The core runner accepts an optional `MailBulkFlagJournal` with four steps:

1. `prepare` atomically saves the complete immutable selection and desired
   state before any provider work.
2. `beginAttempt` commits an applying marker before the matching provider call.
3. `recordResult` commits the typed outcome and, for confirmed commands, the
   exact target flag in an existing matching cache row.
4. `finish` records the stop reason, remaining Not attempted items and any
   persistence problem.

Scope and cancellation are checked again after awaited journal writes.
A failure to save intent or the applying marker prevents provider dispatch.
A failure to save a returned outcome stops later commands while preserving
the known outcome in the live receipt. One local finalization attempt may
save it; this never retries the network operation. If that also fails, the
durable applying marker remains conservative evidence of possible acceptance.

Native production hosts require a journal from their existing SQLite owner.
An unavailable store fails closed before a flag command reaches the provider.
Explicitly injected legacy stores retain the optional foreground-only test
and embedding seam; they are not the production durability path.

## Identity, lifetime and cache consistency

The host translates transient connection identities into the existing stable
local account/profile namespace. IMAP retains folder, UIDVALIDITY and UID;
EWS/Gmail/Graph retain their provider and opaque message identities. RFC
Message-ID and list positions never identify a mutation. The draft/cache owner
must match the verified account exactly.

The repository returns an opaque owner capability with a revision. Commands
cannot adopt another account, another owner, a reopened database or an older
revision. Retiring a foreground view prevents later dispatch and stale UI
publication. A late acknowledgement may still be saved by its original owner;
the host keeps that owner open until the in-flight command settles. Logging
out or reopening retires old write capabilities.

A confirmed result and its cache update share one transaction. Only the
requested read or flagged bit changes, and only for the exact stored remote
identity. Other observed bits are preserved. A missing full flag observation
stays unknown; the journal never fabricates a full snapshot from one confirmed
bit. An affected mailbox view advances its revision so an earlier writer
cannot overwrite that update using a stale revision. Missing cache rows remain
missing. This is not an assertion that all account folders are synchronized.

## Restart and storage boundaries

Schema v6 adds account-scoped batch and item tables without replacing drafts,
Outbox, archive data, cached views or sync cursors. Migrations from versions
1–5 retain their existing data; interrupted migration rolls back transactionally.
The native opener uses its existing exclusive owner and SQLite WAL/FULL setup.

On exclusive reopen or logout, unfinished applying markers become Uncertain,
acknowledged results remain intact, and never-dispatched items stay Not
attempted. The batch is closed as interrupted. Recovery performs no provider
calls and does not resurrect commands. Tests include process termination
before and after intent, applying-marker and acknowledgement commits; these
exercise process-crash boundaries, not every hardware or filesystem failure.

Ordinary creation and completion retain the newest 100 clean receipts, within
a 200-batch total bound and the repository's storage budget. Recovery can close
prepared, never-dispatched batches as clean receipts without immediately pruning
them; the next creation or completion enforces the ordinary clean-history
window. Pruning preserves the receipt just completed. Running or uncertain work
is never evicted to admit a new command;
100 unresolved batches block new journaled flag operations with a quota result.
The current UI cannot resolve historical uncertainty. Provider-observation
reconciliation is the next recovery increment.

Selections are bounded to 1,000 messages and the configured page limit.
Subjects are bounded to 4,096 code units each, with a separate aggregate
metadata budget. Stored problems use typed codes, retry delays and mutation
evidence; raw exception text, credentials, bodies and attachments are not added
to journal records. Existing local mail storage is not encrypted by this change.

## Implementation and qualification

- `quds_mail_core`: portable dispatch ordering, typed immutable receipts,
  persistence stop reasons and strict report restoration.
- `quds_mail_store`: schema v6, transactional journal/cache writes, exclusive
  recovery, bounded history, corruption checks and migration rollback.
- Studio: stable account adapters, shared store ownership, single/bulk routing,
  connected and cached history, and localized persistence feedback.

The [integration and local qualification record](../../validation/mail-command-journal-20261121/README.md)
records exact source manifests, local commands, failed diagnostics and accepted
cohorts. Deterministic provider fixtures and Linux SQLite/process tests do not
claim live-account interoperability, installed macOS/Windows/mobile acceptance
or actual browser SQLite persistence. JavaScript core tests qualify the portable
runner, not those platform boundaries.

## Ordered continuation toward desktop-mail parity

1. Add explicit provider-observation reconciliation for historical uncertainty
   and repository-driven account/folder sessions, with stale observation,
   UIDVALIDITY, conflict and reconnect tests. Keep recovery distinct from replay.
2. Drive account-wide and unified search, saved views and conversations from
   indexed local data with visible completeness and account/source identities.
3. Extend durable desired-state commands to archive/move/delete, then rules and
   quick actions with previews, destination validation and recovery.
4. Continue rich authoring, signatures/templates and Office attachment flows;
   scheduling, Sent reconciliation, Calendar/People and shared mailboxes retain
   separate provider and installed-platform acceptance gates.
