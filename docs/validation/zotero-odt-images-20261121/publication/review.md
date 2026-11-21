# Publication-cutoff remote ref audit

Fetch cutoff: **2026-11-21T18:56:29.620301+00:00**. Both origin and upstream branch/PR-head fetches succeeded. The subsequent snapshot-print TypeError was a display failure; the snapshot is saved and checkout/index trees were unchanged.

Remote main at cutoff: `4970f71f983535d045ce263e86835b499db4fda9`; unchanged from starting main. Remote image checkpoint at cutoff: `81e478ca0ffe249a908362cd233790b8920d439c`.

**381 nonsymbolic refs plus 1 symbolic alias are accounted for:** 363 actual-ancestor, 3 external-in-progress, 1 current-working-checkpoint, 10 retained-patch-equivalent, 4 retained-squash-merged.

Open PRs: **0**. All 10 saved recent PR heads and merge commits are already main ancestors. No initial ref is missing; the 14 historical exceptions retain their exact previously verified heads and committed proof.

| External continuation | Exact head | Current evidence and disposition |
|---|---|---|
| `refs/remotes/origin/codex/word-vba-format-controls-20261121` | `37afb04e1167fe306e4d124368a08e372638f4ab` | The former missing-native-operation gap is resolved: 655b2722 adds the native implementation and registration plus shading deserialization/property merging. The latest merge retains concurrent intake without changing its first-parent package source. Product docs and the merge subject describe the implementation, but the exact-head qualification record still explicitly withholds a completed feature/qualification claim and contains no final execution receipt. Source presence is not a new test pass. **Implementation exists; durable final qualification remains pending at this cutoff.** |
| `refs/remotes/origin/codex/zotero-odt-roundtrip-20261121` | `bf54a8e7d976670af87dd3d36f3afc26c1821d3b` | This is now a source-and-regression checkpoint, not only an intake plan. Its saved record reports targeted development passes and reopening of an untouched prior LibreOffice bibliography artifact, while explicitly leaving final combined validation and external repeat-cycle checks pending. The active footnote separator is still rejected; table-only and endnote-only converter qualifications are separate planned work. **Targeted implementation/development evidence exists; final combined and converter-cycle qualification remains pending.** |
| `refs/remotes/origin/work/mail-scheduled-send-20261121` | `a4ff3da2feeb9b0b8ed53718c3143ab68c1c6c1b` | The head now contains real Mail core/store work and records 482 core plus 107 store-cohort passing cases, clean analysis and formatting. The Studio workflow and final combined-source checks remain pending. Its inherited octopus checkpoint includes Word compiler 85033b80, but not the latest native Word continuation 655b2722 or 37afb04e; its own record requires that continuation before final main publication. **Locally verified scheduling foundation; Studio and combined-source completion remain pending.** |

## Integration decision

No external head has completed, durable final qualification at this cutoff. Preserve all three remote continuations; do not merge their unfinished aggregate into the image milestone. This classification is based on the current exact heads and their actual source/evidence, not the older plan-only checkpoints.

The separate Zotero continuation overlaps `odt_document_reader.dart`, `odt_document_writer.dart`, and `odt_reader_styles.dart`. Its constructor changes for guarded LibreOffice note numbering must be combined with the image reader constructor, and both inherited-style and output changes must survive eventual integration. Its active footnote-separator refusal remains intentional. Finish its combined/external repeat-cycle checks before integrating that work.

The Mail branch already contains the earlier Word compiler checkpoint but not the completed native Word implementation from `655b2722`. Its own record requires the later Word continuation before its final main publication. The latest Word merge incorporates the older Mail intake only, not the new Mail scheduling foundation.

## Read-only verification

Fetch checkout remained `81e478ca0ffe249a908362cd233790b8920d439c`; index tree remained `85bad28ad6aa12fef38af8d4c2c8af8dcee22dae`. Both before/after values match in the saved fetch receipt. Audit checkout was `58fe5b978f63af282ccd3f3406f86e431e440030` before and `58fe5b978f63af282ccd3f3406f86e431e440030` after; its index manifest was unchanged: **True**.

The checkout/index had advanced after the fetch cutoff before this audit ran. Its current stage-zero entries therefore do not equal the earlier fetch tree; that later state does not invalidate the fetch invariance proof or the immutable ref classification.

Later live refs differ from this immutable snapshot; `later_live_ref_deltas_from_snapshot` records exact old/new heads. They are outside this cutoff and belong to root's later frontier check.

The recorded upstream PR heads were refreshed in this cutoff, unlike the preceding pre-qualification audit. No CI, status or workflow endpoint was queried. No source, index, Git ref, or remote state was changed by this audit. Only these scratch accounting files were written.

Rerun `python publish-ref-audit/audit.py` to reproduce this snapshot accounting. A changed external head is flagged for fresh review instead of inheriting an old disposition. Root owns any newer frontier check and final integration decision.
