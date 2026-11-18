# Independent Zotero source review — 18 November 2026

## Outcome and scope

No unresolved correctness issue remains in the reviewed implementation. The final recorded local cohorts passed: **445 engine tests, 257 editor tests and 18 Studio transport tests** (720 substantive tests across 41 suites, with no skips or error events). This reviewer inspected the completed result summaries and independently matched all source-file SHA-256 entries against the current checkout: 419 engine-cohort files, 538 editor-cohort files and 624 Studio-cohort files, with no mismatches. Every recorded source/dependency/runtime/workspace guard passed. These are the execution owner’s cohorts, not a duplicate independent test run. This review covers reference details, exact-tag actions, staged selection management, additive metadata and the final product diff against current main.

The incoming-source audit is recorded separately in `reconciliation-initial.json` and `RECONCILIATION.md`. The implementation starts from PR #159 (`2292548eb69de2dbb5240ab9da59256f362137c6`), preserving #157, #158 and the existing Office reconciliation. Checkpoint `d36413a2cc8e1de9fd7493b5d1baf2900e63f04b` also incorporates new main `1e07cb852766f8651815138785be74c64a09ddc0` as its second parent; that incoming main merge is tree-identical to #159.

## Findings addressed during implementation

1. **Exact tag identity:** The shared manual-input validator trims surrounding whitespace. Applying that normalization to a server tag could select a different tag. Details retain the original label and disable names whose normalized form differs, as well as syntax-ambiguous, invalid, overlong or over-limit additions. The workspace independently revalidates returned tag actions before requesting anything.
2. **Draft preservation:** Clicking a details tag now uses the last submitted query, preserves both text-field drafts, returns to page zero and retains existing selections. Duplicate active tags are disabled without a redundant request.
3. **Abstract fidelity:** Abstracts, DOI and URL values are inert selectable/copyable data. Literal comparison signs and strings resembling script or URL instructions are retained as text. Display does not invoke a browser, HTML renderer, remote resource, or network operation.
4. **Short-window selection layout:** Source review first identified that a fixed instruction/count region could exceed the available height. Moving instructions, count, empty state and cards into one lazy list addressed that inner-layout issue. The first focused execution then exposed a separate, real **8-pixel outer AlertDialog overflow at 320×480 with text scale 2** (18 cases passed, one failed). Both new dialogs now also set `scrollable: true`, allowing their title and bounded content to scroll inside the remaining dialog height while actions remain accessible. The targeted selected-reference retest and the subsequent 21-case focused run passed, as recorded by the execution owner. These overlapping runs are development evidence, not additional tests to add to final unique totals. The suite also covers 320×360 at scale 1; an additional details/copy case at 320×480 and scale 2 is included in final qualification.

5. **Existing workspace layout after adding Review selected:** The first full editor cohort executed 257 substantive cases: **252 passed and five ended with narrow-layout overflow errors**. The extra review action wrapped to an additional row inside existing fixed-minimum-height catalog/import tabs. The correction adds 56 pixels to the narrow catalog and import minimum heights only when viewport width is below 600 pixels, retaining the existing outer-scroll strategy and preserving wide-window dimensions. No request, selection or document-operation logic changes in this correction. The failed full run is preserved as `attempts/editor-initial-overflow`. All five targeted regressions then passed, and the final full editor rerun passed all 257 cases. The five-case rerun overlaps the full cohort and is excluded from final unique totals.

## Correctness checks

