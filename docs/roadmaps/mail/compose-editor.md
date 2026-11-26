# Mail compose editor

**Status:** rich composition continuation, 25 November 2026.

The composer continues to use the shared Word editor so it keeps the existing
draft, undo, IME, signature, Quick Text and recovery contracts. The Mail host uses a flowing message surface with bounded rich formatting and
matching plain/HTML alternatives. Its existing editing behavior is retained:

- the body editor autofocuses when the composer opens;
- the caret is placed at the end of the existing draft;
- the caret is visible and retains focus after Enter creates a new paragraph;
- the body page reflows to the available composer width without replacing the
  controller, input connection, selection or undo history;
- plain-text reading and quotation normalize CRLF and bare CR to LF while the
  original bytes remain available through Raw Source/export.

## Earlier editor verification — 22 November 2026

- `studio_mail_draft_autosave_test.dart` now checks autofocus, a visible caret,
  Enter creating a second paragraph and focus remaining on the body.
- `quds_mail_ui` verifies that CRLF and bare CR are normalized without losing
  paragraph breaks.
- Full `quds_mail_ui` suite passes after the line-ending change.

## Rich composition continuation

[Durable rich composition](rich-composition.md) adds bold, italic, underline,
strikethrough, safe links, alignment and paragraph direction, with undo/redo
and English/German/Arabic controls. Supported formatting survives autosave,
database recovery, MIME and Outbox edit-copy. Empty-paragraph typing styles
created by Word's integrated Enter behavior are retained.

Unsupported structures produce a visible recovery state before they can be
flattened by saving. The current [qualification record](../../validation/mail-rich-compose-20261125/README.md)
separates executed pure-Dart/SQLite and static checks from authored Flutter
widget tests and remaining installed-client acceptance. Received HTML still
uses the distinct safe reader renderer described in
[html-rendering.md](html-rendering.md).
