# Final observed incoming snapshot

The final incoming cutoff is **21 November 2026, 06:15:44 UTC / 07:15:44
Europe/Berlin**. This is a fixed snapshot of actively changing branches, not a
claim about commits published after that time. At the cutoff, fork `main` was
still `84046975f286407e3c62e5e5352bc16bc89c0d26`; the only open pull request was
this continuation, [#284](https://github.com/CrispStrobe/quds_office_suite/pull/284).

The [machine-readable reconciliation](final-intake-review.json) combines the
complete initial fork/upstream/PR inventory with the final observed fork branch
and open-PR heads. All **339 refs** are covered: **315 ancestors**, **24 verified
historical equivalents**, and **zero uncovered refs**. Every equivalence was
checked again against its incorporated replacement. Historical divergent
branches were not blindly replayed over subsequent fixes.

## Preserved incoming heads

| Branch | Final observed head | Relationship to the earlier qualified union |
| --- | --- | --- |
| `perf/keystroke-trace-20261121` | `1460876e70fcf3da49644e232e9942b7ee042d8d` | Unchanged; already incorporated and locally qualified |
| `codex/word-vba-sections-20261121` | `47660815c429e15aa280005dc6d76bb36c53eca4` | Additional qualification records; its transfer brace correction matches the correction already retained |
| `codex/zotero-transfer-20261121` | `f4c493d99413ee6347a4fd7d00a5e480cc61bfb3` | Further transfer and ODT fidelity behavior, regression coverage, acceptance tool and documentation |
| `feat/proofing-scheduling-20261121` | `6c3fb2ef2076fe6d8601cdb24d5125c05490e773` | Provider-trigger selection, quiet local typing passes, missing-provider handling and benchmark accounting |

Remote checkpoint `721ad2c74a5d81d54c2eaa2af084e82ba5077991` retains the accepted
Mail checkpoint `99e46629eb9743ffb190183ab1b65c4ad259137b` and the three advanced
incoming heads as parents. Its tree is
`c6e320878ceffb5ba640e62e4f0046988c86dfbe`, byte-identical to the frozen local
qualification tree at `8ff607b914f1a2828e6dceb68d4859e7f0ed4a8e`.

## Integration decisions

The final cutoff changes four production files relative to the accepted union:
the Zotero transfer model, ODT writer, Zotero dialog and proofing scheduler. Mail
production code, provider authority, repository APIs and dependency versions do
not change. The final focused gate checks the new transfer/proofing behavior and
re-executes the Word-based Mail composer; it also verifies unchanged Mail inputs.

The scheduling-document add/add conflict was resolved by retaining the qualified
local contract and incorporating the new trigger and notification semantics.
Unqualified external-editor comparisons and an unfinished benchmark placeholder
were corrected. Changelog entries retain Mail, proofing and Zotero work together.
A missing Word-sections qualification index was restored. Benchmark category
forwarding uses explicit types, and scheduler comments now accurately include
initial document-wide progress. The Zotero dialog formatting correction has no
behavioral effect.

The [local work record](README.md) links the accepted focused results and full
logs. Earlier receipts remain bound to their exact earlier source; they are not
silently relabeled as evidence for newer code. The final incoming gates passed
562 selected tests and three analyzer groups; all 24 composer cases also passed
after checking unchanged Mail inputs.

## Concurrent main publication

During final qualification, main advanced through PR #286 to
`e1ebcb0cd65716a2a78d2ea1114d9ee37a3017ec`. Remote checkpoint
`f63ba0dc85f5ed419fb184fd166971e981d997f6` incorporates that main commit alongside
the final incoming snapshot. The [reconciliation record](publication-main-merge.json)
shows 12 changed paths under `docs/validation/` and zero source, package-test,
manifest or lock changes. The main branch's complete section qualification and
our scoped provenance are both retained. Source-bound acceptance therefore
remains applicable. Remote `main` is checked again immediately before and after
the requested PR merge. No GitHub Actions result or queue is used as an
acceptance dependency.
