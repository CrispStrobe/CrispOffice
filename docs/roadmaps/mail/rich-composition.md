# Durable rich composition

## Intake and scope — 25 November 2026

This continuation starts from `938832e6dc337a880c15c609aeed95b643379da7`
on PR #396 (`codex/mail-capabilities-20261125`). It preserves that increment's
sender identities, templates and connected provider search. Main was inspected
at `7839eb004f33adc84d4db018e54f032959bb6a03`; its two subsequent commits affect
the Office XML scanner, outside this mail change.

The current composer uses the Word editing surface, but its snapshot keeps only
paragraph text. Draft storage consequently saves only `MailBody.plainText`, MIME
creates HTML by escaping that text, and the Outbox editor rejects any other HTML.
Formatting commands alone would therefore lose authored content on save or send.

## End-to-end contract

The implementation will introduce a bounded, immutable compose-body model with
plain text and deterministic inert HTML derived from the same paragraphs/runs.
It will support bold, italic, underline, strikethrough, explicit safe links,
paragraph alignment and text direction. Its versioned canonical HTML is the
durable representation. Arbitrary received or pasted HTML is not a trusted
editable representation.

Studio will use its existing Word RenderBox editor and undo commands. Snapshots
must detect formatting-only changes and preserve supported formatting through
autosave, close/reopen, signatures/Quick Text, MIME and Outbox edit-copy. Template
replacement remains an explicit whole-message replacement. Existing plain drafts
and frozen plain Outbox messages remain compatible.

Both plain text and HTML are bounded and must agree. Unknown/corrupt rich state
must fail visibly instead of silently flattening to text. The existing core and
SQLite draft body already have an HTML field, so no schema migration is planned.
The frozen Outbox bytes, Bcc/private-envelope split and submission uncertainty
rules remain authoritative.

Lists, tables, inline images, arbitrary HTML import, background delivery and
provider Drafts/Sent synchronization are outside this increment. These need
additional editing, MIME or provider contracts; no placeholder capability is
advertised for them.

## Qualification record

Incremental source checkpoints are kept on
`codex/mail-rich-compose-20261125`. Executed checks and remaining acceptance
boundaries will be recorded in
`docs/validation/mail-rich-compose-20261125/README.md`.

The current executor has a small disk budget. A minimal official Dart 3.13.7
runtime is available; Flutter is not installed. Pure-Dart source and tests will
be exercised in an isolated harness using actual dependencies. Widget tests
will be added, with execution reported separately rather than inferred from
source inspection or earlier PR test totals.
