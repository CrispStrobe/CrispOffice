# Quds Mail native transports

## Gmail and Microsoft 365 / Outlook

`createMailCloudProvider` provides native Gmail API and Microsoft Graph mail.
`authorizeMailCloud` supplies desktop browser PKCE and an in-memory refreshable
token source; embedding hosts can supply their own platform-vault token source.
Both adapters implement bounded mail reads/sync, confirmed actions, MIME
submission and structured redacted diagnostics. Studio also has Yahoo, iCloud
and Fastmail IMAP/SMTP presets.

See the [cloud setup/API guide](../../docs/roadmaps/mail/cloud-providers.md) and
[read-only probe](example/cloud_probe.dart). Browser cloud operation is explicitly
unsupported; live acceptance needs the deployment's registration and test mailbox.

## Exchange Server on premises (EWS)

`createMailEwsProvider` provides direct native Exchange mail access with an
explicit HTTPS endpoint and NTLMv2 by default. It supports folder browsing,
incremental item synchronization, on-demand MIME, read/flag changes, moves,
move-to-Deleted-Items and EWS submission with Sent filing. Basic over verified
HTTPS and host-supplied bearer tokens are opt-in alternatives. The default does
not need Entra, Graph, IMAP, SMTP or a Quds relay.

See [Exchange setup, API contracts and limitations](../../docs/roadmaps/mail/exchange-ews.md)
and the [read-only native probe](example/ews_probe.dart). The provider is a native
mail adapter; Calendar, People, Kerberos/Negotiate, automatic Autodiscover, public
folders and live-server interoperability qualification are separate work.

## IMAP

This is the first M06 native IMAP implementation. It provides manual account
configuration, current host-vault credential access, selectable folders, bounded
UID synchronization, exact on-demand message literals, and guarded flag/move
commands. It is not a completed live-mail client or an OAuth authorization host.

## Public boundary

Import `package:quds_mail_transport/quds_mail_transport.dart` and construct
`createMailImapProvider` with a `MailImapConfiguration`, host-owned
`MailCredentialStore`, and optional `MailCodec` and `MailTransportLimits`.
The default codec is `QudsMimeCodec`. The result implements the portable
`MailProvider` interface. The IMAP configuration API exposes no enough_mail
clients, sockets, filesystem paths, or password/token fields.

Configuration binds a profile/account, explicit validated DNS/IP host and port,
username, TLS mode, authentication mechanism, and account-scoped vault reference.
DNS names must already be ASCII/punycode; IPv6 addresses are unbracketed. The
host persists these settings and owns vault writes, OAuth system-browser/PKCE
authorization, refresh, revocation, account removal, and session invalidation.
The vault payload for this adapter is the strict UTF-8 password or access-token
bytes, limited to 16 KiB by default. No credentials are cached between calls or
written into ordinary account rows by this package.

Implicit TLS and required STARTTLS are supported. The production connector uses
Dart's default certificate/hostname validation, exposes no certificate bypass,
and sends no credentials before the configured TLS path succeeds. Missing
STARTTLS fails explicitly. Token mechanisms require the corresponding
`AUTH=XOAUTH2`/`AUTH=OAUTHBEARER` capability and `SASL-IR`; a server without those
capabilities reports unsupported. This does not implement token acquisition.

The conditional browser entry imports no socket implementation. Every provider
operation returns typed `unsupported` without touching the supplied vault or
codec. It does not advertise generic browser IMAP or a hosted relay.

## Synchronization and resource limits

Synchronization discovers existing UIDs with a strict, bounded
`UID SEARCH UID first:last`, then fetches at most the requested number using
`BODY.PEEK[HEADER.FIELDS (DATE FROM TO CC BCC REPLY-TO SUBJECT MESSAGE-ID
IN-REPLY-TO REFERENCES)]`. MIME content headers and message bodies are not
downloaded or fabricated to project an envelope. Numeric gaps do not consume
the page limit. A typed `MailImapSyncRange` identifies the fully observed closed
interval: the store removes only previously stored memberships absent from the
page, in that exact mailbox and UIDVALIDITY. It never creates a tombstone for an
unused UID. This reconciliation, pending-edit state, upserts and cursor commit
in one transaction. A range may remove more cached records than the fetch page
size; its work is bounded by the store's configured account message limit.
Standard flags include
read, flagged, answered, draft, and deleted; an absent FLAGS item stays unknown.
The session-only IMAP `Recent` flag is not persisted.

Cursors contain a hash of host/profile/account/mailbox scope, UIDVALIDITY, the
next UID, the current sweep ceiling and a durable page revision. The v3 cursor
accepts saved v1 numeric-window and v2 discovery cursors at revision zero,
preserving their continuation position. Each returned page increments that
revision, including empty/completed sweeps and UIDVALIDITY resets. A completed
sweep therefore cannot reuse an earlier cursor value and let a stale page pass
the repository's compare-and-set check. The repository advances the cursor only
by atomically committing its page. UIDVALIDITY changes request a reset.
Completed sweeps start again from UID 1 so old flags and expunges are eventually
observed without pretending CONDSTORE or QRESYNC is implemented. Arrivals beyond
the frozen ceiling enter the next sweep. A server change during a sweep can
require another sweep; this fallback is not a snapshot protocol.

Revisions use exact VM/JavaScript integers up to 9,007,199,254,740,991. A cursor
already at that limit returns `invalidInput` before credential access or protocol
work; it never wraps or rounds back to a previously committed value.

