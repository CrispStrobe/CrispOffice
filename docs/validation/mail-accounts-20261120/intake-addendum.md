# Mail intake reconciliation addendum

Repository: [`CrispStrobe/quds_office_suite`](https://github.com/CrispStrobe/quds_office_suite). Work branch: `work/mail-accounts-20261120`; review [PR #243](https://github.com/CrispStrobe/quds_office_suite/pull/243). Frozen checkpoint: [`cb7f832590b77bd5be6e04814f1b64ae418b2b55`](https://github.com/CrispStrobe/quds_office_suite/commit/cb7f832590b77bd5be6e04814f1b64ae418b2b55).

This receipt accounts for the exact saved captures below. No moving remote heads were fetched or enumerated, no GitHub Actions were queried or awaited, no compiler or tests were run, and no repository source, index, HEAD or refs were changed.

## Included work

- The original **25 named branch heads** resolve to **16 actual ancestors and 9 historical content equivalents**. The original **241 fetched PR refs** resolve to **227 actual ancestors and 14 historical equivalents**.
- The committed continuation receipt additionally records a **16-branch / 244-PR-head** snapshot at **2026-11-20T11:02:39.086768+00:00**. The later reply-lane receipt records **19 branch observations**, followed by the four fixed tips below. Earlier observations remain represented when a ref advanced.
- The union covers **31 fork branch names / 45 branch-head pairs** and **247 PR numbers / 250 PR-head pairs**. These are counts across captures, not a simultaneously live branch inventory. All four captured upstream heads are ancestors. **No fixed head is unresolved.**

| Later captured branch | Exact head | Inclusion |
| --- | --- | --- |
| `fix/mail-credential-stores-chrome-20261120` | `a71a7f19e7146a19ecf79122477210fd71afb51b` | Direct parent of `33b2eba`. |
| `perf/incremental-layout-20261120` | `a66657ab4501e2a77852aa55a61d8b75aee60dec` | Direct parent of `cb7f832`. [PR #247](https://github.com/CrispStrobe/quds_office_suite/pull/247). |
| `work/mail-body-projection-20261120` | `56e1f58c19bbffc00465b8e4e48fa8fbca0c2015` | Direct parent of `91645cd`. |
| `work/mail-reply-forward-20261120` | `ceb2f5308a9b5edfea200294cbb5d62b728cf7d4` | Parent of `56e1f58`; included through its merge. |

## Native merge ancestry

| Checkpoint | Exact parents |
| --- | --- |
| `0c2f09faf32cf5bdd2222cf73d0412abf954e260` | `a059c0249a25bef602640c8b8d504bd8da41c619`; `3ffa599ff003a6e678260df1237b01887693e546`; `84d02025fade09c80f3f58942b466f4522eb4434`; `4f5c153774ab7492430c2b68653c54e0c08dc2ad` |
| `33b2eba965a58d09317ccdf060f1ae1704d735c3` | `0c2f09faf32cf5bdd2222cf73d0412abf954e260`; `a71a7f19e7146a19ecf79122477210fd71afb51b` |
| `91645cd5da644a393f3827ed390b25b750b42c71` | `33b2eba965a58d09317ccdf060f1ae1704d735c3`; `56e1f58c19bbffc00465b8e4e48fa8fbca0c2015` |
| `cb7f832590b77bd5be6e04814f1b64ae418b2b55` | `91645cd5da644a393f3827ed390b25b750b42c71`; `a66657ab4501e2a77852aa55a61d8b75aee60dec` |

The first merge retains saved Mail `a059c02`, fixed main `3ffa599`, newer Downloads `84d0202` and font/PPTX integration `4f5c153`. Fixed main already carries PRs **#245 and #246**, including the optional font-pack catalog stub and dependency correction. The next three merges preserve the four later tips.

Reviewed merge resolutions add storage initialization ownership checks, busy-phase storage guards, clearing of prior account associations, body API regressions and documentation. Ancestry establishes inclusion; it does not imply that every resolved file is byte-identical to an incoming parent.

## Historical equivalents

**Fourteen historical heads** have accepted equivalents: nine appear in captured branch names and five only in old PR refs. Thirteen have identical whole trees. The ODT continuation has exact mode/type/object equality on all **37 changed paths**. Every accepted counterpart is locally confirmed as an ancestor of the frozen target.

Ten historical objects were available and their proofs were rechecked locally. Four obsolete PR-only objects were absent from the restored clone; their exact proofs remain in the committed continuation receipt, with accepted-ancestor inclusion independently verified. They were not fetched or reapplied to restore old trees.

PR #240 illustrates why observations are retained separately: saved metadata and later refs record `586e535`, `0f90dc0`, `c201f68`, `6c23d94`. All four observed heads are ancestors.

## Bounded qualification

The JSON contains every observed branch and PR head, its provenance and disposition, exact checkpoint parents and trees, historical proofs, and previously saved GitHub fixed-SHA comparisons. It makes no claim about refs created or advanced after those captures. Missing enumeration timestamps are stated explicitly; PR update timestamps are not substituted for capture times.

This is an inclusion audit, with no final-main, functional-test, native-store, provider or performance qualification claim. The body-projection increment does not by itself establish a completed new reply/forward workflow. Source preservation and the nine ownership / eleven body regression declarations are recorded separately in `integration-review.json`; the parent task owns local test results and final publication.

## Immutable source receipts

- [docs/validation/mail-accounts-20261120/intake.json](https://github.com/CrispStrobe/quds_office_suite/blob/cb7f832590b77bd5be6e04814f1b64ae418b2b55/docs/validation/mail-accounts-20261120/intake.json), Git blob `0f00e5e8eeb6f0d3ae0429319e841428f4af151a`.
- [docs/validation/office-vba-continuation-20261120/integration/final-inclusion.json](https://github.com/CrispStrobe/quds_office_suite/blob/cb7f832590b77bd5be6e04814f1b64ae418b2b55/docs/validation/office-vba-continuation-20261120/integration/final-inclusion.json), Git blob `aed77ee53a95bcea88ab7a203301d500b9ce69ba`.
- [docs/validation/mail-reply-forward-20261120/intake.json](https://github.com/CrispStrobe/quds_office_suite/blob/cb7f832590b77bd5be6e04814f1b64ae418b2b55/docs/validation/mail-reply-forward-20261120/intake.json), Git blob `fad219108f67a0974922ce2f0f81800f7959c501`.
- [docs/validation/office-vba-continuation-20261120/integration/final-main-reconciliation.json](https://github.com/CrispStrobe/quds_office_suite/blob/cb7f832590b77bd5be6e04814f1b64ae418b2b55/docs/validation/office-vba-continuation-20261120/integration/final-main-reconciliation.json), Git blob `9da4ff39fe8cef6ec8ff54ab574836f8a7b5cee3`.

Full evidence: `intake-addendum.json`.
