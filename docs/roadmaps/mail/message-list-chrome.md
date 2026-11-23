# Compact message-list chrome

**Status:** implemented 23 November 2026 in the shared Mail message list.

## Layout contract

The normal, non-batch mailbox header uses two rows:

1. **Search row** — loaded-mail search field, Filters button and search help.
2. **Stats/controls row** — compact `selected / shown / loaded` numbers, sort,
   Select shown, Clear selection, keyboard-help and bulk-actions controls.
   Each number has its own tooltip explaining its meaning.

The Unread, Flagged and Conversations FilterChips open from the Filters button
only when requested. The previous separate scope-count row and wrapped
selection row are gone. Batch progress/result and Stop appear only while a
batch is active, so they cannot consume normal mailbox height.

## Infinite scrolling

Studio's native IMAP and EWS hosts enable automatic pagination. Reaching near
the end requests the next page; the explicit **Load more** button is replaced by
a small progress indicator. If no user scroll occurs, the fallback remains
available on non-auto hosts. Auto-load never runs twice for the same page and
re-arms when page contents change.

At narrow widths the selection group is scaled down to remain on the controls
row rather than wrapping into more vertical rows. Search remains usable and the
scope count ellipsizes instead of forcing another line.

## Verification

- Header two-row and auto-load regressions: **2/2**.
- Full shared Mail UI suite: **306/306**.
- Native IMAP/EWS/cloud host regression: **201/201**.
- Changed-file analysis and formatting: clean.

## Limits

- Header search still applies only to loaded rows; it is not a provider search.
- Batch progress remains a separate conditional row while work is running.
