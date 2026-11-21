# Loaded mailbox search and sorting

This increment extends the shared connected and cached mailbox list. It does
not change the independent archive's existing full-text search or saved searches.
It is one completed discovery slice toward M04W. The later
[foreground bulk read/flag increment](bulk-flags.md) builds on the same loaded
list; durable synchronization and commands, account-wide search and
conversations remain separate work.

## User path

Open an IMAP, EWS, Gmail or Microsoft 365 folder, or use **Cached mail** for a
verified account. Type a query in the message list. Open **Search help** for
localized examples and **Sort loaded messages** to change the local ordering.
English, German and Arabic have translated help, errors and controls; query
operator names are the same in every language.

| Query | Meaning |
| --- | --- |
| `quarterly report` | Both terms occur somewhere in the subject or sender |
| `"quarterly report"` | The complete phrase occurs in the subject or sender |
| `from:alice subject:"quarterly report"` | Sender contains Alice and subject contains the phrase |
| `to:team@example.test cc:reviewer` | Visible To and Cc header groups contain those values |
| `is:unread is:flagged` | Both observed flags match |
| `is:read` / `is:unflagged` | The corresponding observed flag is true / false |
| `after:2026-10-01 before:2026-11-01` | Local calendar day is strictly between those dates |
| `on:2026-10-15` | Local calendar day is exactly 15 October 2026 |

Text and field matching is case-insensitive substring matching. Whitespace
joins terms with AND. This replaces the earlier whole-query substring behavior:
quote a multiword phrase when adjacency matters. Quoted values allow escaped
quotes and backslashes. Uppercase bare `AND`, `OR` and `NOT`, negation, grouping
and wildcards are unsupported; quote reserved syntax to search it literally.
Unknown field names, incomplete syntax, impossible dates and invalid states
produce a localized error and no results. A bad query never falls back to a
broader search. Queries are limited to 1,024 UTF-16 code units and 32 terms.
Oversized pasted text remains editable and is rejected in full; predicates are
never silently removed by truncation. IME composing text/ranges are preserved.

Dates use the same local timezone conversion as the displayed header date.
Before/after exclude the entire named day. Unobserved read/flag values and
missing dates do not match those predicates. Quick Unread/Flagged chips remain
conjunctive with the query. Bcc, private transport envelopes and body text are
not added to searchable header fields.

## Scope, sorting and interaction

Search and sorting inspect only the current folder's loaded header window.
Connected hosts keep their existing explicit page loading and 1,000-row ceiling.
Cached lists cover the previously retained window. **Load more** remains
available when a valid filter has no matches and the provider has another page;
the user must invoke it explicitly. Search, sorting, focus and help never load
bodies, request provider pages, mark messages read, send mail or mutate storage.

Folder order remains the default and can be restored. Newest/oldest ordering
uses actual message instants; unknown dates remain last in either direction.
Sender/subject ordering uses case-insensitive lexical comparison. Equal keys
retain their input order. Sorting never changes the provider cursor or saved
cached order. A changed account/folder scope resets query, filters, ordering,
scroll position and focus; a compact reader/Back transition preserves them.

Row identities preserve keyboard focus and open-message identity through
reordering. Checked bulk selections have a separate lifetime: filters prune
hidden rows and refresh clears checks, as described in the
[bulk contract](bulk-flags.md). A hidden open message is not replaced
automatically. Stale pointer
callbacks cannot activate hidden rows, invalid-query results or a later scope
with overlapping row IDs; disposed callbacks are ignored. Only an explicit
valid row activation opens a body. Help preserves the originating language
direction and text scale, including narrow Arabic layouts.

## Implementation

- `quds_mail_core` exposes `MailHeaderSearchQuery` and typed parse failures over
  a provider-neutral `MailHeaderSearchDocument`; it has no Flutter/store/socket
  dependency. Parsing is bounded and performed once per edit. Candidate text
  and calendar dates are normalized lazily at most once per query match.
- `quds_mail_ui` owns query, filter, sort and keyboard state in the shared
  `MailMessageList`. Row/strings additions preserve existing constructors.
- Native IMAP, shared EWS/cloud and cached Studio hosts project the visible
  To/Cc names/addresses and typed dates from already-loaded envelopes. No new
  provider capability, authentication path, database migration or dependency
  is introduced.

The [local validation and integration record](../../validation/mail-header-search-20261120/README.md)
records actual commands, results, remote checkpoints and remaining boundaries.

## Next increments toward desktop-client parity

The [foreground bulk read/flag increment](bulk-actions.md) now freezes selected
account/folder/remote identities, reports confirmed, failed, uncertain and
unattempted outcomes, and stops on uncertainty or stale scope. It preserves the
nullable flag contract and does not introduce offline replay.

1. Durable repository-driven sessions, building on the completed
   [command journal](command-journal.md) and [uncertain-action checks](flag-recovery.md),
   with explicit completeness, synchronization ownership and offline/reconnect
   qualification.
2. Account/unified search, saved live views and conversations over the durable
   index, preserving explicit cache completeness and source-message identity.
3. Consistent archive/move/delete, broader bulk commands, rules and quick actions
   over those query/command contracts; rich authoring, signatures/templates and
   Office attachment workflows can progress separately.
4. Scheduling/Sent reconciliation, Calendar/People, shared mailboxes and security
   features retain provider-specific acceptance requirements in the main plan.

This ordering is an engineering decision, not a claim of complete competitor
parity. Official comparison references checked 20 November 2026:
[Thunderbird quick filters](https://support.mozilla.org/en-US/kb/quick-filter-toolbar),
[eM Client mail features](https://www.emclient.com/features-email), and
[classic/new Outlook capability comparison](https://support.microsoft.com/en-us/outlook/getstarted/feature-comparison-between-new-outlook-and-classic-outlook).
