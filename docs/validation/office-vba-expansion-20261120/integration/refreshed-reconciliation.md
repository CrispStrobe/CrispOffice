# Refreshed intake and published source inclusion

The [qualified-source inclusion receipt](qualified-source-inclusion.json)
targets the actual published frozen commit
`c9cbeb1248d6b5f088d1084a8c113a743aa7a77f`, tree
`deecb1a98558680c0537e478bc9159350d97e6ab`. It proves inclusion of the exact
previously captured refs; it makes no final runtime acceptance claim. No refs
were fetched or changed to produce this receipt.

## Two capture stages

| Capture and integration target | Branch refs | Branch disposition | PR heads | PR disposition | Upstream heads |
| --- | ---: | --- | ---: | --- | ---: |
| Initial capture, integrated at `9e0d8173` | 23 | 14 ancestors; 9 historical equivalents | 247 | 233 ancestors; 14 historical equivalents | 4 ancestors |
| Refreshed capture, checked against published `c9cbeb12` | 24 | 15 ancestors; 9 historical equivalents | 249 | 235 ancestors; 14 historical equivalents | 4 ancestors |

The earlier [reconciliation](reconciliation.md) and
[captured inclusion](captured-inclusion.json) remain evidence for the first
stage. The refreshed receipt copies every ref name and SHA from the frozen
[prequalification inventory](prequalification-inventory.json), including its
four upstream heads, and independently recomputes ancestry and historical
equivalence against `c9cbeb12`. Its inventory blob ID and SHA-256 bind that
selection. The separately identified later main advance below is an additional
ancestry check; it does not replace captured SHAs or expand these inventory counts.

All 14 historical proofs pass exact changed-path mode/type/object equality,
and their accepted commits are ancestors of the published target. Thirteen
also have identical complete trees. The ODT continuation proves changed-path
equality only. The nine branch exceptions are a subset of these 14 historical
PR-head mappings, not nine additional unique exceptions. No captured ref is
uncovered.

## Refreshed incoming parents

Published integration commit `050ba58acad35f41803377b385ea22c833822845`
retains feature checkpoint `40572427fc7d62b0fb2423712fa79162814b53a9` as its
first parent and all four refreshed minimal heads as additional parents:

| Branch | Exact preserved parent | Scope |
| --- | --- | --- |
| `work/mail-accounts-20261120` | `0c2f09faf32cf5bdd2222cf73d0412abf954e260` | Reviewed Downloads resolutions, injectable font host, vanished-inventory handling and widget fixtures. |
| `perf/incremental-layout-20261120` / PR #247 | `e6f70bffb3525b33616f0396e3d58c44432c5f7b` | Paragraph break caching, Word chrome rebuild changes, and refreshed main. |
| `work/mail-reply-forward-20261120` / PR #248 | `b2b7ec91e513b1773a8bd26775cde4fd87b738f8` | Complete-source quotations, attachment-only forwarding and provider recovery coverage. |
| `codex/zotero-research-tables-20261120` / PR #249 | `03de5b6ad9eff4666c8e0963d1a6b059417951ed` | Research-note tables, citation ownership, cell soft breaks and conservative layout prefix checks. |

Captured main `7e740a53d3fea4b6bd734537e89888b641a8b735` is included through
the layout parent. The reply parent also includes the captured body-projection,
forward-host-tests and mail-validation heads. Commit `89910ff6` directly
descends from the published integration and corrects/formats incoming fixtures.
The repaired source `4a260716` directly descends from `89910ff6`.
Published `c9cbeb12` retains both `4a260716` and the later main
`a652a205e6daf6b4b8e3baec04db1c1b52fabd0d` as its two parents.

## Conflict resolutions verified in the published source

- The Word layout implementation retains the newer `e6f70bff` cache,
  checkpoint line/frame shifting and semantic fingerprints, plus Zotero's
  five-line convergence guard and the subsequent cache invalidation repair
  described below. The editor controller matches `e6f70bff`, retaining
  local-edit relayout.
- The Downloads manager, layout tests and fake hosts match `0c2f09fa`, including
  the optional font host and safe handling of an inventory item disappearing
  after rendering.
