# Office fidelity continuation — 17 November 2026

Work continues from `57bc0f98eb94997b73f22cc267bd8d61dccaee59` on
`codex/office-fidelity-20261117`. All qualification is local; no GitHub Actions,
workflow checks, or commit statuses are queried or awaited. Checkpoints use
`[skip ci]`.

## Integration before implementation

The [exact incoming snapshot](incoming/snapshot.json) captures 207 named refs
representing 140 distinct commits: 105 fork branches, 94 fork PR heads, four
upstream branches, and four upstream PR heads. Fork refs were observed at
08:19:21–08:19:29 UTC (09:19 Europe/Berlin); upstream timing is retained in the
snapshot. The cutoff is finite; later arrivals are outside this observation.

Main `8a778f18` includes the prior handoff, new proofing/UI work, ODF lint fixes,
and combined TestFlight evidence. Two later tips were also integrated:
`7dc17c97` (German morphology baseline documentation) and `837d06ed` (Zotero
reconciliation history). The actual Git merges completed without conflicts.
Main's TestFlight receipts and ODT assertions remain present.

[Integration verification](incoming/integration.json) confirms every captured
head is an ancestor of the integrated result. No production source differs
from main at this initial checkpoint. This checkpoint precedes new implementation.

## Bounded incoming refresh

A second snapshot observed the fork at 08:42:17–08:42:25 UTC
(**09:42 Europe/Berlin**) and upstream immediately afterward. It captures
**217 references / 147 distinct head commits**: 112 fork branches, 97 fork PR
heads, four upstream branches, and four upstream PR heads. Together the two
observations retain **220 reference/revision pairs / 150 distinct commits**,
including superseded tips. Every observed commit is included by ancestry.

The refresh incorporates main `69a1396e`, ODT list PRs #95/#97 and documentation
PR #96, original/vendor PR histories, and the captured German morphology and
Zotero evidence checkpoints. Actual merges completed without conflicts. See
[exact snapshot](refresh/snapshot.json), [merge trace](refresh/merges.json), and
[resolution decisions](refresh/resolution.json). Later arrivals are outside
this finite cutoff.

## Implemented behavior

- ODT vertical/rectangular merges, compact logical-grid declarations and blank
  padding, and unchanged source model. Orphan continuations stay visible.
- Preserved hidden continuation stories remain in XML but are excluded from
  visible extraction and search, including namespace aliases and fallback paths.
- ODT line-spacing units, heading formatting, explicit zero margins, and paragraph
  direction; first-section header/footer styles, breaks, hyperlinks, and pictures.
- ODP table geometry, cell colors, visible header rows, and portable RTL physical
  placement. Editor/PDF fallback colors avoid unrelated consumer theme defaults.
- Required image link attributes and corrected relative table widths. Incoming
  flat list groups retain core decimal styles without a redundant extension.

The [export guide](../../odf-export-fidelity.md) explains model mappings,
malformed-table policy, complexity bounds, consumer compatibility decisions,
and limits. No dependency manifests or font binaries were changed.

## Local qualification

The reproducible [validation harness](validate.py) selects engine, actual Flutter
editor, Harper contract, and JavaScript/Node cohorts. Event counts are dynamic;
source, fixtures, runtime dependencies, the exact enforced dependency lock, and
HEAD are bound before and after every run. The final receipts will be recorded
from the saved integrated source checkpoint.

[Fixture generation](make_fixtures.dart) supplements test-generated ODF packages
for independent official OASIS schema checks and LibreOffice/Poppler rendering.
These consumer checks measure exact/minimum line spacing, physical RTL cell
positions, authored colors, retained visible labels, and header/footer content.

## Saved implementation checkpoints

| Checkpoint | Result |
| --- | --- |
| `9737788c` | Initial captured histories and inventory, before implementation |
| `f997b9ba` | ODP table geometry/colors/direction implementation |
| `d37859b0` | ODT paragraph properties |
| `d8851443` | ODT table merge topology |
| `75e9566d` | Styled headers/footers, valid image links, consumer-correct ODP rows/RTL |
| `e3ab8e90` | Hidden-story extraction guards and complete empty/ragged grids |

Every remote write verifies the exact Git tree and updates the branch with an
expected parent. All checkpoint messages contain `[skip ci]`; no Actions job,
check, or commit-status endpoint is used.
