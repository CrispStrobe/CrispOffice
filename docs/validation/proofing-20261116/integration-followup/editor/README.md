# Final editor and host validation

**Passed against `3bd4657b1c1cccfad8adbcf5928e30b90e4a1aaa`.**
The run started at **2026-11-16 15:14:55 UTC** and finished at
**15:22:42 UTC**. All eight recorded stages passed.

- Full engine `lib test tool`, editor library plus 23 selected test files, and
  example host library passed strict analysis with `--fatal-infos`.
- The combined editor suite passed **294 tests**, with no failures or skips.
- The separate canvas IME reattachment regression passed **1 test**.
- The example release web build succeeded and produced **117 files**
  totaling **59,800,207 bytes**. Its complete manifest is retained.
- All **2,032 source inputs**, **16 runtime/configuration inputs**, the exact
  workspace lock and the package configuration remained unchanged.
  The resolved workspace contained **108 packages**.

[receipt.json](receipt.json) contains the actual commands, logs and their hashes,
selected test paths, runtime identity, timing and before/after manifest hashes.
[summary.json](summary.json) provides the concise machine-readable outcome.
The original compressed manifests and both copies of the workspace lock and
package configuration are preserved byte for byte.

The [verifier](verify_editor_source_bound.py) imports the repository's committed
integration helpers. Pass `--expected-source
3bd4657b1c1cccfad8adbcf5928e30b90e4a1aaa` when repeating this final run; its
default identifies the earlier checkpoint. See the
[combined report](../README.md#reproduction) for the complete command.

## First attempt

[initial-editor-attempt.tar.gz](initial-editor-attempt.tar.gz) retains the
earlier receipt, complete logs and manifests at `6f87a4e`. It exposed a
strict-analysis warning and a test that incorrectly expected viewing mode to
allow selection. The final source keeps a stable input-guard callback through a
named method and tests the non-mutating selecting mode with all edit-rejection
assertions retained.

The superseded first web build received SIGTERM so the corrected source could
be validated. Flutter returned zero but had not produced required JavaScript;
the verifier explicitly rejected that incomplete bundle. The final run was
uninterrupted, reported successful build completion and verified required
output files.

## Scope

The editor tests execute the actual Flutter Linux testing runtime. The platform
dictionary tests use mock services/channels; they do not establish installed
mobile dictionaries. The release build establishes compilation and artifact
identity, not browser interaction or HTTP/CSP acceptance. Optional Harper
runtime assets were not installed into this fresh bundle by this verifier.

The build's nonfatal CupertinoIcons font warning is preserved in
[example-web-build.log](example-web-build.log). No GitHub Actions were queried
or waited for.
