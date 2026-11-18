## Why

Spreadsheet calendar-relative conditional formatting compared UTC serial dates with local-midnight period boundaries. Timezone offsets and daylight-saving transitions could move an endpoint outside the intended calendar day.

## Changes

- Preserve the injected clock's local year/month/day while constructing period boundaries and performing date arithmetic in UTC.
- Add eight regressions covering midnight endpoints, daylight-saving changes, week ranges and year boundaries.
- Add braces around an inherited rendering-test statement so strict analysis passes, preserving its condition and assertions.
- Preserve reconciled Office evidence, exact runtime recovery, independent audits and complete current-source qualification archives.

Main remains `482e0817`, including merged #151/#152 and subsequent German grammar, phrase-formatting and spreadsheet-icon changes. All 191 branches and 154 PR heads were fetched and reconciled. Separate native spaCy #139/#153 work remains identified; the final W7 arrival at `2df0e930` changes documentation/evidence only.

## Local validation — accepted

Implementation: `9a7c80be00258def2dcae3bb288c28558c83aa72`.
Execution checkout: `9d060658ee6be8ec97d73f56b9aec10d346b7952`; the difference is documentation only. Later branch commits also preserve documentation/evidence without changing implementation or tests.

| Gate | Result |
| --- | --- |
| Strict analysis / formatting | Five analysis commands passed; 145 formatting targets, zero changes |
| Python controls | 117 passed |
| Canonical | 224 files; 4,234 substantive successes; zero unexpected skips |
| Portable | 17 Node suites; 225 successes |
| Editor example | Two smoke tests passed |
| Calendar matrix | Eight tests in each of UTC, Europe/Berlin and America/Los_Angeles; all 24 executions passed |
| Document consumers | 50 fixtures and 220 schema parts accepted; independent archived-output replay reproduced all measurements |
| Native | 23 audit controls and AOT build passed; serial 1/2/4/8-thread arms all exited zero, matched cross-arm semantics and passed the unchanged historical comparison |

All source, dependency, runtime and workspace guards passed. Independent audits accepted 14 saved archives/1,145 members, the document replay and the complete new native sweep with zero findings. The native audit performed 157,981 checks. Short-check p95 was 156.511 / 66.157 / 52.068 / 41.935 ms for 1/2/4/8 threads; all recorded local latency, memory and model-size flags passed.

## Scope

Two unavailable private-PDF early returns are excluded from substantive canonical counts. The timezone matrix overlaps canonical tests. Boundary coverage is four strict layouts plus one bounded control. Document rendering uses LibreOffice; documented lxml diagnostic false negatives retain official Jing schema acceptance.

Native acceptance establishes bounded nonregression: the unchanged panel retains 6/18 exact supported error fixes and 10/10 supported clean controls unchanged, with two corpus cases explicitly unsupported. Local-host measurements do not establish intended-device performance or broad German quality. Stability across every final timed output remains a producer claim; retained first/warmup results and all timed decoder observations were independently audited. Local qualification is complete; deployment/release acceptance remains outside this result.

The earlier disk-full attempt remains rejected and preserved. Its successful events are not substituted for the later complete run.

## Evidence

- [Completed qualification report](https://github.com/CrispStrobe/quds_office_suite/blob/codex/office-local-qualification-20261118/docs/validation/office-completion-20261118/README.md)
- [Machine-readable accepted status](https://github.com/CrispStrobe/quds_office_suite/blob/codex/office-local-qualification-20261118/docs/validation/office-completion-20261118/status.json)
- [Final native audit](https://github.com/CrispStrobe/quds_office_suite/blob/codex/office-local-qualification-20261118/docs/validation/office-completion-20261118/review/native-completion-review.json)
- [Final remote reconciliation](https://github.com/CrispStrobe/quds_office_suite/blob/codex/office-local-qualification-20261118/docs/validation/office-completion-20261118/reconciliation/remote-frontier.json)

Checkpoints were saved incrementally with `[skip ci]`, non-forced expected-head updates and exact remote archive/member readback. No GitHub Actions, workflow, check or status endpoint was queried, awaited or rerun.
