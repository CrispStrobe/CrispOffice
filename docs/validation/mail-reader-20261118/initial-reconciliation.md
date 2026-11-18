# Initial Mail implementation reconciliation

The initial repository snapshot was taken on 18 November 2026 before Mail implementation. The exact branch and PR heads are saved in the adjacent JSON files. The audit completed at 18:49:10 UTC. No GitHub Actions, status or workflow endpoint was queried or awaited.

## Scope and result

- Current main: `4fbc8741f314af67592517595c760ba3036dedba`, including the requested Mail scope and implementation plan.
- All **207 existing branch tips** were accounted for: 193 by ancestry in the selected integration heads and 14 by reverified exact historical equivalence.
- All **169 PR heads** were accounted for: 155 by ancestry and the same 14 historical equivalents. There are no unaccounted initial heads.
- Open PRs were #162, #164, #165 and #169. Review head `eedf2aee03964329a2e4c7ee3c771d43b5df4991` already contains #164, #165 and recently merged #166–#168, including Zotero head `6c993f7406037ba462c6aea32e7e6afeebd28c03`.
- Thesaurus head `315beeb3b2967787e27a3d510d758abfb04c6de6` adds two commits beyond the common `decde7792890bf4724c91403fbb6528d8423b01e` baseline. It requires a real merge with the newer review work.

The needed integration frontier is current main, then #162, then #169. Branch names alone do not imply missing work: the 14 legacy aliases have exact preserved equivalents. In particular, earlier AOT/RML histories are already represented, and later deliberate removal remains intact.

## Conflict decisions

Six conflicts in the #169 merge were resolved together:

| File | Resolution |
| --- | --- |
| `docs/ROADMAP.md` | Preserve the Mail scope and current completed thesaurus section. |
| `office_controller.dart` | Retain both the newer text-proofing target contract and the independent thesaurus capture/result contracts. |
| `office_editors.dart` | Preserve Alt+F7 and Alt+Shift+F7 review navigation, Shift+F10/Menu caret interaction, and Shift+F7 thesaurus. Alt navigation has priority over the Shift-only thesaurus action. |
| `word_review_pane.dart` | Preserve keyboard focus and modal guards, adding the thesaurus button to the current header. |
| `word_review_status.dart` | Preserve responsive language controls and changes status, adding the thesaurus button. |
| `office_thesaurus.dart` | Preserve the 64-shard cache and thesaurus improvements alongside the current explicit `unawaited` cleanup and async import. |

The Dart formatter parsed all five resolved Dart files successfully. The six resolved paths passed Git whitespace checks. The complete imported delta retains pre-existing whitespace in original third-party license notices and an original validation stdout log; those provenance bytes were not edited. This check is structural, not a claim that the merged widget behavior has been exercised; root owns subsequent local regression qualification.

## Evidence

- [Initial incoming metadata](baseline-incoming.json): 207 branch tips and the 50 recent PR metadata records.
- [All branch ancestry and exact equivalence](baseline-branches.json).
- [All 169 PR head dispositions](baseline-pr-heads.json).

All audits and conflict edits were local; remote publication is owned by the root implementation agent.
