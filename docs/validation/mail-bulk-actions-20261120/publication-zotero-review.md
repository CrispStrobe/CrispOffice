# Publication reconciliation: Zotero main advance

Reviewed incoming main `698209aaa6e7f1350b6541df5eb192b7b233443d` against
`e975cec13b289fe067ef406cd3044701ecc44744`. The already reconciled ancestor
`835b8019cbb873c72424e63d4df292174edd3c3e` remains accounted for. This review
found **no concrete blocker** in the four newly changed Zotero production files.

The [machine-readable review](publication-zotero-review.json) records exact Git
blobs, SHA-256 hashes, archive members, source-manifest comparisons and event
recounts. This is incoming evidence review; post-merge local acceptance is a
separate source-bound gate.

## Production changes

| Path beneath `packages/quds_office_engine/lib/src/` | Reviewed behavior |
| --- | --- |
| `word/model/word_zotero_note.dart` | Horizontal spans, logical-column width reconciliation, rectangular row validation and preserved global bounds. Unsupported structures fail while the result is staged. |
| `word/model/word_zotero.dart` | Adjacency from actual citation packet endpoints; paragraph, comment, control, text and structural boundaries remain barriers. |
| `word/model/word_zotero_citing.dart` | Adjacency refers to the next enumerated live field, preserves note/conversion boundaries, and is rechecked before applying staged changes. |
| `zotero/zotero_citing.dart` | Boolean citation-merging capability is accepted; document transfer remains unsupported. |

No new editor production file is introduced. Controller tests exercise the
existing transaction and selection paths with the new engine behavior.

## Incoming evidence verification

The incoming archive `docs/validation/zotero-merged-cells-20261120/local-validation.tar.gz`
is 256,079 bytes with SHA-256
`16555ee79fd5d2699bc015a39cceac70f8d19f7cf700aa7a616b4bf24702917d`.
Every one of its **48 members** matches its declared size and hash.

The qualified source is `180399f99a3898501ab1959e3b845150d7da59fd`, tree
`500931fdbb32699dcce23e3f4eb293b9141168b2`. Independent JSON-event recounts agree
with the incoming report:

| Historical cohort | Passed | Skipped |
| --- | ---: | ---: |
| Engine | 495 | 0 |
| Editor | 378 | 8 |
| Incoming Word/Mail | 928 | 0 |
| Overlapping formatting follow-up | 405 | 0 |

The published 1,801-pass total excludes the repeated 405-case follow-up. Every
cohort has one successful terminal event, no error events or unfinished tests,
and empty stderr. Hidden loader and hook events are excluded; skipped cases
are counted separately. The eight editor skips are recorded by exact case
name in the JSON review.

The 904-input editor source manifest matches all 903 Git-backed inputs at
incoming main. The 769-input engine manifest matches all but the three stated
formatting-only test files; their before/after hashes match the formatting
receipt and the 405-case rerun covers them. Each manifest also binds an
untracked package configuration, which cannot be checked as a Git blob.
All Zotero implementation and test sources match the qualified source.

## Integration and local gate

Retain the consolidated Mail API, accepted canonical measurement sources and
expanded named-measurement tests. Historical Mail code and positional aliases
are already covered by prior reconciliation. Retain the current e975 rendering,
deserializer and font corrections; the incoming qualification predates those
corrections.

After integration, run the following engine suites with strict scoped analysis:

- `word_zotero_adjacent_citations_test.dart`
- `word_zotero_note_table_test.dart`
- `word_zotero_note_tables_integration_test.dart`
- `word_zotero_citing_test.dart`
- `word_zotero_add_note_test.dart`
- `zotero_citing_test.dart`

Their historical population is 282 cases. The two changed editor controller
suites, `word_zotero_add_note_controller_test.dart` and
`word_zotero_adjacent_citations_controller_test.dart`, have 114 historical cases.
Report actual post-merge outcomes separately. These gates cover parsing,
protocol and staging, DOCX persistence, note/cell ownership, undo/redo,
selection restoration and stale-document rejection.

No installed Zotero, Word or LibreOffice round trip is claimed by this review.
GitHub Actions were neither queried nor awaited.
