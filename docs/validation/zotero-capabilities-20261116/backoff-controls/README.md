# Zotero session backoff behavioral control

The same widget assertion compiles against both archived implementations.
The baseline makes a second online request during an unexpired `Retry-After`
pause and fails the request-count assertion. The corrected implementation
keeps the count at one through reconnecting with another key and closing and
reopening the dialog with the same session.

| Source | Observed result |
| --- | --- |
| Before: `357f7a3e87d8536c03ecca2a860a0a564b1659f0` | Exit 1: two `GET /keys/current` requests instead of one |
| After: `039c1e293052f548367f9ea3b0fa5ff56949ccaa` | Exit 0: the unchanged reconnect/reopen test passes |

This is one before/after behavioral control, separate from the final
qualification cohort. Its executions must not increase the final test count.
The baseline failure is an assertion after successful compilation, not an
unavailable API or dependency failure.

## Inputs and verification

The complete `word_zotero_backoff_session_test.dart` fixture is copied verbatim
from commit `039c1e293052f548367f9ea3b0fa5ff56949ccaa` to both isolated archives.
Its SHA-256 is
`1fb5449f1a26ca5df41a73a196e28618ab447182d823109331420e4b81fc0d92`.
The runner selects only `reconnecting and reopening keep an online session pause`.

`source-receipt.json` records both source pins, Git blob IDs and SHA-256 hashes
for all archived files, unchanged copied manifests and lockfiles, rebased
package configurations, runtime binary hashes and the exact fixture hash.
`dependency-inputs.json` retains hashes of external package library files and
manifests. `receipt.json` records exact commands, working directories, process
exit codes and log hashes. Complete logs are in `logs/`.

Post-run verification confirms:

- All **463 before-source files** and **463 after-source files** still match
  their pinned Git blobs and initial SHA-256 hashes.
- All **3,018 external dependency files across 75 packages** are unchanged.
- Copied harness manifests, lockfiles, package configurations and test bytes
  are unchanged in both isolated graphs.
- Every shared input read from the earlier behavioral-controls setup remains
  unchanged, and the two test copies are byte-identical.

Both expected observations and every integrity check pass. No canonical
repository source or shared harness configuration was rewritten. No earlier
control logs were changed. No GitHub Actions or status checks were queried.

## Reproduction

Reconstruct the genuine local Flutter/Dart harness and the sibling
`zotero-toolchain/behavioral-controls` setup first, using its recorded
instructions. Place this script and fixture in a fresh
`zotero-toolchain/backoff-controls` directory with both commits available in
the adjacent `quds_office_suite` checkout, then run:

```bash
source zotero-toolchain/env.sh
python3 zotero-toolchain/backoff-controls/run-controls.py
```

The script archives production source directly from the two commits, verifies
the earlier controls' locked inputs before copying them, rebases only its own
package configurations, and retains the original nonzero baseline exit. It
refuses to overwrite an existing before/after archive.
