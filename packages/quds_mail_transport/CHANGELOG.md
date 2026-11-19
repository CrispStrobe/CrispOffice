# Changelog

## 0.1.0

- Add manual account-scoped IMAP configuration, required TLS, current host-vault
  credential access, and capability-gated password/token authentication.
- Add bounded UID-window envelope synchronization with scoped durable cursors,
  UIDVALIDITY reset, nullable standard flags, and explicit high-UID scan limits.
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
