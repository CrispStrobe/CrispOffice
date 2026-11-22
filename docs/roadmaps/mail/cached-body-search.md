# Cached plain-text body search

**Status:** implemented 22 November 2026. Local-only; no provider search,
attachment extraction, HTML rendering or new storage migration.

## User path

Saved-mail search still searches headers by default. The explicit `body:` field
searches the plain-text body retained by **Cache message**:

```text
body:"delivery address"
from:shop body:parcel
subject:invoice AND NOT body:returned
```

An unqualified term such as `parcel` never reads or searches a body. `body:`
appears in the English, German and Arabic search help. The search dialog remains
a saved-mail workflow and does not download missing bodies.

## Contract

- `MailHeaderSearchDocument.body` is optional retained plain text. It defaults
  to empty; callers that have no retained body do not claim a body observation.
- `MailHeaderSearchQuery.searchesBody` is true when the parsed expression
  contains at least one `body:` term. Hosts use it to decide whether body text
  must be supplied.
- A quoted `body:` phrase must occur within the retained plain-text projection.
- `body:` is independent of `recipient:`/`participant:`; a bare term remains
  limited to subject and sender.
- Search works over the existing bounded saved-header window. It does not scan
  messages that were never cached, attachments or HTML-only content.
- Missing bodies simply do not match `body:`. The result is not proof that the
  provider mailbox does not contain the text.
- No schema migration, network request, body download or provider construction
  is added.

## Implementation

| Layer | Change |
| --- | --- |
| `quds_mail_core` | Body field, `body:` parser term, `searchesBody`, portable matching |
| `quds_mail_store` | Loads retained plain text only when `searchesBody`; passes it to the portable matcher |
| Studio | Search help/about and an example query in EN/DE/AR |
| Live tool | `packages/quds_office_editor/example/tool/mail_live_body_search.dart` |

## Verification

- `quds_mail_core`: full suite **674/674** passed.
- `quds_mail_store`: `cached_header_search_test.dart` **23/23** passed.
- Studio cached-search dialog: **23/23** passed.
- Live IMAP against mailbox.org: connected, discovered INBOX, fetched a message
  with a real plain-text body, cached it locally, matched `body:"…"`, and
  confirmed that an unqualified term did not search the body.
- `dart analyze` on changed files: no issues.

The full store suite's two SIGKILL timing tests passed when re-run individually;
the full parallel run timed out in those process-termination tests. This is
recorded as a test-harness timing limitation, not evidence for or against body
search. The unrelated EWS HTTP suite has pre-existing failures in this
environment and is not used to qualify this local search feature.
