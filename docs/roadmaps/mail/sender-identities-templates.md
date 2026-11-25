# Sender identities and full-message templates

**Source implementation:** 25 November 2026. See the
[extension and validation record](extension-20261125.md) for executed checks.

## Native Studio workflow

Open a mail composer and choose **Writing tools**. Alongside the existing
signature and Quick Text controls, **Sender identities** manages named From
addresses, display names and optional Reply-To addresses. An optional default
identity applies at a new-draft boundary. **Message templates** manages named
To/Cc/Bcc, subject and plain-text body defaults, with an optional sender identity.
The settings are saved together as one account-owned revision.

The composer has an explicit sender selector. A sender recovered from a draft
remains visible even if its original identity was edited or removed. Selecting
another identity updates only that draft. A later change to the default identity
or signature does not rewrite saved drafts or queued mail.

**Save as template** copies the current authored message into the template
editor without modifying the draft. **Use template** requires an explicit
replacement confirmation. It replaces recipients, subject, body and sender;
clears existing attachments and reply/thread references; and creates an
independent message. No template operation sends or queues mail. An empty
template body really clears the existing body. Attachments, delivery schedules,
Message-ID/References and uncertain-delivery state are never stored in a template.

Template bodies use the same Quds Word editing surface as the composer. Controls
and guidance are available in English, German and Arabic, including RTL nested
dialogs and narrow layouts. Templates are literal text: no executable expansion,
HTML evaluation or recipient substitution is performed.

## Sender and provider boundaries

The selected From address, display name and Reply-To are copied into an immutable
draft snapshot. They survive draft recovery, MIME construction, frozen Outbox
submission and supported editable Outbox copies. The SMTP envelope sender and
visible MIME From use the same selected address. Bcc recipients remain in the
private submission envelope, not the transmitted headers.

An identity does not create another account, switch credentials or establish
delegated permission. Native SMTP may submit a configured alias under the
connected account; the server still authorizes that address. EWS, Gmail and
Microsoft 365 retain the account-address submission restriction pending separate
alias qualification. A recovered unsupported alias is shown, with Send and Queue
disabled until the user explicitly chooses the account address. Display names
and Reply-To can still be configured for the primary address.

Supported mailbox addresses use the existing ASCII dot-atom/DNS subset. SMTPUTF8,
quoted local parts, groups, comments and domain literals are not newly enabled.

## Persistence and limits

`MailComposeSettings` now includes immutable `MailSenderIdentity` and
`MailMessageTemplate` lists and an optional default identity ID. The account is
still the settings owner, and every save requires the exact displayed revision.
Identity IDs referenced by the default or a template must exist in the same
snapshot. The UI refuses to remove an identity while a template refers to it.

| Resource | Limit |
| --- | --- |
| Sender identities per account | 16 |
| Message templates per account | 32 |
| Identity/template name | 80 UTF-16 code units |
| From and Reply-To mailbox | 254 ASCII characters, with the transport subset restrictions |
| Sender display name | 256 UTF-16 code units |
| Combined template recipient fields | 25,600 UTF-16 code units |
| Template subject | 512 UTF-16 code units |
| Template body | 16,384 UTF-16 code units |
| Entire compose-settings metadata | 131,072 UTF-16 code units, further bounded by repository limits |

SQLite schema 21 adds account-owned identity/template tables and a nullable
default-sender column. Existing signatures, Quick Text and revisions migrate
without being replaced. Read paths preflight counts, types and byte budgets,
then strictly decode UTF-8 and validate the complete snapshot. Corrupt or
incomplete settings fail instead of producing partial success. Quotas include
the new tables; account/profile removal clears them. Logout and cache cleanup
preserve account-owned compose preferences.

Draft sender snapshots reuse the existing envelope From/Reply-To fields. Outbox
messages remain frozen bytes and envelopes; settings edits never rebuild them.

## Lifecycle and recovery

Template replacement commits pending body edits, captures the draft revision
and settings/account owner, and rechecks them after confirmation. Retired
accounts, changed settings, later edits and in-flight attachment work prevent
stale replacement. Save acknowledgements must match the same owner and the next
revision. Conflicts retain the authored state and follow the existing settings
reload/recovery path.

This increment does not provide HTML composition, inline-image templates,
per-identity signatures, provider Drafts/Sent synchronization or automatic
background sending. Live provider alias acceptance and installed-platform
qualification remain separate from the synthetic and local test results.
