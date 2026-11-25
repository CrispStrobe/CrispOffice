# Provider-side folder search

**Status:** IMAP implementation 23 November 2026. The
[25 November adapters](provider-search-adapters.md) add EWS, Gmail and Microsoft
365 search through a shared typed port and the native Studio dialog. This page
retains the original IMAP contract and live evidence; the new adapters have
separate field/count semantics and live-qualification gates.

## User path

Connected native IMAP Mail now exposes **Search on server** in the View ribbon.
The dialog chooses one field — message body, subject, From or To — a text term
and an optional received-date range (any time, last 7, 30 or 90 days). Searching covers the currently selected folder at the provider's current
snapshot, shows the total match count and displays the first 50 envelope rows.
Opening a row loads that message through the normal reader, body cache and safe
HTML path.

## Coverage contract

- Exactly one selected folder is searched. Other folders and the unified/local
  cache are not included.
- A received-date range narrows the provider-side search; it does not filter
  downloaded rows locally.
- Body search is performed by the IMAP server, not by downloading every body.
  Provider indexing and server capabilities determine what body text matches;
  attachment text is outside the search.
- The result count is the provider's match count. At most 50 rows are returned;
  `truncated` explicitly means more matches exist than are shown.
- A row must have a UID. Search never fabricates a result or silently falls back
  to a local substring filter.
- Results do not change flags, read state, folders or membership.
- The query is 1–512 characters and rejects control characters. No raw IMAP
  grammar is accepted; this slice searches one field at a time.

## Cancellation and failure

Stopping requests cooperative cancellation. enough_mail cannot abort an
already-written `SEARCH` command, so the dialog keeps a bounded progress state
until that command returns; the result is then discarded and no later page or
row is adopted. Closing the dialog cancels adoption immediately. A provider or
protocol failure shows a generic error and preserves the folder and messages.

## Verification

- Server-search dialog behavior: **3/3** (run with a 30-day range, invalid
  input, stop/discard).
- Live mailbox.org test: connected over IMAP, fetched envelope rows, searched a
  real selected folder by From within the last 30 days, verified match rows have
  UIDs, searched body text taken from a downloaded plain-text message, and
  verified an already cancelled token throws before doing work.
- Changed-file analysis and formatting remain clean.

## Limits

- This original implementation is IMAP-specific. EWS/Gmail/Microsoft 365 now
  use the [shared optional search port and provider adapters](provider-search-adapters.md),
  with only their supported fields exposed in Studio.
- One field and one literal term; Boolean operators, date ranges, attachment
  text and multi-folder scope remain subsequent work.
- Server-side indexing is not guaranteed. A zero result is evidence only for
  the provider's searchable content, not proof that a message is absent.
- In-flight IMAP `SEARCH` commands are not hard-cancelled by the current
  enough_mail client.
