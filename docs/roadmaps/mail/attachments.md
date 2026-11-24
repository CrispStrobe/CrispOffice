# Studio outgoing file attachments

**Scope date: 20 November 2026.** The native Studio composer can attach local
files to new messages, replies, Reply all and manually composed forwards. Native
SMTP, on-premises Exchange EWS, Gmail and Microsoft 365 share the same immutable
draft and MIME builder. This is the next foreground M07 increment toward Office
document-to-mail workflows; it does not complete the durable outbox or M08.

The [validation record](../../validation/mail-attachments-20261120/README.md)
separates local qualification from live-provider and installed-platform tests.

## Using attachments

Open **Compose**, **Reply**, **Reply all** or **Forward**, choose **Attach files**,
and select one or more files. The composer lists each filename and size, plus the
total count and bytes. Remove a file with its adjacent remove button. Duplicate
filenames remain separate attachments, in selection order; empty files are valid.

Selection is all-or-none. If any selected file is unavailable, changes length,
has an unsupported filename, exceeds a bound or fails to finish reading, none of
that selection is added. Already attached files and the body stay intact. The
feedback contains a fixed explanation rather than a platform exception or path.

Send and attachment removal are disabled while files are being selected or read.
Cancel closes the composer and invalidates its pending reader. A late selection
or read completion cannot update a disposed composer or submit a message.

The plain-text Word body reflows to the available composer width at normal text
size. Arabic composition uses a right-to-left body, while filenames and byte
labels keep an explicit reading direction. Resizing retains the same body
controller, input composition, selection and undo history.

The selected bytes are copied into an immutable snapshot. Later edits, deletion
or replacement of the source file do not change the attachment already shown in
the draft. Attaching a file does not save, edit or overwrite that file. MIME type
hints for DOCX, XLSX, PPTX, their macro-enabled variants, older Office files,
OpenDocument files, PDF and common text/image formats come from the extension;
they are not a content validation or an editor compatibility claim. Other files,
including EML, are sent as `application/octet-stream`.

## Explicit limits

| Bound | Behavior |
| --- | --- |
| Attachment count | At most 10 across the entire draft, including empty files and duplicate names |
| Combined attachment payload | 20 MiB (20,971,520 bytes) by default; mailbox.org uses 64 MiB derived from its 100 MB message-size claim; other providers may be lower |
| Individual file | The remaining draft byte budget; a single file can use the complete account policy (20 MiB default, 64 MiB mailbox.org) |
| Filename | At most 255 UTF-8 bytes; a basename with valid Unicode and no path separators, control characters, line/paragraph separators, directional control marks, surrounding whitespace, `.` or `..` |
| Stream read deadline | 30 seconds per file by default; elapsed time applies across all chunks of that file |
| Body | Existing 1 MiB UTF-8 limit and no null characters |
| Subject | Existing 512-character limit and no header controls |
| Canonical wire message | At most 150 MiB (157,286,400 ASCII bytes), checked before transport; server limits are not inferred |

The complete selection's declared sizes and names are admitted before any stream
is opened. Actual chunk sizes are checked before retention and must total exactly
the picker-declared file length. Native path fallback reads at most the remaining
byte budget plus one detection byte. It does not use an unbounded `readAsBytes`
for new attachments. Some platform pickers can supply already materialized bytes;
their actual lengths are checked before the application copies them. These
controls bound retained application payloads; they are not a claim of streaming
MIME generation or a bound on every platform picker's internal allocation.

Removing or replacing source data during a read can fail the whole selection.
No source mtime, absolute filesystem path or open file handle is kept in the
draft. Streams are cancelled on failure, timeout and disposal; asynchronous
platform teardown cannot keep the closed composer waiting.

## MIME and recipient handling

Messages with attachments use `multipart/mixed`. Its first child is the existing
`multipart/alternative` plain-text body and escaped HTML projection. Every file
is a separate `Content-Disposition: attachment` part with base64 payload and
declared byte size. Plain messages retain their `multipart/alternative` shape.
Binary `text/*` attachments have no guessed charset; their original bytes remain
opaque and unchanged.

Both `name*` and `filename*` use UTF-8 percent-encoded RFC 2231 parameters. Quotes,
semicolons, percent signs, Arabic, other Unicode and supplementary characters in
supported filenames cannot turn into new MIME fields. The resulting wire is
ASCII-safe for the existing text-oriented SMTP client. The filename limit also
keeps the encoded parameter within the SMTP header line bound. This does not
claim compatibility with clients that ignore RFC 2231 extended parameters.

