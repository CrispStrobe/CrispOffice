# Correspondent and recipient header search

**Status:** source and regression cases implemented; Dart/Flutter execution is
pending because the current workspace cannot start processes. See the
[source and validation record](../../validation/mail-discovery-shortcuts-20261122/README.md).
This extends the existing [loaded-header query language](header-search.md).

## User path

In a connected or cached Mail folder, enter a query in the existing search box.
Use the same query in **Search saved mail**, or save it with explicit account
and folder choices. English, German and Arabic help includes the new fields.

| Query | Matches |
| --- | --- |
| `recipient:alice@example.test` | The value occurs in public To or Cc headers |
| `participant:alice@example.test` | The value occurs in public From, To or Cc headers |
| `recipient:"Review Team"` | The phrase occurs within To or within Cc |
| `participant:alice NOT recipient:team` | Alice occurs in From/To/Cc and team occurs in neither To nor Cc |
| `(participant:alice OR participant:bob) is:unread` | Either correspondent matches and the read state is observed unread |

These are case-insensitive substring searches over the names and addresses
already present in the header projection. They are not address-book expansion
or exact address equality. Quoted phrases never join different header groups.
Header display punctuation can differ between loaded and cached projections;
use a name or address separately when a query must work in both.

A bare `alice` keeps its existing subject/sender meaning. `from:`, `to:` and
`cc:` still restrict matching to their individual fields. These singular Quds
field names are not a claim of compatibility with another client's syntax.

## Scope and privacy

The connected message list examines only its loaded header window. Cached
search examines the retained headers inside its existing selected account and
folder scope. Saving either new field preserves the exact query and chosen
scope; it does not widen the search or fetch additional messages.

The document passed to the evaluator contains public From/To/Cc only. Bcc,
private transport-envelope recipients, message bodies and attachments are not
added. Opening help, entering a query or changing filters neither opens a
message nor requests another page or performs a provider mutation.

## Query behavior

Each new field is one predicate and counts as one term. Negation applies to
the whole field union: `NOT participant:alice` requires Alice to be absent
from all three participating groups. The existing AND/OR precedence,
parentheses, quoted literals and leading-minus negation are unchanged.
Unknown dates and flags retain the existing three-valued Boolean behavior.

The existing limits remain: 1,024 UTF-16 code units, 32 terms, 32 explicit
operators and eight nested groups. An invalid or incomplete query reports the
existing typed error and does not fall back to a broader query. No schema,
dependency, protocol or provider capability changes are required.

## Regression coverage and next work

Authored cases cover From/To/Cc versus subject-only matches, case and Unicode,
quoted literals, per-group phrases, whole-union negation, Boolean composition,
unknown flags and term limits. Store cases protect Bcc/body exclusion and saved
account/folder scope. Shared UI and Studio cases cover no-open/no-load filtering,
localized help and Arabic example direction.

Those cases have not run in this task. Independent source review and exact
remote readback are recorded separately from runtime acceptance. Categories/tags
and ordered rules remain the next larger organization increment, followed by
indexed body/provider search, persistent conversations, Drafts/Sent
reconciliation and fuller background multi-account work.
