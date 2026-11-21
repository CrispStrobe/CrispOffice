# Final incoming-history reconciliation

The frozen **377-ref snapshot is fully reconciled** at `44a980b089b6b452e73bcc3a51ed8f820d83fd7a`: **363 captured refs are ancestors and 14 historical PR refs have verified equivalents**. No captured current production branch remains unintegrated. The snapshot was captured 2026-11-21 at 18:56:54 UTC; later remote advances are outside this finite checkpoint.

| Source | Captured | Ancestors | Verified equivalents |
|---|---:|---:|---:|
| Fork branches |41|41|0|
| Fork PR heads |332|318|14|
| Original upstream branches |4|4|0|
| Total |377|363|14|

The historical PRs are #134,135,136,137,138,140,141,142,145,146,147,149,151,152. Thirteen have exact whole-tree equality with accepted ancestors. PR #140 has exact equality for all 37 paths changed by its original commit. Every replacement is an ancestor of the integrated checkpoint. Full object IDs, paths, trees and proofs are in `final-intake.json`.

## Preserved incoming heads

| Head | Scope | Local merge commit |
|---|---|---|
| `37afb04e1167fe306e4d124368a08e372638f4ab` | Word merge ancestry and intake docs; native Word 655 source already qualified | `056970556f6c821c3070b8e4213769bc81bbf499` |
| `bf54a8e7d976670af87dd3d36f3afc26c1821d3b` | Native ODT bibliography wrappers, producer-specific note offsets, table geometry | `ba615eaa13d8fc08d423767366275e8a293cb4ce` |
| `81e478ca0ffe249a908362cd233790b8920d439c` | Embedded inline PNG/JPEG import/export, image ownership/styles, distinct drawing names | `44a980b089b6b452e73bcc3a51ed8f820d83fd7a` |

Each merge retains its original incoming head as a parent. The only merge conflict was two constructor hunks in `odt_document_reader.dart`: the resolved call and constructor preserve both the ZIP image input and the LibreOffice note-offset flag. Shared writer/style changes merged automatically and received combined runtime validation.

## Combined qualification and corrections

All **1,206 engine tests in 63 focused ODT/ODF-Zotero suites** and **19 editor tests in 3 ODT suites** passed on the final source. Fatal-info analysis and formatting passed on 15 relevant Dart paths. All source inputs also match committed source `e9a95d7795812a8322c3a0c1d508cf05553bfe82`. Hashes for 1,247 engine/editor Dart inputs are identical before and after every final command, and all final commands share the same source snapshot.

The first combined engine run exposed three incoming failures: two continuous-section page-break regressions caused by newly allocated picture names leaking into story comparisons, and one annotation picture structure regression. A narrow writer correction ignores picture identity only in comparison copies, preserving unique names in emitted packages, and retains existing comment-picture structure while ordinary picture style spans remain. The existing continuous-header regression now also checks emitted identities remain distinct. One redundant nullable operator in an incoming bibliography test was corrected for strict analysis. These changes are captured as a three-file patch in the evidence archive; no incoming production capability was dropped.

Raw initial failures, the overlapping 165-test focused rerun, final 1,225 passing tests, strict analysis/format logs, source hashes and exact commands are retained in the ODT evidence package. No external LibreOffice conversion or installed Zotero/CSL session was run here; the committed LibreOffice fixture tests passed. GitHub Actions were neither queried nor awaited.
