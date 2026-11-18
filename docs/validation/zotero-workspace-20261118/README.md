# Zotero reference inspection and selection review — 18 November 2026

## Accepted product

Qualified product and tests: **`d36413a2cc8e1de9fd7493b5d1baf2900e63f04b`**.
All **720 substantive tests across 41 suites** pass, with zero skips or errors.
The saved product contains current merged main
`1e07cb852766f8651815138785be74c64a09ddc0`, including PRs #157, #158 and #159.
Later delivery commits add evidence only. Machine-readable acceptance is in
[status.json](status.json), and all tested source files are bound directly to
the qualified commit in [source-commit-binding.json](source-commit-binding.json).

## User-visible improvements

### Inspect a source before citing it

Choose the **Reference details** information button beside a catalog result.
The dialog shows the untruncated title, creators and roles, publication, date,
publisher, DOI, URL, Zotero identity, tags and abstract when supplied. It uses
the item already loaded for the current page; opening it makes no extra request
and does not select the source. **Copy details** copies a plain-text summary.
Identifiers and URLs remain inert text; abstracts retain literal scientific
comparison signs. Metadata fields can also be selected and copied individually.

Choose an available tag to filter the current library, collection or desktop
saved search. It returns to page one of the last submitted query while preserving
both input drafts, current options and selected references. Already applied tags
are marked. Names that cannot be represented exactly as filters remain visible
with explanatory tooltips; this includes surrounding whitespace, reserved search
syntax, invalid characters and inputs beyond the existing limits. Tags retain
their literal case and Unicode, and manual/automatic tags are treated equally.

The engine adds backward-compatible `abstractNote`, `publicationTitle`,
`publisher` and immutable `tags` fields. Publication names follow Zotero's
item-type mappings, including book sections, proceedings and websites. Optional
malformed metadata is ignored without changing CSL snapshots or source identity.

### Review references collected across pages

**Review selected** is available in both **Library** and **Import CSL JSON**.
It lists all selected sources, including ones hidden by filters or another page.
Move sources up/down or remove individual entries, then **Apply selection**.
Cancel or dismiss the dialog to discard staged edits. Original selection keys,
Zotero identities, locators, embedded metadata and unknown members are retained.
An applied order is passed to the citation composer/native picker; Zotero styles
may apply their own order. Selection management adds no document history, and
citation insertion remains a separate undoable operation. The 20-source limit
is unchanged.

