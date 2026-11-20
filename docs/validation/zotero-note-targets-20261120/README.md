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

## Accepted engine execution

The final integrated engine source passed **294 visible tests**, with no failures,
errors or skips, across the eleven original suites in
`packages/quds_office_engine/tool/zotero/research_target_acceptance.dart`.
The genuine reporter recorded `success: true` and exit code 0. All 359 recorded
source hashes remained unchanged during the run.

The tested local merge `730d2177e9dc2648224fc61dd50b594abe8dc278` has the
same tree `242f8c111a21cb5baeeed3d6d73902a3821e739c` as remote checkpoint
`586e53502701d2f568f38bdcfb4aa5fd64a53142`. This includes main's subsequent
Mail, font-pack and PDF updates and the typing documentation-only follow-up.
The exact source hashes, command, results and cleanup receipt are in `engine/`.

An earlier three-suite run had 94 passes and two new fixture failures. Review
corrected the invalid transient list-restart expectation and found/fixed missing
note list-label resolution on reopening. The final integrated run above covers
those cases and supersedes the earlier attempt. A separate interrupted run that
filled the workspace disk is excluded from accepted evidence.

## Remaining execution at this checkpoint

Flutter/controller acceptance and the final targeted analyzer are still in
progress. This checkpoint preserves the completed engine evidence; it does not
claim those remaining checks passed. The single-importer harnesses retain the
original tests and bound compiler-cache disk use after capacity recovery.

## Source review and limits

Independent reviews covered native field boundaries, bookmark/atomic endpoints,
separate text-box stories, note numbering, controller selection mapping, stale
transactions, rollback and undo. See `source-review.json` and
`latest-integration.json` for exact reviewed blobs and reconciliation evidence.

GitHub Actions were not queried or awaited. This environment has no live Zotero,
Word, LibreOffice or Apache OpenOffice acceptance session. Controlled protocol,
serializer and controller tests cannot qualify those applications. Active ODT
transfer, imported rich-note tables, wider structural selections and broader
raster fidelity remain separate roadmap items.
