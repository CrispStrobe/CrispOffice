# Quds Mail core

Pure Dart contracts and implemented state machines shared by account-free saved
message readers and future connected-mail hosts. This package has no Flutter,
file, socket, credential-string, or `enough_mail` API dependency.

## Implemented

- Immutable saved-header-search definitions with bounded names, Boolean queries,
  exact nonempty account ID scopes and explicit revisions. The host resolves
  those IDs against its verified local directory before each new search; no
  result snapshot, continuation cursor or future account is captured implicitly.

- Bounded loaded-header search with fields, phrases, dates, observed flags and
  AND/OR/NOT expressions. Parentheses and leading-minus negation preserve
  unknown observations through three-valued evaluation. Queries admit at most
  1,024 UTF-16 code units, 32 predicates, 32 explicit operators and eight nested
  groups; matching consults no provider, repository or body.

- Owned immutable raw/attachment bytes, lazy SHA-256 integrity and exact export.
  Byte snapshots copy input once; exported views and their buffers are read-only.
- Typed header/body/attachment projections, parse statuses and redacted diagnostic
  records; full-open and preview limits including cumulative and rendering budgets.
- Immutable `MailMessageFlags` snapshots for read, flagged, answered, draft and
  deleted state. `MailHeaderRecord.flags == null` means the provider did not
  observe flags; an explicit empty snapshot means all five observed flags are
  false. Transient IMAP Recent state and provider keywords are outside this model.
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
- Frozen foreground read/unread/flag/unflag plans with per-message confirmed,
  failed, uncertain and unattempted outcomes. Optional `MailBulkFlagJournal`
  callbacks await durable intent, dispatch markers, outcomes and final receipts.
  A failed local write stops the remaining selection while preserving remote
  acknowledgements; a stale scope cannot authorize a later dispatch.
- `MailImapSyncRange` marks an inclusive, fully observed UID range in one mailbox
  and UIDVALIDITY. The page's upserts are its authoritative survivors; the store
  reconciles absent existing memberships without inventing rows for numeric UID
  gaps. Range values and every supplied identity are validated before use.
- Segregated provider, submission, composition, repository, vault, attachment,
  external-resource, lifecycle and notification ports. The default external
  resource policy denies all actions without IO.

```dart
final bytes = MailBytes(inputBytes); // Enforce the byte budget before this copy.
final message = MailMessage(raw: bytes, envelope: MailEnvelope(subject: 'Example'));
final original = message.raw.copyBytes(); // Exact octets; independently writable.
```

`MailBulkFlagJournal` contains no storage implementation. Its `prepare`,
`beginAttempt`, `recordResult` and `finish` methods must commit before returning
success. The runner checks the original lease and view after each awaited
pre-dispatch callback, records settled provider evidence even when the view
retires, and never retries. `persistenceProblem` remains separate from remote
outcomes, so a confirmed command is still confirmed when its receipt could not
be saved. The store implementation recovers a surviving applying marker as
uncertain after restart. `MailBulkFlagReport.restore` validates a saved report's
frozen identities, desired values and order; it does not execute the plan.

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
