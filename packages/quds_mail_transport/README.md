# Quds Mail native transport

This is the first M06 native IMAP implementation. It provides manual account
configuration, current host-vault credential access, selectable folders, bounded
UID synchronization, exact on-demand message literals, and guarded flag/move
commands. It is not a completed live-mail client or an OAuth authorization host.

## Public boundary

Import `package:quds_mail_transport/quds_mail_transport.dart` and construct
`createMailImapProvider` with a `MailImapConfiguration`, host-owned
`MailCredentialStore`, and optional `MailCodec` and `MailTransportLimits`.
The default codec is `QudsMimeCodec`. The result implements the portable
`MailProvider` interface. No public API exposes enough_mail clients, sockets,
filesystem paths, or password/token fields.

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

Synchronization scans finite numeric UID intervals using
`BODY.PEEK[HEADER.FIELDS (DATE FROM TO CC BCC REPLY-TO SUBJECT MESSAGE-ID
IN-REPLY-TO REFERENCES)]`. MIME content headers and message bodies are not
downloaded or fabricated to project an envelope. Each page has at most the
requested number of upserts plus absent-UID tombstones. Standard flags include
read, flagged, answered, draft, and deleted; an absent FLAGS item stays unknown.
The session-only IMAP `Recent` flag is not persisted.

Cursors contain a hash of host/profile/account/mailbox scope, UIDVALIDITY, the
next numeric UID and the current sweep ceiling. The repository advances a cursor
only by atomically committing its page. UIDVALIDITY changes request a reset.
Completed sweeps start again from UID 1 so old flags and expunges are eventually
observed without pretending CONDSTORE or QRESYNC is implemented. Arrivals beyond
the frozen ceiling enter the next sweep. A server change during a sweep can
require another sweep; this fallback is not a snapshot protocol.

**This initial fallback has an explicit whole-sweep ceiling:** `maxUidScan`
defaults to 10,000 and can be configured up to 100,000. It bounds the highest UID
to scan, **not the number of messages**. A mailbox with `UIDNEXT - 1` above that
ceiling returns `unsupported` before fetching or committing any page. A sparse
mailbox with high UIDs therefore needs the future discovered-UID pagination
adapter. This bound prevents unbounded connection counts and invented-hole
tombstone growth. Direct retrieval of a specified high UID is still supported.

The default page limit is 100. Header literals are limited to 256 KiB, protocol
lines to 64 KiB, and aggregate control/header responses to 16 MiB per operation.
On-demand full-message fetches use the caller's `MailReadBudget` and never trust
an advertised RFC822.SIZE as allocation permission. The exact complete literal
is retained before MIME processing; no line ending or charset reserialization
is used. A partial/malformed/duplicate/out-of-range literal fails the entire
operation. It cannot become a successful prefix or false sync tombstones.

`MailProvider.fetchMessage` cannot carry parse diagnostics. It therefore returns
a message only for a complete codec result, with typed failures for rejected,
unsupported, or partial projections. The account-free MIME API remains the
boundary for callers that need detailed partial-parse diagnostics.

## Mutation and lifecycle semantics

One provider instance allows one active operation. Every call opens a fresh
connection and loads current vault credentials. Operations have a finite total
timeout and poll the account lease for cancellation. The native connection retains
the original TCP socket during and after TLS negotiation. Abort closes that
socket even when the peer never answers ClientHello, settles the pending operation,
and rejects late socket/TLS completions. The provider never automatically replays
a command; retry timing is a host decision.

The fork's manual `connect(Socket)` path continues to support ordinary and
already-secure I/O. A default TLS upgrade of an externally supplied socket is
explicitly rejected because the SDK hides its TCP owner during the handshake.
Native upgrades must use `connectToServer`, as this provider does; controlled
fixtures can inject their connection and upgrade boundaries.

Read/flagged/delete operations verify the UID exists, use UID STORE, then read
that same UID's observed flags before reporting success. **Delete only sets
`\Deleted`; it never issues mailbox-wide EXPUNGE or CLOSE.** MOVE requires the
server's MOVE capability, stays within one account, and confirms source absence
after acknowledgment. The destination needs its own synchronization; this
adapter does not yet expose COPYUID destination identity mapping. An attempted
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

Additional real loopback tests exercise successful implicit TLS and STARTTLS,
peer-observed connection closure after stalled-handshake cancellation/deadlines,
default-trust rejection, and hostname mismatch rejection. A clearly labeled local
certificate is trusted only by injected test clients; production trust is unchanged.
Partial-write controls check queue ordering, final readiness, graceful close, and
abort of a blocked flush. These controls do not qualify live provider
interoperability or every operating system's socket implementation.

OAuth redirect/refresh integration and disposable-account interoperability remain
separate gates, as do discovered-UID pagination for large/sparse mailboxes,
IDLE/CONDSTORE/QRESYNC, SMTP/composition, the account-aware mailbox workspace,
actual browser persistence, and platform credential hosts.

Original package code is MIT. The native adapter uses the reviewed MPL-2.0
`third_party/enough_mail` fork; its new raw-fetch and lifecycle additions retain
MPL notices and are described in that fork's `QUDS_PATCHES.md`. No new hosted
runtime package is introduced by this workspace member.
