## Unreleased

- Add `MailProviderKind.ews` for account-scoped opaque Exchange ItemIds, retaining
  existing provider names and enum positions. ChangeKey remains a concurrency
  token outside stable message identity.
- Add immutable durable standard message flags and nullable header snapshots.
  An unobserved snapshot is distinct from an observed empty flag set.

## 0.1.0

- Require cursor comparison inside sync transactions so concurrent stale pages
  cannot overwrite a newer committed mailbox state.
- Introduce independently implemented MIT portable Mail domain models and ports.
- Preserve exact immutable message/attachment bytes and typed parsing budgets.
- Add profile/account scoping, cooperative cancellation and stale callback guards.
- Add tested immutable outbox transitions and bounded transactional sync-page
  coordination, with explicit uncertain and unsupported outcomes.
