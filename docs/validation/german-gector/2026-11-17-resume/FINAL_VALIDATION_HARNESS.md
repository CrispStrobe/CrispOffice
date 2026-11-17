# Final local validation harness

`validate_final.py` runs explicitly listed local cohorts serially and writes a
receipt, raw output and resolved-input copies for every attempt. It does not
fetch dependencies, dispatch CI, or perform native performance qualification.

The adjacent `final_validation_suites.json` selects explicit final cohorts, including the original eight
cohorts: `gector`, `german`, `shared-report`, `odt-odf`, `odp`, `editor`, `aot`,
and `tooling`. Test file names are explicit; execution never discovers additional
tests. The final selection also includes Studio lifecycle tests, supplemental Node
execution of changed German rule families, and five strict analysis suites.
The final manifest includes the new Office column/break regression file.

## Invocation

Use a fresh output directory for each attempt. Existing directories are refused.

```bash
python3 /workspace/scratch/e5b34feae619/runtime-recovery/validate_final.py \
  --root /workspace/scratch/e5b34feae619/quds_office_suite \
  --out /workspace/scratch/e5b34feae619/runtime-recovery/final-gector-attempt-1 \
  --activation /workspace/scratch/e5b34feae619/runtime-recovery/activate.sh \
  --suite gector
```

The script sources the sibling `activate.sh` automatically. `--activation` and
`--definitions` accept alternative files. `--suite` can be repeated to select a
serial sequence; `--suite all` uses manifest order. By default a failed cohort
stops that sequence; `--keep-going` continues to the remaining requested cohorts.

`--plan` saves the exact commands, selected file list and source hashes without
launching tests or analysis. It still checks that required inputs exist.

## Retained evidence

Every cohort directory contains `receipt.json` and either `events.jsonl` or
`analysis.log`. The receipt is written before the child process starts and
updated after completion, including process launch failures and timeouts. It
records UTC timestamps, elapsed time, exact command/cwd/test selection, git HEAD,
tracked worktree status, runtime executable identities, harness/manifest/runtime
activation identities, and selected source hashes before and after the run.

The original workspace `pubspec.lock` and resolved `package_config.json` are
copied before and after each run. Their hashes also appear among selected source
inputs. Resolved package names and URIs are retained in the receipt. Source
patterns in the manifest expand only the *hash inventory*; they never expand the
test command. Required empty patterns and missing files fail admission.

Dart and Flutter tests use the actual SDK executable. Flutter runs through
`dart flutter_tools.snapshot test --no-pub --reporter=json`, avoiding the mutable
Flutter wrapper. Python tooling tests run through an adapter for standard
`unittest` with per-test JSON events, explicit module paths, failures, skips,
subtest failures, and module/class setup failures. The raw output is retained.

Counts exclude hidden framework tests and loading pseudo-tests from ordinary
passed/failed totals. Loading failures, hidden failures, error events and final
`done` events are retained separately. Each visible test result retains its name
and ID. A successful gate requires an exit code of zero, exactly one successful
completion event, at least one visible passed test, no test/loading/hidden
failure, and zero skips unless the manifest explicitly permits them. Source,
runtime, git HEAD and validation-input stability also gate success. A timeout
terminates the process group and preserves the partial log.

## Adding strict analysis

The same manifest can define a cohort with `runner: "dart-analyze"`, an explicit
`paths` array instead of `tests`, and the same `cwd`, `sources`, and
`source_globs` fields. Analysis always uses `--fatal-infos --fatal-warnings` and
requires the normal `No issues found!` result. Default test cohort timeouts are
1200 seconds and can be changed per cohort using `timeout_seconds`.

No cohort, native fixture, analysis command, or performance run was executed
while creating this harness. Only Python syntax was parsed. Final execution and
source qualification remain the responsibility of the integrating agent.

## Integration review additions

Every cohort now checks the resolved library contents of all 110 packages and
asserts that the 11 workspace package roots point into this checkout. The native
fixture gate is explicitly enabled and recorded. SDK compiler/analysis payloads,
Flutter tester/frontend payloads, the actual Python invocation/venv and Node
identity are pinned. Relevant package analysis options and the original provider
comparison receipt are included in source maps. The retained qualified
`.venv-ref/bin/python` supplies the required ONNX tooling dependencies; its
version/import receipt is in `recovery/python-reference-verification.json.gz`.

Final runs are launched with explicit `--activation` and `--definitions` paths.
Supplemental Node results are reported separately from distinct tests.
