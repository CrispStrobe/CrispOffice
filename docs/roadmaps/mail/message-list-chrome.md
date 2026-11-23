# Compact message-list chrome

**Status:** implemented 23 November 2026 in the shared Mail message list.

## Layout contract

The normal, non-batch mailbox header uses two rows:

1. **Search row** — loaded-mail search field, honest shown/loaded count and
   search help.
2. **Controls row** — Unread, Flagged and Conversations filters, sort, selection
   count, Select shown, Clear selection, keyboard-help and bulk-actions controls.

The previous separate scope-count row and wrapped selection row are gone. Batch
progress/result and Stop appear only while a batch is active, so they cannot
consume normal mailbox height.

At narrow widths the selection group is scaled down to remain on the controls
row rather than wrapping into more vertical rows. Search remains usable and the
scope count ellipsizes instead of forcing another line.

## Verification

- Header two-row position regression: **1/1**.
- Full shared Mail UI suite: **303/303**.
- Changed-file analysis and formatting: clean.

## Limits

- Header search still applies only to loaded rows; it is not a provider search.
- Batch progress remains a separate conditional row while work is running.
