# Studio recipient groups and Reply all

**Scope date:** 2026-11-19. The native Studio foreground composer supports
multiple To recipients, Cc, Bcc and Reply all. Native SMTP, Exchange EWS, Gmail
and Microsoft 365 use the same validated draft and MIME construction.
The [original qualification record](../../validation/mail-recipients-20261119/README.md)
retains its executed subset and dependency limitations. The later
[attachment continuation](../../validation/mail-attachments-20261120/README.md)
qualifies the complete recipient/reply/threading, MIME, provider-host and composer
cohorts against the locked workspace; see the qualification section below.

## Using the composer

Enter bare email addresses in **To**, separated by commas or semicolons.
Choose **Cc / Bcc** beside To to reveal the additional fields. A retained draft
with Cc or Bcc opens with those fields visible. At least one recipient is
required across all three fields; Cc-only and Bcc-only compositions are allowed.
The body remains the shared Word editing surface, with the existing plain-text
submission and quoting behavior.

The supported mailbox grammar is the existing ASCII dot-atom local part and
DNS host. Display names, quoted local parts, address groups, comments, IP domain
literals and SMTPUTF8/internationalized mailboxes are not parsed by these
controls. Spaces around individual addresses are accepted. Empty list entries,
line breaks, tabs, controls and non-ASCII characters reject the complete draft.
No unsupported entry is silently omitted.

| Bound | Accepted boundary |
| --- | --- |
| Mailbox length | 254 ASCII characters |
| Local part | 64 characters |
| DNS label | 63 characters |
| Manual recipient entries | 100 across To, Cc and Bcc, before deduplication |
| Combined input fields | 25,600 characters, before splitting or trimming |
| Reply-all source entries | 1,024 across the chosen reply targets, original To and Cc |
| Reply-all output | 100 distinct recipients after self removal and deduplication |

Repeated addresses occur only once in the outgoing envelope. To takes precedence
over Cc, which takes precedence over Bcc. The first spelling is retained. Only
the DNS domain is folded for comparison; local-part case is preserved. For
example, `Alex@EXAMPLE.test` and `Alex@example.test` are the same recipient, but
`alex@example.test` remains distinct. An address already present in To or Cc
remains visible when it is also entered in Bcc.

## Reply all

The **Reply all** action appears beside Reply in the native mailbox hosts:

1. Use every decoded Reply-To mailbox when that list is nonempty; otherwise use
   every decoded From mailbox.
2. Add the original To participants to outgoing To.
3. Add original Cc participants to outgoing Cc unless already present in To.
4. Exclude the connected sender identity and remove duplicates using the same
   exact-local-part/domain-insensitive comparison as manual composition.

Source Bcc is never inspected or copied. The host does not infer account aliases
or additional identities, so review the editable recipients before sending.
Missing or self-only participants open an unaddressed draft that cannot be sent
until a recipient is entered.

Each decoded source mailbox is validated before it is joined into an editable
field. An unsupported mailbox or exceeded bound produces explicit feedback and
does not create a partial reply. A comma or semicolon embedded in one malformed
decoded address cannot turn it into additional recipients. Ordinary Reply keeps
its existing first-Reply-To/first-From selection, with this same single-mailbox
validation; forwarding starts without any source recipients.

These rules apply to the normalized `MailEnvelope` delivered by the codec or
provider. Its underlying parser may already have omitted malformed raw-header
fragments. This helper does not claim to validate the complete raw address-header
grammar or recover recipients omitted during parsing.

Reply all reuses the bounded plain-text quote and validated reply-thread metadata.
Forwards remain independent conversations. HTML-only quotation and attachment
forwarding remain unsupported, as described in the [threading guide](reply-threading.md).

## Bcc and submission

The canonical MIME message contains the visible To and Cc headers and **no Bcc
header**. The complete deduplicated recipient envelope remains separate:

| Submission path | Hidden-recipient handling |
| --- | --- |
| Native SMTP | Pass the complete explicit envelope to the existing SMTP client; no concurrent Sent-folder append |
| EWS | Pass the complete envelope to the existing adapter, which maps hidden recipients to SOAP BccRecipients |
| Gmail / Microsoft 365 | Pass the complete envelope to the existing adapter; it adds a validated transient Bcc header to its service request because those APIs derive delivery recipients from MIME |

The cloud service is responsible for removing that transient Bcc header from
recipient-facing copies. The frozen prepared MIME remains unchanged. Provider
interoperability and end-to-end delivery privacy have not been verified with live
accounts in this continuation.

The immutable draft retains all three editable fields and its thread metadata
after an uncertain attempt. Reopening it still requires an explicit delivery
check acknowledgement before another attempt. No automatic resend, durable
outbox, background sending or exactly-once delivery claim is introduced.

## Qualification

The 20 November attachment continuation ran all 31 recipient, 39 reply and
24 threading cases, including their MIME assertions, plus the complete focused
composer and native/EWS/Gmail/Graph host suites. It used Flutter 3.47.8 / Dart
3.13.7 and the actual workspace's locked package versions and archive hashes.
The [new record](../../validation/mail-attachments-20261120/README.md) binds those
results to their source and preserves the live-account/platform boundaries.

### Original 19 November qualification

The pinned Flutter 3.47.8 / Dart 3.13.7 runtime was installed locally. Full
workspace dependency setup stopped at the executor's network approval boundary;
the missing packages also prevented a strictly offline workspace resolution.
Focused tests ran against actual production source through a separate cached
Dart dependency graph. This includes recipient/reply/thread behavior, but excludes
the whole MIME-dependent cases. Separate parser checks exercise the input limits.

Prepared tests cover canonical MIME/Bcc separation, maximum-length folded
recipient lists, native/EWS/Gmail/Graph host envelopes, Reply all controls,
uncertain retry retention and narrow composer layouts. Those MIME and Flutter
cases were unexecuted in that original continuation. GitHub Actions were neither awaited nor used as a
gate. Exact commands, source hashes and test-subset transformations are retained
in the qualification record.