Each body child now explicitly uses quoted-printable encoding. A scoped change
in the retained MPL fork encodes terminal spaces/tabs and measures an encoded
Unicode token before wrapping. This preserves body whitespace when a receiver
removes transport padding and keeps quoted-printable lines within 76 columns.
Header Q encoding is unchanged. See RFC 2045 section 6.7 and RFC 2231 in the
[references](#references).

To, Cc, Bcc and validated `In-Reply-To`/`References` remain independent of
attachments. The canonical MIME has visible To/Cc and no Bcc header. The complete
deduplicated envelope still includes hidden recipients:

| Path | Existing submission behavior retained |
| --- | --- |
| Native SMTP | Pass the complete envelope to SMTP; do not append a concurrent Sent copy |
| EWS | Map hidden recipients to SOAP `BccRecipients`; use the existing EWS Sent filing |
| Gmail / Microsoft 365 | Add a validated Bcc header only to the private API request copy; leave the prepared canonical MIME unchanged |

Cloud services remain responsible for removing that request-only Bcc header from
recipient-facing copies. No live mailbox or real delivery was exercised here;
local provider fixtures do not prove end-to-end recipient privacy or delivery.
Provider configuration or server-side quotas may be lower than these composer
limits, and existing rejection/uncertainty handling still applies.

## Draft lifetime and retries

The session retains the submitted immutable draft, including attachment bytes,
if submission is rejected or uncertain. Reopening the retained draft shows those
attachments, and editing the body or recipients keeps them unless removed.
Uncertain attempts still require the explicit delivery-check acknowledgement
before another send. A positive submission outcome clears the retained draft;
acceptance is not a promise of final recipient delivery.

There is no autosave of edits in the open composer. Cancelling it discards those
edits; any previously retained submission draft is unchanged. Disconnecting or
closing the account session clears its retained draft and attachments. These are
memory-only foreground snapshots, not durable drafts, a recoverable outbox,
background sending or automatic retries.

Reply and Reply all still quote the decoded plain body. Forward still creates a
new conversation and explicitly states that source attachments are not included.
Opening any of those actions never copies received attachments automatically.
Users can choose files explicitly in the resulting composer; extracting an
incoming attachment into a new draft is separate work.

## Qualification and next increments

The incoming [Zotero combined qualification](../../validation/zotero-research-materials-20261120/README.md)
also retains controlled mail-host, provider, MIME and SMTP checks and an
independent Python MIME inspection. Those receipts belong to their recorded
source checkpoints; they are kept separate from the resumed mail runs below.

The source-bound [attachment core evidence](../../validation/mail-attachments-20261120/attachment-core/README.md)
contains a new independent Python MIME receiver and production-codec comparison.
The [overall record](../../validation/mail-attachments-20261120/README.md)
adds the complete model/MIME, recipient/reply/threading, vendor codec/builder,
file-reader, composer and provider-host suites. Together they check immutable
ownership, empty and duplicate files, names and media-type admission, count/byte
limits, exact attachment hashes, MIME structure, Bcc absence and reply threading.
A prior maximum-size probe combined ten files totaling 10 MiB with a 1 MiB body of
quotes, whose escaped HTML expands sixfold. In the recorded run the canonical
message is 21,986,572 bytes and its outer-base64 representation is 29,315,432
bytes, below the 22 MiB wire guard and default 32 MiB cloud request budget.
The production codec recovers every file and the complete body. The probe
records a separate allowance estimate for the private Bcc header and request
wrapper; it does not capture a live provider request or establish a server's
quota. It is a serialization bound probe, not a device-wide performance claim.
The 20 MiB default and 64 MiB mailbox.org policy have not yet been re-qualified
against a live provider. mailbox.org's published 100 MB is a message-size
claim; the attachment budget is deliberately lower after base64 and headers.
The composer names the source: ordinary accounts show the CrispOffice default,
mailbox.org shows its larger policy.

Live-provider delivery, actual native picker behavior on each installed OS and
real browser persistence remain separate qualifications.

Next M07 work is durable drafts/outbox integration and broader composition
capabilities. M08 still needs read-only received-attachment preview/edit working
copies and an **attach current document / attach PDF** command that commits
pending edits, captures the correct document identity/revision and rejects stale
async results. This increment adds no Word `SendMail`, Excel `SendMail`,
PowerPoint mail integration, Outlook COM object model, mail-merge sending or VBA
mail API. Existing Office/VBA work is preserved independently; automatic macro
execution and automatic sending are not introduced.

## References

- [RFC 2045, section 6.7: quoted-printable encoding](https://www.rfc-editor.org/rfc/rfc2045#section-6.7)
- [RFC 2231: MIME parameter character sets and continuations](https://www.rfc-editor.org/rfc/rfc2231)
- [Recipient groups and Reply all](recipients-and-reply-all.md)
- [Reply threading](reply-threading.md)
- [Ordered M07/M08 plan](implementation-plan.md)
