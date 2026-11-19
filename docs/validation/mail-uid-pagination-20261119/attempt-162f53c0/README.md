# Retained combined attempt at 162f53c0 — overall FAIL

This attempt is bound to `162f53c0aff2314d88df912f9a64c0838e2a9da4`.
The complete [raw archive](attempt-162f53c0.tar.xz) retains all **82 output files**,
including generated web artifacts, reporter events, diagnostics, receipts and
source/runtime snapshots. Its [index](attempt-162f53c0.tar.index.json) records
all member sizes and SHA-256 values. No output was rewritten after failure.

## Why the combined gate failed

The core/store gate passed. Every native test assertion reported success
(1,007 cases, zero reported failures/skips), and strict analysis, formatting and
whitespace checks passed. However, the real Hunspell missing-dictionary test
emitted three native C standard-error diagnostics. The old runner merged those
bytes into JSON reporter output; strict protocol accounting rejected the three
non-JSON lines. The native gate and aggregate attempt are therefore **FAIL**.
The additional Node plan did not run. This is not a 1,257-case acceptance pass.

The runner repair preserves standard error in separate raw/gzip logs with hashes
and validates the complete reporter standard-output stream strictly. Malformed
stdout and nonzero exits still fail. Three real-subprocess controls cover the
separation, malformed stdout, and a failing exit with apparently successful
reporter events. All prior process-cleanup controls remain.

## Independently accepted unchanged Mail cohorts

The [scoped audit](accepted-mail-audit.json) verifies only the already accepted
cohorts, retaining the overall failure and absence of the final Node gate:

| Cohort | Accepted executions |
| --- | ---: |
| Core and durable store, VM/Node | 250 |
| Native transport/configuration/cursors | 119 |
| Native TLS | 26 |
| Shared protocol fork | 496 |
| MIME consumers | 32 |
| Mail reader UI | 30 |
| **Selected Mail total** | **953** |

These represent **865 distinct cases across 78 files**, with **88 VM/Node
repetitions**. The 91 Node executions here belong to core/store; none is an
execution of the deferred additional Node plan. Separate Python controls total
**98** (23 shared, 16 restorer, 17 AyaSpell, 42 Mail launcher).

Source, dependency and runtime snapshots stayed unchanged during execution.
The independent audit verified published source blobs, all 11,142 retained
runtime files and 24 additional inputs, and all 82 retained evidence files.
These selected results can be carried forward only after proving their product
and dependency inputs unchanged. The changed Arabic/Studio and dependent
Hunspell groups, plus all additional Node groups, require fresh qualification
on the final integrated source. Earlier Arabic/Hunspell assertions are excluded
from that final acceptance matrix to avoid duplicate execution claims.
