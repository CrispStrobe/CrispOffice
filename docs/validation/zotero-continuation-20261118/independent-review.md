# Independent review of Zotero import search and stored CSL copying

**No remaining substantive issue found in the reviewed source.** This is a
read-only source review, separate from the accepted test cohorts. No additional
product tests were executed for this review and the reviewer made no product or
test edits.

## Scope and findings

The review traced the new snapshot and searchable-import helpers through the
existing CSL importer, immutable `ZoteroCitationItem` model, canonical source
address parser, source resolver and catalog selection code. It also followed the
Import and Library copy controls through their shared busy/error handling.

An early implementation passed `item.id` (an `Object`, including numeric IDs) to
a string fallback parameter. This compile issue was reported to the implementation
owner and corrected with explicit string conversion before the final snapshot.
No existing ID is rewritten by that display fallback.

Stored-copy behavior preserves embedded CSL fields, unknown nested JSON, explicit
selection order and repeated records. Linked source URI aliases are added without
mutating the original immutable citation values. Personal, group and local
identities remain distinct; offline records remain usable without a connection.
Per-citation locators and affixes are not reference metadata and are intentionally
not promoted into the CSL export. Validation and the existing import bounds are
applied to the complete export before any clipboard write.

The export action uses the already selected snapshots and has no transport path.
The existing connected export formats still use their original explicit network
operation. The stored menu choice has a non-null wrapper value, so dismissing the
popup does not trigger it. Clipboard failure preserves selection; busy guards
prevent overlapping operations and mounted checks prevent post-disposal state
updates after a delayed clipboard completion.

Import filtering uses literal case-insensitive terms against cached metadata.
Each result retains its original import index, selection key and item object;
duplicate CSL IDs cannot collapse or redirect selection. Hidden selections retain
their order and are counted outside the current results. Reload parsing and view
construction finish before old imported selections are removed. A failed reload
keeps the existing search/list/selection, and a successful reload retains catalog
selections while replacing only imported ones. Search and reload reset the result
scroll position.

## Layout repair review

The implementation's focused widget work exposed overflow in both the import
content and the surrounding workspace at narrow width with enlarged text. The
final repair was reviewed after those changes were frozen:

- Import uses an outer `SingleChildScrollView` with a naturally sized Column.
  The textarea and result list each have finite explicit heights; no `Expanded`
  child is laid out on that unbounded scroll axis. Wrapped controls, explanations
  and counts can therefore grow naturally and remain reachable by scrolling.
- The Library minimum-height reservation scales with enlarged text while keeping
  the original geometry at normal text size.
- The workspace title is bounded to two lines. Informational/error/read-only
  messages share a bounded, independently scrollable area. Their full text is
  retained, and their growth cannot consume the whole tab viewport in the
  observed narrow/enlarged-text case.

No new layout issue was found by source inspection. Actual widget acceptance is
reported by the surrounding validation report; this review does not add a second
test count or claim an additional rendering run.

## Test-only lint follow-up

After the first complete editor run, the snapshot regression fixture changed
`if (data != null) 'itemData': data` to the Dart 3.12 null-aware map element
`'itemData': ?data` to satisfy strict analysis. The reviewer rechecked this patch:
both forms omit the entry exactly when the fixture value is null and otherwise
pass the same map value. This does not change the tested cases or product code.
No tests were rerun by this reviewer; the root validation run records acceptance
of the final formatted test source. The binding below reflects that final file.

## Source binding

Recorded at: 2026-11-18T13:12:38.572423+00:00

Repository HEAD at final binding: `b2bcfc23e692476d16d9a7a534ea95a93ae94cd3`. Hashes below bind the reviewed working
source directly; the commit may advance when the same source is checkpointed.
The binding was refreshed after the final incoming integration. All three reviewed
production files and the import-search tests remain byte-identical to the reviewed
versions; only the formatted null-aware fixture entry described above changed.

| Reviewed file | SHA-256 |
| --- | --- |
| `packages/quds_office_editor/lib/src/embed/word_zotero_snapshot.dart` | `e10b99b3d7e0a5123e2dd9d388050135ada0054eeb1a4d86eae8e5b6b5769309` |
| `packages/quds_office_editor/lib/src/embed/word_zotero_import.dart` | `af193a9307bb8dc82eb48d0de53f6336a3b3efb7c19bb9a52fd2e633700824a1` |
| `packages/quds_office_editor/lib/src/embed/word_zotero_dialog.dart` | `b23ad93db95ba3c7c16327df437576bf885342d6989205501014a598e34e0c4c` |
| `packages/quds_office_editor/test/word_zotero_snapshot_test.dart` | `dafcf1b5b4abac3a43549764664b1507bc8d75131df491ff5ca8e6de0a5c4969` |
| `packages/quds_office_editor/test/word_zotero_import_search_test.dart` | `e6ba9ff186115a51cf44b0bbfafa30191273525e8772f24c02a635abae96a3b8` |
