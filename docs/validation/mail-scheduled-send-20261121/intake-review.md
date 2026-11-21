# Mail continuation intake — 21 November 2026

Baseline: `4970f71f983535d045ce263e86835b499db4fda9`.

Fetched all advertised fork branch tips and PR heads, plus all four upstream branch tips. The captured inventory contains 376 references:

| Scope | Ancestors | Verified historical equivalents | Current unintegrated heads |
| --- | ---: | ---: | ---: |
| Fork branches (40) | 37 | 0 | 3 |
| Fork PR heads (332) | 318 | 14 | 0 |
| Upstream branches (4) | 4 | 0 | 0 |

The connector reported zero open fork PRs. All 14 historical equivalents were independently rechecked from Git objects: 13 complete-tree equalities, plus the established 37-path replacement for PR #140. Accepted replacements are actual baseline ancestors. Do not merge these old heads again. All recent PR heads #153–332 are baseline ancestors.

## Current branch review and order

1. `0fe53777c0bb1fe65950401b381cd6e18a6f4bd9` (`codex/zotero-roundtrip-20261121`): safe documentation checkpoint. Four newly added scope/intake files. Clean merge against baseline; no runtime change.
2. `98a4d0cb69a0d1c70388339c9c76a0b11de6d116` (`codex/zotero-odt-roundtrip-20261121`): safe documentation checkpoint. Two newly added scope/intake files. Distinct paths; clean merge against baseline; no runtime change.
3. `85033b80f7e37a6562a4b86b486badc96ba84153` (`codex/word-vba-format-controls-20261121`): incomplete implementation checkpoint. Adds Word shading compilation, shared Space/String/ChrW/AscW helpers, examples and three suites. The compiler emits `docx.paragraphShading`, but there is no native registration/implementation in the captured engine. Its integration tests require that missing operation. Preserve the checkpoint in the integration branch, then reconcile the native continuation or complete it before final main publication. This is a source finding, not an executed test result.

The shared text helpers charge allocation work, check integer ranges and retain strict publication of isolated surrogate units. The changed compiler is also used by Excel and PowerPoint, so existing shared VBA suites belong to the local validation boundary alongside the three new test files. The two new portable smoke files cover JavaScript behavior. Do not count tests from old evidence as a fresh pass.

No worktree/source changes, remote pushes or merges were performed by this audit. GitHub Actions runs/checks/statuses were neither queried nor awaited. The snapshot is finite: refresh remote main and changed heads before final publication, without indefinitely chasing active work.
