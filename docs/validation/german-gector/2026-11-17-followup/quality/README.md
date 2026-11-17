# Integrated baseline versus final quality replay

The integrated baseline is `db453d88d82700e9b8c96b0d9c00c1061e6ac18d`. Its isolated source snapshot contains 590 exact tracked files (17,401,670 bytes) and all ten workspace package roots. Each archived file is verified against its Git blob identity. Workspace libraries are copied; none link back to the mutable current checkout. External SDK and package-cache roots are shared. The root and engine-example packages have no `lib/` directory in this commit, which the receipts record explicitly.

All workspace manifests match the resolved current workspace. The frozen ignored lock is copied unchanged, then the official Flutter tool runs `pub get --offline --enforce-lockfile`. The lock and canonical package configuration remain byte-identical, resolving 109 packages.

The baseline `incremental-quality` AOT built successfully. Its SHA-256 is `3b6ff99fbb1f72c6339983f827c66f409de91b6340c7f3d6a6615c32c26bc7f7` (8,358,216 bytes). Source, every resolved package library, and SDK fingerprints remained stable during compilation. The preparation record has the local paths. Final compilation and current native inference must wait for the coordinating agent to finish other source changes and schedule serial native work.

## Panels and interpretation

The six existing panels contain 377 rows: original (30), development (76), syntax (56), context (83), context completion (28), and context holdout (104). Five use exact original bytes. Syntax receives only the previously required metadata-key rename `area` → `category`; input, expected text, locale, row order and all values remain unchanged. Both source and run hashes are recorded. These are reused synthetic panels, including the historically named holdout; they do not provide a new prospective or representative accuracy estimate.

The runner uses the existing `run_incremental_quality.dart`, real verified model/native assets, one check per input, and all four existing lanes. Its report durations are diagnostic only; separate serial runs own performance measurements. The incoming runner already orders writing rules before spelling, so panel gains must be read from actual results. The spelling-specific `sein` improvement is separately demonstrated by the retained failed-before unit tests.

## Reproduction

After activating the retained runtime, build the final runner only when its source is frozen:

```bash
source /workspace/scratch/8a4017da88e9/runtime-recovery/activate.sh
quds_quality_work=/workspace/scratch/8a4017da88e9/quality-replay
python "$QUDS_SOURCE_ROOT/tools/proofing/german_model/build_gector_aot.py" \
  --dart "$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" \
  --source-root "$QUDS_SOURCE_ROOT" --target incremental-quality \
  --output "$quds_quality_work/build-final/quality.aot" \
  --receipt "$quds_quality_work/build-final/quality-build.json"
```

The replay helper defaults to preparing commands only. With coordinated native execution, run baseline and final sequentially:

```bash
python "$quds_quality_work/run_quality_replay.py" \
  --source-root "$quds_quality_work/baseline-source" \
  --build-dir "$quds_quality_work/build-baseline" \
  --panels "$quds_quality_work/panels/panels.json" \
  --output-dir "$quds_quality_work/results-baseline" --execute
python "$quds_quality_work/run_quality_replay.py" \
  --source-root "$QUDS_SOURCE_ROOT" --build-dir "$quds_quality_work/build-final" \
  --panels "$quds_quality_work/panels/panels.json" \
  --output-dir "$quds_quality_work/results-final" --execute
python "$quds_quality_work/compare_quality_replay.py" \
  --baseline "$quds_quality_work/results-baseline" \
  --final "$quds_quality_work/results-final" \
  --baseline-build "$quds_quality_work/build-baseline/quality-build.json" \
  --final-build "$quds_quality_work/build-final/quality-build.json" \
  --panels "$quds_quality_work/panels/panels.json" \
  --output "$quds_quality_work/comparison.json"
```

Destinations must be fresh. `--only` can run one named panel without repeating completed panels. The helpers preserve partial provider reports and invocation receipts on failure.

## Independent comparison

The comparison script reconstructs UTF-16 ranges, first-replacement projection, skipped overlaps, displayed findings, provider statuses, the deterministic/model merge and summary counts from raw rows. It checks corpus and AOT/source bindings before comparing all lanes and languages for lost exact corrections or newly changed/flagged clean inputs. Existing misses and clean flags remain visible.

A retained historical raw report passes this audit. Five deliberate corruptions (corrected text, source range, gold, summary count and AOT identity) are rejected. That audit-control exercise ran no new inference and is separate from the current comparison.
