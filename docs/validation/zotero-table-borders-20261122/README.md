# Zotero table-border interoperability — 22 November 2026

## Goal and implementation plan

Continue the [Word/LibreOffice parity roadmap](../../roadmaps/zotero/word-processor-parity.md)
from main `4cc604810fb2f41ac7ba04cbed65cb76300bff59`. The retained LibreOffice
DOCX table-cell fixture has active, editable citations but its explicit Zotero
ODT export cannot reopen because the native reader rejects all visible borders.
This increment adds the solid uniform border strokes and individual cell sides
that the native Word table model can preserve, with active fields and repeated
DOCX/ODT saves. It does not declare complete word-processor plugin parity.

Qualification uses the pinned Flutter 3.47.8 / Dart 3.13.7 runtime and unchanged
workspace dependency manifests/lockfile. The original converter fixtures remain
unchanged. The executable checks, receipts, source hashes and retained converter
files are indexed below; GitHub Actions are not part of this qualification.

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
| `5bcd78b394fddf73b7ef91f81b0b9fe6b253e1c2` | Preserve the bounded ODT border implementation and editor regressions |
| `62f0abfc8bbaae36ee17240198c398c9e3ee28ab` | Correct source DOCX logical borders, direction and scope; retain the independent converter tool |
| `fb1d57d140c5368051f853c5e088b45cee911024` | Reconcile updated main and PR #383 without losing the earlier union |
| `fb51ed7bdd03a8c67d0b20542606807f3131db7b` | Retain both advanced Mail tips, including failed cache-shutdown ownership protection |
| `ca87f7b3ce5563e0f03df323c91c9fc7a7582877` | Guard stale Refresh callbacks exposed by the incoming Mail regressions |

Each checkpoint's remote Git tree and new blobs are verified against the local
snapshot. Branch updates use the expected current head and never force history.
GitHub Actions are neither queried nor awaited; workflows and protections are
unchanged. New checkpoints use `[skip ci]`.

[concurrent-intake.json](concurrent-intake.json) records the later intake of
main `b4f1150b18348f348489c93108158a397c922abe`, Word head `23a934cf`, Mail
workspace head `3e57fda4` and connected-navigation head `9a371b61`. All captured
current tips and all 100 initially captured recent PR heads are included in the
integrated ancestry. The new Mail ownership fixes retain observers and owners
across failed cache shutdown while preserving cancellable Close, late-callback
fences, conditional account refresh and the prior target-validation behavior.

## Border contract and evidence

The bounded ODT envelope uses one solid opaque RGB stroke per table, with exact
eighth-point widths from 0.25 to 12 pt and independent visible cell sides. Visible
input requires an explicit or inherited collapsing border model. Table and cell
family defaults, parent styles, child shorthand resets and same-layer side
overrides resolve before requiring a representable common stroke. Explicit
`none` clears an inherited edge. Declared covered-cell sides must agree with the
merged owner; nested tables resolve their strokes independently. Output uses the
modeled color and width, preserving absent versus explicitly disabled borderless
sides. Mixed/unsupported ODT strokes, visible separating models and unrepresented
covered-cell overrides refuse before an editable result is returned.

The independent retained-source check exposed an earlier DOCX loss: Writer used
`w:start`/`w:end`, but the reader accepted only legacy `w:left`/`w:right`. Native
self-round trips had therefore compared against an already damaged snapshot.
The reader now honors modern aliases over their legacy siblings, resolves the
effective direct/named/default `bidiVisual`, and maps leading/trailing declarations
into physical native sides. The DOCX writer applies the inverse mapping. Native
namespace/direct-scope checks prevent foreign or nested property lookalikes from
selecting a style or direction. Opaque field formatting/revision preservation is
unchanged by this correction.

Editable ODT export explicitly refuses RTL table column order because the bounded
ODT path does not represent it. RTL paragraph direction within a supported table
is separate. The alias correction does not qualify arbitrary external DOCX
per-cell colors, stroke widths or table styles.

Native cell padding remains numerically stable across ODF and DOCX. Independent
LibreOfficeDev conversion controls show that adding half a border width to every
padding side would introduce repeated-save drift. Input/output files and the
converter's exact version are retained separately from native tests. Physical
layout differences and application/plugin acceptance are not inferred from
matching XML values.

Primary reference: [ODF 1.3 Part 3, §20.415 table:border-model and §20.92 fo:border](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html).

DOCX references: [Microsoft start/left precedence](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/95b4a3c3-bcd6-41ad-9761-29b98779e979),
[right/end and bidiVisual semantics](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.rightborder?view=openxml-3.0.1),
and [BiDiVisual](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.bidivisual?view=openxml-3.0.1).

## Actual converter acceptance

The frozen [acceptance tool](../../../packages/quds_office_engine/tool/zotero/table_border_acceptance.dart)
runs three cases through two genuine LibreOffice ODT saves and four paired native
DOCX/ODT cycles each. The accepted attempt completed **6 actual LibreOffice saves,
12 paired native cycles (24 individual native save/reopens), and 3 passing cases**.
All 376 captured engine/tool/fixture/runtime-configuration inputs stayed unchanged.

| Case | Independent checks |
| --- | --- |
| Retained Writer DOCX table-cell citation | The original fixture hash and all four 0.5 pt black sides are asserted before conversion; active citation metadata and owner remain intact |
| Colored table with one disabled side | 1.25 pt `2468AC` stroke, explicit outer-right off edge and 5 pt padding survive |
| Vertical merged citation owner | 0.75 pt `336699` stroke, 4 pt padding, merged owner and empty continuation survive |

