# CrispOffice mail archiving, indexing and search

**Scope date:** 2026-11-19. **Goal:** work toward MailStore feature parity.
This increment supplies a separate durable native archive, file and foreground
mailbox ingestion, local search, original-message export, and maintenance.
Full MailStore Server parity remains a roadmap goal. The comparison below keeps
implemented behavior separate from outstanding enterprise and format support.

The local qualification plan and its evidence rules are in
[mail-archive-search validation](../../validation/mail-archive-search-20261119/README.md).
Existing account, provider and standalone Office scope remains in
[the Mail roadmap](README.md).

## Feature comparison

MailStore's official documentation is the comparison baseline, reviewed on
2026-11-19. This is a functional comparison, not a claim that the products have
identical storage, search semantics, administration, or compliance properties.

| Area | Available in this CrispOffice increment | Remaining parity work | MailStore reference |
| --- | --- | --- | --- |
| Durable archival | Separate native SQLite archive; immutable original message bytes; SHA-256 content identity; multiple source/folder origins for one exact byte sequence | Managed server archive stores and administration | [Archiving basics][mailstore-basics] |
| File ingestion | Multiple EML files and streamed MBOX with explicit `mboxrd` or `mboxo` interpretation; bounded parsing and visible partial/skipped outcomes | PST, MSG, recursive directory jobs, other MBOX dialects, signed MailStore-export metadata import | [File import][mailstore-files] |
| Connected mail | Archive an explicitly selected message or selected folder from the native IMAP, EWS, Gmail and Microsoft 365 readers; paginated, cancellable foreground collection | Whole-account/subfolder traversal, durable resume cursors, unattended scheduling, journal capture and administrative mailbox collection | [Archiving basics][mailstore-basics] |
| Search | Indexed subject, sender/recipients including Bcc, body, attachment names and optional supported attachment text; phrases, prefix terms, Boolean groups, alternatives and exclusions | Leading/infix wildcards and `?`; identical MailStore tokenization and advanced search semantics | [Client search][mailstore-client] |
| Search management | Source/folder filters, optional subfolders, sent/archive dates, exact byte-size filters, attachment filter, sorting, paging, saved searches | Shared search administration and full multi-user archive browsing | [Client search][mailstore-client] |
| Attachment content | Explicit opt-in, bounded UTF-8/BOM-marked UTF-16 extraction for supported text formats; skipped/truncated text is reported | PDF, Office document, image/OCR, encrypted and other binary attachment extraction | [Search indexes][mailstore-indexes] |
| Retrieval/export | Preview from the retained original and export its exact bytes as EML; existing destination paths are refused | Bulk export, restore into provider mailboxes/clients, PST/MSG exports, signed exports and exported archive hierarchies | [Export][mailstore-export] |
| Integrity/repair | Original and metadata hash checks, FTS integrity verification, index rebuilding, typed failures and content-free diagnostic events | Full backup/restore workflows, administrative maintenance scheduling and multi-store tooling | [Maintenance][mailstore-maintenance], [backup][mailstore-backup] |
| Profiles | Credential-free source profile persistence and stable provenance; saved-search persistence | Full profile management UI, scheduling, policy-based source deletion and server job management | [Archiving basics][mailstore-basics] |
| Enterprise controls | Host/profile separation and exclusive ownership of a native archive | Multi-user ACLs, auditor roles, durable audit trails, retention policies, legal hold, journaling, archive encryption/key administration and compliance qualification | [Compliance][mailstore-compliance], [service configuration][mailstore-service] |

## User workflows

### Archive files

The native Studio archive screen opens the app's persistent archive. Choose EML
files or an MBOX file, supply source/folder provenance, and choose whether to
index supported attachment text. EML input preserves the file's message bytes;
display and indexing use a separate parsed projection. Import summaries
distinguish saved records, duplicates, failed/skipped entries and limited or
partial work. Cancelling stops further work while preserving earlier commits.

