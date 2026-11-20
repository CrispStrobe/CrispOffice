# Zotero research-note insertion targets — 2026-11-20

## Scope and checkpoints

This continuation extends native Add Note and Add Annotation to authored
footnotes/endnotes and deliberate selections within one paragraph. It retains
Zotero's own picker and processor, rich content, active citation fields and the
existing detached transaction and single undo boundary.

The initial remote checkpoint is `50e33639c545164af9f693265494c28b4ec8c15e`,
with tree `3fcf9b0d252371b534a9e994d9252713d646e1ce`. Its parents retain the
observed main `d040c15a07f652d01e75363031d0efdee6357bda`, typing PR #237
`afa9272a6e31e2cbd6b9896c450a7bccfd62c579`, Mail workspace
`1d26181b0161d88abe5977f9848ffd4cd99e6259` and Zotero continuation PR #238
`40a8f8eb76bd9bf51205fa0cb9f576ba497ad76b`. All three recent branches merged
cleanly. Historical ODS/ODT branches were checked against exact incorporated
file identities; the prior union branch has an identical accepted tree. All
four upstream branch heads were already ancestors of the observed main.
The accompanying JSON files record these comparisons.

## Acceptance plan

- Insert and replace rich research content in both authored note types.
- Keep body anchors, native note markers, citation ordering and note ownership.
- Preserve surrounding prose, formatting, lists and supported embedded images.
- Verify supported DOCX save/reopen and a subsequent citation transaction.
- Restore both the document and the original selection direction with one undo.
- Refuse stale targets, composition, cross-paragraph and protected selections.
- Exercise the shared native command dialog, including cancellation.
- Run focused regressions for the reconciled proofing cache and slide gradients.

The first implementation checkpoint is saved before local validation completes.
Its presence on the continuation branch is not a test result or a parity claim.
Final local results and remaining limitations will be recorded here before main
publication. GitHub Actions are not a waiting or acceptance path for this work.

This environment has no live Zotero, Word or LibreOffice acceptance session.
Controlled protocol tests and serializer tests do not qualify those applications.
Active ODT transfer, rich note tables and broader raster fidelity remain separate
roadmap items.