Each stage compares citation identity, complete citation JSON including unknown
fields, cached text, editability, balanced field ownership, document preferences,
normalized paragraph text, grid, merged ownership, side masks, common stroke and
padding. Metadata compares exactly; geometry has declared tolerances in the
[converter qualification](evidence/converter-qualification.json).

The converter is **LibreOfficeDev 26.8.0.0.alpha0**, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. These are controlled file-save
checks, not stable-release certification, installed Zotero-plugin sessions or
Microsoft Word execution. The acceptance snapshot does not measure every font,
style or layout property and does not establish pixel-identical rendering.

Attempt 1 is retained as diagnostic history: its weaker oracle missed the
pre-existing logical-edge loss. Attempt 2 retains the genuine source-grounded
failure. **Attempt 3 is the accepted converter result.** Geometry controls also
retain the evidence that rejected uniform halfstroke padding compensation.

## Local regression qualification and reproduction

The final runner covers 130 engine suites, 29 editor/controller suites and four
Studio suites. The separately reconciled Mail union is checked by nine affected
Flutter suites. Exact commands, individual cases, terminal reporter events,
stderr, exit codes and before/after input hashes are retained with the results.
Earlier focused runs overlap these cohorts and are not added to the final count.

| Accepted cohort | Suites | Passing visible cases | Failures / skips |
| --- | ---: | ---: | ---: |
| ODT / Zotero / Word table and field engine | 130 | 3,143 | 0 / 0 |
| Editor and controller | 29 | 643 | 0 / 0 |
| Studio Zotero host | 4 | 48 | 0 / 0 |
| Reconciled Mail integration | 9 | 332 | 0 / 0 |
| **Total** | **172** | **4,166** | **0 / 0** |

All accepted runs have a successful terminal event, zero reporter errors, empty
stderr and stable captured inputs. Formatting and strict analysis also pass for
12 affected non-Mail Dart files and 13 reconciled Mail files. All 35 tracked
manifests/lockfiles remain unchanged, with 166 resolved workspace packages.

[qualification.json](qualification.json) binds the results to product source
checkpoint `ca87f7b3ce5563e0f03df323c91c9fc7a7582877` (tree
`f80876b3b13b22529c397b176fa61ca203c357d6`). Later publication adds documentation
and retained evidence. The engine run predates only the Mail example Refresh
guard: that file is outside the pure Dart engine's dependency graph, while every
other captured input is identical. Editor/Studio captured inputs and all 376
converter inputs match the final product source exactly. The Mail retry began
with the guard as a working change; its 315 hashes match the committed final
source. These distinctions are recorded explicitly instead of assigning a later
commit to an earlier execution.

Activate the repository-pinned SDK and locked workspace dependencies, then run
the cohorts **sequentially** to avoid temporary compiler-cache pressure:

```bash
python docs/validation/zotero-table-borders-20261122/run_checks.py --cohort engine --output /absolute/new/evidence-directory
python docs/validation/zotero-table-borders-20261122/run_checks.py --cohort editor --output /absolute/new/evidence-directory
python docs/validation/zotero-table-borders-20261122/run_checks.py --cohort studio --output /absolute/new/evidence-directory
```

From `packages/quds_office_engine`, with `soffice` available:

```bash
dart run tool/zotero/table_border_acceptance.dart /absolute/new/converter-directory
```

The converter tool refuses an existing output directory. Original files and
earlier failed attempts must remain intact. The initial engine/runtime smoke and
the Flutter smoke interrupted by merge markers are readiness/diagnostic evidence,
not additional qualified product cases.

The first final Mail run exposed three stale Refresh callback failures across
EWS/Gmail/Graph; its last 46 cached-host cases also encountered `ENOSPC` while the
engine compiler retained temporary kernels. The engine run itself completed
successfully with 3,143 passes and released those temporary files. A narrow
null-safe Refresh handler fixes the product error. The same nine Mail suites
reran successfully with their original assertions and sufficient temporary
space; both attempts are retained and classified separately.

## Evidence and remaining parity work

- [Initial intake](initial-intake.json) and [concurrent intake](concurrent-intake.json).
- [Combined qualification](qualification.json),
  [native regression archive](evidence/native-local-evidence.tar.xz),
  [native member index](evidence/native-local-evidence-members.json),
  [native archive verification](evidence/native-local-evidence-verification.json)
  and [implementation review](evidence/implementation-review.json).
- [Converter qualification](evidence/converter-qualification.json),
  [converter archive](evidence/converter-evidence.tar.xz),
  [member index](evidence/converter-evidence-members.json) and
  [readback verification](evidence/converter-evidence-verification.json).
- [Pinned runtime provenance](evidence/runtime-provenance.json),
  [locked workspace resolution](evidence/workspace-resolution.json) and
  [unchanged manifest verification](evidence/runtime-manifest-validation.json).
- [Mail qualification](evidence/mail-qualification.json),
  [Mail evidence archive](evidence/mail-local-evidence.tar.xz),
  [Mail member index](evidence/mail-local-evidence-members.json) and
  [Mail archive verification](evidence/mail-local-evidence-verification.json).

The [parity roadmap](../../roadmaps/zotero/word-processor-parity.md) remains the
implementation sequence. Next bounded interoperability targets include ordinary
link visited styles, continued lists and richer table/heading geometry. Installed
Zotero sessions in Word and LibreOffice, broader plugin workflows and unsupported
document structures still need their own acceptance. This increment closes the
documented supported-border gap; it does not declare full Word/LibreOffice parity.
