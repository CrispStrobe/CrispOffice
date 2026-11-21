# Independent final qualification audit

**Accepted.** An independent parser reconstructed the test populations directly
from the preserved raw JSON events and process exits. No tests were rerun by
this audit, and no source or test files were edited.

| Disjoint execution scope | Suites | Passed |
| --- | ---: | ---: |
| Zotero engine | 41 | 1,157 |
| Word/ODT ownership and fidelity | 27 | 432 |
| Zotero editor/controller/UI | 49 | 929 |
| Studio transport and shortcuts | 2 | 33 |
| **Total** | **119** | **2,551** |

There are zero failed cases, skipped cases, runtime error events or stderr
bytes. Each process exited successfully, reported exactly one successful
terminal event, and completed every started test exactly once. The 119 selected
suite paths are unique and disjoint across cohorts. The 2,551 suite/name case
identities are also unique.

The count excludes exactly 119 successful loading events and 12 successful
setup/teardown events. The audit rejects hidden events that cannot be identified
as loading or lifecycle work; it does not silently discard failed lifecycle
events. No skips are approved or used.

The separate Node run passed 121 cases from the two selected engine suites,
with no errors or stderr. Its exact suite/name population is a subset of the
accepted VM population, and its recorded source inputs match the same frozen
source. These executions add platform coverage and are not added to the unique
case count. The independent 21-probe review remains separate as well.

## Audit correction

The initial engine test process itself succeeded. Its original audit rejected
only the expected-suite path comparison: package:test reported paths relative
to its recorded process working directory, while the first Python auditor
resolved them against its own directory. The preserved v1 and v2 scripts differ
in exactly that one path-resolution expression. Commands, selected files,
timeouts, test semantics and event exclusions are unchanged.

Resolving the raw suite paths against `command.json`'s `cwd` produces exactly
the intended 41 engine files. The original raw streams, process exit, source
snapshots, failed audit summary and v1 bytes remain retained. A separate audit
accepts those same raw bytes; it does not replace the rejection or represent a
second engine test execution. The remaining 78 suites ran once under v2.

## Source and runtime identity

All 2,978 recorded source, manifest, lock and fixture entries match the frozen
commit `a6095c304ad2d6935f2ae6f8b74412038d19f142`, including Git blob identities,
current bytes and executable modes. Every cohort's before/after map and both
run-level maps are identical. The canonical map SHA-256 is
`b02b5b7f62c34bf37698d53e0cb614df93ac30d955ce0ad8b1cb1707f6f18916`.

The source recorder uses `rg --files`, so one hidden Git normalization file
inside the Word review fixtures is excluded from the runtime-bound map. The
independent Git-tree comparison records this exact metadata exclusion and
separately verifies its current identity against the frozen commit. Actual XML
fixture contents are included. This does not justify a claim that every
repository metadata file was bound during execution.

The 33 recorded runtime environment files—binaries, runner configuration,
manifests and locks—are identical before and after both executions. This is the
recorded runtime scope, not an exhaustive snapshot of every extracted package
file. The original test files were invoked through standard `package:test` and
`flutter test`, with engine concurrency two and Flutter concurrency one. No
merged synthetic test modules, test rewrites or name filters were introduced.

`audit_qualification.py` independently replays these checks and writes
`qualification-review.json`, including source identities, cohort counts, raw
stream hashes, overlap accounting and its own script hash. GitHub Actions and
status endpoints were neither queried nor awaited.
