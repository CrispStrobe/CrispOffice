# Native spelling: incoming work reconciliation

The spelling work starts from integration commit
`98a2a15056e55699b8ba5651fc79b26f94e5efd3`. Its parents are the current
native spaCy reference head `6df76a0dff0051312faa04317af41d479dd94162`
(PR #139) and W7 packaging head `2e013f26c7d4db54ecabe2c955117cbce5379408`
(PR #153). The former already contains main
`c8eca37d1639ac1d20efb83ba2e9da51981a3ad4`, including accepted Office
qualification PR #154. These were the only two open PRs at capture; both
remain draft upstream. Including their source here does not activate the
optional grammar provider or qualify broader distribution.

## Captured snapshot

All **193 origin branch heads** (excluding symbolic `origin/HEAD`) and
**154 PR heads** were fetched and inspected before new spelling changes.
The exact names, SHAs, capture time, classifications and comparison evidence
are in [reconciliation.json](reconciliation.json). This is a fixed snapshot;
the newly created `codex/zotero-capabilities-20261118` still pointed to
`c8eca37d` and was already contained at capture.

| Branch disposition | Count | Evidence |
| --- | ---: | --- |
| Ancestor of the combined integration | 175 | `git merge-base --is-ancestor` |
| Already squash-merged on main | 11 | Matching stable Git patch IDs, including the combined PR #140 delta |
| Integration tree already on main | 3 | Exact tree identity for PRs #147, #149 and #152 |
| Superseded Office recovery | 4 | Reviewed source differences and later accepted main fixes |

The eleven patch equivalents cover PRs #134–#138, #140–#142, #145, #146
and #151. Their original branch tips are not ancestors because they were
squashed; their changes have landed. Later accepted edits can make current
file bytes differ without invalidating the recorded original patch equivalence.

The four recovery branches are `codex/gector-office-resume-20261117`,
`codex/office-resume-20261118`, `codex/office-continue-20261118` and
`codex/office-union-resume-20261118`. Their historical evidence remains at the
captured remote SHAs. The earlier common-style frame implementation is
superseded by main's automatic `SectionFrame` style with a common
`QudsTextFrame` parent and matching regressions. The accepted later field,
header ordering, story bookmark and column-boundary repairs are preserved.
Closed PR #150 was reconciled through PR #152. No ancestry-only merge of
obsolete variants is needed to retain these improvements.

## Preserved backend decisions

Main intentionally removed the AOT/RML package, dependencies and analyzer
resources. Its integration history is retained, but older branch presence
does not authorize reintroducing the removed backend. The
[adapter reuse map](../../roadmaps/proofing-adapter-reuse.md) records the
project decision: reuse first-party editor, lifecycle and source-safety work
while keeping the excluded upstream analyzer and data out of the application.
The combined integration has no `packages/quds_proofing_aot` tree.

Native spaCy remains optional and default-disabled. Its consumed native
acceptance and W6 grammar panel retain their original provenance; they are
not fresh spelling-quality evaluation data. This reconciliation does not
claim new runtime validation. GitHub Actions, workflow, check and status
endpoints were not queried, awaited or rerun for this audit.
