# Account signatures and reusable Quick Text

## Delivered source scope

Native Studio's shared composer now exposes **Writing tools**, **Insert
signature**, and **Insert Quick Text** for account stores supporting
`StudioMailComposeToolsStore`. IMAP/SMTP, on-premises EWS, Gmail and Microsoft
365 use the same owned SQLite adapter. Verified offline draft entry uses that
adapter without opening a provider connection.

Open **Writing tools** in a composer, enter a plain-text signature, choose its
new-message and reply/forward defaults, and add named Quick Text entries.
Changes stay local to the dialog until **Save** replaces the account's settings
at the displayed revision. Closing the dialog discards its unsaved settings
edits. The live message body remains independent.

This increment is source-implemented, independently reviewed and locally
tested with the pinned SDK. Mail core/store, composer/settings/adapter and Word
plain-text insertion tests passed during the Word style integration. See the
[qualification record](../../validation/mail-compose-tools-20261121/README.md).
It is not a live-provider, installed-platform or release qualification.

## Draft and insertion behavior

- An automatic signature is inserted only when starting a genuinely new
  message or reply/forward. New messages append it after initial text.
  Replies/forwards place it before the quoted content, leaving an editable
  opening paragraph. The separator is the ordinary plain-text `-- ` line.
- The new-draft catalog applies defaults before saving its first snapshot.
  The primary empty Compose route loads defaults before enabling initial
  editing. Existing draft selection, recovered drafts and Outbox edit-copies
  retain their original text, including a signature the user has edited or
  deliberately removed.
- Saving or reloading writing tools never rewrites an open draft. Explicit
  insertion is repeatable and uses the current body caret/selection.
- Quick Text is literal text, including HTML-looking text and placeholder-like
  strings. There is no HTML evaluation, template expansion, recipient change,
  attachment change, queue operation or provider submission.
- CRLF and CR normalize to LF when inserting text. The Word editor performs
  literal multiline insertion in one undo step without using the clipboard.
  Earlier and later independent edits remain in their own history steps.
- Supported selection shapes are a caret, a selection within one paragraph,
  and selection of the entire message. Other cross-paragraph selections show
  localized feedback and leave the message untouched. This deliberately
  avoids the existing Word structured-deletion behavior for partial boundary
  paragraphs.
- Insertion preflights the resulting 1 MiB plain-text body allowance. The
  current draft's recipients, thread identity, attachments, autosave and
  previous-submission uncertainty retain their existing contracts.

Default insertion and manual writing tools use account/session guards. A late
load, retained menu callback, retired account or replaced draft selection cannot
apply the previous account's content. An initially stale account also releases
its loading barrier so the composer remains closable.

## Storage and failure contract

Core exposes immutable `MailComposeSettings` and `MailQuickText` values.
Settings include the exact account identity, monotonically increasing revision,
signature, two default switches and ordered snippets. Bounds are:

| Value | Limit |
| --- | --- |
| Signature or one Quick Text body | 16,384 UTF-16 code units |
| Trimmed Quick Text name | 80 UTF-16 code units |
| Snippets per account | 32 |
| Aggregate settings metadata | 131,072 UTF-16 code units |
| Revision | Maximum safe JavaScript integer |

Snippet IDs and lowercase trimmed names must be unique within the account.
Malformed UTF-16 and disallowed controls are rejected; multiline text permits
TAB, CR and LF. Original Unicode spelling is retained without accent folding or
normalization. Stored text is decoded strictly as UTF-8 after count, type and
byte-budget preflight.

Additive schema 10 retains schemas 1–9 and adds owned settings/snippet tables.
Saving requires the DTO revision, expected revision and stored revision to
agree; the repository increments it transactionally. Resetting to empty
settings still advances the revision. Concurrent stale saves fail explicitly.
The existing repository quota and sole-owner lifecycle apply.

Logout retains writing tools; account/profile removal clears their local
settings. Drafts, frozen Outbox MIME/envelopes and remote mail are not changed by
a settings operation. The existing local SQLite storage is not encrypted.

The Studio adapter serializes settings with draft writes and drains accepted
operations before close. During a manager save, editing and dismissal are
blocked. An ambiguous or failed acknowledgement retains the displayed edits and
requires closing/reopening the manager to read back stored state before another
write. Only a same-account acknowledgement at the next revision is accepted.

## Remaining parity work

This is one part of M07 authoring. It does not supply multiple SMTP identities
or aliases, full-message templates, HTML alternatives/inline images, provider
Drafts synchronization, rules, encryption or full desktop
mail parity.
The later [scheduled-send increment](scheduled-send.md) supplies foreground
Send later and Undo through the same durable Outbox.

The next sequence remains:

1. Finish the shared synchronized workspace, unified inbox and durable
   move/delete operations.
2. Extend foreground scheduling with background execution and provider-specific
   Sent reconciliation, preserving uncertain-submission handling.
3. Add identity routing, ordered rules and richer authoring/Office attachments.
4. Extend provider/productivity features and qualify installed platforms.

Comparison references:
[Outlook signatures](https://support.microsoft.com/en-us/outlook/mail/how-to-add-and-change-an-email-signature-in-outlook),
[Thunderbird identities](https://support.mozilla.org/en-US/kb/using-identities),
and [eM Client email features](https://www.emclient.com/features-email).
These establish workflow targets, not equivalent support for every product
edition, provider or identity-routing configuration.
