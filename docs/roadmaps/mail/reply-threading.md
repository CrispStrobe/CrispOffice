# Studio mail reply threading

**Scope date:** 2026-11-20. **Implementation:** native Studio replies through the
shared composer and MIME builder. **Runtime qualification:** the
[attachment continuation](../../validation/mail-attachments-20261120/README.md)
qualifies the complete threading/MIME cases and composer/provider-host suites
against the actual locked workspace. The
[recipient record](../../validation/mail-recipients-20261119/README.md) and
original [source review](../../validation/mail-reply-threading-20261119/README.md)
retain their earlier, more limited qualification boundaries.

## Behavior

Use the existing **Reply** action, edit the draft and send normally. When the
fetched message has a supported `Message-ID`, the outgoing message carries that
ID in `In-Reply-To` and appends it to a bounded `References` chain. Its own
`Message-ID` is generated separately. This gives receiving mail clients the
identifiers used for conversation grouping; actual grouping remains a receiving
client decision.

The metadata belongs to the immutable `StudioMailDraft` snapshot. Editing the
recipient, subject or body preserves it, as does reopening a retained draft
after an uncertain send. The existing explicit acknowledgement is still required
before another uncertain-send attempt. Native IMAP/SMTP and the shared EWS,
Gmail and Microsoft 365 host paths use this same builder. No extra setting or
control is required.

A new composition has no thread metadata. **Forward** produces a new
conversation even when its source has references. The existing text-only quote,
recipient validation, source-Bcc and source-attachment exclusion, and Unicode quote
limit continue to apply. Thread metadata does not turn the foreground draft
into a durable outbox or guarantee exactly-once delivery.

## Supported source metadata

The builder accepts complete ASCII `<dot-atom@dot-atom>` identifiers, including
RFC `atext` punctuation on both sides of the single `@`. It preserves their
exact case and spelling. Each dot-separated atom must be nonempty. It never
trims, repairs, decodes an encoded word, adds brackets, or extracts an apparent
ID from a larger string.

This is a deliberately conservative subset of
[RFC 5322 section 3.6.4](https://www.rfc-editor.org/rfc/rfc5322.html#section-3.6.4),
not a complete RFC header parser. Quoted/obsolete syntax, comments, domain
literals, internationalized IDs, whitespace and controls are unsupported. A
missing or unsupported immediate parent produces a usable unthreaded reply,
with neither threading header. It does not infer a parent from older ancestry.

For a supported parent:

1. A nonempty source `References` list is accepted only when every entry is a
   complete supported identifier. Any invalid or unsupported entry discards the
   entire inherited chain, retaining the immediate parent alone. This prevents
   an ID inside a whitespace-split comment from becoming a false ancestor.
2. When the list is empty, a single supported `In-Reply-To` value may supply the
   previous ancestor. The normalized `MailEnvelope` model represents absent and
   empty References identically. A multi-ID or unsupported value is ignored;
   a nonempty invalid References list never activates this fallback.
3. Exact duplicate IDs are removed, preserving first occurrence order. IDs that
   differ in case remain distinct. The immediate parent occurs once, last.
4. A long accepted chain retains its first ancestor and the newest contiguous
   tail that fits before the immediate parent. Omitted middle ancestry is not
   reconstructed or presented as a complete history.

The MIME codec currently splits References on whitespace. Adjacent identifiers
in one token, such as `<a@b><c@d>`, are therefore unsupported and produce the
parent-only result. Original downloaded or archived MIME is not rewritten by
this outgoing-draft policy.

| Bound | Behavior at the boundary |
| --- | --- |
| One identifier | At most 254 ASCII characters, including `<` and `>` |
| Source References entries | At most 1,024 entries examined; a larger list yields parent-only metadata |
| Outgoing References value | At most 900 ASCII bytes, including separating spaces |
| Unsupported parent | Omit both threading headers |
| Unsupported nonempty ancestor chain | Keep the immediate parent in both threading headers |

Validated strings are exposed only through an immutable `StudioMailThread` with
a private nonempty constructor. Submission uses enough_mail's existing
unencoded header API and folding; it does not pass the source message to that
library's automatic reply builder. No dependency or schema change is required.

## Qualification

The 20 November attachment continuation ran all 24 threading cases, including
MIME assertions, and the complete composer and native/EWS/Gmail/Graph host
suites. The [current record](../../validation/mail-attachments-20261120/README.md)
binds these results to the pinned Flutter 3.47.8 / Dart 3.13.7 runtime and actual
locked dependencies. Live-provider delivery and receiving-client conversation
grouping remain unverified.

### Historical source and subset qualification

Focused regressions cover source parsing, malformed metadata, comment fragments,
header injection, identifier/chain limits, deduplication, MIME serialization,
ordinary and forward composition, composer edits and uncertain retries.
The initial implementation was source-reviewed without an executor. The later
recipient continuation installed pinned Flutter 3.47.8 / Dart 3.13.7, formatted
the changed source/tests, and executed 16 pure threading cases through a separate
cached dependency graph. Whole MIME-dependent cases were excluded and recorded;
MIME round trips, composer widgets and full workspace analysis were unexecuted
in that earlier continuation because workspace dependencies could not be resolved.
Those focused results do
not establish full-lock workspace or live-provider interoperability.
GitHub Actions are neither awaited nor used as an acceptance gate.