MBOX import requires a dialect choice. It removes container envelope separators
and reverses that dialect's `From ` escaping: `mboxrd` removes one `>` from
`>+From ` lines, while `mboxo` removes one only from `>From ` lines. The resulting
message bytes, including LF or CRLF endings, are retained exactly. The complete
MBOX container is not stored. Ambiguous literal envelope-looking lines cannot
be recovered automatically. `Content-Length` framing (`mboxcl`/`mboxcl2`) is
rejected instead of guessed. An oversized record can be reported and skipped
while scanning resumes at the next valid separator; cancellation also interrupts
waiting for another stream event.

### Archive connected messages or a folder

Native IMAP, EWS, Gmail and Microsoft 365 reader actions use the same local
archive as file import. A selected-message action stores the original returned
by the provider with source/folder provenance. A selected-folder action captures
the chosen folder and runs `MailArchiveRunner` with visible progress and an
explicit cancel control. It does not traverse child folders or mutate the source
mailbox. Disconnecting, changing account, or disposing the host cancels stale
work through the existing account/session boundaries.

EWS and cloud folder DTOs currently expose a display name rather than a parent
path. Their archive folder label reflects that provider display name; stable
profile/provenance fingerprints separate the actual mailbox identities. This
does not claim reconstruction of the provider's complete folder hierarchy.

Each message commits independently. A run reports `completed`, `partial`,
`cancelled`, `limited`, or `failed`, with separate saved, duplicate and failed
counts. `completed` means the observed page sequence ended; a changing remote
mailbox is not a consistent point-in-time snapshot. A new run starts from the
first page and deduplicates retained original bytes. There is no background
scheduler, automatic retry loop, durable collection cursor, or guarantee that a
provider returns information it no longer retains.

The host persists a credential-free source profile and stable provenance
identity. The runner calls only header/message retrieval, checks account and
folder identity, bounds pages/messages/failures, and rejects overlapping runs
sharing the same provider instance. Its default bounds are 100 messages per
page, 1,000 pages, 100,000 processed messages, 50 retained item failures and three
consecutive provider failures. The terminal result distinguishes a configured
limit from successful exhaustion.

### Find and retrieve mail

The archive screen supplies query help, filters, sorting, result counts and
paging. Saved searches can be saved, loaded and removed. Preview and EML export
load the retained original after validating its SHA-256 identity; exporting does
not reconstruct the message from visible header fields. Removing an account,
clearing the live cache, deleting a saved search, or removing a source profile
does not delete archived messages. The archive UI has English, German and Arabic
strings and narrow-layout coverage.

## Query language and filters

The query parser emits a fixed SQL structure and bound FTS literals. User input
never supplies SQL syntax or unquoted FTS expressions.

| Syntax | Meaning | Example |
| --- | --- | --- |
| Words separated by spaces | All terms must match; equivalent to uppercase `AND` | `invoice approved` |
| Quoted phrase | Consecutive indexed tokens | `"board minutes"` |
| Trailing `*` | Token prefix | `budget*` |
| Uppercase `OR` | Either expression | `invoice OR receipt` |
| Parentheses | Group Boolean expressions | `(invoice OR receipt) approved` |
| `-` or uppercase `NOT` | Exclude a term or group | `invoice -draft` |
| Square brackets | Alternatives | `[invoice receipt]` |
| Field prefix | Restrict a term or phrase to that indexed field | `subject:invoice from:alice` |

Supported case-insensitive field names are `subject`, `from`, `to`, `cc`, `bcc`,
`bcontent` (body), `acontent` (supported attachment text), and `attachment`
(attachment names). Boolean operators must be uppercase; lowercase words such
as `and` are literal terms. Within phrases, escaped quote and backslash are
supported. An empty query lists records using the selected filters and sort.

Leading/infix `*`, `?`, wildcards inside phrases, unknown fields, malformed
groups and unsupported escapes are rejected with a typed parse problem and
offset. Default parser limits are 1,024 UTF-16 code units, 32 terms, and eight
nested groups. Matching uses SQLite FTS5 `unicode61` with diacritic removal;
punctuation and address components are tokens, not an exact byte/substring
comparison. Search ordering is archive date, sent date, or subject rather than
a relevance score.

