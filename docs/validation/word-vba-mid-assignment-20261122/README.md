# VBA substring assignment continuation

## Baseline and work in progress

This continuation starts from fork `main`
`3f3cb8508663dde917e913867908dbfd6c3efcf0`, after Word table-navigation PR #376
and Zotero research-note PR #377. Initial intake checked all 37 fork branch
heads, the latest 100 updated PR heads and all four upstream branch heads;
every head is already an ancestor of that baseline. The explicit open-PR
inventory was empty. Upstream `main` was
`15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba`.

The working branch is `codex/word-vba-string-search-20261122`. Progress is saved
there incrementally with ordinary, non-forced updates. GitHub Actions are not
queried or awaited for acceptance; the final integration will refresh remote
heads and use local checks of the affected source.

## Intended increment

Add source-only `Mid` / `Mid$` assignment for mutable local String and
String-valued Variant variables and allocated String/Variant array elements.
The operation replaces a bounded span of UTF-16 code units without growing
the target, allowing fixed-width template data to be prepared before normal
Word table and paragraph operations are emitted.

The intended contract retains the compiler's strict scalar types, exact
integer arguments, once-only expression evaluation, source diagnostics,
resource accounting and detached native publication. Property lvalues, byte
mode (`MidB`), implicit String coercion and live document reads remain outside
this increment. Ordinary expression `Mid$` retains its current behavior.

## Acceptance record

Implementation and independent compiler, corpus, native Word transaction,
CLI and portable-host checks are in progress. This initial checkpoint records
the baseline and scope only; it does not claim completed qualification.

Primary references:

- [Microsoft VBA Mid statement](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/mid-statement)
- [MS-VBAL Mid/MidB/Mid$/MidB$ statement](https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/2a8f3567-c8e0-4176-a802-cf2edeba425f)
