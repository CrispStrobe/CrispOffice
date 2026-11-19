# Preflight incoming refresh

This is a separate bounded refresh after the UID-discovery implementation was
published as `5fcdf726694b5356d8fb85fb8e01a715e0fadc0c`.

Origin capture completed at **2026-11-19 07:50:37 UTC** (08:50:37 CET); upstream
capture completed at 07:50:41 UTC. Raw advertisements, exact capture windows and
SHA-256 digests are retained beside this file.

The advertisement contains **417 actual references**: 217 fork branches, 179
pull-request heads, 17 tags and four upstream branches. Four additional rows
are peeled annotated-tag advertisements. All 14 historical equivalence proofs
were freshly reverified.

## Changes detected before qualification

The initial `before-integration-audit.json` intentionally reports 11 unaccounted
reference rows across six distinct new heads. Its `passed: false` is an incoming
integration requirement, not a runtime failure. The minimal frontier is:

| Commit | Captured source | Change needing preservation |
| --- | --- | --- |
| `f059065f` | `main` | Includes Arabic publication metadata and the captured Arabic branch `16cbbebd` |
| `19969056` | Mail reader / PR #172 | Concurrent reconciliation and retained Mail documentation |
| `cd430b22` | Office main integration / PR #179 | Concurrent reconciliation of already included source and evidence |
| `c268ce3b` | Office current reconciliation / PR #177 | Restricts AyaSpell uploads to verified relative filenames; seven offline tests |
| `0b8f8f7f` | Office main sync / PR #178 | Independently applies the upload restriction; five offline tests including deterministic builds |

The two AyaSpell implementations agree on the security-relevant change: pass an
explicit list of verified bundle filenames and the generated manifest to the
upload client. Their tests cover complementary intentions and should be retained
together. The source-selection and test gates must bind the resulting builder
and test files. No external publication is performed by these offline tests.

No new Mail runtime implementation was identified beyond the checkpointed UID
discovery source. The passing `post-integration-audit.json` binds local integration
`ea900499af1a59fbf5d433b8b7a522c8d8a4a144` to this exact capture: **389
ancestors + 28 verified historical equivalents**, with zero unaccounted refs.
No additional remote refresh is implied. The final published qualification
checkpoint is identified by the parent report; this local commit records the
actual merge reconciliation.

The immutable source-equivalence checks do not imply application acceptance.
GitHub Actions were not queried or awaited.

## Merged AyaSpell controls

The exact incoming builder from `0b8f8f7f` retains the current publication
metadata and verified-filename upload restriction. Both test suites are retained:
seven cases in `test_build_bundle.py` and five in
`test_build_bundle_reproducibility.py`. The seven-case suite's assertion about
the planned adapter follows the equivalent current card wording; the five-case
suite is retained byte-for-byte under its new filename. All 12 offline cases
passed in the development check. The frozen driver now binds all tracked
AyaSpell inputs, rejects untracked additions in that directory, and executes
this offline discovery gate before the Mail gates.
