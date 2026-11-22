# Ordered local rules

**Status:** implemented 22 November 2026. Local-only automation over retained
mail; no provider keywords, folders, read state or server search are changed.

## User path

Open connected Mail and choose **Rules** in the Mailbox ribbon. Add, edit,
enable, disable, reorder or delete rules. Each rule has:

- a name;
- a saved-mail search expression using the existing header/body grammar;
- one or more local tags to add and/or remove.

**Preview** counts saved matches per enabled rule. **Apply now** asks for
confirmation and then updates local tags for every matched retained message. A
short status reports the number of changed messages. Preview and apply never
contact a provider; body conditions use retained body text only.

## Ordering and conflicts

Rules run from top to bottom. A later matching rule wins when it changes a tag
already changed by an earlier rule, including an explicit removal. Add actions
within one rule run before that rule's remove actions. A rule may not add and
remove the same tag, which avoids intra-rule ambiguity.

Rule matching uses the saved-mail state captured before the run. A `tag:` rule
therefore does not see a tag added by an earlier rule in the same run; matching
and mutation are separate. Re-running Apply evaluates the new state.

The complete replacement of an account's rule list and the complete batch of
tag updates are separate atomic transactions. An invalid rule set, stale
operation, missing retained message or storage failure preserves the previous
rules/tags. There is no partial application across a batch.

## Bounds and safety

- At most **100** rules per account; positions are unique and zero-based.
- Each query is limited by the published header-search parser (1,024 code units,
  32 terms, 8 nesting levels, 32 operators).
- Each rule has at most 8 add tags and 8 remove tags.
- Apply stops explicitly at **1,000 matched messages** rather than silently
  truncating. Preview displays at most 1,000 matches per rule.
- Rules are account-scoped and removed with the account.
- Rules cannot move mail, delete mail, change read/flag state, send mail or
  write provider keywords.

## Storage

Schema **v19** adds `mail_rules(account,id,position,name,enabled,query,
add_tags,remove_tags)` with an account/position index. Tag arrays are bounded
JSON string arrays. v17 databases gain both `message_tags` and `mail_rules`; v18
databases gain `mail_rules`. All earlier payloads are preserved. Future schemas are rejected.

## Verification

- Core rule model/order/conflict tests: **6/6**.
- Store persistence, isolation, atomic batch and v17/v18→v19 migration tests:
  **6/6**.
- Rules dialog add/preview/confirm/invalid tests: **4/4**.
- Live mailbox.org test: fetched a real header, persisted an ordered rule,
  matched it against the cached identity, applied its local tag through the
  batch API and found the message by exact `tag:liverule`.
- Existing tag, migration, compose and HTML suites remain green.

## Limits

- Rules are local to this profile/database and are not synchronized across
  devices.
- No scheduled/background rule execution: applying is explicit.
- No provider-side keywords, Gmail labels, Exchange categories or server-side
  rules.
- No rule import/export, per-folder scope chooser, stop-processing flag,
  exceptions list or template/forward actions yet.
