# Zotero table-border interoperability — 22 November 2026

## Goal and implementation plan

Continue the [Word/LibreOffice parity roadmap](../../roadmaps/zotero/word-processor-parity.md)
from main `4cc604810fb2f41ac7ba04cbed65cb76300bff59`. The retained LibreOffice
DOCX table-cell fixture has active, editable citations but its explicit Zotero
ODT export cannot reopen because the native reader rejects all visible borders.
This increment adds the solid uniform border strokes and individual cell sides
that the native Word table model can preserve, with active fields and repeated
DOCX/ODT saves. It does not declare complete word-processor plugin parity.

The implementation is being qualified locally with the pinned Flutter 3.47.8 /
Dart 3.13.7 runtime and unchanged workspace dependency manifests/lockfile.
The original converter fixtures remain unchanged. The completed results and
exact source binding will be recorded here before publication to main.

## Initial intake and preservation

[initial-intake.json](initial-intake.json) captures 46 fork branch heads, four
canonical upstream heads, all 383 available PR heads, and metadata for the 100
most recently updated PRs. Three branch tips were not ancestors of starting main:

| Captured branch | Tip | Integration |
| --- | --- | --- |
| `codex/word-vba-text-authoring-20261122` / PR #383 | `c971ad0e1515db8deed59b7d8360960c64e13059` | Retain Word Split evidence, empty field-code formatting fixes, and guarded Mail handoff |
| `work/mail-account-workspace-20261122` | `068c46395a58c67a9537874b6a2030008296793e` | Retain Mail owner/release protections and complete opaque field formatting history |
| `work/mail-connected-navigation-20261122` | `4015d7544ec3aa392ce2f375a35f00a4c3d4c5a3` | Retain cancellable Close, provider setup/dispatch fences, and qualification evidence |

All captured current branch tips and all 100 recent PR heads are ancestors of
the integrated remote checkpoint below. The fourteen older nonancestor PR heads
have verified historical replacements: thirteen identical full trees and one
identical changed-path projection. Replacement ancestry and equivalence were
recomputed against this intake; the old changes are already represented.

Crisscross conflicts were reconciled without choosing an entire branch's copy.
Mail retains expected-record account refresh, guarded observer/session adoption,
held-owner release recovery, cancellable provider operations and independent
provider setup. Duplicate merged test fixture methods were removed. Word keeps
the complete original field-boundary property XML, leaves boundary-only revision
history opaque, and retains ordinary empty-run revision provenance and review.
Invisible instruction formatting cannot become refreshed visible-result styling.

Remote checkpoints on `codex/zotero-parity-progress-20261122`:

| Commit | Purpose |
| --- | --- |
| `f2be4b4679ccab15420db13f8d3b8b6df66b95f6` | Preserve first Word/Mail integration and original incoming ancestry |
| `3244b81b9cb9506deb00ca5286b6f029a49d21d0` | Preserve all initial incoming branches and reconciled Word/Mail behavior |

Each checkpoint's remote Git tree and new blobs are verified against the local
snapshot. Branch updates use the expected current head and never force history.
GitHub Actions are neither queried nor awaited; workflows and protections are
unchanged. New checkpoints use `[skip ci]`.

## Border contract and evidence

The border envelope uses one supported solid RGB stroke per table, with
independent visible sides on individual cells. Table and cell style inheritance,
explicit `none`, merged-cell ownership and nested-table independence are checked
before a document is returned. Unsupported stroke styles, mixed strokes,
unrepresented ownership and visible separating borders remain explicit refusals.

Native cell padding remains numerically stable across ODF and DOCX. Independent
LibreOfficeDev conversion controls show that adding half a border width to every
padding side would introduce repeated-save drift. Input/output files and the
converter's exact version are retained separately from native tests. Physical
layout differences and application/plugin acceptance are not inferred from
matching XML values.

Primary reference: [ODF 1.3 Part 3, §20.415 table:border-model and §20.92 fo:border](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html).