Structured filters are separate from this query language:

- Source and normalized folder, with optional descendant folders.
- Sent date and archive date: inclusive lower bound and exclusive upper bound.
  Studio's inclusive end-day control maps to the following UTC midnight.
  Messages without a sent date do not match a sent-date constraint.
- Inclusive minimum/maximum original byte size and with/without attachments.
- Archive-newest, sent-newest, sent-oldest or subject ordering, with stable ID
  tie-breaks, bounded limit and offset, and a matching total count.

Saved searches preserve the query, filters, ordering and page size. Loading one
starts at the first page; a previous scroll offset is not a durable cursor.

## Storage and durability

`quds_mail_store` exposes `SqliteMailArchive` and `MailArchiveRunner`. The native
opener places the archive at
`<application-support>/quds_mail_archive/<host-and-profile-namespace>/archive.sqlite3`.
This is physically separate from the existing live-mail cache namespace.
Studio uses one app archive profile for file import and its connected readers;
provenance identifies their separate sources and folders.

Original bytes, their derived metadata/index projection, and provenance commit
together. Identical raw SHA-256 content is stored once; distinct bytes with the
same Message-ID remain distinct records. A duplicate import validates the
existing original and stored metadata, and can repair its derived index from
the verified projection. It never silently replaces a corrupted original.

The native connection uses WAL, `synchronous=FULL`, foreign keys and a bounded
busy timeout. An exclusive SQLite owner lease prevents simultaneous owners of
the same archive path. Close rejects new work, drains already accepted work,
then closes the archive and releases ownership. A future schema version is
refused rather than downgraded. Fault-injection checkpoints and actual
subprocess termination tests exercise rollback before commit and persistence
after a confirmed commit.

These mechanisms protect local transactional integrity. Hashes stored beside
the data are not signatures or an independent tamper-proof audit trail. They
do not establish legal retention, authenticity, compliant storage, or backup
coverage. The archive has no encryption/key-management or managed backup API in
this increment; deployment and backup qualification remain separate work.

## Indexing policy and bounds

The searchable projection contains subject, sender, To/Cc/Bcc, body, attachment
names and optional attachment text. Plain text is preferred; bounded HTML is
reduced to text for indexing without rendering, loading URLs or executing
content. Original MIME remains unchanged.

Attachment text is off by default. Supported media types are `text/plain`,
`text/csv`, `text/tab-separated-values`, `text/html`, `text/xml`,
`application/xml`, and `application/json`. Decoding accepts strict UTF-8 or
BOM-marked UTF-16. Unsupported, malformed, oversized or over-budget attachment
content is counted as skipped; the original attachment remains inside the
retained message. PDF, DOCX/XLSX/PPTX, legacy Office files, OCR and encrypted
content do not acquire searchable attachment text through this implementation.

| Default bound | Value |
| --- | --- |
| Original message | 32 MiB |
| Logical archive bytes | 1 GiB |
| Messages / provenance records | 100,000 / 200,000 |
| Per-message metadata projection | 2,097,152 UTF-16 code units |
| Total indexed fields per message | 262,144 UTF-16 code units |
| Decoded attachment bytes considered per message | 1 MiB |
| Search/maintenance maximum page size | 200 records |
| Saved searches / source profiles | 100 / 100 |
| References, each address group, attachments | 1,024 entries each |

Logical quotas do not reserve disk space or predict SQLite/WAL/index overhead.
Disk-full and permission failures remain authoritative and are reported.
Metadata and index writes enforce exact Dart UTF-16 unit limits. Reads first
bound SQLite materialization using text-length checks and
`length(CAST(column AS BLOB))`; a conservative UTF-8 byte cap of three times the
configured UTF-16 limit preserves valid Arabic, CJK and supplementary text.
Exact Dart length checks follow bounded hydration. The byte cap also prevents
embedded NUL from defeating SQLite's text-length preflight. Search pages and
origin lists additionally bound their aggregate returned metadata.