| Area | Review result |
| --- | --- |
| Metadata requests | New fields are read from the existing `data,csljson` response. No new endpoint, extra request, authentication handling or query option is introduced. |
| Optional metadata | Empty defaults preserve existing constructor callers. Malformed optional values are ignored. Type-specific publication fields do not borrow another item type’s value. |
| Tag data | Exact names and source order are retained, exact duplicates removed, and the resulting list detached and immutable. Metadata is not incorrectly limited to the active-filter cap. |
| Source identity | Existing item/library/URI validation is unchanged. Details never invent a durable URI for an unlinked local item. Tags and abstracts are not inserted into CSL snapshots. |
| Details actions | Inspecting does not select an item or change a document. Filter actions recheck mounted state, client identity, library identity and catalog generation after the dialog returns. |
| Tag filtering | Current library/collection/saved-search scope, type and sort settings remain in the existing request path. Exact-name validation, AND semantics and bounded input are shared with manual tag filtering. |
| Selection staging | The dialog copies only the original selection keys. Remove/reorder operations stay local until Apply. Cancel or barrier dismissal returns no result and leaves the original selection intact. |
| Selection identity | Map-entry keys are preserved, including catalog URI keys and `import:index:id` keys. The immutable `ZoteroCitationItem` values are reused, preserving identities, locators, affixes and unknown metadata. |
| Concurrent changes | Apply requires the selection to have the same key/value identities as the captured snapshot; it does not overwrite a later selection replacement. Disposal discards returned results. |
| Document safety | Reviewing/removing/reordering only modifies workspace selection. Insertion still uses the existing guarded document transaction and undo path. |
| Offline access | Review selected is available in both Library and Import CSL JSON. It does not require a connection or API key. |
| Large content | Both dialogs allow the outer title/content to scroll within the available height. Details also have a scrolling metadata body, while tags and selection cards are lazy lists. Narrow catalog/import tabs reserve the additional wrapped review-action row. Long labels are ellipsized with complete tag tooltips and complete copied metadata. |
| Clipboard | Copy is an explicit user action, with a disabled button during the operation and fixed success/failure feedback. Clipboard exceptions do not expose raw platform details. |
| Native ordering | UI text explains that Zotero styles may impose their own citation order; staged ordering is not represented as overriding CSL processing. |

## Regression-test design reviewed

The new engine suite covers constructor compatibility, immutability, user/group reads, publication-field mappings, malformed metadata, unusual tag names, more than twenty display tags, local saved searches, unlinked identities, metadata batches, identity rejection and noncitable child items.

The widget suite exercises loaded metadata inspection without selecting/fetching; inert URL/abstract text and copied content; clipboard failure; exact tag filtering in library, collection and local saved-search scopes; draft preservation; unrepresentable/already-active tags; cross-page reorder/removal; Apply, Cancel and barrier dismissal; empty selection; import-key/checkbox consistency; insertion order and undo/redo; long metadata/tag lists; a changed session while Details is open; mixed catalog/import selection keys; and narrow/short/high-scale layouts. These are behavior-level assertions rather than a mirror of the implementation.

## Final diff and result cross-check

Against current main, product changes are limited to two existing Zotero engine source files, the existing Zotero workspace file and the new library-dialog helper. Two new behavioral test files and both package changelogs accompany them. No other package implementation file, dependency manifest, workflow, network transport, shared Office controller, or native citing processor was modified by this increment. The three concurrently active external work branches remain separate, as recorded in the final reconciliation decision.

Completed summaries inspected: `engine-current/summary.json`, `editor-current/summary.json`, and `studio-current/summary.json` in the local validation output. Source-manifest cross-check evidence is retained in `zotero-review-validation-binding.json`. The complete evidence directory and primary validation report own final totals, strict-check receipts, commands and execution details.

## Practical limits

This change displays a snapshot already loaded for the catalog page; opening Details does not refresh it from Zotero. It does not edit Zotero metadata or tags. The selected-reference review does not deduplicate separate identities by title or item key. Native CSL ordering is still owned by Zotero. Live-account acceptance and a full application build are separate from the controlled transport/widget verification.

## Reviewed source binding

The reviewed product source is saved in checkpoint `d36413a2cc8e1de9fd7493b5d1baf2900e63f04b`, including the 56-pixel narrow catalog/import height correction. The exact implementation-file hashes below match the completed cohorts and bind this review independently of later evidence-only commits. The three concurrent external work branches were not integrated or requalified.

Recorded at `2026-11-18T12:22:54.699364+00:00`.

| Source | SHA-256 |
| --- | --- |
| `packages/quds_office_editor/lib/src/embed/word_zotero_library.dart` | `3bdbc522824e013e7cd4e55749ecd6e59d141f4666638a10be2eefceb774e8c7` |
| `packages/quds_office_editor/lib/src/embed/word_zotero_dialog.dart` | `17e411b9f9be1743335503c62acd8a6e035042e1daffdf4c90ea591bc6101d2d` |
| `packages/quds_office_engine/lib/src/zotero/zotero_models.dart` | `6fd982a56c1c30316d24d44c36820dc71ebd0aee1e3ed96f638b1883b8a5611b` |
| `packages/quds_office_engine/lib/src/zotero/zotero_client.dart` | `de76599335f53bceb979e99898c0bd6f44bfd7741531e8dbb2b90fb730a92395` |
