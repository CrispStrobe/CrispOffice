# Cached mailbox views

Native Studio Mail retains the latest successfully saved header window for
each folder you visit in IMAP/SMTP, Exchange EWS, Gmail and Microsoft 365.
Messages you explicitly open also retain their original source, decoded body
and attachment bytes for later local reading.

## User path

1. Connect normally and browse a folder. Each successful first page, refresh or
   **Load more** saves the displayed ordered window, up to the existing 1,000
   header limit. A folder becomes available locally after its first saved view.
2. Open a message to download and retain its body and attachments. Merely
   listing, searching or selecting keyboard focus does not download bodies.
3. Disconnect or close Mail. Later, open **Drafts for connected accounts** and
   choose the account's separate **Cached mail** button. The original row
   action continues to open local drafts.
4. Choose a saved folder, filter its retained headers and open a cached
   message. The displayed capture time describes a saved view, not live server
   state. A partial-view notice explains that additional mail may exist.
5. A header without retained content explains that the message was not saved
   for offline reading. Close the local workspace and reconnect to download it
   or refresh the folder.
6. If local storage fills up, choose **Clear cached mail** in the local
   workspace and confirm. Each bounded step removes saved views and eligible
   downloaded copies; repeat when the result says more remain. Drafts, Outbox,
   credentials, authoritative sync state and server mail are preserved.
7. If a draft cannot be saved, its composer also offers **Clear cached mail**.
   Confirmation keeps the current editor open and retries saving its latest
   contents after cleanup. It never sends or queues the draft automatically.
   Canceling or failing cleanup leaves the unsaved editor available.

Cached access uses the verified non-secret account directory and the existing
account-specific local database. It does not require passwords, OAuth tokens,
authorization, endpoint discovery or a live provider. English, German and
Arabic controls cover local folder/reader navigation and failure states.

## What is retained

The cache stores visited folder identities/display names, header ordering,
observed flags, a monotonic view revision, capture time and whether the
foreground view had a further continuation. View order and capture time stay
fixed until that folder's next save; shared message metadata can receive newer
observations through another saved label or a future synchronization pass.
It retains up to 1,000 visited
folders per account and 1,000 headers per view, subject to the repository's
stricter configurable metadata, message and byte quotas. Each view also has a
hard ceiling of 2 Mi UTF-16 code units of metadata.

The stored scope is exactly the successfully saved loaded window. Search and
Unread/Flagged filters apply to that window. No account-wide search, complete
folder download or unified inbox is implied. Read/flag values are retained
header observations and can differ from the current server. Local
reading never marks a message read on the provider.

Original message bytes and decoded attachment snapshots are retained only
after an explicit successful open. Missing content and storage failures are
reported separately from an empty folder. A foreground cache failure leaves
the current connected reader usable and reports that local saving failed;
refresh or reopen while connected to retry the corresponding operation.

## Identity and ownership

The stable account fingerprint is unchanged from local drafts: host, provider,
verified endpoint, effective login and sending identity. Autodiscovered/custom
IMAP ports, EWS domains and cloud tenant identities retain their existing
namespaces. Local drafts and Outbox content remain in the same database.

Foreground provider sessions keep their own ephemeral identities and operation
leases. The cache bridge validates the original session account/provider and
then deterministically maps the full remote identity into the stable local
account. IMAP includes folder, UIDVALIDITY and UID; opaque providers retain
their complete message identity. RFC Message-ID headers, mutable high-level
message fields and IMAP sequence numbers never serve as cache identities.

The IMAP bridge retains the immutable original header record when constructing
the foreground projection. Later mutation of that projection cannot redirect
a cached message. Reconnects establish new write leases even when the local
account is identical. Disconnect invalidates in-flight writes before releasing
the shared draft/cache owner. The local reader awaits pending opens and reads
before completing close, preserving exclusive ownership.

Removing an account shortcut preserves cached mail, drafts, Outbox,
credentials and provider mail. Local files follow the host's existing
unencrypted storage policy. There is no automatic eviction or provider
deletion. Reaching a storage quota is explicit; confirmed **Clear cached mail**
provides a local recovery path so replaceable downloads do not permanently
block draft saving. Editor-pinned bodies and header identities needed by active
local operations remain protected; the cleanup report distinguishes remaining
work from bodies retained for open editors. Pending command records remain
intact; their replaceable cached bodies follow the existing eviction policy.
A failed cleanup rolls back its entire step.
When clearing from a connected composer, refresh the folder or reconnect before
retaining its headers again. Cleanup does not refill the cache automatically
and consume the space just recovered for the draft.

## Transaction and synchronization boundary

Schema v5 adds browse-view metadata and ordered references without resetting
existing content. Each view replacement compares its revision and checks the
current account lease inside the transaction immediately before commit. A
failed save, cancellation or interrupted precommit write leaves the prior
view intact. A committed view remains recoverable after process termination.
Body caching also checks an optional lease before its final commit. View
revisions use a durable profile counter, so clearing and recreating a view
cannot make a stale compare-and-swap revision valid again.

Stored cached-body metadata is size/type checked in SQLite before it is
transferred and decoded. Encoded JSON bounds include legitimate escaping
overhead; semantic decoded limits remain authoritative. This bounds corrupt or
previously larger cached rows when a profile is reopened under tighter limits.
Cleanup can discard an oversized or corrupt cached envelope without decoding
it, even after metadata/account limits are lowered. It invalidates each evicted
body's search entry so discarded body text cannot remain searchable. Headers
retained for synchronization or pending commands remain stored and can regain
their search entries through bounded reindexing or a subsequent sync update.

Browse views are independent of synchronization membership and cursors.
Replacing a limited view does not declare absent server messages deleted,
advance a sync cursor or discard pending operations. Retained view references
protect their messages from ordinary sync pruning. Existing draft, Outbox and
editor blob references remain protected by the shared repository.

Foreground continuation tokens are intentionally not stored. They can be
session-specific or expire, and they cannot be treated as synchronization
checkpoints. Reconnection starts a fresh provider browse. This is the first
repository-backed cached-read slice of M04W; it does not complete durable
synchronization or the reusable multi-account workspace milestone.

## Next acceptance boundaries

The next workspace increment should connect repository streams to foreground
lists and durable synchronization commands, with provider-specific reset,
reconciliation, retry and cancellation behavior. It then needs a unified
multi-account inbox, durable remote read/flag/move/delete commands and consistent
bulk workflows. Provider-side Drafts synchronization remains a separate
composition milestone with explicit conflict handling.

The [local qualification record](../../validation/mail-cached-workspace-20261120/README.md)
separates actual synthetic-provider/native-store execution from live-provider,
installed-platform and browser-storage acceptance. Those release gates remain
open.
