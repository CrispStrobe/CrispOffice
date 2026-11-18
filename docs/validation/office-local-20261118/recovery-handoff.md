# Recovery handoff — 18 November 2026

## Durable source and status

Repository: `CrispStrobe/quds_office_suite`. Branch: `codex/office-local-qualification-20261118`.
Corrected source: `9a7c80be00258def2dcae3bb288c28558c83aa72`; tree `695ec1a326965894eff7c37583e3b9c4fcf4492d`.
Later branch commits contain documentation/evidence only. Last verified source checkout was clean and detached at that source.

**Qualification remains rejected/incomplete.** Preserve the failed receipts. The latest attempt completed five strict-analysis commands, formatting of 145 files, and 117 Python controls. Engine Zotero emitted 390 successful visible test events across 19 suites, then exited 255 because its compiler could not create a disposal/cache directory (errno 28, disk full). The test-event summary cannot override that process failure.

The shared filesystem repeatedly reached zero available space after several safe cleanups. Even command creation failed; a persistent read-only session was used to upload completed evidence. The execution workspace then became unavailable. A later process-creation attempt failed at the exec-server with “No such file or directory”. No remaining test processes were reported by either qualification agent.

## Exact saved evidence

The complete ended current-source attempt is `evidence/canonical-attempt-9a7c80be.tar.xz`:
638,988 bytes, SHA-256 `14a2e5d6d0ae73501eb6e240d67896a3936482188a3344c1eee44c877e161e42`, 42 indexed members.
Its index SHA-256 is `8a018da23c0ed0fca075f256dd48646f9e7e1fd7cf0ba8c9c4b84efaee643f07`.
The producer completed archive readback; the independent reviewer verified the entire archive hash, receipts, logs and event counts, but environment loss interrupted the separate complete member-hash audit. That remaining audit must not be reported as completed.

The helpers archive `evidence/qualification-helpers.tar.xz` contains the bounded consumer/native orchestrators and the unchanged focused-frame harness: 14,328 bytes, SHA-256 `1bcaeeb785d918b155fa47d220c1930198e63668efcaef1e4404e7c8442817d5`, ten indexed members.

The native recovery, Flutter recovery, rejected 401d0126 lint preflight, independent runtime reviews, source review, sparse-checkout/dedup/release receipts, and exact calendar/example/canonical helper commands are also saved in this directory. Do not relabel historical consumer archives as results for 9a7c80be.

## Reconciliation

Main cutoff `482e0817` includes PR #151, PR #152 and later German/formatting work.
The initial fetch captured 190 live branch heads and 152 PR heads; follow-up connector review captured 191 branches and all 152 PR records.
Only PR #139 was open at that review, owned by the separate native spaCy continuation.

The latest observed concurrent Office head was `codex/office-continue-20261118` at `a52332b2488b1c07f65894903b4296c15bb3ebd4`. It merges our original 401d0126 checkpoint and spaCy W6, and retains an alternate direct-common SectionFrame implementation. Do not silently replace the main-based common-parent implementation with that tree.
The separate `feat/native-spacy-w7-20261118` head was `13747281fb25b5c55c549255595c75a7ca0854ef`, with documentation-only additions relative to spaCy `20026ff4` at that observation.
Refresh refs before new work; inventory and assess any new source changes without awaiting CI.

## Restore execution before launching gates

1. Restore a usable workspace with stable free storage. Inspect existing files and archives before redownloading. Do not delete another task's files.
2. Fetch this branch and the current remote refs. Inspect local status and preserve unexpected edits. Freeze the explicit source to be tested; the saved 9a7c80be candidate needs no further known product repair.
3. Restore the recorded runtime pins. Recovery recipes and receipts are archived; adapt only workspace paths and recorded storage selections. Do not weaken model/library hashes or omit selected tests.
4. Use the **actual** Flutter path consistently, not its symlink alias. Resolve the unchanged package lock offline, then prewarm the CLI before input snapshots.
5. Verify clean source, exact dependency/runtime inputs and a stable package config. Start every attempt in a new output directory.

The previous workspace was:
`/workspace/scratch/5e1b9c2fa60d`.
Relevant paths below must be adapted together if recovery uses a new workspace.

```bash
TASK_ROOT=/workspace/scratch/5e1b9c2fa60d
REPO="$TASK_ROOT/quds_office_suite"
WORK="$TASK_ROOT/flutter-qualification/workspace"
SOURCE=9a7c80be00258def2dcae3bb288c28558c83aa72
source "$TASK_ROOT/native-consumers/native-qualification-runtime/native-env.sh"
export FLUTTER_ROOT="$TASK_ROOT/toolchains/flutter"
export PUB_CACHE="$TASK_ROOT/toolchains/pub-cache"
export TMPDIR="$WORK/tmp"
export XDG_CONFIG_HOME="$WORK/config"
export PATH="$FLUTTER_ROOT/bin/cache/dart-sdk/bin:$PATH"
export CI=true DART_SUPPRESS_ANALYTICS=true FLUTTER_SUPPRESS_ANALYTICS=true
export DASH__SUPPRESS_ANALYTICS=true PYTHONDONTWRITEBYTECODE=1
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
```

