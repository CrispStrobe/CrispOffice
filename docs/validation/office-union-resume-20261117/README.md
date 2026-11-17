# Resumed Office union qualification — 17 November 2026

## Current state

This continuation starts at `16c7b0fb`, reconciles landed main `4b2b4e78` (PR #149), and retains the newer GECToR/Office recovery `205e913e`. The old PRs #143, #144 and #148 are closed. The new remote branch is `codex/office-union-resume-20261118`; its first reconciliation checkpoint is `1ba5559d`.

All 183 captured branch heads and 149 PR heads were fetched before reconciliation. Their exact refs are in `incoming-refs.json`. Native spaCy #139 remains separate. Deliberate product AOT/RML removal is retained.

**Final qualification is not yet accepted.** The prior continuation saved its source repairs but no completed final `16c7b0fb` test archives. New runs will record one published, frozen source and retain complete raw evidence. Existing results remain attributed to their original sources.

## Reconciled source

The product libraries are unchanged from `16c7b0fb`: this preserves the spreadsheet conditional-format repairs and the common-parent frame bookmark repair. The incoming alternate direct-common-style implementation is reconciled to that existing parent-style implementation. Its added frame tests retain first/later frame anchors, geometry and bookmark assertions. The six cached PAGE/NUMPAGES whitespace cases move into the inline suite so they also run on Node. No assertion is discarded.

The canonical selection now has 222 unique files (the previous 221 plus the frame regression), and the portable selection retains all previous 14 suites plus the two header variant suites and frame suite (17 total). The separate two-test example smoke, 40 retained document consumers, five boundary consumers and serial native 1/2/4/8-thread sweep remain required. Independent review explicitly checks every gate; the older generic audit does not by itself cover smoke and native receipts.

## Recovery and publication

The consumer runtime was restored with all 710 archive members checked, 3,504 runtime file hashes matching, eight pinned fonts, and schema/render smoke controls. The complete recovery receipt is archived under `evidence/`. Flutter and native restoration are complete from the recorded exact pins. The rebuilt native library and quantizer, F32/mixed-Q4_K models, development pack, reference, and all 27 frozen Python dependencies reproduce their expected hashes. Native contract controls pass.

Checkpoint publication uses GitHub Git Data objects and non-forced expected-SHA branch updates because this workspace has no CLI push credentials. Each meaningful source or completed-evidence checkpoint is published independently. A separate publication checkout will preserve the frozen test checkout. GitHub Actions and check/status endpoints are not queried or awaited.

## Active frozen run

Draft PR #150 preserves every checkpoint. The first candidate `3d487008` was rejected by its focused compile check: an added regression attempted to place a body-only WmlFrame into a header/footer visual list. That unsupported test construction is removed; both incoming body/no-unused-style cases remain. No product API or product logic changes. The final source will be re-frozen and all gates rerun. The completed 33-consumer run on the rejected candidate is retained only as historical evidence.
