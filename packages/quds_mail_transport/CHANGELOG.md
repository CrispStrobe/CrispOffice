# Changelog

## Unreleased

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
