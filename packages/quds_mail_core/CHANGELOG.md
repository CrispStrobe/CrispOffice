## Unreleased

- Add `recipient:` (To/Cc) and `participant:` (From/To/Cc) header-search
  predicates for names and addresses. Preserve Boolean negation, phrase
  boundaries, bounded queries and the existing public-header scope; bare text
  still searches subject/sender. No provider work or schema change is required.

- Add immutable account-owned ordinary Archive settings and an optional
  persistence port. Preserve exact mailbox values and Unicode, reject foreign
  ownership and invalid metadata, and retain reset revisions for stale-write
  protection. A saved preference grants no live provider or message authority.

- Add explicit Gmail Inbox Archive to the durable foreground command model,
  retaining other labels and rejecting cross-provider, non-Inbox and invented
  destination plans. Archive outcomes retain the existing uncertain/no-replay
  contract. Expose an optional read-only Archive destination resolver so folder
  providers can freeze a reviewed ordinary folder in an existing Move plan.

- Add optional mutation receipts carrying validated authoritative Move identity
  transitions and canonical destination cache keys. Preserve generic provider
  and flag APIs; carry exact move evidence through the shared durable runner,
  reject mismatched/nonconfirmed evidence, and validate restored receipts.
  Add optional repository-only cursor revisions and a null-safe atomic sync
  snapshot port for local membership fencing. Coordinator and bounded runner
  preserve that optional capability while retaining legacy repository support.
  Retain local revisions before the first provider cursor; reject inconsistent
  cursor stamps and stale pages while allowing a fresh first synchronization.
  Preserve lease checks, cursor-cycle detection and acknowledged run progress.

- Add optional read-only membership observation with immutable exact identity,
  IMAP generation/deletion semantics, complete Gmail labels and Graph/EWS parent
  folders. Bound and validate provider evidence independently from command
  outcomes; an unavailable original identity never proves a moved destination.

- Extend the existing durable foreground runner to exact-destination move and
  recoverable delete commands. Retain legacy flag API names, strict frozen
  receipt restoration and no automatic replay. Expose flag-only action checks
  and a distinct recoverable-delete provider capability; confirmed membership
  commands require a fresh view because a unit receipt does not establish
  destination membership.

- Add immutable exact folder sets to saved header searches. Keep null as the
  legacy all-folders scope, preserve significant mailbox whitespace and retained
  display labels, and require nonempty unique folder identities representing
  every selected account. Bound folder counts and metadata, reject malformed
  Unicode, and require an explicit reset when changing back to all folders.
  Preserve the published `folderScopes` and `maxFolderScopes` names as aliases
  and retain the existing 200-folder ceiling.

- Add durable Outbox deadlines as canonical UTC instants, monotonic schedule
  revisions and exact due-time guards. Only never-attempted, certain queued
  entries can be scheduled; clearing a deadline retains its revision. Preserve
  frozen message content and schedule history through cancellation, submission,
  outcomes and interrupted recovery. Extend the repository save contract with
  optional schedule compare-and-set fencing for compatible legacy callers.

- Add immutable account-owned compose settings and ordered named Quick Text
  snippets. Bound text, names, count, aggregate metadata and revisions; reject
  malformed Unicode, controls and duplicate identities or case-insensitive names.
  Keep literal signatures and snippets separate from existing draft content.

- Add immutable, bounded saved-header-search definitions with validated Boolean
  queries, fixed exact account scopes, stable IDs and explicit revisions.
  Reject unpaired UTF-16 surrogates before UTF-8 storage can silently replace
  query, display-name or identity characters; preserve valid pairs unchanged.

- Extend loaded-header search with uppercase AND/OR/NOT, implicit AND,
  leading-minus negation and bounded parenthesis groups. Preserve literal
  field/quoted values, strict parsing and unknown flag/date observations
  through three-valued evaluation. Expose nesting/operator limits and typed
  malformed-expression/depth errors; retain the existing query/term limits.

- Add explicit bounded `MailBodyDownloadRunner` and an atomic complete-message
  cache port. Freeze canonical header identities, retain raw/body/attachment
  snapshots sequentially, skip existing complete cache entries on resume, and
  report immutable downloaded/cached/byte counts. Per-message and cumulative
  payload limits, account/folder guards and cancellation preserve acknowledged
  saves without retrying, mutating provider mail or advancing sync cursors.

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
