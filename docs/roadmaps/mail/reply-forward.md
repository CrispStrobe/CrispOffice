# Reply and forwarding fidelity

This increment extends the existing native Studio mail composer across
IMAP/SMTP, on-premises Exchange EWS, Gmail and Microsoft 365. Account catalogs,
connection ownership and provider submission contracts keep their existing
owners and behavior.

## User workflow

Open a loaded message and choose one of these reader actions:

| Action | Recipients | Quoted content | Files |
| --- | --- | --- | --- |
| Reply | Reply-To, otherwise From | Authoritative plain body, or inert text from HTML-only mail | None copied |
| Reply all | Visible participants, excluding the connected sender | Same body selection | None copied |
| Forward text only | Empty; choose recipients in Compose | Same body selection, with text-only notice | None copied |
| Forward with attachments | Empty; choose recipients in Compose | Same body selection, with file-forwarding notice | Every admitted decoded attachment, including inline parts as ordinary files |

Review recipients, quote and files in Compose. Individual files can be removed
using the existing attachment controls. Save and close retains the complete
draft; reconnecting and opening Compose restores it. Starting another reply or
forward never replaces a retained draft. Discard remains explicit and does not
cancel a message that might already have reached the sending server.

English, German and Arabic labels distinguish both forward choices and report
quotation/attachment failures without including source data in error messages.

## Text quotation contract

An existing plain-text alternative is authoritative, including an empty string.
HTML is used only when plain text is absent. The account-free
buildMailBodyPresentation API in quds_mail_ui accepts a MailBody, with no
envelope or attachment collection. It reuses the inert renderer's entity
decoding and paragraph/list breaks, and has no resource-fetching path.

Active markup, CSS and remote resources remain blocked. CID references produce
generic unavailable-image notices; attachment names and source IDs are not
projected into quotes. Body projection validates the selected alternative's
UTF-8 byte budget, rendered text, node count and nesting depth. Strict quotation
refuses incomplete markup that would otherwise yield a misleading prefix.
The general message reader retains its existing recovery behavior.

The Studio builders accept the original MIME status for HTML fallback, and
both connected hosts supply their reader's actual status. Noncomplete HTML
sources are refused. Direct model callers must supply accurate provenance;
a MailBody alone cannot establish whether an earlier MIME decode was complete.

Quotes retain the existing 8,000-Unicode-scalar limit, normalized newlines and
an explicit localized truncation marker. Surrogate pairs are not split.
Envelope display headers, Bcc lists and attachment summaries are never used
as a body fallback. Replies keep their bounded validated thread identifiers;
both forwarding choices start a new conversation.

## Complete attachment forwarding

The explicit file-forwarding builder takes a MailParseResult, not just its
visible message. Only MailParseStatus.complete is accepted, so a partial MIME
result cannot hide missing or undecodable parts behind a valid-looking list.

Admission checks the entire set before copying payloads:

- At most ten attachments, including zero-byte and inline parts.
- At most 10 MiB of aggregate decoded attachment bytes.
- Exact supported filenames and MIME types under the existing composer rules.
- No dropped entries, silent renaming, type relabeling or partial selection.

The outgoing list preserves order, duplicate filenames, Unicode filenames and
exact bytes. Each attachment owns an immutable snapshot. Inline parts become
ordinary outgoing files without their source Content-ID relationships. The
existing MIME builder creates base64 file parts and ASCII-safe filename
parameters; draft storage and submission retain the same snapshots.

A complete attachment-only message with supported files can be forwarded with
an empty quote plus attribution. A message with neither a supported body nor
files remains unavailable. Malformed HTML is never treated as an empty body.
An unavailable set produces fixed feedback and leaves the reader/draft state
untouched; the user can choose the text-only action or add files manually.

Container types such as message/rfc822 and multipart/* are not accepted by
this first outgoing attachment contract. A decoded attached EML with
message/rfc822 therefore refuses the complete file-forward action. Original
message export and manual opaque-file attachment remain separate workflows.

## Verification and remaining work

The [validation record](../../validation/mail-reply-forward-20261120/README.md)
binds source checkpoints to the actual formatter, analyzer and test outcomes.
Focused cases cover body privacy, incomplete/oversized HTML, Unicode cutoff,
all-or-none file admission, complete bodyless messages, MIME byte preservation,
draft recovery, uncertainty acknowledgement, capability gating and host actions.

This increment does not supply HTML editing, preserved rich quotation layout,
inline-image composition, signatures/templates, forwarding an original message
as an RFC 822 attachment, multiple simultaneous drafts or server-side Drafts
synchronization. Live-provider delivery and installed-platform behavior retain
their separate qualification boundaries.

Continue the ordered desktop-parity matrix in [README.md](README.md).
The next independent reliability milestone is a visible durable outbox: freeze
MIME and envelope together, expose queued/uncertain outcomes, survive restart,
and make retry/cancel explicit before adding undo-send or scheduling.
