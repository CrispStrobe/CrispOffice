# Word VBA extension: initial remote intake

This intake starts from fork `main` at
`bf761552d22dcd1eb8cbb0ab00ddab6507e1d572` and reconciles the later
`codex/word-vba-unit-conversions-20261120` head
`bbccae1bdead10951e2d7a23b33cf14c55382e02` before the new Word macro work.
The fork is `CrispStrobe/quds_office_suite`; the upstream repository is
`MohammedAsaadAsaad/quds_office_suite`.

## Captured remote work

The branch and pull-request collections were read to exhaustion. Fork PR pages
contain 100, 100 and 80 records. No fork or upstream PR is open. The latest fork
PRs include #278 (Word measurements), #279 (durable Mail flag journal) and #280
(Word bookmark clamping and incremental layout); all are merged.

| Captured category | Total | Ancestor of initial main | Verified historical equivalent | Incoming merge |
| --- | ---: | ---: | ---: | ---: |
| Fork branches | 40 | 29 | 10 | 1 |
| Fork PR heads | 280 | 266 | 14 | 0 |
| Upstream branches | 4 | 4 | 0 | 0 |
| Upstream PR heads | 4 | 4 | 0 | 0 |
| **Total** | **328** | **303** | **24** | **1** |

[intake-inventory.json](intake-inventory.json) records exact branch/PR names,
head SHAs, collection page lengths and the inherited equivalence mappings.
[intake-verification.json](intake-verification.json) records the fresh local
ancestry and immutable-tree checks for every captured ref. There are no
uncovered refs after including the incoming branch as a merge parent.

The historical equivalence mappings were independently recomputed from local
Git objects: complete-tree identities where applicable, all 37 changed ODT
paths for `c3494576`, and identical changed paths plus before/after Git entries
for the three-file `ec70b942` patch. Each accepted replacement is an ancestor
of initial main. These checks establish source inclusion and equivalence; they
do not claim fresh execution of historical test populations.

## New branch reconciliation

The incoming branch has two unmerged commits: `5c7b76a6` reconciles the older
PR277/Word histories and `bbccae1b` saves their source-bound evidence. Initial
main already contains their earlier parents plus newer Mail journal, reader,
native-host, Word layout and qualification changes. There are two merge bases,
`0e4e999a` and `383c0c0c`, so this is a crisscross merge.

The normal merge retains both histories. Twenty-eight overlapping files retain
reviewed current-main behavior, with one compatible API addition: the Mail
presentation constructor accepts `remoteImageUris` and `remoteImageUrls` as
aliases. Both expose the same immutable ordered list; contradictory arguments
are rejected. The incoming alias regression is retained. The existing bounded
reader, image loader, cancellation guards, journal and native-host logic remain
the integration basis.

All **30 unique incoming evidence/checkpoint files** retain their exact incoming
Git blobs, including both PR277 qualification directories and two historical
Zotero checkpoint documents. Their numbers remain attributed to their original
execution sources and are not counted as new tests.

Two incoming test filenames duplicate retained coverage. The incoming
`bulk_flag_runner_test.dart` is byte-for-byte the current
`bulk_flags_test.dart`; the canonical filename is kept. The incoming reader
loader suite maps to the existing `studio_mail_remote_images_incoming_test.dart`
using the current `loadInto`/`clientFactory` API. Its cumulative decoded-byte
assertion is added to the canonical case alongside the stronger existing
placeholder checks. The current 13-case Word header-picture suite retains the
same coverage as the incoming fixture rewrite.

[overlap-resolution.json](overlap-resolution.json) lists every reviewed overlap,
the exact retained evidence blobs and the test-alias dispositions. Runtime
qualification is recorded separately by the new feature work; this intake
record does not represent a fresh run of the old evidence bundles.

GitHub Actions, check runs, statuses and workflow endpoints were neither queried
nor awaited. No workflow or repository policy was changed. Later remote advances
must be refreshed before final publication; this record describes the fixed
initial snapshot above.
