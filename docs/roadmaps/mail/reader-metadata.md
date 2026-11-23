# Reader metadata and raw headers

**Status:** implemented 23 November 2026 for every shared `MailMessageView`
host, including native IMAP, EWS, saved mail, archive and cached search.

## User path

The reader shows a compact metadata card above the body. On wide readers the
address fields occupy the left column and Date/Time is aligned in a right
column; narrow readers fall back to a single column. The card shows any observed:

- From;
- To;
- Cc;
- Bcc;
- Reply-To;
- Date and local time.

Empty fields are omitted. **Inspect headers** opens the received header block in
a selectable monospace dialog with a **Copy headers** action. The body remains
available in plain-text or formatted mode; the metadata card does not replace
the reader's find, copy, source or attachment actions.

## Bounds and safety

- The raw header dialog reads only the original message header block, never a
  network resource.
- At most the first 64 KiB of original bytes are decoded; malformed UTF-8 uses
  replacement characters instead of failing the reader.
- The header text is inert and selectable. It is not interpreted as HTML.
- Dates use the host's localized `MailReaderLabels.formatDate`, including time.
- Bcc is shown only when the received message actually contains it. The reader
  never invents missing recipients.
- Full raw source and hexadecimal views remain separate explicit host actions.

## Verification

- Focused reader metadata/raw-header and one-row-chrome tests: **2/2**.
- Full shared Mail UI suite: **302/302**.
- Reader actions remain in one horizontally scrollable row. Labels are shown
  only when the available width can carry them; otherwise the same actions use
  icon buttons with tooltips. Find and its match statistics share one row.
- Changed-file analysis and formatting: clean.

## Limits

- The metadata card is a display projection, not a full RFC header editor.
- Raw source/EML export remains a separate host action with its own byte bounds.
- Header display does not resolve authentication results, signatures or provider
  trust claims.
