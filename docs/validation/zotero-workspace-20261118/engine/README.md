# Current Zotero engine qualification

**Passed: 445 substantive tests across 22 suites; zero skips/errors; runner exit 0.**
The cohort is every top-level engine test matching `*zotero*_test.dart`, including
23 cases in the new `zotero_item_details_test.dart`. Each new case is counted once.
The separate 31-test runtime setup smoke is excluded.

## Source and execution binding

The complete exact command, environment paths, selected suites, actual runner
exit, timestamps, and test completion records are in `run.json` and
`summary.json`. `events.jsonl.gz` is the raw Dart test JSON event stream;
`stderr.log.gz` is the raw separate stderr. Per-case records are in
`cases.json.gz`; 22 hidden suite-loading events are in `excluded-events.json.gz`
and are not counted as tests.

Acceptance binds to the current source inventories, not merely the branch HEAD.
Root may save commits while source remains unchanged. Both SHA-256 and Git blob
identities are retained for every source input so the final product commit can
be matched to this run without repeating tests.

Before/after guards all pass:

| Inventory | Files | Outcome |
| --- | ---: | --- |
| Engine/parser source, selected tests and Zotero fixtures | 419 | Identical |
| Reachable hosted dependency sources | 1,714 | Identical |
| Genuine Dart SDK runtime files | 1,047 | Identical |
| Workspace graph, manifests, lock and analysis options | 7 | Identical |

Every started test event finished exactly once, all 22 selected suites executed,
the suite selection remained unchanged, the runner emitted one successful
completion event, and JSON parsing reported no errors.

## Runtime

The runtime is genuine official Flutter 3.47.8 / Dart 3.13.7. Its release archive
was SHA-256 verified before extraction; SDK tracked source is unchanged. All 162
required official Pub archives were verified against exact lock hashes. Both the
workspace lock and Flutter tools lock remain unchanged after enforced offline
resolution. The current validation graph has 110 packages and all 11 manifests
match current source.

The compact `setup/` directory preserves the runtime receipt, archive receipt,
package receipt, commands, logs and reproduction scripts. It deliberately omits
the downloaded SDK/archive/cache binaries. The two interrupted setup-only
Flutter launch attempts ran no tests and remain recorded; the later real widget
setup smoke passed 31 cases and is excluded from these 445 engine passes.

## Reproduction

Prepare the recorded genuine SDK and exact locked packages, recreate the current
source workspace with `setup/prepare_workspace.py`, then invoke `run_engine.py`
with `--repo`, `--workspace`, `--toolchain`, and a **fresh** `--output` directory.
The runner uses the configured `package:test` entrypoint directly with the actual
Dart executable, JSON reporting, and concurrency 4, avoiding implicit Pub or CI.
Absolute paths in receipts identify this execution; they are not repository
requirements.

## Scope

This cohort exercises controlled Zotero responses and synthetic document/fixture
behavior. It does not claim live-account or running-desktop acceptance, a full
application build, or new Microsoft Word/LibreOffice acceptance. No GitHub
Actions, status or check endpoints were used.
