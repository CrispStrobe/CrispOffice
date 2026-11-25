# Durable rich composition

## Intake and scope — 25 November 2026

This continuation starts from `938832e6dc337a880c15c609aeed95b643379da7`
on PR #396 (`codex/mail-capabilities-20261125`). It preserves that increment's
sender identities, templates and connected provider search. Main was inspected
at `7839eb004f33adc84d4db018e54f032959bb6a03`; its two subsequent commits affect
the Office XML scanner, outside this mail change.

Before this continuation, the composer used the Word editing surface but kept
only paragraph text in its snapshot. Draft storage consequently saved only
`MailBody.plainText`, MIME escaped that text into HTML, and the Outbox editor
rejected any other HTML.
Formatting commands alone would therefore lose authored content on save or send.

## Audit of the existing capability set

| Area | Existing foundation | This continuation |
| --- | --- | --- |
| Accounts/providers | IMAP/SMTP, EWS, Gmail and Microsoft 365; verified remembered-account navigation; one connected account at a time | Preserves the existing account and submission routing |
| Mailbox/offline | Header synchronization, cached bodies, journaled flags/Move/Delete/Archive, recovery for uncertain outcomes | No provider or synchronization changes |
| Discovery | Header/participant/Boolean and cached-body search, saved scopes, conversations, local tags/rules; PR #396 adds other provider-search adapters | No competing search implementation |
| Composition | Word editing surface, To/Cc/Bcc, reply/forward, attachment snapshots, signatures, Quick Text; PR #396 adds identities and plain full-message templates | Supported formatting now survives the complete composition lifecycle |
| Sending | Frozen MIME and private envelope, explicit foreground send/retry, uncertain-outcome recovery, scheduling/Undo | Existing immutable bytes and Bcc semantics preserved; rich edit-copy and inert review added |

The highest-value bounded gap was formatting fidelity across layers. A toolbar
alone would have left stored drafts and queued copies lossy. Provider Sent/Drafts
reconciliation and simultaneous live accounts remain valuable but require
separate provider and lifecycle contracts.

## Implemented end-to-end contract

The implementation introduces a bounded, immutable compose-body model with
plain text and deterministic inert HTML derived from the same paragraphs/runs.
It supports bold, italic, underline, strikethrough, explicit safe links,
paragraph alignment and text direction. Its versioned canonical HTML is the
durable representation. Arbitrary received or pasted HTML is not a trusted
editable representation.

Studio uses its existing Word RenderBox editor and undo commands. Snapshots
detect formatting-only changes and preserve supported formatting through
autosave, close/reopen, signatures/Quick Text, MIME and Outbox edit-copy. Template
replacement remains an explicit whole-message replacement. Saving a formatted
message into the existing plain-template system requires a separate confirmation
that the template keeps text; the source draft retains its formatting. Applying
a template resets old styles, links, attachments, threading and undo history.
Existing plain drafts and frozen plain Outbox messages remain compatible.

Both plain text and HTML are bounded and must agree. Unknown/corrupt rich state
fails visibly instead of silently flattening to text. The existing core and
SQLite draft body already have an HTML field, so there is no schema migration.
The frozen Outbox bytes, Bcc/private-envelope split and submission uncertainty
rules remain authoritative.

### Supported authoring surface

The toolbar provides bold, italic, underline, strikethrough, explicit links,
left/center/right/justified alignment, paragraph direction and undo/redo. Labels,
feedback and link dialogs are localized in English, German and Arabic.

HTTP/HTTPS links and simple mailto addresses are explicit authored links.
Relative/local/executable URLs, credentials, control characters and mailto
query parameters are refused. A delayed link dialog is fenced by the original
compose owner, selection and edit revision. Reopening a draft never fetches
the target.

Unsupported Word blocks, lists, fields, hidden stories, imported packages and
formatting are refused before a text-only snapshot can erase them. The composer
retains editable work and the existing undo/save-recovery flow. Inconsistent
initial rich/plain input cannot overwrite saved work.

### Limits and persistence

| Rich body limit | Value |
| --- | ---: |
| UTF-8 plain text | 1 MiB |
| Canonical HTML | 4 MiB |
| Paragraphs | 4,096 |
| Runs | 16,384 |
| UTF-8 link | 2,048 bytes |

Model limits do not bypass configured store quotas. Both alternatives count
toward the existing draft metadata quota. A failed save retains the earlier
durable revision and current editor; a regression covers this boundary.

Unformatted drafts bypass rich HTML/structural limits. Existing unfinished
plain drafts retain the repository's persistence budget independently of the
stricter 1 MiB submission budget. Inferred Arabic direction does not silently
opt a legacy plain draft into rich limits; explicit direction/formatting does.
Unicode, CRLF split across runs, soft breaks and empty paragraphs round-trip.

### Outbox review and edit-copy

The MIME-shape validator still rejects unexpected parts, hidden headers,
unrepresented attachments and arbitrary HTML. A non-plain HTML alternative must
parse as the exact canonical format and match the normalized plain alternative
before it can become an editable copy. Atomic handoff and uncertain-submission
restrictions remain unchanged.

Formatted review uses inert Flutter text spans with no HTML renderer, link
recognizer or resource loader. Preview work is bounded to 64 KiB of UTF-8 text,
256 paragraphs and 2,048 runs. Clipping never splits a surrogate pair and is
reported explicitly. It cannot change exact EML or private-envelope exports.

## Remaining work

Lists, tables, inline images, arbitrary HTML import, background delivery and
provider Drafts/Sent synchronization remain outside this increment. No
placeholder capability is advertised for them.

After installed/widget acceptance, useful next increments are rich-template
storage, image/CID authoring with deterministic multipart/related MIME, and
explicit read-only Sent observations. A Sent observation must not be described
as recipient delivery or permission to resend an uncertain message. Retained
multi-account sessions require separate storage-owner and cancellation work.

## Qualification

Incremental source checkpoints are on `codex/mail-rich-compose-20261125`.
The [validation record](../../validation/mail-rich-compose-20261125/README.md)
contains executed checks, source fingerprints and remaining acceptance gates.

The executor has a small disk budget. A minimal official Dart 3.13.7 runtime
executes pure-Dart source/tests with actual locked dependencies and the package's
genuine SQLite native library. A full Flutter runtime is unavailable. Widget
tests are supplied separately from execution. Source-only Flutter analysis uses
the pinned framework and sky_engine sources; it does not establish rendering,
interaction, installed application or live-client acceptance.
