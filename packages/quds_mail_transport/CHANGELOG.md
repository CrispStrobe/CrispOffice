# Changelog

## Unreleased

- Return authoritative move identities through an optional receipt port while
  preserving generic `apply`. Validate single-UID IMAP COPYUID without expanding
  UID sets; reject malformed/ambiguous evidence and retain generic confirmation
  when no mapping was supplied. EWS requests new IDs, confirms the exact new
  parent and original disappearance when applicable, and never derives a
  replacement from absence alone. Lost acknowledgements remain uncertain.

- Add read-only current-location observations for uncertain Move/Delete:
  exact IMAP source UID/generation and Deleted marker, Gmail's complete label
  set/Trash, and Graph/EWS parent folders with resolved Deleted Items IDs.
  Missing original identities never establish a destination or historical
  success. Checks use bounded metadata and preserve account/cancellation
  fences; unsupported factories access no credentials or network.

- Advertise recoverable Delete explicitly for IMAP, Exchange EWS, Gmail and
  Microsoft 365. IMAP marks only the selected UID as Deleted without expunge;
  the other adapters use their existing Trash/Deleted Items operations.
  Reject IMAP moves to the source folder, including INBOX case aliases,
  before credentials or network work. Preserve uncertain outcomes after a
  possibly accepted move/delete and never replay the command automatically.

- Observe current read/flag state without mutation for exact IMAP, EWS, Gmail
  and Microsoft 365 identities. Use bounded metadata reads, validate IMAP
  UIDVALIDITY and returned identity, reject incomplete flag observations, and
  distinguish exact-message absence from authentication/transport failures.
  Browser factories return explicit unsupported without accessing credentials.

- Retain uncertainty after a dispatched cloud mutation returns HTTP 410,
  stopping later flag commands until refresh. Preserve the independent Send
  rejection policy, with Gmail and Microsoft 365 regression coverage.

- Treat dispatched timeouts and unfamiliar client-error responses as uncertain;
  explicit request, authorization, resource, precondition and documented rate
  limit rejections certify no mutation. Preserve rate-limit retry guidance while
  foreground bulk coordination stops later dispatches without automatic retry.
- Preserve the separate submission rejection and Retry-After contract when
  classifying foreground flag mutations.

- Report explicit mutation-boundary evidence for failed IMAP, EWS, Gmail and
  Microsoft 365 operations. Foreground bulk commands can distinguish definite
  no-write failures from uncertain writes without guessing from a problem code.

- Add bounded newest-first IMAP header browsing with fixed initial UID ceilings,
  separately scoped descending cursors and explicit UIDVALIDITY conflicts.
  Ascending archive retrieval and durable synchronization remain independent.
- Keep first pages available for mailboxes larger than the discovery budget by
  searching bounded UID tail windows. Count and protocol byte limits remain
  unchanged; each page performs one SEARCH and at most one header FETCH. A small
  observed mailbox count permits a whole-range sparse search. Empty windows
  retain an explicit continuation while older ranges remain unexamined.
  SEARCH uses conservative protocol-line and aggregate-response headroom; the
  original connection-wide quota still rejects unusually large control or
  header replies without silently truncating a successful page.

- Add native Gmail API and Microsoft Graph providers with desktop browser PKCE,
  refreshable session tokens, verified mailbox ownership, bounded HTTP reads,
  folder/label browsing and incremental synchronization.
- Add confirmed actions, Graph moves, envelope-validated MIME sending, explicit
  rejected/uncertain outcomes and structured redacted diagnostics. No sends or
  mutations are automatically retried. Add a read-only cloud connection probe.
- Add `createMailEwsProvider` for Exchange Server on premises with explicit HTTPS
  configuration, NTLMv2/MIC/TLS channel binding, optional Basic or host-supplied
  bearer tokens, and current host-vault credential access per operation.
- Add bounded folder browsing, header retrieval, incremental `SyncFolderItems`,
  scoped revisioned cursors, expired-state recovery, and on-demand MIME reading.
- Add fresh-ChangeKey read/flag changes, move and move-to-Deleted-Items operations
  with post-write confirmation and no automatic replay.
- Submit prepared MIME through EWS `SendAndSaveCopy`, preserving Bcc envelope
  recipients and reporting uncertain writes without automatic retries.
- Keep browser EWS explicitly unsupported without vault or codec access. Add
  a password-prompted, read-only native endpoint probe and dedicated protocol,
  HTTP/TLS, NTLM, storage, lifecycle and JavaScript regression tests.

## 0.1.0

- Page bounded synchronization by strictly discovered UIDs across sparse/high
  UID spaces, retaining v1/v2 cursor continuation and fixed sweep ceilings.
- Advance a durable v3 page revision on every observation, including empty and
  completed sweeps, so stale pages cannot restore expunged data or overwrite
  newer flags. Reject revision exhaustion before protocol work.
- Reconcile typed UID ranges atomically through storage without invented-hole
  tombstones. Bound discovery by existing UID count and protocol bytes; retain
  an explicitly configured legacy numeric ceiling without applying one by default.
- Add manual account-scoped IMAP configuration, required TLS, current host-vault
  credential access, and capability-gated password/token authentication.
- Add bounded envelope synchronization with scoped durable cursors,
  UIDVALIDITY reset and nullable standard flags.
- Retain exact on-demand message literals through the MPL fork's strict raw UID
  FETCH API, with header/literal/line/response limits and fail-closed parsing.
- Add verified UID flag changes, mark-deleted behavior, capability-gated MOVE,
  write reconciliation, cancellation, timeouts, and late connection/TLS cleanup.
- Provide a socket-free browser entry that reports typed unsupported results.
- Add controlled protocol fixtures and provider/coordinator/SQLite integration
  controls, plus real loopback TLS success, trust, hostname, and stalled-handshake
  cancellation/deadline controls with retained TCP ownership.
- Preserve ordinary/already-secure manual socket I/O and Socket-returning
  overrides. The default owned transport provides the pending-TLS cancellation
  guarantee; custom socket factories retain their lifecycle responsibility.
  Live-account, OAuth-host, SMTP, broader
  platform interoperability, and mailbox UI gates remain separate and open.
