# Persistent cross-folder conversations

**Status:** implemented 22 November 2026. Local retention only; no provider
conversation IDs, server threads or fetched missing messages are used.

## User path

Saved-mail search and retained folder views expose **Conversations** when rows
carry conversation metadata. Turning it on folds rows that share a persisted
conversation key, including copies or replies retained in different folders.
The existing disclosure, keyboard and aggregate read/flag behavior is unchanged.

## Key derivation

`MailConversationKey` derives one deterministic account-scoped key from:

1. the first valid Message-ID in a complete `References` list;
2. otherwise a valid `In-Reply-To`;
3. otherwise a valid own Message-ID;
4. otherwise `local:<retained-row-id>`.

The complete reference list is trusted only when every entry is a strict ASCII
dot-atom Message-ID. A partial or malformed list is ignored as a whole. No
subject, sender, recipient or date guessing is performed. Message-ID is never
used as the mailbox row identity.

This is deliberately conservative. A nonstandard client that sends only the
immediate parent in `References` can split a deep thread in the persisted index;
the loaded union-find view can still join rows whose explicit IDs are present.
No missing messages are fabricated.

## Storage and lifecycle

Schema **v20** adds `messages.conversation` and an account/conversation index.
New browse and synchronization upserts compute the key before insertion; a moved
copy inherits the source key. Opening a v19 or older database backfills every
retained message in a transaction from its stored envelope. The key survives
restart, folder moves, cache views and saved-search reads.

Search results expose the key through `MailHeaderRecord.conversationId`. The
shared list uses that key as an additional union link alongside explicit
Message-ID/References, so incomplete cross-folder rows can still group. Account
namespaces remain separate.

## Bounds and safety

- Reference lists longer than 64 entries are not trusted for the key.
- Fallback row IDs must be 1–1,024 code units.
- Only retained headers are indexed; opening a conversation never fetches
  missing messages.
- Conversation keys are local metadata and never change provider threads,
  folders, flags, keywords or membership.
- The index is rebuilt only during migration or normal header upsert; there is
  no background provider scan.

## Verification

- Core grouping/key derivation: **12/12**.
- Store cross-folder/search and v19→v20 backfill: **2/2**.
- Shared list conversation UI: **19/19**.
- Live mailbox.org test: fetched a real threaded header, persisted its key,
  wrote a synthetic reply into another retained folder with the same root,
  verified both headers share the key and that it survives repository reopen.
- Existing rule, tag, migration, move and sync regressions remain green.

## Limits

- No provider-native conversation IDs or server-side thread discovery.
- No subject-only thread reconstruction.
- Deep nonstandard threads may split; malformed reference lists are rejected.
- Conversation-aware bulk actions still operate on the loaded/visible rows and
  do not silently broaden to hidden cross-folder members.
