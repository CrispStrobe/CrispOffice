## Unreleased

- Add bounded foreground `MailSyncRunner` with immutable partial-progress
  receipts, persisted-cursor resume, cancellation across an entire run and
  explicit completed/paused/cancelled/failed outcomes. Reuse atomic sync-page
  coordination, reject cursor cycles before commit, sanitize external failures
  and isolate progress observers. No automatic retry or submission is introduced.

- Add optional `MailFlagObserver` and typed current-state observations for exact
  message identities. Distinguish present flags, an unavailable identity and
  an invalidated IMAP generation without claiming an earlier command succeeded
  or authorizing its replay. Existing provider implementations remain compatible.

- Add an optional awaited `MailBulkFlagJournal` lifecycle to the shared runner
  and coordinator. Persist the frozen intent and dispatch marker before network
  work, recheck scope after each awaited write, and retain each result before
  continuing. Persistence failures stop further dispatch without erasing known
  provider acknowledgements. Expose separate persistence problems and validated
  read-only receipt restoration; no retry or background replay is introduced.

- Add bounded foreground bulk read/flag plans and sequential, single-use
  coordination. Every frozen identity has a confirmed, definitely failed,
  uncertain or unattempted outcome. Stop on uncertainty, cancellation or stale
  scope; preserve in-flight receipts without authorizing stale publication.
  Preserve immutable progress snapshots and optional stop-after-current checks.
  Add explicit optional mutation-boundary evidence to problems and map provider
  results conservatively: only certified no-mutation failures are definite.
  Recheck leases after caller guards, preserve uncertainty when a certificate
  contradicts mutation evidence, and require refresh after invalidated scopes.
  Stop the remaining selection on certified quota rejection without automatic
  retry, preserving provider retry guidance and requiring no uncertainty refresh.
- Add bounded frozen foreground bulk read/flag plans and sequential execution
  with confirmed, definite failed, uncertain and unattempted per-message results.
  Stop on uncertain writes or stale/cancelled scope without retrying. Add explicit
  optional mutation-boundary evidence to problems; unknown evidence stays uncertain.
  Preserve the concurrent coordinator API through the same dispatch engine:
  certified attempts, single-use coordination, optional provider validation,
  public `operationAt`, operation-bearing receipts and typed stop reasons. Use
  stable `planId:index` operation IDs and nonblank plan IDs up to 256 characters.
  Uncertainty takes precedence over simultaneous stop or scope changes.
  Expose `MailBulkFlagAttempt.fromResult` as the shared provider-evidence
  adapter used by the runner and certified coordinator integrations.

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
