# Mail compose editor

**Status:** corrected 22 November 2026.

The composer continues to use the shared Word editor so it keeps the existing
draft, undo, IME, signature, Quick Text and recovery contracts. The mail host now
treats it as a disposable plain-text body surface rather than a paper document:

- the body editor autofocuses when the composer opens;
- the caret is placed at the end of the existing draft;
- the caret is visible and retains focus after Enter creates a new paragraph;
- the body page reflows to the available composer width without replacing the
  controller, input connection, selection or undo history;
- plain-text reading and quotation normalize CRLF and bare CR to LF while the
  original bytes remain available through Raw Source/export.

## Verification

- `studio_mail_draft_autosave_test.dart` now checks autofocus, a visible caret,
  Enter creating a second paragraph and focus remaining on the body.
- `quds_mail_ui` verifies that CRLF and bare CR are normalized without losing
  paragraph breaks.
- Full `quds_mail_ui` suite passes after the line-ending change.

The editor is still a plain-text mail body. Formatted HTML composition remains
a separate future increment; the safe reader renderer is described in
[html-rendering.md](html-rendering.md).