**Discovery remains explicitly bounded:** `maxDiscoveredUids` defaults to 10,000
and can be configured up to 100,000. It limits the number of existing UIDs in one
remaining-sweep SEARCH result, independently of their numeric values. Exceeding
that count or the protocol byte budgets returns `quotaExceeded` without FETCH or
page commit. The fallback searches the remaining range again for each page;
it does not implement server-side ESEARCH/PARTIAL pagination and can repeat
substantial discovery work for large mailboxes. The default 64 KiB protocol-line
limit can bind before the UID count limit. Larger configured count budgets may
also require an explicitly larger line/response budget.

There is no default numeric UID ceiling. The optional legacy `maxUidScan`
setting retains its original numeric meaning when explicitly supplied; an
exceeded legacy ceiling reports `unsupported`. It has not been silently
redefined as a message-count limit. Direct retrieval of specified high UIDs
continues to work.

Exactly one complete simple SEARCH result is required, including an explicit
empty result. Missing, repeated, duplicate, malformed, overflowing, out-of-range
or unrequested extended results fail the whole operation. UIDs are sorted before
selecting the page. A UID disappearing between SEARCH and FETCH is reconciled as
absent; an unexpected fetched UID that was not discovered rejects the page.
Arrivals above the frozen ceiling wait for the next sweep. These rules retain
the existing eventual-refresh semantics rather than claiming a server snapshot.

The default page limit is 100. Header literals are limited to 256 KiB, protocol
lines to 64 KiB, and aggregate control/header responses to 16 MiB per operation.
On-demand full-message fetches use the caller's `MailReadBudget` and never trust
an advertised RFC822.SIZE as allocation permission. The exact complete literal
is retained before MIME processing; no line ending or charset reserialization
is used. A partial/malformed/duplicate/out-of-range literal fails the entire
operation. It cannot become a successful prefix or false sync tombstones.

Well-formed unsolicited FLAGS-only updates may arrive before or after requested
literals without consuming the page's message limit. An update for an in-range
UID still requires that UID's complete literal. When an update lacks a UID and
cannot be correlated safely with a returned message, a sparse response is
rejected; it is never converted into an unverified deletion.
Later safely identified flag updates replace the earlier observed snapshot.
An expunge followed by an uncorrelated UID-less update is rejected even when
all requested literals arrived, so stale flags cannot falsely confirm a write.

`MailProvider.fetchMessage` cannot carry parse diagnostics. It therefore returns
a message only for a complete codec result, with typed failures for rejected,
unsupported, or partial projections. The account-free MIME API remains the
boundary for callers that need detailed partial-parse diagnostics.

## Mutation and lifecycle semantics

One provider instance allows one active operation. Every call opens a fresh
connection and loads current vault credentials. Operations have a finite total
timeout and poll the account lease for cancellation. The default connector
retains a cancellable raw transport owner through TCP connection, TLS handshake
establishment and encrypted operation. Abort closes stalled implicit-TLS and
STARTTLS connections before their handshakes complete, destroys established
sockets, and
rejects late completions. Certificate and hostname verification remain enabled.
The provider never automatically replays a command; retry timing is a host
decision. Custom protocol-library socket factories remain responsible for their
own pending transport ownership.

Read/flagged/delete operations verify the UID exists, use UID STORE, then read
that same UID's observed flags before reporting success. **Delete only sets
`\Deleted`; it never issues mailbox-wide EXPUNGE or CLOSE.** MOVE requires the
server's MOVE capability, stays within one account, and confirms source absence
after acknowledgment. The optional `MailMutationReceiptProvider` path preserves
strict single-message COPYUID mappings (including untagged replies) and EWS
replacement IDs verified in the requested destination. Missing mapping evidence
retains generic success without inventing an identity. Hosts can atomically
reconcile retained entries through the durable store; destination coverage still
needs explicit synchronization. See the
[identity-transition contract](../../docs/roadmaps/mail/identity-transitions.md).
An attempted
write followed by cancellation, loss, malformed data, or failed confirmation
returns `conflict` for host reconciliation, without a retry hint.

The default connection suppresses legacy protocol-library print statements
within its operation zone. Public failures contain fixed typed codes and optional
retry durations; server text, subjects, addresses, literal bytes and secrets
are not propagated as error strings.

## Evidence and remaining M06 gates

The test fixture drives the actual enough_mail command, greeting, literal,
and response parsers with controlled socket streams. Tests cover scoped cursors,
UIDVALIDITY, flag observations, multipart header-only retrieval, exact non-UTF-8
octets, malformed input, resource limits, dropped connections, TLS sequencing,
late completion cleanup, token protocol framing, mutation reconciliation, and
real SQLite/coordinator transactions. A Node test exercises the public browser
entry and throwing vault/codec spies. Source-bound acceptance logs are maintained
in the repository's continuation validation records.

Separate real Linux loopback tests exercise implicit TLS and STARTTLS. They
observe a ClientHello, keep the peer's handshake stalled, and require the peer
to observe connection closure after cancellation or timeout before teardown.
They also check a fresh same-provider connection, delayed exact 1 MiB encrypted
payloads and subsequent replies, trust and hostname refusal, credential
sequencing, partial-write handling, and cancellation of an open write producer.
The successful handshakes use an isolated test-CA context; no test bypasses
certificate checks or changes global trust.

These local checks do not establish external-provider interoperability,
all certificate-chain or platform trust-store scenarios, other operating
systems, OAuth redirect/refresh integration, or disposable-account acceptance.
Other remaining gates include discovery beyond the bounded simple SEARCH
fallback, IDLE/CONDSTORE/QRESYNC, SMTP/composition, the account-aware mailbox
workspace, actual browser persistence, and platform credential hosts.

Original package code is MIT. The native adapter uses the reviewed MPL-2.0
`third_party/enough_mail` fork; its new raw-fetch and lifecycle additions retain
MPL notices and are described in that fork's `QUDS_PATCHES.md`. No new hosted
runtime package is introduced by this workspace member.