Before whole-index FTS maintenance, guards bound index row count, per-row text
and byte lengths, aggregate index bytes and ID size. These checks may scan all
index content; they are not a constant-time operation. Limits can be configured
by a host, subject to validation, and the UI reports partial indexing rather
than claiming that all preserved content is searchable.

## Verification, rebuilding, cancellation and errors

Per-message verification pages through original hashes, stored metadata hashes,
derived index values and provenance. On the **first page**, verification also
runs FTS5's **whole-index** `integrity-check`, which can detect damaged posting
shadow tables even when content columns look normal. SQLite exposes this
command through a virtual-table INSERT, so verification requires a write-capable
connection. Clean verification leaves persisted originals, projections and index
content unchanged; it is not physically read-only SQL.

Rebuilding likewise performs FTS5's **whole-index** `rebuild` on its first page,
then refreshes a bounded page from verified projections. A codec can optionally
reparse retained originals to refresh extraction or attachment-text policy.
Original bytes are never rewritten. Failure or cancellation rolls back the
current transaction; earlier completed maintenance pages remain completed.
Raw corruption is reported and retained for diagnosis, not disguised by a new
index. Oversized damaged index data is rejected before global reconstruction.

Cancellation is checked before and after the synchronous SQLite whole-index
command, between records, and immediately before committing after quota/lease
checks. It cannot interrupt that individual SQLite command mid-call. Large
indexes may therefore take time to return a cancellation result. See the
[SQLite FTS5 integrity and rebuild documentation][sqlite-fts5] for the command
semantics.

Public operations use `MailResult` and bounded enum/numeric diagnostics.
Malformed input, unsupported formats/schema, ownership conflicts, cancellation,
permission errors, quota failures and corruption have distinct safe problem
codes. Source/file/provider exceptions do not leak raw message bodies, tokens,
queries or paths into diagnostic events. Optional verbose diagnostics report
operation IDs, fixed phases, duration, counts, bytes and safe problem codes.
Observer/logger exceptions are caught so they cannot alter archival correctness.
Runner reports also count observer failures and bound retained per-item errors.

## Next parity milestones

The next work should preserve the existing separation between original data,
searchable projections and host/provider authorization:

1. Broader import/export: PST/MSG with an approved parser and fixtures, bulk EML
   export, mailbox restore, recursive source enumeration and explicit container
   format coverage.
2. Searchable binary attachments: bounded PDF/Office extraction, cancellation,
   extractor failure reporting, format-specific fixtures and resource budgets.
3. Collection operations: durable resume state, robust scheduling, journal
   collection and source reconciliation with clearly stated completeness rules.
4. Administration: multi-user authorization, durable audit records, retention,
   legal hold, encryption/key lifecycle, backup/restore and independent recovery
   qualification. Local hashes and a profile namespace do not satisfy these
   requirements by themselves.

[mailstore-basics]: https://help.mailstore.com/en/server/Email_Archiving_with_MailStore_Basics
[mailstore-client]: https://help.mailstore.com/en/server/Accessing_the_Archive_with_the_MailStore_Client_software
[mailstore-files]: https://help.mailstore.com/en/server/Archiving_Emails_from_External_Systems_-_File_Import
[mailstore-indexes]: https://help.mailstore.com/en/server/Search_Indexes
[mailstore-export]: https://help.mailstore.com/en/server/Exporting_Email
[mailstore-maintenance]: https://help.mailstore.com/en/server/Maintenance_and_Repair
[mailstore-compliance]: https://help.mailstore.com/en/server/Compliance_General
[mailstore-backup]: https://help.mailstore.com/en/server/Backup_and_Restore
[mailstore-service]: https://help.mailstore.com/en/server/MailStore_Server_Service_Configuration
[sqlite-fts5]: https://www.sqlite.org/fts5.html
