# Authentic Flutter setup and recovery

**Setup passed**, resolving the actual Flutter tools and repository workspace
offline. The workspace contains **108 packages**. This setup receipt establishes
the runtime and dependency preparation; execution results are recorded separately
in the editor validation directory.

The selected official Flutter 3.47.8 archive was streamed in full
(1,581,444,364 compressed bytes) and checked against SHA-256
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`
before the SDK ran. The selected installation occupies 1,363,358,854 bytes across
4,299 files. It includes the genuine Git metadata, version/engine stamps, Dart
3.13.7, Linux testing and web artifacts; unused platform artifacts and framework
tests/examples were omitted. No SDK identity or engine stamps were fabricated.

[bootstrap-receipt.json](bootstrap-receipt.json) records the actual runtime:
Flutter revision `737ba8f885dc774b53b442759999a312c9461e4e`,
engine `cf636b1dfb818dd6a3ff16e390e93b1a036969c8` and Dart 3.13.7.
[bootstrap-evidence.tar.gz](bootstrap-evidence.tar.gz) preserves the complete
installation manifest, pinned package download receipts, all setup command
logs, the first two failed attempts and the scripts. Extract it to inspect the
original file names referenced by the receipt.

Two bounded preparation errors are retained:

1. Two package downloads ended with incomplete HTTP bodies. Retrying those
   exact pinned URLs completed them; their archive digests matched the locks.
2. The helper initially added a newline to Pub's cached SHA-256 text files.
   Pub expects exactly 64 hexadecimal bytes. The repair removed only that LF
   after verifying that the hexadecimal value matched the already verified
   locked archive digest. No package bytes or digest values were changed.
   The exact [repair record](cache-metadata-repair.json) is retained.
   The reusable [bootstrap script](bootstrap_flutter.py) now writes the correct
   metadata format.

The final tools and workspace Pub commands both returned zero. Earlier isolated
sessions became inaccessible during setup; no editor pass is inferred from those
lost sessions. Source was already saved remotely before the recovery.

To reproduce in a separate workspace, run the bootstrap script with
`--repo`, `--sdk-parent`, `--pub-cache` and a fresh `--output` directory.
It downloads only pinned archives, checks their hashes, and resolves offline.
Do not run another Pub writer against the same cache concurrently.
