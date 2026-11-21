# Latest-main Zotero qualification

This is the final source-specific qualification after incorporating the
concurrent Word/Mail integration from main `613c0ba130c538f18670be69dd6617b6560c0760`.
It supersedes the earlier source qualifications for current publication while
retaining every original receipt and its historical attribution.

## Source and integration

Qualified source: `9ed8cc2667a0d441f193915417a5662ad2793d50`.
Qualified tree: `a239db0ab4fccc3e712038533b8fd16f4b14f57b`.

This ordinary merge preserves both the preceding qualification checkpoint
`5d6a7ad0ebcfea510340f1ec20bf035130ced4a9` and latest main `613c0ba1`.
The merge required no production correction. Its documentation merge retains
the incoming Word/native-color findings and the earlier Zotero records.

The expected-base publication check detected this update before any final
main ref mutation. The incoming changes include native run foreground handling
in the DOCX reader/property/style layer, generic editor shortcut dispatch,
focused host ownership and Mail selection/help behavior. Because the native
reader and editor paths changed, the final engine and UI cohorts are executed
freshly; the earlier retained-engine exception is not used in this aggregate.

## Fresh qualification

**Accepted: 3,861 unique passing cases across 190 suites, all freshly executed
on the qualified source. Zero failures, errors or skips.** No historical
execution is carried into this final aggregate.

| Fresh gate | Suites | Actual passing cases |
| --- | ---: | ---: |
| Engine and directly related native-color integration | 125 | 2,732 |
| Editor, five disjoint batches | 55 | 1,022 |
| Studio, including both dispatch and host-ownership suites | 9 | 106 |
| Existing continued-notes golden | 1 | 1 |
| **Total** | **190** | **3,861** |

Strict analysis reports no issues across all **51 live changed Dart files**;
formatting reports zero changes. All accepted processes have empty stderr.
The audit excludes 20 successful fixture hooks and 190 successful loaders;
all 4,071 started lifecycles complete. The golden performs twelve comparisons
against unchanged baseline images.

Every accepted gate captures the same 6,333 inputs before and after execution,
including code, tests, fixtures/assets, local dependencies, root/configuration
files, the runner and resolved package configuration. The shared input-manifest
SHA-256 is:

```text
8943d1163a5196f6cbbe82c51f6b077475248defa1a39246ad0884018c9ce4cd
```

The [independent audit](checks/independent-audit.json) verifies raw/compressed
stream hashes, exact case identities, complete reporter lifecycles, suite and
group counts, disjoint editor batches and equality with the committed source.
The [qualification receipt](checks/qualification.json) records runtime and
lockfile checks and the exact per-gate commands/results. Previous runs are not
added to this total.

The frozen independent audit's SHA-256 is
`1231ae40bb31b49c04611cf27197fc1c5ffb1f5e90b838cea7449cf36b0ae074`.
All 6,332 tracked captured inputs match the qualified Git source; the unchanged
generated package configuration is the sole additional input. The
[intake replay](intake-replay.json) again verifies 345 ancestor observations
and 14 historical replacements, with zero uncovered captured observations.

An initial static selection also included two archived historical Dart
snapshots under `docs/`. Its six info diagnostics concern documentary filenames
and imports outside their original package context. That
[failed attempt](checks/analysis-archived-inputs-attempt/receipt.json) is retained
without acceptance credit. The archived snapshots are unchanged; the corrected
51-file live-source analysis and formatting pass.

## Concrete integration coverage

The native cohort retains every original 122 Zotero/ODT/note/persistence suite
and adds three directly relevant incoming color suites. They verify native
foreground ownership, namespace/theme handling, actual source entry points,
active footnote geometry, nonstandard special-note IDs/settings references,
note content and anchors, repeated DOCX saves and failure rollback. Native run
color and separator paragraph-border color remain separate representations.

The editor cohort retains all 55 original suites. Studio includes all eight
previous host/shortcut/ODT suites plus the preserved host-ownership suite.
The incoming dispatcher now has actual-focus, composition, repeat and standalone
editor coverage; the prior host lifetime and hidden-document cases remain
selected too. The existing three-page continued-notes golden is replayed
without changing any baseline image.

The inherited Word and Mail qualification records remain separate. Their
broader macro, VM/JavaScript, provider and Mail totals are not added to this
Zotero aggregate. The three harmless trailing-space lines in inherited raw
analyzer logs are preserved as original evidence rather than normalized.

## Publication and remaining limits

Publication adds documentation and evidence only after this source freeze.
The final merge is constructed against the observed main head and uses a
non-forced ref update with that expected head. An intervening main update must
be inspected rather than silently changing the tested base. Both work branches
and every earlier checkpoint remain reachable.

The original intake is replayed against the qualified source and again after
publication. Remote read-back checks the actual main SHA/tree, branch heads,
ancestry, captured source inputs and a clean local main checkout.

Actual converter findings retain their identified runtime and scope. The fresh
engine gate replays retained unmodified converter outputs through the current
native code. Direct ODT geometry remains qualified for the tested fixtures;
LibreOffice normalization of custom DOCX separator paragraphs remains a
recorded failed route. Installed Microsoft Word, supported-release LibreOffice
and live Zotero plugin workflows are separate acceptance work.

No GitHub Actions, check/status or workflow queue was queried or awaited.
