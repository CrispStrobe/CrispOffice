# German proofing continuation, 17 November 2026

## Recovery checkpoint

The starting remote checkpoint is `f986fd031e4f984200c392e844ad83ae1ef5eb24`
on `codex/german-morphology-20261117`, PR #105. The user requested continued
work, integration of recent commits/PRs/branches, incremental remote saves,
and local validation without waiting for GitHub Actions.

The first fetch captured **128 branch heads and 107 PR heads** (235 refs,
158 distinct commits). See [incoming-refs.json](incoming-refs.json) and
[the recent PR inventory](incoming-prs.json). Eleven distinct heads are not
ancestors of the starting checkpoint. They are all reachable from these
three incoming tips:

| Branch | Captured SHA | Incoming work |
| --- | --- | --- |
| `feat/german-gector-proofing` | `d2e50c3a298679fed873d045a4b2d07663b37246` | Same-number verb-person aliases, immutable development-pack/AOT tooling, v2/v3 provider evidence, current main and Office integrations |
| `codex/office-fidelity-20261117` | `4ca30ec3ba9e2a1c2288d78bb83d2a3ce3678e0d` | Authored list siblings and mixed ODT list marker kinds |
| `codex/office-continuation-20261117` | `555eb728ce3ea872cb5ceb3e5fd2104b21f932aa` | Strict interpolation lint fixes and retained runtime-attempt evidence |

Current main at the capture is `67482c25a90631d54dd6dff6cda489687efb380f`,
including merged PR #106 (nested ODT lists) and #107 (bookmarks/linked ranges).
It is contained in the captured GECToR history. All existing reports remain
historical evidence for their explicitly recorded source and runtime inputs.

This first checkpoint records discovery before integration or fresh tests.
The next step is to combine the captured histories, verify ancestry and
preservation, then measure the optional model's incremental benefit over the
deterministic checker using the actual application conflict policy.

## Combined source and shared overlap policy

The three histories are integrated at
`17f1483a02c1d9819ff4a1b3dcf2dbc512cdfb57`. The
[ancestry audit](integration.json) confirms that **all 235 captured refs are
ancestors** of that checkpoint. Conflict resolution retained both historical
evidence series, combined authored list levels/marker kinds with current ODT
section and bookmark handling, and preserved the morphology/worker/locale fixes.

The editor's existing deterministic-first overlap policy is now the pure-Dart
`mergeOfficeProofingReports` helper. The editor and forthcoming quality runner
use the same policy. It preserves provider failures/unsupported statuses and
original offsets, rejects mixed snapshots or duplicate provider ownership,
and treats insertion points at either range boundary as conflicts. It never
applies edits or enables additional background checking.

Focused checks pass: 20 new merge-contract tests, 14 existing service tests,
11 manual/F7 editor tests, and strict changed-file analysis. Complete local
qualification and the prospective synthetic panel will be recorded separately
from the earlier source-specific reports.

No main merge, release or model publication is performed. No workflow is
dispatched, awaited, or used as a validation gate.
