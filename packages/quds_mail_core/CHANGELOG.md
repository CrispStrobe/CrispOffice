## Unreleased

- Add bounded foreground bulk read/flag plans and sequential, single-use
  coordination. Every frozen identity has a confirmed, definitely failed,
  uncertain or unattempted outcome. Stop on uncertainty, cancellation or stale
  scope; preserve in-flight receipts without authorizing stale publication.
  Adapt provider mutation evidence through the same coordinator, with immutable
  progress and per-message reports; absent evidence remains uncertain.

- Add bounded portable loaded-header search with field-scoped text, quoted
  phrases, observed read/flag states and strict local-calendar date predicates.
  Queries are conjunctive, reject unsupported syntax explicitly and never fetch
  bodies or infer unknown observations.

- Add explicit terminal `closedUncertain` Outbox state: stop retries locally while retaining possible acceptance, frozen content and attempt information. Expose guarded closure and terminal-cleanup eligibility.

- Add explicitly acknowledged outbox retries with a durable earlier-uncertainty
  guard. A later definite rejection cannot enable ordinary retry or cancellation
  after a possibly accepted submission; inherited composer uncertainty is kept.

- Add the optional `MailImapHeaderBrowser` port for descending foreground pages
  bound to an explicit mailbox generation, independent of durable sync cursors.

- Add optional typed draft editor state for lossless unfinished recipient text,
  durable submission uncertainty and revision-preserving cleared markers.

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
