# Boolean search of loaded mailbox headers

This increment extends the existing structured header search in connected IMAP,
EWS, Gmail, Microsoft 365 and cached mailbox lists. The search remains local to
the headers currently loaded in the selected folder. It does not turn a partial
cache into an account-wide or server search.

## User workflow

Type a query in the existing message-list search box. Open **Search help** for
English, German or Arabic instructions. The same operator spelling works in all
three languages.

| Query | Behavior |
| --- | --- |
| `from:alice OR from:bob` | Either sender matches |
| `(from:alice OR from:bob) is:unread` | Either sender, with an observed unread state |
| `from:alice AND subject:report` | Both conditions match; a space also means AND |
| `NOT subject:invoice` | Subject does not contain invoice |
| `from:alice -subject:"weekly digest"` | Alice's mail excluding that subject phrase |
| `NOT (is:read OR is:flagged)` | Both flags are observed and both are false |
| `(on:2026-11-20 OR on:2026-11-21) from:team` | Team mail on either named local day |
| `subject:OR` or `"OR"` | Literal text; field values and quotes do not become operators |

Precedence is **NOT, then AND, then OR**. Parentheses override that order.
For example, `from:alice OR from:bob is:unread` includes all loaded mail from
Alice, plus unread mail from Bob. Add parentheses around the alternatives when
the unread condition should apply to both.

Boolean operator names must be uppercase and standalone. Lowercase
`and`, `or` and `not` remain ordinary text. A leading minus negates the following
condition or group. Internal hyphens, including date separators, stay literal.
Spaces separate adjacent operands; parentheses can touch their contents.
Concatenations such as `foo(bar)`, `(foo)(bar)` and `"foo"bar` are rejected.
Field values must follow the colon directly; use
`(subject:alpha OR subject:beta)` instead of `subject:(alpha OR beta)`.

Existing field names, phrases, escapes and local-calendar date semantics remain
unchanged. Before and after exclude the entire named day. Unread and Flagged
chips combine with the whole query using AND.

## Unknown observations

A missing flag or date is unknown, not false. Negation preserves that unknown
state. `NOT is:read` therefore matches observed unread messages but does not
include a message whose read state has never been fetched. Missing dates also
do not satisfy a negated date test.

The evaluator uses three-valued Boolean logic internally. A true OR alternative
can establish a match despite an unknown alternative; a false AND condition can
establish non-match. Only an overall true result is visible. This also means
`NOT (is:read AND subject:invoice)` can match a definitely non-invoice message
even when its read flag is unknown: the subject already disproves the group.
No missing provider observation is filled in or persisted by search.

## Bounds and interaction safety

Queries retain the 1,024 UTF-16 code-unit and 32 predicate limits. Every leaf in
every Boolean branch counts toward the predicate limit. Up to 32 explicit
AND/OR/NOT/minus operators and eight nested parenthesis groups are accepted.
The complete input is parsed before matching any message. Malformed expressions,
unsupported fields, wildcards, invalid dates, dangling operators and excess
limits fail closed with a localized error and zero matching rows.

Query editing never opens a body, fetches more headers, changes read state,
writes a command journal or sends mail. Existing explicit **Load more** remains
available. Changing filters prunes hidden checked messages; broadening the query
does not reselect them. Previously opened bulk menus and row callbacks cannot
act after a query edit or an account/folder change. The same account/folder
reset and compact-reader state rules apply as before.

Help examples beginning with parentheses, NOT or minus retain left-to-right
syntax inside Arabic prose. Ordinary localized prose keeps the host direction.

## Verification status

This increment includes focused core regression tests, mailbox widget tests,
bulk-selection regressions and EN/DE/AR help/error checks. The implementation
and test expectations received independent static review.

**The original checkpoint had no Dart/Flutter runtime qualification.** Its
checkout exhausted disk space before commands could run. That original record
is retained without relabeling it as a pass. The later
[unified cached-search continuation](../../validation/mail-unified-cache-20261121/README.md)
executes the complete Mail core and shared Mail UI suites with the pinned
Flutter 3.47.8 / Dart 3.13.7 runtime, including both preserved Boolean regression
suites and the existing locale/selection tests. Its source-bound results are
fresh execution, separate from the original static review.

See [the validation record](../../validation/mail-boolean-search-20261121/README.md)
for the exact scope and reproduction commands. GitHub Actions are neither a
dependency of this work nor evidence of a passing local run.

## Next increments

This is a bounded discovery improvement, not full desktop-client parity.
The next broader work remains:

1. Extend the [account-wide/unified cached-header workflow](unified-cached-search.md)
   with saved live views and broader indexed body/server coverage.
2. Conversation grouping over stable message identities and the shared workspace.
3. Durable archive/move/delete and rules using the existing command journal.
4. Rich composition, signatures/templates, scheduling and provider Sent
   reconciliation, each with provider and installed-platform acceptance.

The staged benchmark follows the documented workflows in
[Thunderbird search](https://support.mozilla.org/en-US/kb/global-search),
[Thunderbird saved searches](https://support.mozilla.org/en-US/kb/using-saved-searches),
[eM Client mail features](https://www.emclient.com/features-email) and
[Microsoft's Outlook capability comparison](https://support.microsoft.com/en-us/outlook/getstarted/feature-comparison-between-new-outlook-and-classic-outlook).
These are product benchmarks, not a claim that their query syntax or provider
coverage is identical to Quds.
