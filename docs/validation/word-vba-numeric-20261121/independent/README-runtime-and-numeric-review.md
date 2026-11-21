# Local Dart runtime and independent numeric review

## Runtime

- Genuine Dart SDK 3.13.7 stable, Linux x64.
- Download: `https://storage.googleapis.com/dart-archive/channels/stable/release/3.13.7/sdk/dartsdk-linux-x64-release.zip`.
- Archive verified against the official `.sha256sum`: `eb99aed266efbcb615c6ae21c12f52cfe935b9f208bccc5fea7f64c21e867229`.
- The verified SDK was extracted with original executable modes. The ZIP was subsequently removed to recover scratch space; the SDK remains.
- Executable: `/workspace/scratch/55ae4c05da4e/runtime/dart-sdk/bin/dart`.

The checkout is a Flutter workspace. To run the pure-Dart engine without changing its tracked manifests or root lock, an isolated harness resolves the exact existing hosted closure of `archive`, `characters`, `crypto`, `image`, `test`, `lints`, and `xml`. The 56-package transitive closure was computed from the locked versions' published dependency metadata and supplied as exact overrides in the external harness. All 56 downloaded package archive hashes match the original root lock. Twenty-two tracked pubspec manifests/locks were verified unchanged.

The first overbroad harness included all 137 hosted overrides and was refused because it included Flutter dependencies. Narrowing to the actual pure-Dart closure resolved this. The first package download attempt then found no `/tmp`; the final wrapper uses a scratch `TMPDIR`. Neither setup failure changed any tracked source, manifest, or lock.

`engine-harness/` retains the original lock parsed as JSON, the exact dependency closure, the standalone harness manifest and resolved lock, original tracked-manifest SHA-256 values, and effective package config. `finish-engine-harness.py` verifies package archive hashes and the tracked manifests, makes all generated package roots absolute, adds the actual checkout `quds_office_engine` and `legacy_doc_parser` roots, and creates only ignored `.dart_tool/package_config.json` in the checkout. It also creates `run-engine-tests.sh`.

Replay:

```sh
DART_DISABLE_ANALYTICS=1 \
TMPDIR=/workspace/scratch/55ae4c05da4e/runtime/tmp \
PUB_CACHE=/workspace/scratch/55ae4c05da4e/runtime/pub-cache \
/workspace/scratch/55ae4c05da4e/runtime/dart-sdk/bin/dart pub get \
  --directory=/workspace/scratch/55ae4c05da4e/runtime/engine-harness
python3 /workspace/scratch/55ae4c05da4e/runtime/finish-engine-harness.py
/workspace/scratch/55ae4c05da4e/runtime/run-engine-tests.sh \
  test/office_vba_word_position_test.dart --reporter json
```

The wrapper runs the real `package:test` CLI directly with the generated package config, sets `DART_DISABLE_ANALYTICS`, `PUB_CACHE`, `TMPDIR`, and SDK `PATH`, and selects the engine working directory. This avoids a new Flutter workspace resolution while preserving the checked-out source paths.

## Runtime sanity test

`office_vba_word_position_test.dart` passed 33 visible cases, zero failures/skips, successful process exit, and no stderr. Raw stream and summary are `baseline-position-tests.jsonl` and `baseline-position-summary.json`. This was a runtime sanity check during development, not a source-bound final regression gate.

## Independent numeric review

Read-only inspection found the new intrinsic dispatch consistent with existing checker/evaluator rules: single positional argument, static numeric/Variant validation, reserved identifiers, explicit Empty and Null behavior, common portable numeric bounds, single argument evaluation, and zero normalization. The documentation explicitly distinguishes this bounded numeric model from full VBA subtype/overflow semantics; no installed Word differential qualification is claimed.

`numeric-independent-probes.dart` exercises 81 checks covering:

- negative zero and minimum subnormal inputs;
- both signs at the 2^53-1 envelope and rejection beyond it;
- explicit String-to-number conversion;
- composed Null preservation and Sgn Null diagnostics;
- inactive branch static checks and unexecuted runtime refusals;
- single helper evaluation, including a Null-returning helper;
- reserved local/parameter/procedure names and qualified-call refusal;
- typed Font alias preservation.

The script passed on the Dart VM and after compilation to JavaScript and execution with Node. The two JSON receipts are byte-identical. VM, JS compilation, and Node exit statuses were zero, with empty stderr. The compiler Git blob stayed `b960ae6004c7292421a25bf9c8e75dc6f123e75e` from before the probes through final readback.

Six initial probe expectations used `vba_unsupported` for reserved declarations; the established checker correctly emits `vba_name_error`. Only those expectations changed. The initial rejected receipt and stderr are retained separately as `numeric-independent-initial-vm.*`; no production change resulted.

See `numeric-independent-summary.json` for exact probe/receipt hashes. These are supplemental compiler checks, kept separate from root's final regression totals. No GitHub Actions, check, or status queue was queried or awaited.
