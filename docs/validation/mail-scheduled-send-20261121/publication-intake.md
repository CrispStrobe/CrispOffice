# Publication refresh: incoming history and source qualification

The separate publication snapshot captures **380 refs** and is fully reconciled at **`964783488cfa8079464e7dc80c1df6bb139323f5`**, tree `47ec5e720309a1efeb3a91824ab49b5700b16b27`. **366 refs are ancestors; 14 historical PR heads have independently reverified equivalents.** All captured current branch and PR work is accounted for.

This refresh preserves the original 377-ref report and its source-specific qualification unchanged. It captures the already-fetched publication refs, including new PRs #333/#334 and the typography branch, without continuing to chase concurrent branch changes.

| Source | Captured | Ancestors | Historical equivalents |
|---|---:|---:|---:|
| Fork branch tips |42|42|0|
| Fork PR heads |334|320|14|
| Original upstream branches |4|4|0|
| **Total** |**380**|**366**|**14**|

The 14 historical exceptions retain the original proof: 13 identical whole trees, and PR #140 with all 37 original changed paths identical to an accepted ancestor. The corresponding replacement commits remain ancestors of this publication source. The four upstream branch heads are unchanged.

## Newly integrated source and ancestry

| Captured head | Disposition and source delta |
|---|---|
| Main `5c59a062e86e24d043ba06cfe8f0a69074c44f62` | Explicit publication parent. Includes merged PR #334 and Word `26748a56`; its two changed Word Dart files are byte-identical to the prior qualified source, so effective additions are provenance/documentation. |
| Word `26748a56f9597d3198c7652c26eade6a97da7c2f` | Ancestor through main. PR #334 was merged 2026-11-21 at 18:57:33 UTC. |
| Typography branch | Its captured tip equals main `5c59a062`; no separate typography implementation exists in this capture. |
| Zotero images `58fe5b978f63af282ccd3f3406f86e431e440030` | Explicit publication parent. Uses an allocated-to-authored picture-name map for continuous-story comparison, with collision/title regression coverage. Comment picture tests now verify preserved character styling. |
| Zotero native ODT `3eac83d12180f189430e8c81bfef4bf438087c5d` | Explicit publication parent. Adds uniform native DOCX table-cell margins, bounded direct/style/default inheritance, optional ODF soft-page-break hints and valid negative-zero sequence syntax. PR #333 was open/draft when inspected; its captured head is fully included in the publication commit. |

The publication commit's first parent is prior qualified source `e9a95d7795812a8322c3a0c1d508cf05553bfe82`, followed by main and both Zotero heads. Root reconciled documentation conflicts preserving both feature records. The incoming picture-name map and styled comment-picture behavior supersede the earlier local temporary workarounds; table-alignment changes and the independent emitted-name uniqueness assertion remain.

The margin importer projects only complete uniform physical edges with admitted values. Unsupported, partial, asymmetric, foreign, duplicate and historical declarations retain opaque source rather than being guessed into a scalar. Named/default style behavior, zero margin and repeated DOCX cycles are covered. The soft-break hint permits only XML boolean syntax; authored hard breaks and citation offsets are retained.

## Fresh combined qualification

**1,725 engine cases across 86 suites** and **19 editor cases across 3 suites** passed, with zero failures or skips. The engine set combines all 64 ODT/ODF-Zotero suites and 22 affected native Word table, style, layout and package-preservation suites. Strict analysis and formatting passed all 11 changed Dart files. No source or formatting repairs were needed during this qualification.

All **1,250 engine/editor Dart inputs** are identical across before/after snapshots for every final command and match the Git blobs of the publication commit. The unchanged broad VBA cohort was not repeated. These counts overlap earlier tests and must not be added to prior gates as distinct cases.

`qualification.json`, `publication-source.patch`, raw command/event logs and immutable input manifests are retained in the publication evidence archive. No GitHub Actions were queried or awaited. No external LibreOffice converter or installed Zotero/CSL session was executed here; the existing retained-fixture tests ran locally. Studio Mail source/tests are separately qualified by the runtime agent.
