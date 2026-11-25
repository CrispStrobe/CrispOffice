# Provider folder-search adapters

Source increment: 25 November 2026. This document extends the original
[IMAP provider-search contract](provider-search.md); it does not replace the
live-provider acceptance record for that earlier feature.

## Shared boundary

`MailProviderSearch` is an optional read-only port. Implementations expose
`searchFields` and accept a `MailProviderSearchRequest` owned by one exact
account and folder/label. The request contains one literal text value of at
most 512 UTF-16 code units, one field, optional UTC received-time bounds and a
result limit from 1 through 100. The lower bound is inclusive; the upper bound
is exclusive. Empty/control/malformed Unicode input, inverted ranges, invalid
limits and foreign account ownership fail before mail IO.

Provider grammar is constructed by the adapter. User input never supplies
raw IMAP/AQS/KQL/Gmail operators. Provider indexing and tokenization still
determine matching; literal input does not promise an identical substring
algorithm across services.

| Adapter | Fields | Date precision | Count |
| --- | --- | --- | --- |
| Existing Studio IMAP | Body, Subject, From, To | Provider calendar dates | Exact SEARCH identity count |
| Gmail | Subject, From, To | UTC seconds | Estimated if supplied by Gmail; otherwise unknown |
| Microsoft Graph | Body, Subject, From, To | UTC calendar-day boundaries | Unknown; Graph search has a service cap |
| Exchange EWS | Body, Subject | UTC seconds | Exact `TotalItemsInView` while observations agree; estimated after observed changes; otherwise unknown |

Gmail's documented search grammar has no body-only operator. From/To EWS
search requires separate AQS participant semantics and is not advertised by
this structural-restriction implementation. Graph sub-day bounds fail as
unsupported. Gmail and Graph reject embedded double quotes, backslashes and
wildcards rather than interpreting uncertain literal escapes. Other query
text, including apparent Boolean operators and property names, remains inside
a quoted phrase. EWS uses an XML constant and preserves quotes and XML-special
characters as authored text.

## Adapter behavior

Gmail searches `users.messages.list` with both a constructed `q` and an exact
`labelIds` filter. It uses UTC epoch seconds rather than Gmail's PST date-string
interpretation. An inclusive lower bound is widened by one second for the
provider query and checked against each metadata `internalDate`. Metadata
retrieval verifies the requested message ID and explicit label membership;
messages deleted or moved between observations are omitted. Gmail's
`resultSizeEstimate` is never labeled an exact total, even on the last page.

Graph searches the exact `mailFolders/{id}/messages` collection. It constructs
a quoted KQL field phrase, appends typed UTC received-date conditions and
requests bounded header properties. Continuations must stay on the same HTTPS
Graph account/folder collection. Returned IDs must be unique and each explicit
`parentFolderId` must match the searched folder. Received-time values are also
checked when a range is active. Index coverage and the service cap prevent
claiming a globally exact total from the returned row count.

EWS uses `FindItem` with a structural `Contains` restriction on Body or Subject,
plus `IsGreaterThanOrEqualTo` / `IsLessThan` restrictions on DateTimeReceived.
The normal XML builder escapes constants. A separate bounded `GetItem` obtains
the complete header projection and current parent-folder identity. Missing or
moved rows are skipped and lower count certainty. No AQS string is accepted.

All adapters fetch at most eight search pages per operation and use a
one-match look-ahead to establish truncation. A server's final page may carry
additional bounded rows beyond the requested display limit; only the bounded
projection is adopted. Continuation cycles and duplicate identities fail.
Existing transport byte limits, deadlines, credential verification and lease
checks apply. Logout/account changes, cancellation and disposed sessions
discard late results. Search performs only reads and does not touch drafts,
Outbox, flags, membership, local rules or cached search indexes.

## Qualification boundary

Tests use explicit synthetic HTTP/SOAP responses and verify grammar isolation,
ownership, date boundaries, membership races, count precision, pagination,
cancellation and malformed-response behavior. Live disposable-account tests
for these new search adapters and installed-platform UI acceptance remain
separate gates. Provider-dependent scope/permission errors are reported as
typed failures; there is no local-scan fallback presented as full server search.

## Primary protocol references

- [Gmail messages.list](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/list): query, label scope, continuation, estimate and metadata-scope restriction.
- [Gmail search and filtering](https://developers.google.com/workspace/gmail/api/guides/filtering): UTC epoch dates and API/UI differences.
- [Graph message search](https://learn.microsoft.com/en-us/graph/search-query-parameter): searchable message properties, KQL and service result cap.
- [EWS search filters](https://learn.microsoft.com/en-us/exchange/client-developer/exchange-web-services/how-to-use-search-filters-with-ews-in-exchange): structural contains and compound restrictions.
- [EWS Body/Subject search example](https://learn.microsoft.com/en-us/previous-versions/office/developer/exchange-server-2010/dd633693%28v%3Dexchg.80%29): FindItem Body restrictions with paging and received-date sort.
