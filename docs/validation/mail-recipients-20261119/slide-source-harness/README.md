# Slide source harness

This executes the existing 14 slide import/model tests and the incoming explicit-run-style test against actual repository production files. The only test adaptation replaces the broad engine import with direct source-file imports; assertions are unchanged. The transitive source graph contains 45 files and only the external `crypto` production dependency.

The run uses Dart 3.13.7, cached test 1.31.1, and crypto 3.0.7. The full workspace locks crypto 3.0.8, so this is a qualified source test rather than a full workspace dependency qualification. The receipt records exact source/test hashes, import-only diffs, the command, and post-execution hash verification. `run.py` regenerates those artifacts and the log.

Reproduce in this workspace:

```bash
source /workspace/scratch/32e3793609d8/runtime/env.sh
python3 /workspace/scratch/32e3793609d8/validation/slide-source-harness/run.py \
  --repo /workspace/scratch/32e3793609d8/quds_office_suite \
  --dart /workspace/scratch/32e3793609d8/runtime/flutter/bin/cache/dart-sdk/bin/dart \
  --package-config /workspace/scratch/32e3793609d8/runtime/core-validation/.dart_tool/package_config.json \
  --test-runner /workspace/scratch/32e3793609d8/runtime/pub-cache/hosted/pub.dev/test-1.31.1/bin/test.dart
```

This evidence does **not** execute MIME/mail, PDF, Flutter widgets, or the full engine barrel. The asynchronous text-fidelity test still pulls unavailable `characters`; PDF rendering also pulls unavailable `image`. No mock dependencies were substituted. No GitHub Actions were queried or awaited.
