# Recovery handoff after execution-workspace outage

## Durable state

- Repository: `CrispStrobe/quds_office_suite`.
- Branch: `codex/odt-column-boundary-followup-20261117`.
- Draft PR: https://github.com/CrispStrobe/quds_office_suite/pull/144, base `main`.
- Last complete source/test checkpoint: `9e21e4c08a0a7f04c165dedc316038038b2c47d4`.
- Source tree: `3aab8c7bb1522468c4a821e4ae588c826acbea27`.
- Merge parents: `4557f66052ad1a7863fd9fdf5545ad6cb39fc95d` and `16e2477ff93f7a1ec5c6ed78491f2716ce4d1658`.
- Captured #143 ancestor: `83f8c380f9271b6bf34a300c3aedc19442cb61f1`.
- The source checkout was clean before the final runs. Subsequent remote checkpoint changes are documentation only.
- The user explicitly authorized incremental remote saves and instructed us not to wait for GitHub Actions. No further publication confirmation is needed for this continuation.

The original pasted handoff was already merged through #140. The new work fixes leading ODT column breaks at later multi-column section starts and reconciles two stale fidelity assertions plus one stale editor grammar rule-ID expectation. Do not revive the rejected standalone paragraph-page-break disjunct: independent native DOCX rendering demonstrated that its left-column precedence must remain unchanged.

The first fetch inventoried 175 branch / 143 PR heads; a later refresh inventoried 177 branch / 144 PR heads. Latest captured main is included. Native spaCy #139 remains separately owned and unmerged. AOT/RML remains deliberately removed. #143 was not closed or mutated.

## Exact stopping point

The full runner started on 9e21e4c0 with **217 unique test files**: engine Zotero 19, editor Zotero 13, engine integration 131, editor integration 37, Harper 3 and Gector 14. The five strict-analysis commands, formatter and Python-control command reported passing. The last observed cohort event was the start of engine Zotero. The final broad and Node outcomes and after-run integrity receipts were not observed before the execution environment became unavailable.

Fresh retained consumers reported **40 fixtures / 160 XML parts** passing. Their archive completed and verified 708 members, but copying/uploading it never started. Fresh boundary consumers reported **four strict layouts plus one bounded control**, 15 PDF variants and 10 DOCX reopen checks passing; packaging never started. The independent reviewer did not inspect those fresh final receipts. Preserve these as observations, not certified durable evidence.

No source or test change was pending when the outage occurred. Do not invent pass totals or reconstruct raw receipts from these observations.

## Last known local paths

These paths were in the unavailable workspace; their continued existence has not been verified.

| Purpose | Last known path |
| --- | --- |
| Repository | `/workspace/scratch/9089a56d3a33/quds_office_suite` |
| Full qualification | `/workspace/scratch/9089a56d3a33/qualification-9e21e4c0` |
| Portable run | `/workspace/scratch/9089a56d3a33/portable-9e21e4c0` |
| Full pinned workspace | `/workspace/scratch/9089a56d3a33/full-validation-workspace` |
| Flutter SDK | `/workspace/scratch/9089a56d3a33/toolchains/flutter-sdk` |
| Native/Python setup | `/workspace/scratch/9089a56d3a33/native-qualification-runtime/native-env.sh` |
| New boundary outputs | `/workspace/scratch/9089a56d3a33/boundary-consumers-9e21e4c0` |
| Retained consumer archive | `/workspace/scratch/9089a56d3a33/consumers-9e21e4c0.tar.xz` |
| Retained archive index | `/workspace/scratch/9089a56d3a33/consumers-9e21e4c0.tar.index.json` |

The unuploaded retained archive was reported as 2,225,404 bytes, SHA-256 `02eaa4edd604072300c683cb3266b1b55017c7add82d3ee50572c664eea245ac`. There is no verified remote blob for it.

## Required resumption steps

1. Restore execution access. Inspect existing receipts and running-process state before restarting anything. If final receipts survived, verify their exact source and all before/after maps, event counts and command outcomes.
2. Refresh remote branches and PR heads, recording any newer relevant changes. Preserve the existing branch history and use expected-SHA leases for remote updates.
3. If the old runs cannot be fully audited, run the unchanged qualification and portable scripts on one clean frozen source. Do not mutate source, tests, harness, package graph or HEAD during those runs. New documentation-only HEADs can be qualified with their own recorded SHA; do not label them as runs of 9e21.
4. Recover the retained and new consumer raw outputs and verify them; otherwise rerun those unchanged harnesses once on the same frozen product source.
5. Archive complete logs, commands, event summaries and source/dependency/runtime maps with `resume/package_checkpoint.py`. Read back every archive member and verify hashes. Upload each completed archive incrementally.
6. Complete independent evidence review, update verification/README/PR with actual results and keep historical/rejected outcomes separate. Do not report complete qualification until the missing gates pass.

