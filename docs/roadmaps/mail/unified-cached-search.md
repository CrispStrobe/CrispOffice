# Search saved mail across folders and accounts

This increment takes the existing Boolean header query beyond the currently
loaded folder window. The native local-account chooser offers **Search saved
mail** across its listed accounts, or one selected account. It reads the existing
SQLite caches for IMAP/SMTP, EWS, Gmail and Microsoft 365 without signing in or
contacting a mail server.

## User workflow

1. Open the local-account chooser and choose **Search saved mail**.
2. Choose all listed accounts or a single account. Provider-specific account
   choosers retain their provider scope.
3. Enter a query and choose **Search**. An empty query lists saved headers.
4. Choose **Search more** while local candidates remain. A bounded scan can
   find no matches while more saved mail remains to inspect.
5. Select a result to open its retained body. A message without saved bytes
   explains that it needs to be downloaded after reconnecting.

Results show their account and observed folder/label provenance. A canonical
message appears once per account even if it has several labels. Equal local
message IDs or RFC Message-IDs in different accounts remain separate results.
Search is ordered by account identity and stable local message ID; it does not
claim global date or relevance ordering. The UI retains at most 1,000 matches
and asks for a narrower query when that display budget is reached while more
candidates remain.

The query language is the same as [loaded-header Boolean search](boolean-search.md):

| Example | Meaning |
| --- | --- |
| `(from:alice OR from:bob) is:unread` | Saved unread messages from either sender |
| `subject:"quarterly report" NOT is:flagged` | Matching subject with an observed unflagged state |
| `to:team@example.test cc:manager` | Both recipient conditions |
| `after:2026-10-01 before:2026-11-01` | Dates strictly between the named local calendar days |
| `NOT (subject:invoice OR subject:receipt)` | Exclude either subject |

The entire query is validated before any account is opened. Uppercase AND/OR/NOT,
implicit AND, minus negation, parentheses, quoted phrases and existing bounds
are unchanged. Unknown flags/dates remain unknown under negation. Bcc, bodies
and attachment text are outside this header-search contract. The independent
[archive search](archive-search.md) retains its own collected-content index.

## Coverage and partial results

The searchable set is the union of retained synchronization memberships and
current saved browse-window memberships. Orphaned cached bodies, drafts and
Outbox records are not additional search candidates. Current browse windows
and synchronized memberships are deduplicated by their canonical message ID.
Older valid synchronization memberships can exist without a recorded checkpoint;
they are searchable but do not acquire an invented completion time.

Coverage preserves each source's capture/synchronization time and provider
continuation flag. Completing the local scan says that all eligible saved
headers in the selected cache were inspected. It does not certify the server's
current state, unvisited folders, unsynchronized messages or body availability.
Accounts are separate snapshots, not one atomic cross-account server view.

An unavailable, busy, removed or corrupt account has an explicit failed coverage
entry. Other selected accounts can still be searched. Failure is never displayed
as a successfully empty mailbox. Retry starts a fresh search. A query or account
scope change immediately retires the old results and reader callbacks.

## Repository and ownership contract

`SqliteMailRepository.searchCachedHeaders` accepts an account, the original query
and optional opaque continuation. Each transaction inspects at most the configured
scan limit (500 by default; maximum 1,000) and returns at most the result limit
(100 by default; maximum 200 subject to store limits). Candidate text and folder
metadata are bounded before transfer and decoding. Matching reuses the portable
`MailHeaderSearchQuery` evaluator; no SQL approximation changes Unicode,
Boolean, unknown-observation or local-calendar semantics.

Pagination uses a stable local-ID key. A zero-hit page still returns continuation
when candidates remain. The cursor binds the exact query, account, repository
owner and committed content generation. A successful repository domain write or
reopen invalidates it; the caller restarts instead of silently skipping or
duplicating a changed result set. A rolled-back transaction does not invent a
committed generation. Cursors are intentionally not persisted.

The Studio adapter serializes the query through its existing draft/cache owner.
The cross-account session keeps one search owner open between pages, closes it
before moving to the next account, and uses a temporary owner for explicitly
reading a result from a completed account. The non-secret account directory is
revalidated before access and publication. Reads verify account, provider,
local ID and remote identity. Close fences late completions, drains operations
and releases both owners. A close failure remains visible and retryable.

The search route invokes no transport, credential, draft-editor or submission
operations. The repository query performs no writes and reads no
body/blob/draft/Outbox payload. Opening an account still performs the existing
profile/account initialization and interrupted-operation recovery; those
opening steps can update local metadata and recovery records before the query.
No database migration, dependency change, network search or new automatic send
is introduced by cached search.

## Qualification

The work record is [mail-unified-cache-20261121](../../validation/mail-unified-cache-20261121/README.md).
It records the integrated source checkpoint, local runtime, raw commands and
actual test results. The preceding Boolean implementation's original unexecuted
record remains historical; fresh execution is recorded separately here.

The captured intake includes all 24 starting fork branches, all 300 pull-request
heads and four upstream branches/four upstream pull requests. New Word VBA text
functions are preserved with main's newer Mail behavior, including both Boolean
regression suites. The [intake proof](../../validation/mail-unified-cache-20261121/intake.md)
explains exact ancestry and historical equivalence. Current refs are refreshed
again before the final merge. GitHub Actions are not an acceptance dependency.

## Next parity increments

| Order | Increment | Acceptance boundary |
| --- | --- | --- |
| 1 | Saved live searches and broader discovery | Durable account/folder scope and query; refresh/change streams; body-index coverage; no stale result actions |
| 2 | Conversation grouping and a shared unified workspace | Stable thread identities, cross-folder navigation, clear account provenance, reader/composer lifecycle and usable large-mailbox pagination |
| 3 | Durable archive/move/delete and rules | Persist intent before provider work; distinguish confirmed, failed and uncertain results; deterministic preview/order/recovery |
| 4 | Rich composition and sending workflow | Signatures/templates, supported HTML alternatives, durable undo delay and scheduling, provider Sent reconciliation |
| 5 | Broader interoperability and release qualification | OAuth lifecycle, authorized disposable-account testing, installed-platform/browser persistence gates, migration and supported security formats |

These priorities are engineering choices informed by the documented workflows
in [Thunderbird global search](https://support.mozilla.org/en-US/kb/global-search),
[Outlook Search Folders](https://support.microsoft.com/en-us/outlook/mail/use-search-folders-to-find-messages-or-other-outlook-items)
and [eM Client mail features](https://www.emclient.com/features-email), reviewed
21 November 2026. They are product benchmarks, not a claim of identical syntax,
provider coverage or complete parity.
