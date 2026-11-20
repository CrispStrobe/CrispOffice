# Word paragraph-spacing original-suite regression evidence

Accepted source commit: `0201b549d0dc3f601c50e36255d557034cb01699`.
Accepted source tree: `86531c002a6b1d6e748849f7370a87072a5fa768`.

The local gate passed all **2,799 cases across 75 original test modules**, with
zero failures, skips, or reporter errors. Each original Dart file ran as its own
normal package:test VM suite/isolate. All 75 files occur exactly once across eight
accepted bounded invocations (seven groups of ten modules and one group of five). Each
invocation has its own successful terminal reporter event, zero process exit,
and before/after source and runtime bindings. At most two invocations ran at
once, each with concurrency two, for a maximum of four original suites. No
aggregate harness or shared test isolate was introduced.
The frozen launcher still defaults to one suite, but the gate passes a later
`--concurrency=2` option. The included package:test configuration-parser probe
confirms that its effective value is two.

All 70 previous modules remain byte-identical to their accepted source. Their
2,569 exact `(file, name, occurrence)` case identities match the prior raw
reporter and case inventory. The new modules contribute 99 compiler, 96 native,
and 23 integration cases. Two additional existing line-layout modules contribute
12 cases. These categories are disjoint and total 2,799.

Every before/after snapshot across all eight invocations binds 1,131 repository inputs by
path, Git mode/blob, byte size, and SHA-256. The two Liberation Sans/Mono font
fixtures used by actual line-box tests are included. The run also fingerprints
3,489 runtime files, including the launcher, env,
test runner kernel, SDK executables/snapshots/libraries, configured hosted
package lib/bin sources and manifests, package configurations, and coordinator
interpreter. Source and recorded runtime inputs remain identical across all 16 phase snapshots
and the final audit snapshot. This runtime file set does not claim to census every shared
operating-system dependency.

The evidence retains the full raw JSON reporter, stderr, exact invocation,
timestamps, declared/per-file counts, complete case IDs, before/after manifests,
prior raw-event proof, and frozen gate/audit source. The earlier long invocation was interrupted without a process exit receipt,
automatic after snapshot, or terminal done event. Its 2,679 partial completions
are diagnostic only and excluded from the accepted 2,799-case total. Its raw
files and a separate post-interruption observation are retained in this archive
under runtime/word-spacing-final-0201b549 and
runtime/word-spacing-interrupted-observation. The post-interruption observation
is not represented as a normal completion snapshot.

Two overlapping CLI-heavy attempts also hit the unchanged two-minute per-test
timeout: two reporter errors in batch 2 and one in batch 3. Batch 3 ended with
exit 1 and complete before/after bindings. Batch 2 had stalled cleanup and was
interrupted only after its observed timeout failures; its owned session returned
exit 130, with no automatic completion/after receipt. Their original files and
launcher logs are retained with byte-for-byte relocation proofs under the
accepted output directory's diagnostics folder. A separately labeled observation
captures the interrupted batch's unchanged inputs. Resource contention is an
inference from overlapping CLI processes and reduced available memory; the
errors themselves are precisely recorded timeout exceptions. Serial replacements
passed using the same per-invocation concurrency 2 and unchanged timeout 4x.
These failed attempts contribute zero cases to the accepted total. Remaining
CLI-heavy invocations ran serially. Other development attempts remain separate.

Root inputs-before/after files are exact aliases of the earliest accepted
batch's before snapshot and final audit snapshot; root-binding-aliases.json
records their provenance. Individual batch snapshots remain authoritative.
No GitHub Actions were queried or awaited.

## Reproduce in a fresh location

1. Clone the repository with history into `<fresh>/quds_office_suite`, then
   check out the accepted source commit above. All source and font inputs are
   supplied by that Git commit; the archive does not duplicate the repository.
2. Run the included `runtime/prior/runtime/reproduce_runtime.py` with
   `--repo <fresh>/quds_office_suite`, `--runtime <fresh>/runtime/toolchain`,
   and `--record` pointing to this archive's `runtime/toolchain/environment.json`.
   The destination toolchain and fresh checkout's `.dart_tool/package_config.json`
   must not exist. The script verifies the recorded Dart 3.14.1 SDK archive digest,
   resolves all 56 exact hosted version pins, creates package configuration
   against the clone, and compiles the normal package:test runner kernel.
3. Copy `runtime/run_word_spacing_full_gate.py` and
   `runtime/run_word_spacing_batched_gate.py` into `<fresh>/runtime`, preserving
   that relative layout. The script retrieves the
   previous evidence from the checked-out repository and refuses to overwrite
   an existing gate invocation.
4. From `<fresh>`, run:

```bash
python3 runtime/run_word_spacing_batched_gate.py prepare --out runtime/regression-reproduction --source-commit 0201b549d0dc3f601c50e36255d557034cb01699
for batch in 1 2 3 4 5 6 7 8; do
  python3 runtime/run_word_spacing_batched_gate.py run-batch --out runtime/regression-reproduction --batch "$batch" || exit 1
done
python3 runtime/run_word_spacing_batched_gate.py audit --out runtime/regression-reproduction
```

The runner produces new host-path/runtime manifests and timings; those metadata
need not byte-match the original host. It must still pass the complete case,
source-stability, original-suite, and exact-prior-identity audits. Serial bounded invocations reproduce the same file/case selection; up
to two disjoint invocations may run simultaneously as in this recorded gate.
Inspect each batch-NN raw reporter for active progress.

## Archive integrity

Archive members have sorted paths, zero timestamps/UID/GID, and empty owner/group
names. The packaging script builds the archive twice and verifies identical
SHA-256 digests, then verifies every indexed member after reopening it. The
included member index covers every other archive member; the external packaging
receipt binds that index and the whole archive. SDK/hosted dependency binaries
are not vendored here; the recorded pins, archive digest and runtime manifest
retain their provenance.
