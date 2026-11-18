# Mail M05 incoming reconciliation — 18 November 2026

Captured all local refs freshly fetched by the parent. 211 origin branch heads and 172 PR heads include the current task branch/PR. The external inventory is **210 branches and 171 PR heads**. No GitHub Actions, checks or status endpoints were used.

The saved Mail head is `2fef06f5fe9aefb07a48c75c0e762eee3edf26e1`. Current main is `690e6ac8a1f7d8f5c8d4bea69d989a6728f3b27e`, with 12 commits missing from that saved Mail head. It incorporates latest review/thesaurus head `4600c0eb` and Zotero Notes evidence `c93fc23b`. The unique additional branch is `codex/zotero-word-parity-20261118` at `aad56eb498aa4839ad5bb11fd35d9f734d2ca397`: exactly one merge commit whose parents are the saved Mail head and `4600c0eb`. It adds no new Zotero feature beyond this reconciliation. Both main and this merge head must be included to account for all captured history.

## Ref accounting before the merge

| Inventory | In saved Mail ancestry | In main ancestry only | Additional parity merge | Verified historical equivalents | Unaccounted |
| --- | ---: | ---: | ---: | ---: | ---: |
| External branches | 191 | 4 | 1 | 14 | 0 |
| External PR heads | 155 | 2 | 0 | 14 | 0 |

All 14 historical equivalents were reverified from immutable git objects: 10 exact raw deltas, three identical trees, and the ODT continuation's 37 changed-file identities. Their equivalent commits remain ancestors of the saved Mail head and current main. They need not be blindly re-applied. The full receipt contains every ref/SHA, changes against the prior full capture plus publication addendum, new commits and equivalent proofs.

## Conflicts and selected resolutions

`git merge-tree --write-tree` found four real conflicts. Parent handles the browser network-guard local variable rename. Three Office files were resolved here:

- `studio_chrome.dart`: use the incoming measured Arabic-aware label height and matching app-switcher padding. This is identical to the reviewed parity-branch source.
- `suite_workspace.dart`: incoming title/ribbon metric sizing, scroll keys and document-title drag region, while preserving the Mail branch's compact navigation button/live modal refresh, scaled status bar, independent compact/desktop PDF thumbnail controllers, and numeric oversized-draft feedback. The combined file is identical to the parity-branch source.
- `studio_comment_draft_proofing_test.dart`: preserve the stricter 390px scaled Arabic fixture, compact modal navigation exercise and optional visual capture. Keep the exact numeric-limit assertion (`16384`) matching the retained user-visible message; the incoming generic text assertion would mismatch that retained behavior.

The protected-review keyboard inspection change in `office_editors.dart` merges cleanly and remains present. Existing Mail source/fork improvements and provenance should remain intact.

## Local regression targets

Run analysis on the three resolved files plus `office_editors.dart`. Run `studio_comment_draft_proofing_test.dart`, `studio_compact_navigation_test.dart` (explicit Linux Material scrollbar/resize fixture), and `studio_comment_keyboard_review_test.dart`. The relevant protected document-review tests live in `word_keyboard_review_test.dart`, `word_keyboard_context_geometry_test.dart` and `word_keyboard_review_identity_test.dart`. These are suggestions; no tests were run as part of the read-only ancestry audit.

## Evidence limits

This is an incoming-source audit and conflict resolution record, not new runtime qualification. Parent owns the final merge, checkpoint, local tests and post-merge ancestry readback. Branches can move after capture; a final fetch is necessary before the task's closing report.
