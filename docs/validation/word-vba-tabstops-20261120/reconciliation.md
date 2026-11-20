# Refreshed source reconciliation

The fresh source audit at **2026-11-20T14:19:00.148362+00:00** is bound to published checkpoint `b5410b107a83f213e27c1476e766551b3f6cd6a4`, tree `4ac401fd0cd2de3fe5f305bf605f20fdc728d3f2`. [refreshed-intake.json](refreshed-intake.json) retains every exact captured ref/head and recomputed inclusion proof. The original [intake.json](intake.json) is preserved unchanged; its SHA-256 is `ed213b718104045276192b8cb556e0ab5262c6a592e491cb81db620732d95d9d`.

## Captured heads and coverage

| Inventory | Ancestors | Exact target | Historical equivalents | Uncovered |
| --- | ---: | ---: | ---: | ---: |
| 19 current fork branches | 9 | 1 | 9 | 0 |
| 255 PR heads | 241 | 0 | 14 | 0 |
| 4 upstream branches | 4 | 0 | 0 | 0 |

The fork count includes the current work branch, `codex/word-vba-ranges-20261120`, whose captured head is the audited checkpoint itself. The initial 18-branch inventory predated that branch. All earlier heads of advancing branches remain included.

| Incoming branch | Captured head | Inclusion |
| --- | --- | --- |
| Main | `243b99a5ee56e591991f381533b2363586bd5dd0` | Direct parent |
| Zotero research tables | `24312d991915418fd6891736a1b427fa8dcbcb71` | Direct parent |
| Outbox management | `d4497a689fa0e27517169bd964d0352ae6d4b2b1` | Direct parent |
| Mail accounts | `86e44e87f829b0309ea7b84fd5d390f596fe7f26` | Ancestor through main |
| Multiple Mail drafts | `b3abdf3b4628a8a703857d69b8f11cd21bc502e1` | Ancestor through main |

The checkpoint's first parent, `535538520a7b71622e6becb9ab8fc5c6862af138`, preserves the incremental Word tab-stop work. The three incoming parents above retain their own source and evidence histories. At capture, the only open PR was draft #254 at the included Outbox-management head; source inclusion is distinct from a PR-interface state change.

## Reconciliation decisions

Main already contained the advanced accounts and drafts heads plus the preceding Zotero evidence head. Its new non-validation files were limited to two Mail test adjustments and an acceptance-runner update. The final Zotero commit contributed four validation files after that shared history. Outbox management contributed its Mail source/tests and intake review. These incoming changes did not modify the Word tab-stop compiler, native editing, or style-cascade implementation.

Integration used ancestry-aware merges. It retained the newer Word layout and PowerPoint imported-inset repairs from the existing feature lineage instead of replacing them with an older Zotero snapshot. Both earlier Outbox intake documents were preserved.

All 14 original historical equivalence proofs were recomputed on this checkpoint. Thirteen pairs have identical full Git trees. The ODT continuation pair matches mode, type and blob identity on all 37 originally changed paths. Every accepted equivalent is an ancestor. No newly advanced branch or PR head was classified using a historical equivalence from a different SHA.

## Scope

This record establishes source/history inclusion for the captured heads. It does not claim runtime qualification of incoming Mail, Flutter, keychain, Zotero or provider workflows. Local Word/Office execution results belong to the separate qualification record and retain their source bindings. GitHub Actions, workflow runs and status checks were neither queried nor awaited. A later advance of main or another ref requires a separate final consistency check.
