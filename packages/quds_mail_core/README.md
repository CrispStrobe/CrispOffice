# Quds Mail core

Pure Dart contracts and implemented state machines shared by account-free saved
message readers and future connected-mail hosts. This package has no Flutter,
file, socket, credential-string, or `enough_mail` API dependency.

## Implemented

- Owned immutable raw/attachment bytes, lazy SHA-256 integrity and exact export.
  Byte snapshots copy input once; exported views and their buffers are read-only.
- Typed header/body/attachment projections, parse statuses and redacted diagnostic
  records; full-open and preview limits including cumulative and rendering budgets.
- Host/profile/account/IMAP identity isolation; UIDVALIDITY is part of persistent
  IMAP identity. Content hashes and Message-ID headers are not local primary keys.
- Independent Mail/Calendar/People capability flags and explicit typed failures.
- Cooperative cancellation and account generation leases. Dispose/invalidate
  rejects pending callbacks after asynchronous work.
- Immutable outbox transitions. Freeze wire bytes, envelope and draft revision;
  persist `beginAttempt` before network submission. A crash during submission or
  possible acceptance is `uncertain` and never retries automatically. The
  all-or-abort recipient policy distinguishes RCPT acceptance from submission.
- A bounded sync-page coordinator with injected provider/repository/session. The
  repository atomically commits records and cursor and rechecks its lease inside
  the transaction. Tests use a deterministic in-memory transaction fixture.
- Segregated provider, submission, composition, repository, vault, attachment,
  external-resource, lifecycle and notification ports. The default external
  resource policy denies all actions without IO.

```dart
final bytes = MailBytes(inputBytes); // Enforce the byte budget before this copy.
final message = MailMessage(raw: bytes, envelope: MailEnvelope(subject: 'Example'));
final original = message.raw.copyBytes(); // Exact octets; independently writable.
```

The saved-message `MailCodec` only parses. Canonical composition is negotiated
through the separate `MailComposer` port. An application cannot infer send
support from the presence of a reader. Accountless parsing has no account or
repository prerequisite.

## Contract limits

Ports are contracts, not working authentication, persistent storage or network
adapters. The core does not claim an SMTP implementation, durable recovery,
Google/Microsoft connectivity, Calendar support, or platform release readiness.
A result of `submitted` means acceptance by a submission server, never final
recipient delivery. Missing per-recipient provider responses remain unknown.

Mail HTML and decoded addresses remain untrusted display data. The reader must
sanitize HTML, apply direction isolation, and mediate external actions. A codec
must validate `MailReadBudget` and enforce its limits before allocation and during
processing; models alone do not make parsing bounded. `MailDiagnostic.message`
must contain fixed explanations, never source headers, bodies or credentials.

## Validation

From the root workspace after dependency resolution, run:

```sh
cd packages/quds_mail_core
dart analyze --fatal-infos
dart test
dart compile js test/compile/portable_import.dart -o build/core.js
node build/core.js
```

The portable harness uses only this public package entry. Focused tests cover
immutable byte aliases, profile/account/mailbox isolation, stale callbacks,
all-or-abort recipient outcomes, interrupted and uncertain outbox attempts, and
cursor/data transaction failure. JavaScript compilation is a separate real gate.