The exact workspace lock SHA-256 is `344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.
Flutter is 3.47.8 / Dart 3.13.7, framework `737ba8f885dc774b53b442759999a312c9461e4e`, engine `cf636b1dfb818dd6a3ff16e390e93b1a036969c8`.
Native library SHA-256: `9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604`.
Mixed model SHA-256: `549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b`.
Python controls use ONNX 1.19.1 / ONNX Runtime 1.23.2 / NumPy 2.3.5. The original 27-package recovery and the 25-package runtime after removing build-only cmake/ninja are separately recorded.

### Package-config stabilization

The failed attempt's sole workspace hash delta was `.dart_tool/package_config.json`:
before `5cb1855e6f1b1b05fb0ff43347a2adaee7755d861dc8f13aae0b836652e3292b`;
after `abcc19f74f1237fac97ccc920e4df402d49fd974ada14ca75f6a187fc7d6eb0b`.
The runner author observed identical 109 normalized package records and only the top-level `flutterRoot` URI changing from `flutter-sdk` to `flutter`.
The independent reviewer verified both counts, URIs and the live after-file hash, but its full normalization loop did not finish. Exact after-file bytes were not added to the archive before access was lost. If the old workspace survives, preserve them before changing it.

Do not waive the original failed integrity flag. Offline resolution under the actual FLUTTER_ROOT and a bounded `dart test --help` warm-up must happen **before** fresh snapshots. The cold CLI previously created a reproducible 27 MB bootstrap snapshot; startup then completed and the tests ran.

### Canonical and portable gates

```bash
"$QUALIFICATION_PYTHON" -u   "$REPO/docs/validation/office-reconciled-20261117/qualification/run_qualification.py"   --repo "$REPO" --source-commit "$SOURCE" --flutter-root "$FLUTTER_ROOT"   --workspace "$WORK" --output "$TASK_ROOT/flutter-qualification/canonical-9a7c80be-retry"
```

Selection: 224 unique files: engine Zotero 19, editor Zotero 13, engine integration 138, editor integration 37, Harper 3, GECToR 14. The same five analysis commands, 145 formatting targets and 117 Python controls remain required. Native fixture skips are forbidden.

After canonical success, use the same five arguments and distinct fresh outputs for:
- `docs/validation/gector-office-resume-20261117/run_portable.py`: 17 Node suites.
- `docs/validation/gector-office-resume-20261117/run_editor_example.py`: two smoke tests.
- Saved `setup/run_calendar_timezones.py`: eight regression tests each under UTC, Europe/Berlin and America/Los_Angeles. The helper verifies actual timezone offsets; these 24 executions overlap canonical coverage and must not be added to it as unique tests.

### Document consumers and native sweep

Restore the helpers archive to the external native-consumers workspace. Its index stores the three orchestration scripts under `helpers/`; place them at `$TASK_ROOT/native-consumers/`. Place `frame-harness/*` at `$TASK_ROOT/native-consumers/frame-consumers/harness/`. The `runtime/` members are recorded receipts, not an installed Python environment. Preserve their original archive paths/hashes in the evidence.

Set:
`REF="$TASK_ROOT/native-consumers/consumer-runtime/retained-reference"`,
`DART="$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart"`,
`NATIVE="$TASK_ROOT/native-consumers/native-qualification-runtime"`.

Run `run_guarded_consumer.py` sequentially with `--gate retained33`, then `current7`, `boundary5`, and `frame5`, always supplying `--commit "$SOURCE" --workspace "$WORK"`.
Each gate has a bounded process-group timeout, exact-source/runtime guard and immediate archive/readback.
Retained40 means 33+7 fixtures / 160 XML parts. Boundary5 means four strict layouts plus one bounded control, 15 PDF variants and 10 DOCX reopens. Focused frame5 is separate overlapping feature coverage.

Only after other model/compile jobs finish, run `run_guarded_native.py --phase prepare` then `--phase sweep`, with that same source and workspace.
The unchanged underlying sweep is `docs/validation/german-gector/2026-11-17-followup/native-threads/run_native_thread_sweep.py`.
It runs 1/2/4/8 threads serially and writes partial receipts after each arm. Report semantic acceptance separately from exploratory performance-budget flags.

All these current-source gates were unstarted when execution access was lost.

## Acceptance and publication

Package completed gates immediately, read back all members against their indexes, publish each meaningful checkpoint, and independently verify remote blobs. Keep HEAD/source/tests/harness and consumed runtime inputs stable during every gate. Publish documentation through a separate index or direct Git Data objects.

Use non-forced expected-SHA branch updates and `[skip ci]` messages. Inspect a changed remote head before retrying. No additional publication permission is needed for this authorized continuation.
Never query, await or rerun GitHub Actions/check/status endpoints for this work.
Do not claim release acceptance until all required gates and independent evidence audits pass.

## Final remote refresh and review link

Draft PR #154 records this continuation. At the final refresh, main was still `482e0817`. Separate draft PR #153 now tracks W7 native spaCy packaging on `feat/native-spacy-w7-20261118` at `2e57784093fd2d1f44fe27edb31077d4163693f2`, stacked on #139. Its installed-worker acceptance is still reported as in progress. See `review/final-remote-refresh.json`; this separate packaging work was not silently merged into the Office qualification candidate.