No optional expansion of the test scope is required. The existing tests already cover the concrete defects and the latest incoming main changes.

## Pinned runtime

- Flutter 3.47.8, framework `737ba8f885dc774b53b442759999a312c9461e4e`.
- Dart 3.13.7, language formatter setting 3.12.
- Engine `cf636b1dfb818dd6a3ff16e390e93b1a036969c8`.
- Exact 108-package workspace lock SHA-256: `344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.
- Required native library SHA-256: `9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604`.
- Required native model SHA-256: `549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b`.
- Python ONNX 1.19.1 / ONNX Runtime 1.23.2 / NumPy 2.3.5.
- LibreOfficeDev 26.8.0.0.alpha0, pdftotext 25.03, Java 21 and pinned Jing with unchanged official ODF schemas.
- All eight public font fixtures were restored. Two private PDF fixture early returns remain explicitly excluded from substantive counts; no native-test skips are allowed.

Recovery scripts, build provenance and hashes are retained in `evidence/runtime-recovery.tar.xz`. Large SDK/native/model binaries are not committed. Do not weaken native hash pins or production manifests to get a run through.

## Full local runner

Run from the restored repository after paths and pinned prerequisites have been verified. Use a fresh output path; the runner refuses to overwrite an attempt.

```bash
source /workspace/scratch/9089a56d3a33/native-qualification-runtime/native-env.sh
export FLUTTER_ROOT=/workspace/scratch/9089a56d3a33/toolchains/flutter-sdk
export PUB_CACHE=/workspace/scratch/9089a56d3a33/toolchains/pub-cache
export TMPDIR=/workspace/scratch/9089a56d3a33/full-validation-workspace/tmp
export XDG_CONFIG_HOME=/workspace/scratch/9089a56d3a33/full-validation-workspace/config
export CI=true DART_SUPPRESS_ANALYTICS=true FLUTTER_SUPPRESS_ANALYTICS=true
export PYTHONDONTWRITEBYTECODE=1
export PATH=/workspace/scratch/9089a56d3a33/toolchains/flutter-sdk/bin/cache/dart-sdk/bin:$PATH
QUALIFICATION_SOURCE=$(git rev-parse HEAD)
QUALIFICATION_OUTPUT=/workspace/scratch/9089a56d3a33/qualification-recovery-1

"$QUALIFICATION_PYTHON" docs/validation/office-reconciled-20261117/qualification/run_qualification.py \
  --repo /workspace/scratch/9089a56d3a33/quds_office_suite \
  --source-commit "$QUALIFICATION_SOURCE" \
  --flutter-root "$FLUTTER_ROOT" \
  --workspace /workspace/scratch/9089a56d3a33/full-validation-workspace \
  --output "$QUALIFICATION_OUTPUT"
```

The portable runner is `resume/run_portable.py`, with the same repo/workspace/flutter-root/source-commit arguments and a separate fresh output directory. Its 14-file selection excludes the VM-only fixture-export helper that reads `Platform.environment`; that file remains in the full VM cohort.

The retained 33+7 consumer runners and support files are preserved in `../recovered/consumer-intermediate-1d8325d4.tar.xz`, SHA-256 `49b519e8ef949a3dd6ff6cf1befa7f0264b90dab23da932aaa93879afc2e2951`. The new scoped checker is `consumer-new/verify_boundary_consumers.py`, SHA-256 `bb842e4a0a03b921ed59f8a2c48a781b3975b3b569f054d449fc4c8624cce84d`. Exact invocation details are preserved in `interruption-observations.json`.

## Evidence already saved remotely

Seven archives and their member indexes are present under `evidence/`: runtime recovery, rejected e95 candidate, 9b retained consumers, failed 9b broad/portable attempt, focused boundary/native controls, failed 622 broad attempt with passing portable cohort, and the 32-test editor rule-ID correction.

The 622 full run failed the stale editor expectation after passing engine cohorts; it is not an accepted full run. Its portable selection passed 207 tests with zero errors/skips and stable maps. The incoming writer fails nine final-byte boundary controls; the repaired writer passes all 21 on VM and Node. These results overlap broader cohorts and must not be added together.

The earlier exact-source consumer bridge from 9b to 622 is historical. Latest main changes engine inputs, so that bridge does not qualify 9e21. Native DOCX rendering uses LibreOffice, and the fifth bounded control retains its documented follower-balancing difference.

## Publication mechanics

CLI fetch worked, but CLI push had no credentials. Remote checkpoints were published through the GitHub connector's Git Data tools: create verified blobs/tree, create commit, then update the branch with `expected_sha` and `force=false`. Merge 9e21 retained both parents. Never force-push or overwrite another writer's checkpoint.

No GitHub Actions, workflow, check-run or CI-status endpoint was queried or awaited. Keep `[skip ci]` on checkpoint commit messages. The next action depends on execution access, not an approval request.
