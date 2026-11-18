# Branch reconciliation — 18 November 2026

The complete live inventory contains **191 branches**. GitHub returned pages of 100, 91, and zero names; every returned name matched a locally fetched origin ref. The raw connector pages, exact branch heads, trees, commit timestamps, and key comparisons are saved beside this report. No GitHub Actions, workflow, check, or status endpoint was queried or awaited.

## Current heads and decisions

| Branch | Current head | Decision |
| --- | --- | --- |
| `main` | `482e08176dea6bd8f5fc80d1c0064d96b712db43` | Unchanged from the supplied handoff; already contained in the qualification branch. |
| `codex/office-local-qualification-20261118` | `9d060658ee6be8ec97d73f56b9aec10d346b7952` | Unchanged from the supplied handoff; continue from this preserved checkpoint. |
| `codex/office-continue-20261118` | `e397671e815232847d7223314ba946d1d6740f44` | Concurrent work with all50 consumer evidence on source `9e591cc6`; preserve attribution and do not treat it as qualification of the current product tree. |
| `feat/native-spacy-reference-20261117` | `20026ff49ac37391e2a1fd0947560a587f2f7332` | Separately owned optional native spaCy W6 work remains separate. The isolated calendar fix is already present in the qualification branch. |
| `feat/native-spacy-w7-20261118` | `995a8cd500787f2fe3ae5f268201efa73a15dea6` | Advanced by one documentation-only commit after the supplied handoff's recorded head `2e577840`. Keep the paired packaging continuation separate. |

The W7 advance changes only `docs/validation/native-spacy-w7-20261118/CONTINUE.md`, `README.md`, and `checkpoint-status.json`. Its source and installed-consumer execution still have the qualifications and pending items stated in that handoff. No Office source change from this advance needs integrating.

## Concurrent Office source is different

`codex/office-continue-20261118` retains the alternate direct-common `SectionFrame` implementation; the qualification branch retains the common `QudsTextFrame` parent plus automatic `SectionFrame` style already landed on main. The concurrent branch also imports guarded spaCy W6 and lacks the qualification branch's braces repair in the spreadsheet rendering test. Its newer consumer evidence therefore cannot substitute for fresh qualification of `9a7c80be` / `9d060658`, and a wholesale merge would change the reviewed source. This is consistent with the prior explicit source-reconciliation decision recorded in `docs/validation/office-local-20261118/review/remote-source-review.json`.

## Evidence and limits

- `branch-inventory.json`: complete live GitHub search responses, including final empty page.
- `branch-heads.json`: all 191 exact fetched heads, trees, timestamps and subjects, matched to the live names.
- `key-branch-comparisons.json`: raw GitHub comparisons against the supplied checkpoint. Some large GitHub comparisons return only 300 file entries, so they are not used as complete source-diff inventories.
- `key-head-summary.json`: local Git exact head comparisons and complete changed source path sets for the seven principal heads.
- `local-remote-refs.txt`: local origin ref inventory.

The only commit in the fetched remote histories dated later than the supplied `9d060658` checkpoint is W7's documentation commit `995a8cd5`. Chronology is supplementary evidence; unchanged main and qualification heads are confirmed independently by live GitHub compare responses and local fetched refs. The PR reconciliation is handled independently by the PR reviewer.
