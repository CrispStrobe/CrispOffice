# Mail final intake refresh

Frozen local graph target: `55825a375c6acd875f7bb2d408b6069795f10b48`.
Remote main remains `4970f71f983535d045ce263e86835b499db4fda9`.

The refresh captured 377 refs: 41 fork branches, all 332 fork PR heads and all four upstream branches. 360 are current-work-branch ancestors, 14 old PR heads are independently reverified equivalents, and three current branch heads need ancestry integration. No GitHub Actions/status queries or waits were used.

## Frozen incoming heads

- Word `37afb04e1167fe306e4d124368a08e372638f4ab`: merges the already captured Zotero intake checkpoints into the already accepted Word source. No engine change relative to qualified `655b2722`.
- Bibliography `bf54a8e7d976670af87dd3d36f3afc26c1821d3b`: admits bounded LibreOffice bibliography section wrappers, qualifies producer-specific note numbering offsets, preserves explicit editable-ODT table alignment/width, validates inert sequence declarations, and adds source fixtures/regressions. Production changes are `odt_document_reader.dart`, `odt_document_writer.dart` and `odt_reader_styles.dart`.
- Images `81e478ca0ffe249a908362cd233790b8920d439c` (following `fac61ecd`): imports bounded embedded PNG/upright JPEG frames, preserves inline picture positions and metadata through editable ODT, assigns unique frame names, and validates the associated graphic/link styles. It changes those same three files plus `odt_writer_zotero.dart` and adds `odt_reader_images.dart`, three engine suites, an editor suite and acceptance tooling/docs.

## Merge review

A read-only `git merge-tree --write-tree bf54a8e7 81e478ca` found one conflicted file, `odt_document_reader.dart`. Its two conflict regions are the constructor call/signature: images supplies a positional `ZipReader`, while bibliography supplies named `libreOfficeNoteOffsets`. Preserve both parameters and both initialization behaviors. Writer and style changes merge automatically because their edits concern different behaviors.

The new image reader does not fetch external image URLs. It reuses bounded raster validation and accounts for previously unsupported inventory paths only after fully decoding their corresponding frames. Images inside citation/bibliography fields remain refused. The bibliography continuation admits only wrapper properties that have no active protection/layout effect and requires observed ordinal agreement when applying its restricted LibreOffice-producer convention. No source-review blocker was found; execution on the combined source remains required.

Relevant new/changed tests are `odt_libreoffice_bibliography_test.dart`, `odt_libreoffice_fixture_test.dart`, `odt_libreoffice_note_offsets_test.dart`, `odt_zotero_table_geometry_test.dart`, `odt_image_style_review_test.dart`, `odt_reader_images_test.dart`, `odt_zotero_image_lifecycle_test.dart` and editor `word_odt_image_load_test.dart`. Existing bounded ODT/ODF-Zotero reader/writer suites should run on the combination, since these shared serializers feed the imported features.

No source was merged or modified during this read-only refresh. This is a finite captured inventory, not a promise that concurrently active branches cannot advance afterward.

## Reconciliation completed

The frozen 377-ref snapshot is now reconciled at `44a980b089b6b452e73bcc3a51ed8f820d83fd7a` (tree `4d1b2ec8a519a283897e703e385aa92165ea6b19`): 363 captured refs are ancestors and 14 historical PR refs retain exact verified equivalents. All 41 fork branch tips, 318 of 332 PR heads, and all 4 upstream branch tips are ancestors. The remaining 14 PR heads have 13 whole-tree equivalences and one original-change-path equivalence across all 37 paths, reverified after merging. No captured current production branch remains unintegrated.

Merge commits preserve the original branch heads as parents: `05697055` for Word37, `ba615eaa` for bibliography bf54, and `44a980b0` for images81. The only conflict was the ODT reader construction/constructor; both the ZIP image input and producer-specific note-offset flag are retained. Combined engine/editor validation is recorded separately. The snapshot remains finite: no Actions polling and no endless branch chasing.
