# Zotero host ownership and workspace shortcuts

This follow-up keeps an open Zotero operation attached to the Word view that
started it and preserves citation shortcuts when workspace commands are
customized. It is built on the integrated Office main, including the earlier
table-margin/ODT work, Mail refresh and Word VBA authoring.

**Local acceptance: 232 distinct passing cases in 17 suites,
with no failures, errors or skips.** The source is
[`22dd2a4d474a59ad231f24a61dcb8046b029e993`](https://github.com/CrispStrobe/quds_office_suite/commit/22dd2a4d474a59ad231f24a61dcb8046b029e993),
tree `c265e4d354d4d8af5a3dcbf55d2ae51fdee7a667`. Publication is [PR #347](https://github.com/CrispStrobe/quds_office_suite/pull/347).

## Delivered behavior

- `showWordZoteroDialog` accepts an optional `isCurrent` host predicate. It is
  checked before committing pending edits, through the existing protocol and
  publication guards, and before field reveal or return of editing focus.
- Studio captures its navigation generation when Zotero opens. Opening Mail
  invalidates it before the asynchronous title update; switching applications
  and closing Mail also advance it. Returning to Word cannot reactivate an
  operation that belonged to an earlier view.
- Reserved Ctrl/Cmd+Alt+C/R citation commands and other uncatalogued workspace
  chords cannot be replaced by a conflicting stored override. The recorder
  explains reserved conflicts and the effective settings display reflects
  accepted bindings.
- Reassigning redo or zoom retires their previous alternate keys. Structural
  deduplication and the incoming precedence of explicit configurable overrides
  remain intact. The established zoom-in chord is preserved; subscript is
  shown as unassigned until the user chooses a binding.
- Persisted modifier-only triggers are rejected before constructing Flutter
  activators. Bare F1–F24 and valid modified shortcuts remain supported.
- Word mutations require the current editable Word view and the appropriate
  body/comment formatting capability. Native text actions go to their focused
  control, including dialogs and Mail; fallback commands cannot reach a hidden
  document. Comment bold, italic and underline remain available.

The optional predicate lets existing embedders retain their document/caret
guards. Hosts with multiple views can opt into the stronger lifetime contract.
It must remain true while the Zotero workspace's own dialogs are open.

## Demonstrated regression

The tests-only checkpoint
[`08f23ace`](https://github.com/CrispStrobe/quds_office_suite/commit/08f23acef7b170d04428d524585bd1982c0ca011)
parents main `52e72ca` without changing production code. Two tests hold a
terminal `Document.complete` response after it has staged changed document
preferences, navigate to Mail, and optionally return to Word before releasing
the response. Both fail on that production source because the old dialog
writes the new metadata. The complete before/after source manifest is stable.

Both cases pass in the accepted source: document identity, metadata and undo
history remain unchanged, and the operation reports its stale target. Their
raw failing baseline is retained separately from the passing qualification.

## Fresh local qualification

| Cohort | Suites | Passing cases |
| --- | ---: | ---: |
| Studio catalog, settings, dispatch, Mail isolation and Zotero/ODT workflows | 8 | 94 |
| Shared Zotero dialogs and note preview | 9 | 138 |
| Total distinct cases | 17 | 232 |

All seven changed Dart files pass formatter verification and fatal-info,
fatal-warning analysis. The Git whitespace check also passes.
6,131 tracked package/application files have identical SHA-256 manifests
before and after the accepted execution. The evidence verifier checks every
indexed file against the recorded Git commit and tree, verifies all archive
members, and independently recounts complete raw JSON reporter events.

Runtime: genuine Flutter 3.47.8 / Dart 3.13.7. The official SDK archive and
executables were hash-verified; all 204 hosted dependency archives were
verified against the lockfiles, and offline enforced-lockfile resolution
preserved the workspace lock. Runtime receipts, the reconstruction script,
package configuration and dependency hashes are retained.

Each accepted suite runs in its own local Flutter process. An earlier grouped
attempt exposed an incorrect null-anchor assumption in a newly reconstructed
test and stopped advancing while loading later suites. Its raw prefix and
unchanged-source receipt are retained as an excluded attempt. The corrected
test compares the complete numeric caret/anchor tuple and asserts a collapsed
selection. An earlier static-check failure concerned test accessors and braces
only; both the failed and corrected logs are preserved.

The first isolated ODT-open run passed its three visible cases but reported a
Dart compiler exit. That raw run remains excluded. A single-suite retry passed
cleanly on the same commit and identical input manifest. The accepted receipt
combines the sixteen other successful process runs with this successful retry;
the prior receipt and both ODT logs are preserved.

No GitHub Actions, check-status or workflow queue was queried or awaited.

## Earlier evidence and integration

The [table-layout record](../zotero-table-layout-20261121/README.md) retains
**4,635 cases across 239 suites** on D112, including the two actual
LibreOfficeDev saves of the six-table/nine-active-field fixture. Those are
historical executions on their recorded source; they are not added to this
follow-up count.

The independently checked
[incoming-source continuity record](../zotero-table-layout-20261121/main-source-continuity-52e72ca0.json)
finds 1,516 of 1,527 indexed baseline inputs unchanged at main `52e72ca`,
enumerates all eleven changes and thirteen new relevant paths, and verifies
344 archived members from incoming qualification. Incoming Word evidence
contains 6,665 engine passes, including 376 table/ODT continuation cases, plus
73 final-source UI passes. The separate Mail shortcut record contains 46
passes. These scopes overlap older work and remain separate.

Main `cc797dc2` subsequently changed sixteen Markdown files only. Its scannable
guides and detailed archives are retained. This follow-up changes three
production Dart files in the editor/Studio; the engine library, tests and
tools retain the incoming qualified identities. Both recovered implementation
branches and the independent continuity branch are retained as merge parents.

## Reproduce and verify

From a checkout containing the recorded commits:

```sh
python3 docs/validation/zotero-table-layout-20261121/verify_evidence.py \
  --index docs/validation/zotero-host-ownership-20261121/index.json
```

After preparing the recorded Flutter/Dart runtime and enforced workspace
dependencies, set `FLUTTER_ROOT` and the corresponding `PUB_CACHE`, then run:

```sh
python3 docs/validation/zotero-host-ownership-20261121/run_local.py \
  --repo "$PWD" --out "$PWD/../zotero-host-replay" --phase all
```

`run_local.py` records the source commit/tree, complete input manifests,
commands, raw events and outcome receipts. The archived runtime bootstrap
records the exact pinned downloads; its task-specific root can be adapted for
a new checkout. Archive verification requires no network or installed Flutter.

## Remaining parity limits

This establishes local command, dialog and host-lifetime behavior. It does
not claim an installed Zotero/Word or supported-release Writer plugin session.
The external converter was not rerun after the incoming Word deserializer
change or this follow-up; the earlier development-converter results retain
their original attribution.

Active footnote separator modeling/layout/interchange remains the next
document-fidelity milestone. Asymmetric or per-cell ODT padding, unsupported
table styles/borders and arbitrary native ODF rewriting remain outside the
bounded editable profile. Installed Word/Zotero and Writer/Zotero interchange
must be qualified separately before claiming full plugin parity.
