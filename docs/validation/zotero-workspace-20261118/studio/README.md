# Studio Zotero transport — current source qualification

**Passed: 18 substantive tests across 1 suites; zero skips/errors; actual process exit 0.**

The exact command, selected suites, timestamps and actual exit are in `run.json`,
`process-exit.json` and `summary.json`. Raw Flutter machine output and stderr are
preserved as `events.jsonl.gz` and `stderr.log.gz`. `cases.json.gz` records every
counted case; hidden/loading and setup/teardown events are excluded and retained
separately. These cases are disjoint from the engine and the other package cohort.

## Source binding

Acceptance binds to actual before/after source bytes. Branch history can advance
during a run without changing source; the recorded HEAD alone is not an acceptance
binding. Both SHA-256 and Git blob SHA-1 identities allow comparison with the final
saved product commit.

| Inventory | Files | Result |
| --- | ---: | --- |
| Current source, selected tests and fixtures | 624 | Identical before/after |
| Reachable dependency sources | 2738 | Identical before/after |
| Genuine Flutter/Dart runtime | 1170 | Identical before/after |
| Workspace graph, manifests, lock and configuration | 17 | Identical before/after |

Every selected suite ran, every started test event finished exactly once, all
input guards passed, and the runner emitted exactly one successful completion.
The diagnostic marker scan is retained in `diagnostics.json`.

## Runtime and scope

This run uses the genuine pinned Flutter 3.47.8 / Dart 3.13.7 runtime and exact
110-package workspace graph. The shared complete setup receipts are preserved
with the engine cohort; no SDK, dependency or product substitutes were used.

The 31-test setup smoke, focused feature/development checks, the first failed
complete editor attempt, and the interrupted editor attempt are excluded from
current totals. Their evidence retains its original scope and input identities.

This qualification uses real Flutter execution with controlled responses and
synthetic documents. It does not claim a fresh live Zotero session, full application
build or new Microsoft Word/LibreOffice acceptance. No GitHub Actions, check or
status endpoints were queried, awaited or rerun.
