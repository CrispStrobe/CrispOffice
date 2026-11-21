# Word VBA comparisons and foreground colors — 21 November 2026

## Scope

This increment adds shared bounded binary `StrComp` and Word
`Font.ColorIndex`/automatic foreground writes. It retains the source-to-plan
boundary, strict types, metered work, guarded native mutation and detached
atomic publication. The runnable BAS selects status colors using source data,
formats independent header/footer paragraphs and fills two existing table
cells. It does not introduce document-value reads, general VBA project
execution, locale collation, implicit text coercion or cell formatting.

## Captured intake and checkpoints

- Initial remote main: `3058d36c5354d46bde418555d59282116cce1e26` (PR #346).
  All six then-current fork heads and all four upstream heads were contained;
  no open PRs were returned. The latest 100 PRs (#247–346) were merged.
- The source checkout refreshed to main
  `52e72ca0b5677549f31742faae457f08df05759b` (README reorganization).
  Full current fork heads and pull-request heads were fetched, as were the
  four upstream heads. A new Mail intake checkpoint
  `02ef9dc85ff7e716809ee2e0de03bfc3546821a0` was merged before implementation.
- Remote work branch: `codex/word-vba-comparison-colors-20261121`.
- `8b7123d73d58a2d211a2657288fa84f73f917b8e`: reconciled intake with both
  original parent histories.
- `490828f98dd25a2dfa29e565bc97220036f43ef1`: shared StrComp plus focused tests.
- `e1eeb3dc6c13449b1e6357529f325067bdcf5048`: font-color implementation,
  native/source tests, complete BAS workflow and portable tools.

Remote writes use expected-head, non-forced GitHub ref updates. The local git
transport can read this public repository but has no write credential, so Git
objects are saved through the connected GitHub API and fetched back locally.
No existing branch was force-pushed or deleted. GitHub Actions are not a gate;
checkpoint messages use `[skip ci]` and no Actions run is queried or awaited.

## Local environment

The first full checkout exhausted the initial executor's storage and that
executor became unavailable. Work resumed in a recovered runtime using a
source checkout and a standalone Dart validation workspace. There was no
dependency on the hosted CI queue.

The standalone SDK is Dart 3.14.1. The minimal validation workspace links the
actual engine/legacy-parser sources and resolves all 56 dependencies to the
versions and sources in the repository lockfile. Repository manifests and the
lockfile remain unchanged. This headless setup is distinct from the repository's
Flutter 3.47.8 pin and from installed Microsoft Office qualification.

## Executed focused qualification

| Gate | Result |
| --- | --- |
| Existing Word language/integration baseline | 170 tests passed |
| Shared StrComp source tests | 78 passed |
| New Word color compiler tests | 74 passed |
| New native Word color tests | 43 passed |
| Actual BAS/native/CLI/MCP integration | 10 passed |
| Independently authored conformance wrapper | 31 tests passed: 30 cases plus provenance receipt |
| StrComp portable smoke | 72 checks, identical VM/JavaScript JSON |
| Actual BAS portable workflow | Identical VM/JavaScript results and native XML hashes |
| Versioned corpus | Same 30 fixture cases, identical VM/JavaScript receipts |
| Scoped source/new-test analysis and formatting | Passed |

The new corpus fixture SHA-256 is
`d527b6ca049ee154a3dd17297c4e3ec9a800f3498ceac67d47fb4118adc65241`.
Its identical VM/JavaScript receipt SHA-256 is
`2cca54083876741238892d12b1e454fcd2d97dcef87a49db7f4e0de7da77d60c`.
The StrComp smoke receipt SHA-256 is
`8df099428192365cb1befbcee1b3525555b69102f861c274c0c31b6581250aa5`.

Native checks cover automatic versus fixed black, every palette entry,
same-value style overrides, theme-selector removal, foreign attributes and
children, namespace aliases, Unicode ranges, repeated save/reopen, DOCM/custom
XML retention, guarded refusals, policy, recording/replay and whole-run
rollback. The tests caught and verified a fix for generated fragments whose
native `w` prefix is intentionally unbound before insertion into a document.

The source expectations distinguish specification-derived results from Quds
dialect restrictions. No test claims a recorded Microsoft Office host result.

## Final integration qualification

The broader source regression and current-main reconciliation are being
recorded in the next checkpoint. Current main's documentation reorganization
and newer independent Mail/Zotero heads will retain their histories; final
qualification records will state which exact combined source was executed.

Material limits remain explicit: general VBA execution/document reads,
locale-dependent StrComp behavior and installed Word differential testing are
not delivered by these changes. Native automatic foreground is preserved;
this increment does not add a new automatic-contrast rendering policy.
