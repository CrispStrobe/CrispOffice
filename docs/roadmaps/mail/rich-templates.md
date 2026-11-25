# Rich message templates

## Scope — 25 November 2026

This continuation extends the canonical [rich composition](rich-composition.md)
body into reusable full-message templates. It follows the initial rich composer,
draft, MIME and Outbox implementation on PR #397. The source includes main
through `1eb5a9af54d97732696057dffae1d29d5b76074f`.

The preceding increment's plain-template conversion confirmation is replaced
by lossless preservation of supported formatting. The source draft remains
independent of the reusable template.

## Authoring and reuse

1. Compose and format a message with the existing Mail controls.
2. Choose **Save as template**, give the template a unique name, and review its
   recipients, subject, body and optional sender. The custom Word body editor
   retains the snapshot's supported formatting.
3. Save the account-settings revision. Reopening Writing tools or restarting
   the account restores the template's canonical body.
4. Choose **Use template** in a composer and confirm whole-message replacement.
   The selected template's body and sender replace the draft's content.

Saving a template does not change the live draft, its attachment objects, reply
threading or Bcc. Templates contain recipients, subject, body and optional sender
identity only; they do not contain attachments, delivery instructions or thread
identity. Applying a template creates an independent message and clears the
previous document, old formatting, links, undo history, attachments and threading.
It does not send or queue the message.

Template metadata edits and text edits preserve the body through the checked
Word converter. Unsupported Word structures produce visible feedback and keep
the editor open for recovery or Undo. Conflicting initial plain/rich alternatives
show the saved plain text with a localized explanation and block Apply.

The full composer remains the formatting authoring surface. Template editing
uses the existing Word body editor and does not add a separate HTML editor or
HTML-import path.

## Model and validation

`MailMessageTemplate.richBody` is an optional immutable `MailComposeBody`.
Its supported styles, links, paragraph direction/alignment, empty typing styles,
canonical grammar and structural limits are the same as the composer.

The rich body's plain alternative must equal the template body after CRLF/CR
normalization. Literal markup in a legacy plain body remains literal text.
`copyWith` retains rich content by default; `clearRichBody: true` explicitly
removes it. Updating plain text without updating a conflicting rich body fails
validation instead of silently discarding formatting.

| Bound | Value |
| --- | ---: |
| Plain template body | 16,384 UTF-16 code units |
| Canonical template HTML | 65,536 UTF-16 code units |
| Complete account compose settings | 131,072 UTF-16 code units |
| Stored template HTML transfer preflight | 262,144 UTF-8 bytes |

The plain and aggregate settings ceilings are existing limits. HTML now
contributes to the aggregate settings budget, configured host metadata budget
and account logical-byte quota. SQL's byte ceiling bounds transfer before
decoding; the stricter model code-unit limit and canonical parser still apply.
Ordinary plain templates do not create HTML solely for validation.

## Durable storage and migration

Schema **22** adds nullable `account_message_templates.body_html`. It retains
the existing literal `body` column, account owner, ordering, sender references
and shared compose-settings revision.

Fresh creation and upgrades apply the real additive DDL inside the existing
migration transaction. Upgrading schema 21 leaves every old template plain and
does not rewrite body bytes or increment settings revisions. Fault injection
tests cover rollback of both the column addition and schema version, then retry.
The existing historical migration suites now assert version 22; fixtures for
old and future unsupported databases retain their intended behavior.

Stored content is checked for nullable SQL type and byte bounds before text
transfer, decoded strictly, checked against the HTML code-unit limit and parsed
as the exact canonical format. Both alternatives must agree. Empty, malformed,
unsupported-version or mismatched rich HTML is a storage failure and blocks
replacement of the corrupt settings revision.

Formatting-only changes use the normal atomic settings transaction and revision
comparison. Failed quota checks, stale writes and commit failures preserve the
previous durable revision. Saving settings never rewrites existing drafts or
frozen Outbox bytes.

## Ownership and asynchronous dialogs

Save as template captures the compose owner, account, tools epoch, immutable
settings object and draft revision. A changed owner or draft cannot publish a
stale snapshot after the editor returns. The template-management dialog also
requires the same pending settings object, even when a replacement object has
the same durable revision.

The template Apply handler checks ownership before capture and before returning
the result. A retained callback after retirement displays stale feedback, and
a callback after disposal returns safely.

## Sending and review

Applying a valid rich template carries its typed rich body into
`StudioMailDraft`. Normal composition persistence, shared MIME construction,
frozen Outbox review/edit-copy and private Bcc envelope handling then use the
existing rich-composition contract. No provider API or submission policy is
changed.

A new native regression covers settings close/reopen, template application,
draft saving, atomic Outbox admission, canonical HTML recovery and private Bcc.
These tests use synthetic mail and do not send live messages.

## Qualification and remaining work

The [continuation validation record](../../validation/mail-rich-templates-20261125/README.md)
separates executed SQL checks and earlier-head CI from the current source's
Dart/Flutter qualification. It also documents the analyzer and real-Enter test
fixtures corrected after the first rich-composition runtime run.

Inline images/CID authoring, lists/tables, arbitrary HTML import, provider Drafts
synchronization, exact-message Sent reconciliation, retained concurrent accounts
and background delivery remain separate increments. Installed-app behavior and
actual mail-client rendering remain acceptance work.
