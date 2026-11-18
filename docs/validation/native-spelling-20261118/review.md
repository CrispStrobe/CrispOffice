# Independent native spelling review

Review base: `98a2a15056e55699b8ba5651fc79b26f94e5efd3`.

Status: **accepted for source review** after the whole-word correction repair
below. No remaining blocking defect was identified in the reviewed production
sources. Local suite results and platform device acceptance remain distinct
from this review.

## Scope and source identity

The review covered shared platform-channel ownership, queued deadlines,
disposal and late completion, exact representable locales, framework cache
invalidation, original UTF-16/grapheme boundaries, protected prose ranges,
apostrophe comparison and presentation, personal-vocabulary persistence and
locale scope, and bounded compound candidate generation.

| Reviewed production file | SHA-256 |
| --- | --- |
| `platform_spelling_provider.dart` | `abd68bc42b835838330c119f8f306d82b32b181ae57e0312f0a3f2b300d1ad26` |
| `german_spelling.dart`, revised implementation | `2a1aeb6d651361418cb1be7f3b3751e60f038cc06f9c435093740fa687157f43` |

## Finding R1: preserve whole-word corrections before compound expansion

The intermediate implementation (SHA-256
`2efdf9df21100db84f6512cf87e8cff8e15bbdd3f3357da791f77a2ad7633fa9`)
returned from its multi-component branch
before the existing full-token dictionary search. Its dedicated personal-word
search preserved complete declared names, but ordinary dictionary corrections
that remove a hyphen were lost. Direct Dart runs against the baseline and
the draft reproduced the regression:

| Input | Baseline retained correction | Draft behavior |
| --- | --- | --- |
| `Make-up` | `Makeup` | Offers `Hake-um`, `Sake-um`, `Mike-um`, `Macke-um`, `Made-um` |
| `Arbeits-zimmer` | `Arbeitszimmer`, `Arbeitszimmern`, `Arbeitszimmers` | Replaces the original with constituent combinations; loses all three |
| `Regierungs-zeit` | `Regierungszeit` | Loses the whole-word correction |
| `Bür-ger` | `Bürger`, `Bürgern`, `Bürgers` | Loses the whole-word corrections |
| `On-line` | `Online`, `Outline`, `Offline` | Loses the whole-word corrections |

**R1 is resolved.** The revised implementation preserves ordinary whole-token
dictionary search within a slice of the same shared candidate budget, before
component expansion. Independent repeat execution against both checkouts
confirmed the principal baseline correction is now **first** for all five
inputs above and the additional nonbreaking-hyphen `Make‑up` case. The exact
six paired outputs and exit codes are retained in
[review-comparison.json](review-comparison.json). The focused regression file
also preserves complete personal names that do not contain the erroneous
separator.

This does not promise identical or exhaustive alternative lists: sharing the
finite search budget can change secondary suggestions. These examples are
engineering regressions, not a linguistic precision/recall panel.

## Revised suggestion-budget review

One `_GermanSuggestionBudget` is shared by the personal-word, whole-token and
component searches. Every examined search candidate decrements it; each
component also has a local allocation. The whole-token call disables compound
splitting, so it cannot recurse back into the compound dispatcher. The normal
64-UTF-16-unit suggestion limit and eight-component bound remain in place.
Breadth-first combination exploration examines at most `maximumSuggestions`
rank vectors with at most eight neighbors each, rather than expanding a
Cartesian product. A component without a validated replacement prevents a
partially corrected compound from being published.

Known component case and exact personal spelling remain intact. Personal
matches use the language-scoped declared vocabulary, not ignored misspellings.
Comparison canonicalizes internal apostrophes without changing source offsets;
replacement presentation restores each source separator kind independently
when its count is preserved. Corrections that intentionally remove a separator
do not receive an invented positional mapping.

## Platform review

The scheduler correctly separates caller completion from physical channel
occupancy: timeout or disposal settles the owner, while the native slot stays
occupied until the underlying future completes. Default services share one
lane; identical injected services share one lane; independent injected
services remain independent. Queued requests have their own deadlines.

The locale conversion rejects unrepresentable variants/extensions rather than
discarding them, preserves scripts and numeric regions, and leaves the
existing reviewed German/English alias mapping in control. Platform findings
use original UTF-16 coordinates with extended-grapheme boundary checks and
shared URL/email/backtick exclusions before constructing source-bound findings.

The requested late-error control is now **passed** in the accepted editor
cohort. It exercises both a disposed and a timed-out active owner, a late raw
service error, and a second queued owner that starts only after physical
completion and then succeeds. Independent event-log inspection found all
21 platform tests successful with no skips, including this control; the cohort
has a successful final event. Exact event identity and the retained log digest
are in [review-closeout.json](review-closeout.json).

## Inherited optional spaCy analysis boundary

The complete optional spaCy package has nine informational strict-analysis
findings in its unchanged `tool/consume_distribution.dart`: eight
`avoid_slow_async_io` findings and one
`curly_braces_in_flow_control_structures` finding. Running
`dart analyze --fatal-infos` on baseline `98a2a150` reproduced the exact current
diagnostic log byte for byte and exited 1. The source is identical in both
checkouts: Git blob `644c0e686fc47e328eebb5b7705b2ee84827cf80`, SHA-256
`cecbc3a4c52dc8880c9eae7add5a925b0c74660e9d1ba1aee7aaae0ffe02cdf6`.

The sealed W7 consumer is retained without stylistic source edits. A clean
library/test or changed-code analysis must be reported with that scope; the
full optional-package strict run is not clean. The baseline log is preserved
as [review-spacy-baseline.log](review-spacy-baseline.log), with exact diagnostic
locations and comparison hashes in the closeout record.

## Later concurrent branch observation

A final bounded read of the named refs found main, native spaCy reference and
W7 unchanged from the captured integration roots. The separate
`codex/zotero-capabilities-20261118` branch had advanced from captured
`c8eca37d1639ac1d20efb83ba2e9da51981a3ad4` to
`1180537c95309fc23bd971b087720d2c66b201b1`. This is a later concurrent arrival,
outside the fixed incoming snapshot. It was not integrated into or qualified
by this spelling change. The original reconciliation snapshot remains intact;
the later observation is recorded separately in the closeout JSON.

## Boundaries

This source review and the direct Dart comparison do not establish installed
Android/iOS dictionaries, physical OS cancellation or device acceptance.
The platform adapter does not claim physical cancellation. No GitHub Actions,
workflow, check or status endpoint was used.