Both dialogs support narrow windows and enlarged text. The surrounding catalog
and import tabs reserve space for the additional wrapped action row. The
[user guide](../../zotero-support.md#inspect-references-and-manage-a-selection)
and both package changelogs describe the new workflow.

## Incoming work and preservation

Before implementation, all fork/upstream branch and PR heads were fetched and
reviewed: **363 refs / 235 distinct heads**. The
[initial inventory](reconciliation-initial.json) and
[reconciliation decisions](RECONCILIATION.md) record the result. The continuation
started from PR #159's combined head `2292548e`, which already contained #157,
#158 and the earlier Office reconciliation. Historical branches were retained;
superseded implementations were not reintroduced.

A later refresh caught #159 merging into main. The incoming main tree was
identical to the original #159 base, so the qualified checkpoint added main as
its second parent while preserving current Zotero source. See
[integrated-main.json](integrated-main.json) and the
[completed refresh review](reconciliation-final-review.md).

The final fetched frontier contains **366 refs**, including this continuation.
Three independent work branches appeared after initial integration: document
comparison/review, German spelling continuation and optional spaCy NER. Their
exact observed heads, scopes and ongoing status are preserved in the
[final frontier](final-frontier.json) and
[external comparisons](reconciliation-final-external-comparisons.json).
They have no new completed PR at the recorded cutoff, and document review
explicitly identifies itself as a checkpoint. They remain separate increments
and are not claimed as integrated or qualified here. Upstream did not move.

All changes were saved incrementally to `codex/zotero-workspace-20261118` with
`[skip ci]`, non-forced updates requiring the observed branch head, and verified
blob content. Product/reconciliation checkpoints before the final evidence save:

| Commit | Checkpoint |
| --- | --- |
| `146cdead` | Preserve incoming ref inventory and reconciliation |
| `045c307d` | Add metadata parsing and engine regression cases |
| `919122e7` | Add reference details and staged selection review |
| `b292ee94` | Save workflow tests, user guidance and engine qualification |
| `d36413a2` | Incorporate merged main, complete narrow-layout fixes and strict checks |

No GitHub Actions, check or status endpoints were queried, awaited, dispatched
or rerun. No dependency manifest, workflow, shared Office controller, network
transport or native citing processor was changed by this increment.

## Accepted local validation

| Cohort | Suites | Substantive passes | Skips / errors |
| --- | ---: | ---: | ---: |
| [Engine Zotero](engine/README.md) | 22 | 445 | 0 |
| [Editor Zotero](editor/README.md) | 18 | 257 | 0 |
| [Studio transport](studio/README.md) | 1 | 18 | 0 |
| **Disjoint total** | **41** | **720** | **0** |

The total includes **45 new regression cases once**: 23 engine cases and 22
widget cases. The new coverage includes metadata defaults/type mappings,
literal tag identity, user/group/local sources, immutable lists, existing
identity rejection, no-request inspection/copying, clipboard failure, exact tag
actions in each scope, preserved drafts/selections, stale sessions, cancellation,
mixed catalog/import source keys, source ordering and insertion undo/redo.
Layouts cover 320/360/420-pixel widths, 20 selections, many tags, a 320×360
selection dialog and both new dialogs at 320×480 with doubled text size.

All actual test-process exits are zero. Every selected suite executed, every
started event finished once, and all source/dependency/runtime/workspace guards
passed. Final Flutter runs contain no missed-tap or overflow diagnostics.
The [strict checks](checks/summary.json) also pass: fatal-info analysis, Dart 3.12
formatting and whitespace checks for all six changed Dart targets.

The genuine [runtime receipt](engine/setup/runtime-ready.json) records official
Flutter **3.47.8** / Dart **3.13.7**, verified SDK/archive identities, 162 exact
hosted package archives, 11 unchanged current manifests and the 110-package
workspace graph. Both the workspace and Flutter tools locks stayed unchanged.
All 419 engine, 538 editor and 624 Studio source inputs match the qualified
commit exactly. These overlapping input counts are not test totals.

The [independent source review](zotero-independent-review.md) found no remaining
implementation issue and separately verified every accepted source hash. Its
[binding receipt](zotero-review-validation-binding.json) refers to the same
runtime cohorts; it is not an additional test run.

### Earlier attempts, retained and excluded

The first focused widget run passed 18 cases and exposed a real 8-pixel dialog
overflow with doubled text. The scrolling title/content fix passed its targeted
retest and all subsequent checks. The first complete editor run had 252 passes
and five narrow catalog/import layout failures; reserving the additional wrapped
row fixed all five before the accepted complete rerun.

One editor run was interrupted for two test-only brace corrections. Its
orchestration exit is 130, but the Flutter child exit is explicitly unknown;
there is no final completion or source-after guard claim. The 31-test setup
smoke and every overlapping focused/development run are excluded from the
accepted totals. See [attempts](attempts/README.md) and
[development evidence](development/README.md) for preserved raw streams,
commands, exact outcomes and archive indexes.

## Scope and reproduction

Acceptance covers controlled online/desktop Zotero responses, real Flutter
widgets and local HTTP transport. It does not claim a fresh live-account or
desktop session, a full application build or new Word/LibreOffice acceptance.
Existing acceptance evidence retains its original source identity.

Each cohort README gives exact commands and retained runners. The setup receipts
and reproduction scripts are under `engine/setup/`; the root
[evidence index](index.json) records file sizes and SHA-256 hashes. No SDK,
package-cache binaries or private credentials are included in this report.

## Protocol references

- [Zotero JSON object data](https://www.zotero.org/support/dev/web_api/v3/write_requests#json_object_data)
- [Zotero tag object examples](https://www.zotero.org/support/dev/web_api/v3/write_requests#creating_an_item)
- [Pinned official item-type schema](https://github.com/zotero/zotero-schema/blob/b86c79b56479cadac3288e1f122cf34ef04e8809/schema.json)
