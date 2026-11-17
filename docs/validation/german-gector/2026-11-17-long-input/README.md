# German proofing continuation: bounded long inputs — 17 November 2026

Starting remote checkpoint: `d2e50c3a298679fed873d045a4b2d07663b37246` on
`feat/german-gector-proofing`. The user requested all incoming work first,
incremental remote checkpoints, and local validation without waiting for
GitHub Actions. No Actions job is dispatched, polled or awaited by this work.

## Incoming integration

`incoming-snapshot.json` records the GitHub branch and recent PR inventory;
`fetched-refs.json` records all fetched Quds branch and PR-head refs. Only the
morphology, Office-fidelity and Office-continuation tips were missing from the
starting checkpoint. All older fetched Quds refs were already ancestors.
The cooperating audit retains all 257 branch refs and finds no new work in
CrispEmbed, onnx_runtime_dart or fastembed-rs relative to the prior inventory.

First merge: morphology `f986fd031e4f984200c392e844ad83ae1ef5eb24` (PR #105).
This retains its source-bound local evidence and strict-analysis brace fix.
The roadmap conflict combines the implemented guard/native descriptions with
the newer 6/18 GECToR result; historical 5/18 morphology measurements retain
their own source identity. `docs/PROOFING.md` now distinguishes those reports.

The first checkpoint saved the incoming merge before retesting; the completed
integration and local results are recorded below.

Second merge: Office continuation `555eb728ce3ea872cb5ceb3e5fd2104b21f932aa`.
The section tests adopt its interpolation lint fixes. The annotation fixture
keeps the already-equivalent local `annotationText` variable, so both branches'
4,096-character byte-budget assertion is preserved without an unused variable.
The incoming initial-analysis-failure receipt is retained unchanged.

Third merge: Office fidelity `4ca30ec3ba9e2a1c2288d78bb83d2a3ce3678e0d`
(PR #101), including the previously deferred `097475fb` integration. The list
writer compares authored levels and preserves per-item bullet/number styles.
Its first-paragraph style stays applied once across nested lists. Existing
section activation and bookmark/link tests are retained; older section-style
code from the incoming merge does not replace the newer integrated behavior.
Duplicate Unreleased changelog bullets from earlier integrations are collapsed.
The new 13-case list-fidelity suite is retained for combined local validation.

## Integrated source validation

The complete incoming implementation is `145a0c04fa79a04fd903d196b2d6559b7e195b93`.
`integrated-ancestry.json` verifies every fetched Quds branch and PR-head tip as
an ancestor of that commit. The morphology, Office-continuation and
Office-fidelity merges were each saved remotely and read back before proceeding.

| Local cohort | Passed |
| --- | ---: |
| ODT/ODF, including authored-list and covered-cell/export-text controls | 191 |
| Deterministic German grammar | 268 |
| Editor proofing and manual/F7 | 97 |
| Total distinct tests | 556 |

Focused strict Dart analysis of four changed engine files also passed.
The retained `integration-summary.json` and compressed logs/receipts bind the
commands, source maps, runtime, duration and exit statuses. Receipt/log names
in that index refer to their original validation directory; here the same
bytes are stored with the `integration-` prefix. Engine/editor source maps
and package configuration were unchanged throughout each run.

The expanded ODT cohort is broader than the previous 148-test cohort; it is not
an arithmetic continuation of that historical test count. No visual desktop
word-processor export or intended-device qualification is claimed.
