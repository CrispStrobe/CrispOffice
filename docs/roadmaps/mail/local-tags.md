# Local tags and categories

**Status:** implemented 22 November 2026. Local-only metadata; no provider
keywords, folders or labels are changed.

## User path

Open a retained message and choose **Tags** in the reader action bar. Select
existing account tags or add a new one, then save. Tags are available in saved
mail search with:

```text
tag:Work
subject:invoice AND tag:Receipts
(tag:Work OR tag:Travel) after:2026-11-01
```

Matching is case-insensitive and exact: `tag:work` matches `Work`, while
`tag:wor` does not. Tags never become bare text terms and do not search the
subject, sender or body. A tag search reads no message body.

Assigned tag names are shown in mailbox and saved-search row metadata. Up to
three names are displayed, followed by a `+N` count, using the same
account-scoped values as `tag:` search. The list never reads bodies or contacts
a provider to render them.

## Contract

- Tags are scoped to one account and one retained message identity.
- At most 32 tags per message; each tag is 1–64 Unicode letters, numbers,
  spaces, dots, hyphens or underscores. Control and bidi-control characters are
  refused.
- Duplicate spelling is case-insensitive and keeps the first stored display
  form.
- Replacing the tag set is atomic. Invalid input and missing messages leave the
  previous set unchanged.
- Removing a message/account removes its tags. Removing a saved search or cache
  view does not.
- The optional assignment action is present only when the current host owns a
  tag-capable local store.

## Storage

Schema **v18** added `message_tags(account,message,tag_key,name)` with an exact
foreign key to the retained message and an account/tag search index. Schema
**v19** adds ordered local rules and schema **v20** adds persistent
conversations; both preserve these tags. Earlier schemas
upgrade additively and preserve every existing table and payload.

## Verification

- Core tag parser/search: **5/5**.
- Store tag behavior: **4/4**, including account isolation, exact matching,
  atomic rejection, cached-search integration and view/search row attachment.
- Schema/migration suites pass; the future-schema rejection moves to v21/v22.
- Studio tag dialog: **2/2**.
- Live mailbox.org test: fetched a real header, retained its cached identity,
  added local tags, reloaded them and matched `tag:live` without a provider
  search or body read.
- Shared message-list tag metadata regression and the full UI suite remain green.
- HTML/compose regression suites remain green.

## Limits

- Tags are local to this profile/database and are not synchronized across
  devices or written to IMAP keywords, Gmail labels or Exchange categories.
- Provider keyword/category mapping, tag colors, shared tags and ordered rules
  remain subsequent organization slices.
- The current assignment path is available for retained native IMAP messages;
  EWS/cloud and offline-only views require a host tag store to expose it.
