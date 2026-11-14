# Notes, sorting and cell-state regression controls — 14 November 2026

The [validation receipt](suite-controls-validation.json) compares four unchanged
regression files against distinct source snapshots. The baseline ran in an
isolated detached worktree; the active implementation was never replaced.

- Baseline: `79d001522c6550a21b01f2c033fb293c372d3208`.
- Candidate: `2182916ec1ecca84832194e6f49f7ae94b703aa7`.
- Runtime: Flutter 3.47.8 / Dart 3.13.7 on Linux.

| Comparable regression cohort | Baseline | Candidate |
| --- | --- | --- |
| Engine cell lock and border preservation | 0 passed, 2 failed | 2 passed, 0 failed |
| Editor cell history, sorting and speaker notes | 5 passed, 11 failed | 16 passed, 0 failed |

## Hash scope

Each input manifest hashes 420 local package-library, package-declaration,
resolved-lockfile and selected regression inputs. All four tests are
byte-identical between snapshots. Every recorded input was rehashed after
execution and remained unchanged. The receipt includes manifest hashes,
canonical input-map hashes, individual affected-library/test hashes and
SHA-256 hashes of all four test logs. Copied evidence retains its original
bytes; absolute paths describe the historical execution locations.

Each worktree resolved its own local packages. Offline setup used the same
lockfile and cached dependencies. Failure names and complete runner output
are preserved; the five passing baseline editor controls cover guarded or
unchanged behavior.

## Rejected pending-input probe

The candidate editor log contains **17** passes: the 16 comparable regressions
plus one candidate-only [probe](suite_sort_validation_guard_test.dart), excluded
from the comparison above. Its source hash is recorded separately.

With an invalid numeric draft in A2 and A1:A3 selected, sorting raises
`StateError` before mutation. Values, revision and command history remain
unchanged; the visible draft stays open and a corrected value still commits
to A2. No additional production guard was needed.

## Reproduction and bounds

Check out both recorded commits, copy the same four tests listed in the
receipt, resolve the workspace with the recorded SDK/lockfile, and run its
`commands` from the relevant engine or editor package. Use `CI=true`,
`BOT=true`, suppressed analytics and writable temporary/Pub directories.
Supply the preserved probe's new path for the additional candidate-only case.

These controls validate controller and cell-copy behavior. Lock/border tests
cover modeled state, not new XLSX serialization support. Broader suite, host
and external-format results are recorded separately.