- Mail credentials and workspace match `e6f70bff`. Native Mail differs only by
  the two required `sourceStatus: result.status` arguments, preserving selected
  credential-store and chrome behavior while adding complete-source checks.
- Zotero citing implementation matches `03de5b6a`; the note implementation has
  only formatter changes. The automatic note-marker test fixture supplies the
  required default run properties; assertions were retained.

## Differential failure and cache repair

The first frozen integrated source, `89910ff6`, failed the independent geometry
comparison for seed 7 with structures enabled at edit 44. A paragraph edited at
step 40 while frame wrapping was active retained its older unwrapped breaks:
the later comparison reported a 154-point line instead of the fresh layout's
176-point line. Frame wrapping bypassed cache reads and writes without clearing
the old entry, so subsequent flow changes could make stale glyphs readable again.

Commit `4a260716` adds seven lines at paragraph-layout entry to invalidate an
old cache entry whenever the block is not proven clean. This happens before
empty-paragraph returns or frame wrapping can bypass cache replacement. Clean
paragraph caching remains enabled, and the cache contract comment is corrected.
Two focused regressions cover text and font edits under a square wrapping frame,
followed by frame removal and clean-paragraph layout; they compare full geometry
at all three phases. The existing randomized comparison and its assertions are
unchanged. This records the defect and repair, without claiming a completed
final passing gate for the repaired source.

## Main advance after the inventory

While local qualification was in progress, remote main advanced to
`a652a205e6daf6b4b8e3baec04db1c1b52fabd0d`. It includes
`bbfc015acf22f8552993e846b07b469e04b87533`, which adds explicit invalidation
when frame wrapping selects the separate breaker, and updates two omitted
`Mid$` argument diagnostic expectations from `vba_syntax_error` to
`vba_unsupported`; both cases still require rejection. The subsequent main
commit aligns release/development macOS credential signing identity.

Merge `c9cbeb12` retains both cache guards: the entry guard clears old entries
for dirty/full layouts before early returns, while the wrapping guard clears
the ordinary cache whenever wrapping is active, including clean blocks. The
conditions overlap for dirty wrapped paragraphs and complement each other
elsewhere. Both focused regressions, the existing randomized comparisons,
and the cache-fix changelog entry are unchanged from `4a260716`. The later
diagnostic expectations and macOS packaging change are also retained; no
captured incoming head or either cache repair was dropped.

The packaging script passed `bash -n` syntax checking only. No macOS signing,
upgrade, credential-store or scoped-grant runtime validation was executed.
The local source gate was restarted after this integration because engine
and test inputs changed. This document makes no final passing-gate claim.

## Earlier receipt and filename routing

[Prequalification inclusion](prequalification-inclusion.json) names local
commit `bf170af74695840234e58cc0f4dcc8a5ade6309e`. That local commit is not an
ancestor of the published target. Its tree differs from published `050ba58a`
only by the three subsequently added prequalification evidence files, but it
must not be cited as published ancestry. The new inclusion receipt provides
the correct published target and independently rechecks the same inventory.

The copied [prequalification review](prequalification-review.json) retains its
original scratch filename `incoming-before-qualification.json`. In this
repository, that inventory is [prequalification-inventory.json](prequalification-inventory.json).
The review records pre-merge recommendations; the preceding section records
the inspected resolutions.

## Qualification boundaries

Inclusion and source review do not establish application runtime behavior.
The earlier [layout differential receipt](layout/receipt.json) qualifies its
recorded pre-cache engine tree; the [PowerPoint review](powerpoint-review/receipt.json)
is explicitly development evidence without a source freeze. Final runtime
totals must come from a completed local gate on the integrated source. Aborted
or setup-only attempts do not contribute passing totals.

No Flutter UI/controller execution, installed Microsoft Word/PowerPoint,
platform keychain, native signing or live mail-provider validation is claimed
here. PowerPoint margin projection remains scoped to direct `bodyPr` values;
native inheritance is preserved without claiming inherited-margin rendering.
GitHub Actions was neither queried nor awaited.
