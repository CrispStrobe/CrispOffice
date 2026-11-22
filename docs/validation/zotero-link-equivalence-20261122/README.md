# Zotero hyperlink equivalence continuation

Date: 22 November 2026.
Working branch: `codex/zotero-continued-parity-20261122`.

## Outcome and scope

Native ODT import accepts ordinary hyperlinks whose separately named visited
and unvisited styles resolve to equivalent supported formatting **and**
inheritance state. Both states use the same current paragraph/inline context.
The comparison retains Western, complex-script and Asian properties, nullable
fallback slots, explicit-property state, generated native script XML and typed
nullable strings.

This removes a name-only refusal while keeping genuinely state-dependent
appearance unsupported. A child span masking unequal parent styles is not an
exception. The glyph-free linked-picture exception remains unchanged in
substance. The original LibreOffice converter case with different visited
appearance is not claimed fixed.

The change is implemented and independently source-reviewed. **No new
executable qualification has run in this continuation.** The 20 regression
cases below are authored, not passed.

## Why compare inheritance too?

A complex-script weight inherited from the Western slot and an explicit
`normal` complex weight can initially look the same. A nested span changing
Western weight to bold changes only the inherited case. Likewise an inherited
complex font and an explicit matching complex font diverge after a nested
Western font change. Comparing only current native projections would lose that
behavior. Strict nullable-slot and explicit-property equality keeps those
documents guarded.

Native property snapshots stringify nullable values. Direct comparisons for
style, language and highlight strings also distinguish absent values from a
literal `"null"` value. The helper regression constructs that counterexample.

[ODF 1.4 Part 3](https://docs.oasis-open.org/office/OpenDocument/part3-schema/OpenDocument-v1.4-os-part3-schema.html)
sections 19.880.2 and 19.907 define the unvisited and visited hyperlink style
references. The strict equivalence rule is this implementation's conservative
choice; the standard does not prescribe that algorithm.

## Incoming work

All 48 captured fork branch heads and upstream main were inspected before new
Zotero source changes. There were no open pull requests at intake; the 100 most
recent requests were merged. Main `ea7ae724` lacked only the last two commits
from `work/mail-connected-navigation-20261122`. Reconciliation `096a69c3`
preserves that ancestry and all 38 missing historical evidence blobs while
retaining newer main production source and Mail tests. Two documentation paths
retain useful historical additions without reverting current Mail behavior.

[intake.json](intake.json) records the exact heads, retained test blobs and
historical evidence blobs. GitHub marked [PR #388](https://github.com/CrispStrobe/quds_office_suite/pull/388)
merged into the working branch after that ancestry-preserving commit. The
42-path intake diff changes documentation/evidence only. Historical tests
remain bound to their original source; none is credited as a fresh run.

Concurrent Mail and VBA branches appeared after that initial intake. Their
source checkpoints explicitly lack executable qualification or promised test
completion. They remain on their own remote branches; recheck and retain any
actual main advance before final publication, without silently importing
unrelated active work.

## Source review and corrections

Two independent reviews checked the style resolver, native property
projection, script fallbacks, field ownership and test APIs. Review identified
and corrected three issues before final publication:

1. Equal current projections do not prove equal nested-span inheritance.
2. Stringified nullable property values can collide with a literal null token.
3. Two XML attribute quotes were missing in the transcribed positive span
   fixture; both fixture strings were corrected.

Review confirmed the existing missing/unsupported/cyclic-style refusal and
the linked-image exception, as well as the public document/citation/save APIs.
This is a source review, not an analyzer or successful test run.

## Authored regression coverage

`packages/quds_office_engine/test/odt_reader_hyperlink_styles_test.dart`
contains 20 cases:

| Cases | Intended coverage | Execution |
| --- | --- | --- |
| 1 | Absent Western language versus literal null language | Not run |
| 3 | Mixed-script DOCX cycles, nested spans, adjacent editable citation/UTF-16 offsets | Not run |
| 11 | Western and script-specific formatting distinctions | Not run |
| 2 | Weight/font inheritance hidden by equal initial appearance | Not run |
| 3 | Child-masked unequal colors, missing styles, unsupported properties | Not run |

The existing `odt_image_style_review_test.dart` remains unchanged and should
run with the new cases. It covers glyph-free image links, missing visited
styles and explicit whitespace/text.

## Execution limitation

The local checkout exhausted workspace capacity while querying repository
object sizes. Subsequent sandbox startup and local file edits failed with
`ENOSPC`. The fixed environment approval policy rejected the cache-cleanup
escalation. GitHub read/write operations remained available, so checkpoints
were saved through Git objects and non-forced expected-head ref updates.

No Dart test, formatter, analyzer, native renderer, DOCX execution, Zotero
desktop or Word/LibreOffice plugin run is claimed. No GitHub Actions status is
queried or awaited.

With the pinned runtime and locked dependencies available, run from
`packages/quds_office_engine`:

```bash
dart test test/odt_reader_hyperlink_styles_test.dart test/odt_image_style_review_test.dart test/odt_document_reader_test.dart test/odt_reader_script_styles_test.dart
dart analyze lib/src/word/serial/odt_document_reader.dart lib/src/word/serial/odt_reader_text_style.dart test/odt_reader_hyperlink_styles_test.dart
dart format --output=none --set-exit-if-changed lib/src/word/serial/odt_document_reader.dart lib/src/word/serial/odt_reader_text_style.dart test/odt_reader_hyperlink_styles_test.dart
```

These commands are recorded follow-up work; they were not executed here.

## Incremental remote checkpoints

| Commit | Saved work |
| --- | --- |
| `096a69c39b5f2ed2e3b81f0873355fbfb46be728` | Initial branch/PR reconciliation, 38 historical evidence blobs and intake record |
| `7c9ecf1cfed7c7439f4b56eca7f51730907029e9` | Bounded hyperlink-state implementation |
| `6d00f68d1fc37bcad0a76546a02930b9bf21b787` | Typed nullable comparisons and 20 authored regressions |
| Following correction/documentation commit | Fixed XML fixture quotes and completed scope/validation documentation |

## Next parity steps

First execute the focused regressions and existing reader/image suites. Then
qualify equivalent links alongside active citations in real LibreOffice files
and native Zotero editing/Refresh, keeping the distinct-appearance failure as
a separate case.

Directional research lists are a useful later implementation: accept canonical
list-container direction, retain matching marker/text direction, inherit
nested list direction with explicit overrides, apply physical right indentation
for RTL, and verify numbering, wrapping, DOCX persistence and editor undo.
The current parser/layout guard remains until that work is implemented and
qualified. Full installed Word/LibreOffice plugin acceptance remains open.
